import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_desktop/services/maya_provider_transport.dart';

Matcher _llmFailure(MayaLlmFailureKind kind) =>
    isA<MayaLlmException>().having((error) => error.kind, 'kind', kind);

Future<HttpServer> _serve(
  FutureOr<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    unawaited(
      Future<void>.sync(() => handler(request)).catchError((Object _) async {
        try {
          await request.response.close();
        } catch (_) {}
      }),
    );
  });
  return server;
}

Uri _endpoint(HttpServer server, String path) =>
    Uri.parse('http://127.0.0.1:${server.port}$path');

void main() {
  test('POSTs bounded JSON to the exact loopback URI when opted in', () async {
    late Map<String, Object?> received;
    late String receivedPath;
    late String receivedMethod;
    late String? receivedContentType;
    late String? receivedAuthorization;
    final server = await _serve((request) async {
      receivedPath = request.uri.toString();
      receivedMethod = request.method;
      receivedContentType = request.headers.contentType?.mimeType;
      receivedAuthorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      received = Map<String, Object?>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(<String, Object?>{'ok': true}));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final transport = MayaProviderHttpTransport();
    addTearDown(transport.close);

    final result = await transport.postJson(
      endpoint: _endpoint(server, '/v1/messages?mode=test'),
      headers: const <String, String>{
        'Authorization': 'Bearer test-only-secret',
        'X-Provider-Version': '2026-01-01',
      },
      payload: const <String, Object?>{
        'model': 'test-model',
        'messages': <Object?>[],
      },
      cancellation: MayaLlmCancellationToken(),
      allowLoopbackHttp: true,
    );

    expect(result, <String, Object?>{'ok': true});
    expect(receivedPath, '/v1/messages?mode=test');
    expect(receivedMethod, 'POST');
    expect(receivedContentType, ContentType.json.mimeType);
    expect(receivedAuthorization, 'Bearer test-only-secret');
    expect(received['model'], 'test-model');
  });

  test('plain HTTP requires explicit literal-loopback opt-in', () async {
    final transport = MayaProviderHttpTransport();
    addTearDown(transport.close);
    final token = MayaLlmCancellationToken();

    await expectLater(
      transport.postJson(
        endpoint: Uri.parse('http://127.0.0.1:1/v1'),
        headers: const <String, String>{},
        payload: const <String, Object?>{'ok': true},
        cancellation: token,
        allowLoopbackHttp: false,
      ),
      throwsA(_llmFailure(MayaLlmFailureKind.configuration)),
    );
    await expectLater(
      transport.postJson(
        endpoint: Uri.parse('http://localhost:1/v1'),
        headers: const <String, String>{},
        payload: const <String, Object?>{'ok': true},
        cancellation: token,
        allowLoopbackHttp: true,
      ),
      throwsA(_llmFailure(MayaLlmFailureKind.configuration)),
    );
    await expectLater(
      transport.postJson(
        endpoint: Uri.parse('http://192.168.1.10/v1'),
        headers: const <String, String>{},
        payload: const <String, Object?>{'ok': true},
        cancellation: token,
        allowLoopbackHttp: true,
      ),
      throwsA(_llmFailure(MayaLlmFailureKind.configuration)),
    );
  });

  test('redirects are rejected and authorization is never forwarded', () async {
    var redirectedRequests = 0;
    final server = await _serve((request) async {
      if (request.uri.path == '/redirected') {
        redirectedRequests++;
        request.response
          ..headers.contentType = ContentType.json
          ..write('{}');
      } else {
        request.response
          ..statusCode = HttpStatus.temporaryRedirect
          ..headers.set(HttpHeaders.locationHeader, '/redirected');
      }
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final transport = MayaProviderHttpTransport();
    addTearDown(transport.close);

    await expectLater(
      transport.postJson(
        endpoint: _endpoint(server, '/start'),
        headers: const <String, String>{
          'Authorization': 'Bearer redirect-secret',
        },
        payload: const <String, Object?>{'ok': true},
        cancellation: MayaLlmCancellationToken(),
        allowLoopbackHttp: true,
      ),
      throwsA(_llmFailure(MayaLlmFailureKind.invalidResponse)),
    );
    expect(redirectedRequests, 0);
  });

  test('requires a JSON response content type without exposing body', () async {
    const remoteBody = 'remote-body-secret-must-not-leak';
    final server = await _serve((request) async {
      request.response
        ..headers.contentType = ContentType.text
        ..write(remoteBody);
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final transport = MayaProviderHttpTransport();
    addTearDown(transport.close);

    Object? failure;
    try {
      await transport.postJson(
        endpoint: _endpoint(server, '/mime'),
        headers: const <String, String>{},
        payload: const <String, Object?>{'ok': true},
        cancellation: MayaLlmCancellationToken(),
        allowLoopbackHttp: true,
      );
    } catch (error) {
      failure = error;
    }
    expect(failure, _llmFailure(MayaLlmFailureKind.invalidResponse));
    expect('$failure', isNot(contains(remoteBody)));
  });

  test('rejects malformed JSON without retaining response text', () async {
    const remoteBody = '{"secret":"remote-json-secret"';
    final server = await _serve((request) async {
      request.response
        ..headers.contentType = ContentType.json
        ..write(remoteBody);
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final transport = MayaProviderHttpTransport();
    addTearDown(transport.close);

    Object? failure;
    try {
      await transport.postJson(
        endpoint: _endpoint(server, '/invalid-json'),
        headers: const <String, String>{},
        payload: const <String, Object?>{'ok': true},
        cancellation: MayaLlmCancellationToken(),
        allowLoopbackHttp: true,
      );
    } catch (error) {
      failure = error;
    }
    expect(failure, _llmFailure(MayaLlmFailureKind.invalidResponse));
    expect('$failure', isNot(contains('remote-json-secret')));
  });

  test('streams and rejects a response above the byte limit', () async {
    final server = await _serve((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.add(
        utf8.encode(jsonEncode(<String, Object?>{'value': 'x' * 512})),
      );
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final transport = MayaProviderHttpTransport(maxResponseBytes: 64);
    addTearDown(transport.close);

    await expectLater(
      transport.postJson(
        endpoint: _endpoint(server, '/large'),
        headers: const <String, String>{},
        payload: const <String, Object?>{'ok': true},
        cancellation: MayaLlmCancellationToken(),
        allowLoopbackHttp: true,
      ),
      throwsA(_llmFailure(MayaLlmFailureKind.responseTooLarge)),
    );
  });

  test('applies the response limit after gzip decompression', () async {
    final server = await _serve((request) async {
      final compressed = gzip.encode(
        utf8.encode(jsonEncode(<String, Object?>{'value': 'x' * 512})),
      );
      request.response.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.contentEncodingHeader, 'gzip');
      request.response.add(compressed);
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final transport = MayaProviderHttpTransport(maxResponseBytes: 64);
    addTearDown(transport.close);

    await expectLater(
      transport.postJson(
        endpoint: _endpoint(server, '/gzip-large'),
        headers: const <String, String>{},
        payload: const <String, Object?>{'ok': true},
        cancellation: MayaLlmCancellationToken(),
        allowLoopbackHttp: true,
      ),
      throwsA(_llmFailure(MayaLlmFailureKind.responseTooLarge)),
    );
  });

  test('rejects oversized requests before opening a socket', () async {
    var requests = 0;
    final server = await _serve((request) async {
      requests++;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final transport = MayaProviderHttpTransport(maxRequestBytes: 32);
    addTearDown(transport.close);

    await expectLater(
      transport.postJson(
        endpoint: _endpoint(server, '/request-limit'),
        headers: const <String, String>{},
        payload: <String, Object?>{'value': 'x' * 128},
        cancellation: MayaLlmCancellationToken(),
        allowLoopbackHttp: true,
      ),
      throwsA(_llmFailure(MayaLlmFailureKind.configuration)),
    );
    expect(requests, 0);
  });

  test('maps provider status without retaining remote body', () async {
    const remoteBody = 'provider-error-secret';
    final server = await _serve((request) async {
      request.response
        ..statusCode = int.parse(request.uri.pathSegments.single)
        ..write(remoteBody);
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final transport = MayaProviderHttpTransport();
    addTearDown(transport.close);
    const expected = <int, MayaLlmFailureKind>{
      401: MayaLlmFailureKind.unauthorized,
      403: MayaLlmFailureKind.unauthorized,
      429: MayaLlmFailureKind.rateLimited,
      500: MayaLlmFailureKind.providerFailure,
      503: MayaLlmFailureKind.providerFailure,
    };

    for (final entry in expected.entries) {
      Object? failure;
      try {
        await transport.postJson(
          endpoint: _endpoint(server, '/${entry.key}'),
          headers: const <String, String>{},
          payload: const <String, Object?>{'ok': true},
          cancellation: MayaLlmCancellationToken(),
          allowLoopbackHttp: true,
        );
      } catch (error) {
        failure = error;
      }
      expect(failure, _llmFailure(entry.value));
      expect('$failure', isNot(contains(remoteBody)));
    }
  });

  test('total timeout aborts a response that never arrives', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final server = await _serve((request) async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
      try {
        request.response
          ..headers.contentType = ContentType.json
          ..write('{}');
        await request.response.close();
      } catch (_) {}
    });
    addTearDown(() {
      if (!release.isCompleted) release.complete();
      return server.close(force: true);
    });
    final transport = MayaProviderHttpTransport(
      totalTimeout: const Duration(milliseconds: 80),
    );
    addTearDown(transport.close);

    final call = transport.postJson(
      endpoint: _endpoint(server, '/timeout'),
      headers: const <String, String>{},
      payload: const <String, Object?>{'ok': true},
      cancellation: MayaLlmCancellationToken(),
      allowLoopbackHttp: true,
    );
    final expectedCall = expectLater(
      call.timeout(const Duration(seconds: 2)),
      throwsA(_llmFailure(MayaLlmFailureKind.timeout)),
    );
    await entered.future;
    await expectedCall;
  });

  test('cancellation token aborts an in-flight response', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final server = await _serve((request) async {
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"value":"');
      await request.response.flush();
      if (!entered.isCompleted) entered.complete();
      await release.future;
      try {
        request.response.write('late"}');
        await request.response.close();
      } catch (_) {}
    });
    addTearDown(() {
      if (!release.isCompleted) release.complete();
      return server.close(force: true);
    });
    final transport = MayaProviderHttpTransport();
    addTearDown(transport.close);
    final cancellation = MayaLlmCancellationToken();

    final call = transport.postJson(
      endpoint: _endpoint(server, '/cancel'),
      headers: const <String, String>{},
      payload: const <String, Object?>{'ok': true},
      cancellation: cancellation,
      allowLoopbackHttp: true,
    );
    final expectedCall = expectLater(
      call.timeout(const Duration(seconds: 2)),
      throwsA(_llmFailure(MayaLlmFailureKind.cancelled)),
    );
    await entered.future;
    cancellation.cancel();
    await expectedCall;
  });

  test('pre-cancelled requests never open a socket', () async {
    final transport = MayaProviderHttpTransport();
    addTearDown(transport.close);
    final cancellation = MayaLlmCancellationToken()..cancel();

    await expectLater(
      transport.postJson(
        endpoint: Uri.parse('http://127.0.0.1:1/pre-cancelled'),
        headers: const <String, String>{},
        payload: const <String, Object?>{'ok': true},
        cancellation: cancellation,
        allowLoopbackHttp: true,
      ),
      throwsA(_llmFailure(MayaLlmFailureKind.cancelled)),
    );
  });

  test('close is idempotent, aborts requests and rejects new work', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final server = await _serve((request) async {
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"value":"');
      await request.response.flush();
      if (!entered.isCompleted) entered.complete();
      await release.future;
      try {
        request.response.write('late"}');
        await request.response.close();
      } catch (_) {}
    });
    addTearDown(() {
      if (!release.isCompleted) release.complete();
      return server.close(force: true);
    });
    final transport = MayaProviderHttpTransport();
    final call = transport.postJson(
      endpoint: _endpoint(server, '/close'),
      headers: const <String, String>{},
      payload: const <String, Object?>{'ok': true},
      cancellation: MayaLlmCancellationToken(),
      allowLoopbackHttp: true,
    );
    final expectedCall = expectLater(
      call.timeout(const Duration(seconds: 2)),
      throwsA(_llmFailure(MayaLlmFailureKind.cancelled)),
    );
    await entered.future;

    final firstClose = transport.close();
    final secondClose = transport.close();
    expect(identical(firstClose, secondClose), isTrue);
    await expectedCall;
    await firstClose.timeout(const Duration(seconds: 2));

    await expectLater(
      transport.postJson(
        endpoint: _endpoint(server, '/after-close'),
        headers: const <String, String>{},
        payload: const <String, Object?>{'ok': true},
        cancellation: MayaLlmCancellationToken(),
        allowLoopbackHttp: true,
      ),
      throwsA(_llmFailure(MayaLlmFailureKind.unavailable)),
    );
  });

  test('invalid headers are rejected without echoing their values', () async {
    const secret = 'Bearer do-not-echo-header-secret';
    final transport = MayaProviderHttpTransport();
    addTearDown(transport.close);
    Object? failure;
    try {
      await transport.postJson(
        endpoint: Uri.parse('https://example.invalid/v1'),
        headers: const <String, String>{'Authorization': '$secret\ninvalid'},
        payload: const <String, Object?>{'ok': true},
        cancellation: MayaLlmCancellationToken(),
        allowLoopbackHttp: false,
      );
    } catch (error) {
      failure = error;
    }
    expect(failure, _llmFailure(MayaLlmFailureKind.configuration));
    expect('$failure', isNot(contains(secret)));
  });
}
