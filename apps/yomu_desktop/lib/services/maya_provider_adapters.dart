import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_storage/yomu_storage.dart';

import 'maya_credential_store.dart';
import 'maya_custom_provider_security.dart';
import 'maya_provider_codecs.dart';
import 'maya_provider_controller.dart';
import 'maya_provider_transport.dart';

const int kMayaProviderMaxModelIdChars = kMayaProviderModelIdMaxChars;

final RegExp _modelIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$');

final Uri _openAiEndpoint = Uri.parse('https://api.openai.com/v1/responses');
final Uri _anthropicEndpoint = Uri.parse(
  'https://api.anthropic.com/v1/messages',
);
final Uri _ollamaEndpoint = Uri.parse('http://127.0.0.1:11434/api/chat');

typedef MayaProviderTransportFactory = MayaProviderTransport Function();

/// Builds the concrete adapter factory injected into [MayaProviderController].
///
/// A new transport belongs to each adapter generation. Provider credentials
/// are read only inside [MayaLlmProvider.complete], never during construction,
/// and are retained only in request-local variables and headers.
MayaProviderAdapterFactory createMayaProviderAdapterFactory({
  MayaProviderTransportFactory? transportFactory,
}) {
  final createTransport = transportFactory ?? MayaProviderHttpTransport.new;
  return ({
    required MayaProviderAdapterSettings settings,
    required MayaProviderCredentialReader readCredential,
  }) async {
    final configuration = _configurationFor(settings);
    final codec = createMayaProviderCodec(
      providerId: configuration.providerId,
      model: configuration.model,
    );

    MayaProviderTransport transport;
    try {
      transport = createTransport();
    } on MayaLlmException {
      rethrow;
    } catch (_) {
      throw const MayaLlmException(MayaLlmFailureKind.unavailable);
    }

    return _MayaConcreteProviderAdapter(
      configuration: configuration,
      codec: codec,
      transport: transport,
      readCredential: configuration.requiresCredential ? readCredential : null,
    );
  };
}

final class _MayaConcreteProviderAdapter implements MayaLlmProvider {
  _MayaConcreteProviderAdapter({
    required _MayaProviderConfiguration configuration,
    required MayaProviderCodec codec,
    required MayaProviderTransport transport,
    required MayaProviderCredentialReader? readCredential,
  }) : _configuration = configuration,
       _codec = codec,
       _transport = transport,
       _readCredential = readCredential;

  final _MayaProviderConfiguration _configuration;
  final MayaProviderCodec _codec;
  final MayaProviderTransport _transport;
  final MayaProviderCredentialReader? _readCredential;

  bool _closed = false;
  Future<void>? _closeFuture;

  /// Consent and context-sharing policy belong to the controller. Returning a
  /// disabled policy fails closed if this internal adapter is wired directly.
  @override
  MayaLlmContextPolicy get contextPolicy =>
      const MayaLlmContextPolicy.disabled();

  @override
  Future<MayaLlmResponse> complete(MayaLlmRequest request) async {
    _throwIfClosed();
    request.cancellation.throwIfCancelled();

    String? credential;
    final headers = <String, String>{};
    try {
      final readCredential = _readCredential;
      if (readCredential != null) {
        request.cancellation.throwIfCancelled();
        try {
          credential = await readCredential();
        } on MayaLlmException {
          request.cancellation.throwIfCancelled();
          _throwIfClosed();
          rethrow;
        } catch (_) {
          request.cancellation.throwIfCancelled();
          _throwIfClosed();
          throw const MayaLlmException(MayaLlmFailureKind.unavailable);
        }
        request.cancellation.throwIfCancelled();
        _throwIfClosed();

        final currentCredential = credential;
        if (currentCredential == null) {
          throw const MayaLlmException(MayaLlmFailureKind.unauthorized);
        }
        try {
          validateMayaApiKey(currentCredential);
        } catch (_) {
          throw const MayaLlmException(MayaLlmFailureKind.configuration);
        }
        _addCredentialHeaders(
          headers,
          providerId: _configuration.providerId,
          credential: currentCredential,
        );
        credential = null;
      }

      request.cancellation.throwIfCancelled();
      _throwIfClosed();

      Map<String, Object?> payload;
      try {
        payload = _codec.encode(request);
      } catch (_) {
        throw const MayaLlmException(MayaLlmFailureKind.configuration);
      }

      final response = await _transport.postJson(
        endpoint: _configuration.endpoint,
        headers: headers,
        payload: payload,
        cancellation: request.cancellation,
        allowLoopbackHttp: _configuration.allowLoopbackHttp,
      );
      request.cancellation.throwIfCancelled();
      _throwIfClosed();

      try {
        return _codec.decode(response);
      } catch (_) {
        throw const MayaLlmException(MayaLlmFailureKind.invalidResponse);
      }
    } on MayaLlmException {
      rethrow;
    } catch (_) {
      throw const MayaLlmException(MayaLlmFailureKind.providerFailure);
    } finally {
      credential = null;
      headers.clear();
    }
  }

  @override
  Future<void> close() {
    _closed = true;
    return _closeFuture ??= _closeTransport();
  }

  Future<void> _closeTransport() async {
    try {
      await _transport.close();
    } catch (_) {
      throw const MayaLlmException(MayaLlmFailureKind.transport);
    }
  }

  void _throwIfClosed() {
    if (_closed) {
      throw const MayaLlmException(MayaLlmFailureKind.cancelled);
    }
  }
}

final class _MayaProviderConfiguration {
  const _MayaProviderConfiguration({
    required this.providerId,
    required this.model,
    required this.endpoint,
    required this.allowLoopbackHttp,
    required this.requiresCredential,
  });

  final String providerId;
  final String model;
  final Uri endpoint;
  final bool allowLoopbackHttp;
  final bool requiresCredential;
}

_MayaProviderConfiguration _configurationFor(
  MayaProviderAdapterSettings settings,
) {
  if (settings.modelPolicy != MayaProviderModelPolicy.explicit) {
    throw const MayaLlmException(MayaLlmFailureKind.configuration);
  }

  final providerId = settings.providerId;
  final model = _normalizeModel(providerId, settings.modelId);
  if (providerId != kMayaCustomProviderId &&
      (settings.customEndpointUrl != null ||
          settings.customUseApiKey != null)) {
    throw const MayaLlmException(MayaLlmFailureKind.configuration);
  }
  return switch (providerId) {
    'openai' => _MayaProviderConfiguration(
      providerId: providerId,
      model: model,
      endpoint: _openAiEndpoint,
      allowLoopbackHttp: false,
      requiresCredential: true,
    ),
    'anthropic' => _MayaProviderConfiguration(
      providerId: providerId,
      model: model,
      endpoint: _anthropicEndpoint,
      allowLoopbackHttp: false,
      requiresCredential: true,
    ),
    'gemini' => _MayaProviderConfiguration(
      providerId: providerId,
      model: model,
      endpoint: Uri.parse(
        'https://generativelanguage.googleapis.com/'
        'v1beta/models/$model:generateContent',
      ),
      allowLoopbackHttp: false,
      requiresCredential: true,
    ),
    'ollama' => _MayaProviderConfiguration(
      providerId: providerId,
      model: model,
      endpoint: _ollamaEndpoint,
      allowLoopbackHttp: true,
      requiresCredential: false,
    ),
    kMayaCustomProviderId => _customConfiguration(settings, model),
    _ => throw const MayaLlmException(MayaLlmFailureKind.configuration),
  };
}

_MayaProviderConfiguration _customConfiguration(
  MayaProviderAdapterSettings settings,
  String model,
) {
  final rawEndpoint = settings.customEndpointUrl;
  final requiresCredential = settings.customUseApiKey;
  if (rawEndpoint == null || requiresCredential == null) {
    throw const MayaLlmException(MayaLlmFailureKind.configuration);
  }
  final endpoint = MayaCustomProviderEndpoint.parse(rawEndpoint);
  if (endpoint.canonicalUrl != rawEndpoint) {
    throw const MayaLlmException(MayaLlmFailureKind.configuration);
  }
  return _MayaProviderConfiguration(
    providerId: kMayaCustomProviderId,
    model: model,
    endpoint: endpoint.uri,
    allowLoopbackHttp: endpoint.uri.scheme == 'http',
    requiresCredential: requiresCredential,
  );
}

String _normalizeModel(String providerId, String? modelId) {
  if (modelId == null) {
    throw const MayaLlmException(MayaLlmFailureKind.configuration);
  }
  var model = modelId.trim();
  if (providerId == kMayaCustomProviderId) {
    if (model.isEmpty ||
        model.length > kMayaProviderMaxModelIdChars ||
        model.runes.any(
          (rune) => rune < 0x20 || (rune >= 0x7f && rune <= 0x9f),
        )) {
      throw const MayaLlmException(MayaLlmFailureKind.configuration);
    }
    return model;
  }
  if (providerId == 'gemini' && model.startsWith('models/')) {
    model = model.substring('models/'.length);
  }
  if (model.isEmpty ||
      model.length > kMayaProviderMaxModelIdChars ||
      !_modelIdPattern.hasMatch(model)) {
    throw const MayaLlmException(MayaLlmFailureKind.configuration);
  }
  return model;
}

void _addCredentialHeaders(
  Map<String, String> headers, {
  required String providerId,
  required String credential,
}) {
  switch (providerId) {
    case 'openai':
    case kMayaCustomProviderId:
      headers['Authorization'] = 'Bearer $credential';
      return;
    case 'anthropic':
      headers['x-api-key'] = credential;
      headers['anthropic-version'] = '2023-06-01';
      return;
    case 'gemini':
      headers['x-goog-api-key'] = credential;
      return;
    default:
      throw const MayaLlmException(MayaLlmFailureKind.configuration);
  }
}
