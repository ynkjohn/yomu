import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_desktop/services/maya_credential_store.dart';
import 'package:yomu_desktop/services/maya_provider_adapters.dart';
import 'package:yomu_desktop/services/maya_provider_controller.dart';
import 'package:yomu_desktop/services/maya_provider_transport.dart';
import 'package:yomu_storage/yomu_storage.dart';

Matcher _failure(MayaLlmFailureKind kind) =>
    isA<MayaLlmException>().having((error) => error.kind, 'kind', kind);

MayaLlmRequest _request({
  MayaLlmCancellationToken? cancellation,
  Object? contextLease,
}) {
  return MayaLlmRequest(
    currentUserText: 'Explique a biblioteca atual.',
    history: const <MayaLlmMessage>[],
    library: const <MayaLlmLibraryItem>[],
    availableTools: const <MayaLlmTool>{},
    libraryAvailable: true,
    cancellation: cancellation ?? MayaLlmCancellationToken(),
    contextLease: contextLease,
  );
}

Future<MayaLlmProvider> _adapter({
  required String providerId,
  required String? modelId,
  required MayaProviderCredentialReader readCredential,
  required _RecordingTransport transport,
  MayaProviderModelPolicy modelPolicy = MayaProviderModelPolicy.explicit,
}) {
  final factory = createMayaProviderAdapterFactory(
    transportFactory: () => transport,
  );
  return factory(
    settings: MayaProviderAdapterSettings(
      providerId: providerId,
      modelPolicy: modelPolicy,
      modelId: modelId,
    ),
    readCredential: readCredential,
  );
}

void main() {
  test(
    'OpenAI uses the fixed Responses endpoint and a JIT bearer key',
    () async {
      const secret = 'sk-openai-adapter-test';
      var reads = 0;
      final transport = _RecordingTransport(
        expectedCredential: secret,
        response: <String, Object?>{
          'output': <Object?>[
            <String, Object?>{
              'type': 'message',
              'content': <Object?>[
                <String, Object?>{
                  'type': 'output_text',
                  'text': 'resposta openai',
                },
              ],
            },
          ],
        },
      );
      final adapter = await _adapter(
        providerId: 'openai',
        modelId: 'gpt-5-mini',
        readCredential: () async {
          reads++;
          return secret;
        },
        transport: transport,
      );
      addTearDown(adapter.close);

      final response = await adapter.complete(_request());

      expect(response.text, 'resposta openai');
      expect(reads, 1);
      expect(
        transport.endpoint,
        Uri.parse('https://api.openai.com/v1/responses'),
      );
      expect(transport.allowLoopbackHttp, isFalse);
      expect(transport.credentialMatched, isTrue);
      expect(transport.headers, <String, String>{
        'Authorization': '<redacted>',
      });
      expect(transport.payload?['model'], 'gpt-5-mini');
      expect(jsonEncode(transport.payload), isNot(contains(secret)));
      expect('${transport.headers}', isNot(contains(secret)));
      expect(transport.expectedCredential, isNull);
    },
  );

  test(
    'Anthropic uses fixed endpoint, x-api-key and pinned API version',
    () async {
      const secret = 'sk-ant-adapter-test';
      var reads = 0;
      final transport = _RecordingTransport(
        expectedCredential: secret,
        response: <String, Object?>{
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'resposta anthropic'},
          ],
        },
      );
      final adapter = await _adapter(
        providerId: 'anthropic',
        modelId: 'claude-sonnet-4-5',
        readCredential: () async {
          reads++;
          return secret;
        },
        transport: transport,
      );
      addTearDown(adapter.close);

      final response = await adapter.complete(_request());

      expect(response.text, 'resposta anthropic');
      expect(reads, 1);
      expect(
        transport.endpoint,
        Uri.parse('https://api.anthropic.com/v1/messages'),
      );
      expect(transport.allowLoopbackHttp, isFalse);
      expect(transport.credentialMatched, isTrue);
      expect(transport.headers, <String, String>{
        'x-api-key': '<redacted>',
        'anthropic-version': '2023-06-01',
      });
      expect(transport.payload?['model'], 'claude-sonnet-4-5');
      expect(jsonEncode(transport.payload), isNot(contains(secret)));
    },
  );

  test(
    'Gemini normalizes models/ into one injection-safe path segment',
    () async {
      const secret = 'gemini-adapter-test-key';
      var reads = 0;
      final transport = _RecordingTransport(
        expectedCredential: secret,
        response: <String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{
              'content': <String, Object?>{
                'parts': <Object?>[
                  <String, Object?>{'text': 'resposta gemini'},
                ],
              },
            },
          ],
        },
      );
      final adapter = await _adapter(
        providerId: 'gemini',
        modelId: ' models/gemini-2.5-pro ',
        readCredential: () async {
          reads++;
          return secret;
        },
        transport: transport,
      );
      addTearDown(adapter.close);

      final response = await adapter.complete(_request());

      expect(response.text, 'resposta gemini');
      expect(reads, 1);
      expect(
        transport.endpoint,
        Uri.parse(
          'https://generativelanguage.googleapis.com/'
          'v1beta/models/gemini-2.5-pro:generateContent',
        ),
      );
      expect(transport.endpoint?.query, isEmpty);
      expect(transport.allowLoopbackHttp, isFalse);
      expect(transport.credentialMatched, isTrue);
      expect(transport.headers, <String, String>{
        'x-goog-api-key': '<redacted>',
      });
      expect(transport.payload, isNot(contains('model')));
      expect(jsonEncode(transport.payload), isNot(contains(secret)));
    },
  );

  test(
    'Ollama uses only fixed literal loopback and never reads the vault',
    () async {
      var reads = 0;
      final transport = _RecordingTransport(
        response: <String, Object?>{
          'message': <String, Object?>{'content': 'resposta ollama'},
        },
      );
      final adapter = await _adapter(
        providerId: 'ollama',
        modelId: 'llama3.2:3b',
        readCredential: () async {
          reads++;
          throw StateError('credential store must not be touched');
        },
        transport: transport,
      );
      addTearDown(adapter.close);

      final response = await adapter.complete(_request());

      expect(response.text, 'resposta ollama');
      expect(reads, 0);
      expect(transport.endpoint, Uri.parse('http://127.0.0.1:11434/api/chat'));
      expect(transport.allowLoopbackHttp, isTrue);
      expect(transport.headers, isEmpty);
      expect(transport.payload?['model'], 'llama3.2:3b');
    },
  );

  test(
    'real controller factory reads the credential only for each request',
    () async {
      const secret = 'sk-controller-adapter-test';
      final root = Directory.systemTemp.createTempSync(
        'yomu-provider-adapter-integration-',
      );
      final database = await YomuDatabase.openForTest(
        root,
        useProcessLock: false,
      );
      final credentials = _CountingCredentialStore();
      final transport = _RecordingTransport(
        expectedCredential: secret,
        response: <String, Object?>{
          'output': <Object?>[
            <String, Object?>{
              'type': 'message',
              'content': <Object?>[
                <String, Object?>{
                  'type': 'output_text',
                  'text': 'resposta integrada',
                },
              ],
            },
          ],
        },
      );
      final controller = await MayaProviderController.open(
        database: database,
        credentialStore: credentials,
        adapterFactory: createMayaProviderAdapterFactory(
          transportFactory: () => transport,
        ),
      );
      addTearDown(() async {
        try {
          await controller.close();
        } catch (_) {}
        try {
          await database.close();
        } catch (_) {}
        try {
          if (root.existsSync()) root.deleteSync(recursive: true);
        } catch (_) {}
      });

      await controller.saveCloud(
        providerId: 'openai',
        modelPolicy: MayaProviderModelPolicy.explicit,
        modelId: 'gpt-5-mini',
        apiKey: secret,
        shareRecentHistory: false,
        shareLibraryContext: false,
      );

      expect(controller.status, MayaProviderControllerStatus.cloudReady);
      expect(
        credentials.readCalls,
        2,
        reason: 'previous-value capture and readback before activation',
      );
      expect(
        transport.postCalls,
        0,
        reason: 'factory must not issue a request',
      );

      final response = await controller.complete(
        _request(contextLease: controller.contextPolicy.contextLease),
      );

      expect(response.text, 'resposta integrada');
      expect(
        credentials.readCalls,
        3,
        reason: 'one additional JIT request read',
      );
      expect(transport.postCalls, 1);
      expect(transport.credentialMatched, isTrue);
      expect('${transport.headers}', isNot(contains(secret)));
    },
  );

  test(
    'factory rejects defaults and unknown providers before allocation',
    () async {
      var transportCreations = 0;
      var reads = 0;
      final factory = createMayaProviderAdapterFactory(
        transportFactory: () {
          transportCreations++;
          return _RecordingTransport(response: const <String, Object?>{});
        },
      );

      await expectLater(
        factory(
          settings: const MayaProviderAdapterSettings(
            providerId: 'openai',
            modelPolicy: MayaProviderModelPolicy.providerDefault,
            modelId: null,
          ),
          readCredential: () async {
            reads++;
            return 'unused';
          },
        ),
        throwsA(_failure(MayaLlmFailureKind.configuration)),
      );
      await expectLater(
        factory(
          settings: const MayaProviderAdapterSettings(
            providerId: 'https://provider.invalid',
            modelPolicy: MayaProviderModelPolicy.explicit,
            modelId: 'model',
          ),
          readCredential: () async {
            reads++;
            return 'unused';
          },
        ),
        throwsA(_failure(MayaLlmFailureKind.configuration)),
      );

      expect(transportCreations, 0);
      expect(reads, 0);
    },
  );

  test('model allowlist blocks path, query and URL injection', () async {
    var transportCreations = 0;
    final factory = createMayaProviderAdapterFactory(
      transportFactory: () {
        transportCreations++;
        return _RecordingTransport(response: const <String, Object?>{});
      },
    );
    final invalidModels = <String?>[
      null,
      '',
      '   ',
      '../gpt-5',
      'gpt-5?api_key=do-not-leak',
      'https://example.invalid/model',
      'models/gemini/foo',
      'gemini%2fescape',
      'x' * (kMayaProviderMaxModelIdChars + 1),
    ];

    for (final model in invalidModels) {
      Object? failure;
      try {
        await factory(
          settings: MayaProviderAdapterSettings(
            providerId: 'gemini',
            modelPolicy: MayaProviderModelPolicy.explicit,
            modelId: model,
          ),
          readCredential: () async => 'unused',
        );
      } catch (error) {
        failure = error;
      }
      expect(failure, _failure(MayaLlmFailureKind.configuration));
      expect('$failure', isNot(contains('do-not-leak')));
    }
    expect(transportCreations, 0);
  });

  test('missing, invalid and failed credential reads fail closed', () async {
    final missingTransport = _RecordingTransport(
      response: const <String, Object?>{},
    );
    final missing = await _adapter(
      providerId: 'openai',
      modelId: 'gpt-5',
      readCredential: () async => null,
      transport: missingTransport,
    );
    addTearDown(missing.close);
    await expectLater(
      missing.complete(_request()),
      throwsA(_failure(MayaLlmFailureKind.unauthorized)),
    );
    expect(missingTransport.postCalls, 0);

    const invalidSecret = 'invalid-key\nraw-secret-must-not-leak';
    final invalidTransport = _RecordingTransport(
      response: const <String, Object?>{},
    );
    final invalid = await _adapter(
      providerId: 'anthropic',
      modelId: 'claude-test',
      readCredential: () async => invalidSecret,
      transport: invalidTransport,
    );
    addTearDown(invalid.close);
    Object? invalidFailure;
    try {
      await invalid.complete(_request());
    } catch (error) {
      invalidFailure = error;
    }
    expect(invalidFailure, _failure(MayaLlmFailureKind.configuration));
    expect('$invalidFailure', isNot(contains('raw-secret')));
    expect(invalidTransport.postCalls, 0);

    final failedTransport = _RecordingTransport(
      response: const <String, Object?>{},
    );
    final failed = await _adapter(
      providerId: 'gemini',
      modelId: 'gemini-test',
      readCredential: () async {
        throw StateError('credential failure raw-secret');
      },
      transport: failedTransport,
    );
    addTearDown(failed.close);
    Object? readFailure;
    try {
      await failed.complete(_request());
    } catch (error) {
      readFailure = error;
    }
    expect(readFailure, _failure(MayaLlmFailureKind.unavailable));
    expect('$readFailure', isNot(contains('raw-secret')));
    expect(failedTransport.postCalls, 0);
  });

  test(
    'cancellation is checked before and after the credential read',
    () async {
      var preCancelledReads = 0;
      final preCancelledTransport = _RecordingTransport(
        response: const <String, Object?>{},
      );
      final preCancelled = await _adapter(
        providerId: 'openai',
        modelId: 'gpt-5',
        readCredential: () async {
          preCancelledReads++;
          return 'sk-unused';
        },
        transport: preCancelledTransport,
      );
      addTearDown(preCancelled.close);
      final firstToken = MayaLlmCancellationToken()..cancel();
      await expectLater(
        preCancelled.complete(_request(cancellation: firstToken)),
        throwsA(_failure(MayaLlmFailureKind.cancelled)),
      );
      expect(preCancelledReads, 0);
      expect(preCancelledTransport.postCalls, 0);

      var postReadCalls = 0;
      final postReadTransport = _RecordingTransport(
        response: const <String, Object?>{},
      );
      final secondToken = MayaLlmCancellationToken();
      final postRead = await _adapter(
        providerId: 'openai',
        modelId: 'gpt-5',
        readCredential: () async {
          postReadCalls++;
          secondToken.cancel();
          return 'sk-cancelled-after-read';
        },
        transport: postReadTransport,
      );
      addTearDown(postRead.close);
      await expectLater(
        postRead.complete(_request(cancellation: secondToken)),
        throwsA(_failure(MayaLlmFailureKind.cancelled)),
      );
      expect(postReadCalls, 1);
      expect(postReadTransport.postCalls, 0);
    },
  );

  test(
    'close is idempotent, aborts transport and rejects future work',
    () async {
      var reads = 0;
      final transport = _RecordingTransport(
        expectedCredential: 'sk-close-adapter',
        response: const <String, Object?>{},
        blockUntilClosed: true,
      );
      final adapter = await _adapter(
        providerId: 'openai',
        modelId: 'gpt-5',
        readCredential: () async {
          reads++;
          return 'sk-close-adapter';
        },
        transport: transport,
      );

      final completion = adapter.complete(_request());
      final completionExpectation = expectLater(
        completion,
        throwsA(_failure(MayaLlmFailureKind.cancelled)),
      );
      await transport.entered.future;
      final firstClose = adapter.close();
      final secondClose = adapter.close();

      expect(identical(firstClose, secondClose), isTrue);
      await firstClose;
      await completionExpectation;
      expect(transport.closeCalls, 1);
      expect(reads, 1);
      await expectLater(
        adapter.complete(_request()),
        throwsA(_failure(MayaLlmFailureKind.cancelled)),
      );
      expect(reads, 1);
    },
  );

  test('codec failures become sanitized invalid responses', () async {
    const secret = 'sk-codec-adapter-test';
    final transport = _RecordingTransport(
      expectedCredential: secret,
      response: _ThrowingResponse(),
    );
    final adapter = await _adapter(
      providerId: 'openai',
      modelId: 'gpt-5',
      readCredential: () async => secret,
      transport: transport,
    );
    addTearDown(adapter.close);

    Object? failure;
    try {
      await adapter.complete(_request());
    } catch (error) {
      failure = error;
    }
    expect(failure, _failure(MayaLlmFailureKind.invalidResponse));
    expect('$failure', isNot(contains('remote-body-secret')));
    expect('$failure', isNot(contains(secret)));
  });
}

final class _RecordingTransport implements MayaProviderTransport {
  _RecordingTransport({
    required this.response,
    this.expectedCredential,
    this.blockUntilClosed = false,
  });

  final Map<String, Object?> response;
  String? expectedCredential;
  final bool blockUntilClosed;

  final Completer<void> entered = Completer<void>();
  final Completer<void> _closedSignal = Completer<void>();
  Uri? endpoint;
  Map<String, String>? headers;
  Map<String, Object?>? payload;
  bool? allowLoopbackHttp;
  bool credentialMatched = false;
  int postCalls = 0;
  int closeCalls = 0;
  bool _closed = false;

  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Object? payload,
    required MayaLlmCancellationToken cancellation,
    required bool allowLoopbackHttp,
  }) async {
    postCalls++;
    if (_closed) {
      throw const MayaLlmException(MayaLlmFailureKind.cancelled);
    }
    cancellation.throwIfCancelled();
    this.endpoint = endpoint;
    this.allowLoopbackHttp = allowLoopbackHttp;
    this.payload = Map<String, Object?>.from(payload! as Map);

    final expected = expectedCredential;
    if (expected != null) {
      credentialMatched =
          headers['Authorization'] == 'Bearer $expected' ||
          headers['x-api-key'] == expected ||
          headers['x-goog-api-key'] == expected;
    }
    expectedCredential = null;
    this.headers = Map<String, String>.unmodifiable(<String, String>{
      for (final entry in headers.entries)
        entry.key: _isCredentialHeader(entry.key) ? '<redacted>' : entry.value,
    });

    if (blockUntilClosed) {
      if (!entered.isCompleted) entered.complete();
      await Future.any<void>(<Future<void>>[
        _closedSignal.future,
        cancellation.whenCancelled,
      ]);
      if (_closed) {
        throw const MayaLlmException(MayaLlmFailureKind.cancelled);
      }
      cancellation.throwIfCancelled();
    }
    return response;
  }

  @override
  Future<void> close() async {
    closeCalls++;
    _closed = true;
    if (!_closedSignal.isCompleted) _closedSignal.complete();
  }

  static bool _isCredentialHeader(String name) {
    return switch (name.toLowerCase()) {
      'authorization' || 'x-api-key' || 'x-goog-api-key' => true,
      _ => false,
    };
  }
}

final class _CountingCredentialStore implements MayaCredentialStore {
  final Map<String, String> _values = <String, String>{};
  int readCalls = 0;

  @override
  Future<void> save({
    required String providerId,
    required String apiKey,
  }) async {
    validateMayaCredentialProviderId(providerId);
    validateMayaApiKey(apiKey);
    _values[providerId] = apiKey;
  }

  @override
  Future<String?> read({required String providerId}) async {
    validateMayaCredentialProviderId(providerId);
    readCalls++;
    return _values[providerId];
  }

  @override
  Future<void> delete({required String providerId}) async {
    validateMayaCredentialProviderId(providerId);
    _values.remove(providerId);
  }
}

final class _ThrowingResponse extends MapBase<String, Object?> {
  @override
  Object? operator [](Object? key) {
    throw StateError('remote-body-secret-from-codec');
  }

  @override
  void operator []=(String key, Object? value) {
    throw UnsupportedError('read only');
  }

  @override
  void clear() {
    throw UnsupportedError('read only');
  }

  @override
  Iterable<String> get keys => const <String>[];

  @override
  Object? remove(Object? key) {
    throw UnsupportedError('read only');
  }
}
