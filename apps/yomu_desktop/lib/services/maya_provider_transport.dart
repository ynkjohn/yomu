import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:yomu_ai/yomu_ai.dart';

const int kMayaProviderMaxRequestBytes = 256 * 1024;
const int kMayaProviderMaxResponseBytes = 1024 * 1024;
const int kMayaProviderMaxHeaders = 32;
const int kMayaProviderMaxHeaderBytes = 32 * 1024;
const int kMayaProviderMaxHeaderValueBytes = 8 * 1024;

typedef MayaHttpClientFactory = HttpClient Function();

/// Minimal provider transport boundary used by concrete adapters and tests.
///
/// The production implementation below remains responsible for endpoint,
/// header, payload, timeout and response validation.
abstract interface class MayaProviderTransport {
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Object? payload,
    required MayaLlmCancellationToken cancellation,
    required bool allowLoopbackHttp,
  });

  Future<void> close();
}

final RegExp _headerNamePattern = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

const Set<String> _transportOwnedOrUnsafeHeaders = <String>{
  'accept',
  'connection',
  'content-length',
  'content-type',
  'expect',
  'host',
  'proxy-authorization',
  'proxy-connection',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
};

/// Provider-neutral, bounded JSON-over-HTTP transport for Maya adapters.
///
/// Provider adapters remain responsible for supplying an exact allowlisted
/// endpoint and provider-specific request/response schemas. This transport
/// owns HTTP framing, cancellation, limits and sanitized failure mapping.
final class MayaProviderHttpTransport implements MayaProviderTransport {
  MayaProviderHttpTransport({
    this.totalTimeout = const Duration(seconds: 30),
    this.maxRequestBytes = kMayaProviderMaxRequestBytes,
    this.maxResponseBytes = kMayaProviderMaxResponseBytes,
    MayaHttpClientFactory? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new {
    if (totalTimeout <= Duration.zero ||
        totalTimeout > const Duration(minutes: 2) ||
        maxRequestBytes <= 0 ||
        maxRequestBytes > kMayaProviderMaxRequestBytes ||
        maxResponseBytes <= 0 ||
        maxResponseBytes > kMayaProviderMaxResponseBytes) {
      throw const MayaLlmException(MayaLlmFailureKind.configuration);
    }
  }

  final Duration totalTimeout;
  final int maxRequestBytes;
  final int maxResponseBytes;
  final MayaHttpClientFactory _clientFactory;

  final Set<_MayaHttpOperation> _active = <_MayaHttpOperation>{};
  bool _closed = false;
  Future<void>? _closeFuture;

  /// Sends one bounded POST request and returns a JSON object.
  ///
  /// Plain HTTP is rejected unless [allowLoopbackHttp] is explicitly true and
  /// [endpoint] uses a literal loopback IP. `localhost` is intentionally not
  /// accepted because its DNS/hosts-file resolution is mutable.
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Object? payload,
    required MayaLlmCancellationToken cancellation,
    required bool allowLoopbackHttp,
  }) async {
    if (_closed) {
      throw const MayaLlmException(MayaLlmFailureKind.unavailable);
    }
    cancellation.throwIfCancelled();
    _validateEndpoint(endpoint, allowLoopbackHttp: allowLoopbackHttp);
    final safeHeaders = _validateHeaders(headers);
    final requestBytes = _encodeRequest(payload);
    if (_closed) {
      requestBytes.fillRange(0, requestBytes.length, 0);
      throw const MayaLlmException(MayaLlmFailureKind.unavailable);
    }
    try {
      cancellation.throwIfCancelled();
    } on MayaLlmException {
      requestBytes.fillRange(0, requestBytes.length, 0);
      rethrow;
    }

    HttpClient? client;
    _MayaHttpOperation? operation;
    Timer? timeoutTimer;
    Uint8List? responseBytes;
    try {
      client = _clientFactory()
        ..autoUncompress = true
        ..connectionTimeout = totalTimeout
        ..idleTimeout = totalTimeout;
      operation = _MayaHttpOperation(client);
      _active.add(operation);

      final weakOperation = WeakReference<_MayaHttpOperation>(operation);
      unawaited(
        cancellation.whenCancelled.then((_) {
          weakOperation.target?.abort(_MayaHttpAbortReason.cancellation);
        }),
      );
      timeoutTimer = Timer(
        totalTimeout,
        () => operation?.abort(_MayaHttpAbortReason.timeout),
      );

      final request = await client.openUrl('POST', endpoint);
      operation.request = request;
      operation.throwIfAborted();
      cancellation.throwIfCancelled();

      request
        ..followRedirects = false
        ..maxRedirects = 0
        ..contentLength = requestBytes.length;
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      for (final entry in safeHeaders.entries) {
        request.headers.set(entry.key, entry.value);
      }
      request.add(requestBytes);

      final response = await request.close();
      operation.throwIfAborted();
      cancellation.throwIfCancelled();
      _throwForStatus(response.statusCode);
      _validateJsonContentType(response.headers.contentType);

      final builder = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response) {
        operation.throwIfAborted();
        cancellation.throwIfCancelled();
        total += chunk.length;
        if (total > maxResponseBytes) {
          throw const MayaLlmException(MayaLlmFailureKind.responseTooLarge);
        }
        builder.add(chunk);
      }
      responseBytes = builder.takeBytes();
      if (responseBytes.isEmpty) {
        throw const MayaLlmException(MayaLlmFailureKind.invalidResponse);
      }

      operation.throwIfAborted();
      cancellation.throwIfCancelled();
      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(responseBytes, allowMalformed: false));
      } catch (_) {
        throw const MayaLlmException(MayaLlmFailureKind.invalidResponse);
      }
      if (decoded is! Map) {
        throw const MayaLlmException(MayaLlmFailureKind.invalidResponse);
      }
      try {
        return Map<String, Object?>.unmodifiable(
          Map<String, Object?>.from(decoded),
        );
      } catch (_) {
        throw const MayaLlmException(MayaLlmFailureKind.invalidResponse);
      }
    } on MayaLlmException {
      final reason = operation?.abortReason;
      if (reason != null) throw _exceptionForAbort(reason);
      rethrow;
    } catch (_) {
      final reason = operation?.abortReason;
      if (reason != null) throw _exceptionForAbort(reason);
      if (cancellation.isCancelled) {
        throw const MayaLlmException(MayaLlmFailureKind.cancelled);
      }
      throw const MayaLlmException(MayaLlmFailureKind.transport);
    } finally {
      timeoutTimer?.cancel();
      final bytes = responseBytes;
      if (bytes != null) bytes.fillRange(0, bytes.length, 0);
      requestBytes.fillRange(0, requestBytes.length, 0);
      if (operation != null) {
        _active.remove(operation);
        operation.finish();
      } else {
        client?.close(force: true);
      }
    }
  }

  /// Stops admission, aborts active sockets and waits for admitted calls.
  /// Repeated calls return the same completion future.
  @override
  Future<void> close() {
    _closed = true;
    return _closeFuture ??= _closeActive();
  }

  Future<void> _closeActive() async {
    final active = List<_MayaHttpOperation>.of(_active);
    for (final operation in active) {
      operation.abort(_MayaHttpAbortReason.shutdown);
    }
    await Future.wait(active.map((operation) => operation.done));
  }

  List<int> _encodeRequest(Object? payload) {
    List<int> bytes;
    try {
      bytes = utf8.encode(jsonEncode(payload));
    } catch (_) {
      throw const MayaLlmException(MayaLlmFailureKind.configuration);
    }
    if (bytes.isEmpty || bytes.length > maxRequestBytes) {
      bytes.fillRange(0, bytes.length, 0);
      throw const MayaLlmException(MayaLlmFailureKind.configuration);
    }
    return bytes;
  }

  static void _validateEndpoint(
    Uri endpoint, {
    required bool allowLoopbackHttp,
  }) {
    if (!endpoint.isAbsolute ||
        !endpoint.hasAuthority ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.fragment.isNotEmpty) {
      throw const MayaLlmException(MayaLlmFailureKind.configuration);
    }
    if (endpoint.scheme == 'https') return;
    if (endpoint.scheme == 'http' && allowLoopbackHttp) {
      final literal = InternetAddress.tryParse(endpoint.host);
      if (literal != null && literal.isLoopback) return;
    }
    throw const MayaLlmException(MayaLlmFailureKind.configuration);
  }

  static Map<String, String> _validateHeaders(Map<String, String> headers) {
    if (headers.length > kMayaProviderMaxHeaders) {
      throw const MayaLlmException(MayaLlmFailureKind.configuration);
    }
    final result = <String, String>{};
    var totalBytes = 0;
    for (final entry in headers.entries) {
      final name = entry.key;
      final lowerName = name.toLowerCase();
      final value = entry.value;
      if (!_headerNamePattern.hasMatch(name) ||
          _transportOwnedOrUnsafeHeaders.contains(lowerName)) {
        throw const MayaLlmException(MayaLlmFailureKind.configuration);
      }
      if (value.length > kMayaProviderMaxHeaderValueBytes ||
          value.codeUnits.any((unit) => unit < 0x20 || unit > 0x7e)) {
        throw const MayaLlmException(MayaLlmFailureKind.configuration);
      }
      totalBytes += name.length + value.length;
      if (totalBytes > kMayaProviderMaxHeaderBytes) {
        throw const MayaLlmException(MayaLlmFailureKind.configuration);
      }
      result[name] = value;
    }
    return Map<String, String>.unmodifiable(result);
  }

  static void _throwForStatus(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) return;
    if (statusCode == HttpStatus.unauthorized ||
        statusCode == HttpStatus.forbidden) {
      throw const MayaLlmException(MayaLlmFailureKind.unauthorized);
    }
    if (statusCode == HttpStatus.tooManyRequests) {
      throw const MayaLlmException(MayaLlmFailureKind.rateLimited);
    }
    if (statusCode >= 300 && statusCode < 400) {
      throw const MayaLlmException(MayaLlmFailureKind.invalidResponse);
    }
    if (statusCode >= 500 && statusCode < 600) {
      throw const MayaLlmException(MayaLlmFailureKind.providerFailure);
    }
    throw const MayaLlmException(MayaLlmFailureKind.providerFailure);
  }

  static void _validateJsonContentType(ContentType? contentType) {
    final mime = contentType?.mimeType.toLowerCase();
    if (mime == null ||
        (mime != ContentType.json.mimeType && !mime.endsWith('+json'))) {
      throw const MayaLlmException(MayaLlmFailureKind.invalidResponse);
    }
  }

  static MayaLlmException _exceptionForAbort(_MayaHttpAbortReason reason) {
    return switch (reason) {
      _MayaHttpAbortReason.timeout => const MayaLlmException(
        MayaLlmFailureKind.timeout,
      ),
      _MayaHttpAbortReason.cancellation || _MayaHttpAbortReason.shutdown =>
        const MayaLlmException(MayaLlmFailureKind.cancelled),
    };
  }
}

enum _MayaHttpAbortReason { cancellation, timeout, shutdown }

final class _MayaHttpOperation {
  _MayaHttpOperation(this.client);

  final HttpClient client;
  final Completer<void> _done = Completer<void>();
  HttpClientRequest? request;
  _MayaHttpAbortReason? abortReason;
  bool _finished = false;

  Future<void> get done => _done.future;

  void abort(_MayaHttpAbortReason reason) {
    if (_finished || abortReason != null) return;
    abortReason = reason;
    final failure = MayaProviderHttpTransport._exceptionForAbort(reason);
    try {
      request?.abort(failure);
    } catch (_) {}
    client.close(force: true);
  }

  void throwIfAborted() {
    final reason = abortReason;
    if (reason != null) {
      throw MayaProviderHttpTransport._exceptionForAbort(reason);
    }
  }

  void finish() {
    if (_finished) return;
    _finished = true;
    client.close(force: true);
    if (!_done.isCompleted) _done.complete();
  }
}
