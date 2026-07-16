import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_desktop/services/maya_credential_store.dart';
import 'package:yomu_desktop/services/maya_provider_controller.dart';
import 'package:yomu_storage/yomu_storage.dart';

Matcher _controllerError(MayaProviderControllerErrorCode code) =>
    isA<MayaProviderControllerException>().having(
      (error) => error.code,
      'code',
      code,
    );

bool _containsBytes(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  if (needle.length > haystack.length) return false;
  final lastStart = haystack.length - needle.length;
  for (var start = 0; start <= lastStart; start++) {
    var matches = true;
    for (var offset = 0; offset < needle.length; offset++) {
      if (haystack[start + offset] != needle[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

MayaLlmRequest _request({
  String text = 'pergunta para a Maya',
  Object? contextLease,
}) => MayaLlmRequest(
  currentUserText: text,
  history: const <MayaLlmMessage>[],
  library: const <MayaLlmLibraryItem>[],
  availableTools: const <MayaLlmTool>{},
  libraryAvailable: false,
  cancellation: MayaLlmCancellationToken(),
  contextLease: contextLease,
);

final class _CredentialStore implements MayaCredentialStore {
  final Map<String, String> values = <String, String>{};
  final List<String> events = <String>[];
  int saveCalls = 0;
  int readCalls = 0;
  int deleteCalls = 0;
  bool failSave = false;
  bool failRead = false;
  bool failDelete = false;
  String? Function(String providerId, String? stored)? readOverride;
  Future<void> Function(String providerId, String apiKey)? onSave;
  Future<void> Function(String providerId)? onDelete;
  Completer<void>? blockNextSave;
  Completer<String>? nextSaveStarted;

  @override
  Future<void> save({
    required String providerId,
    required String apiKey,
  }) async {
    saveCalls++;
    events.add('save:$providerId');
    validateMayaCredentialProviderId(providerId);
    validateMayaApiKey(apiKey);
    final saveStarted = nextSaveStarted;
    nextSaveStarted = null;
    saveStarted?.complete(providerId);
    if (failSave) throw StateError('raw-secret-write-failure');
    final blocker = blockNextSave;
    blockNextSave = null;
    if (blocker != null) await blocker.future;
    await onSave?.call(providerId, apiKey);
    values[providerId] = apiKey;
  }

  @override
  Future<String?> read({required String providerId}) async {
    readCalls++;
    events.add('read:$providerId');
    validateMayaCredentialProviderId(providerId);
    if (failRead) throw StateError('raw-secret-read-failure');
    final stored = values[providerId];
    return readOverride?.call(providerId, stored) ?? stored;
  }

  @override
  Future<void> delete({required String providerId}) async {
    deleteCalls++;
    events.add('delete:$providerId');
    validateMayaCredentialProviderId(providerId);
    await onDelete?.call(providerId);
    if (failDelete) throw StateError('raw-secret-delete-failure');
    values.remove(providerId);
  }
}

class _Adapter implements MayaLlmProvider {
  _Adapter({this.rawCompleteFailure});

  final Object? rawCompleteFailure;
  MayaLlmRequest? request;
  int completeCalls = 0;
  int closeCalls = 0;
  bool closed = false;

  @override
  MayaLlmContextPolicy get contextPolicy =>
      const MayaLlmContextPolicy.disabled();

  @override
  Future<MayaLlmResponse> complete(MayaLlmRequest request) async {
    this.request = request;
    completeCalls++;
    final failure = rawCompleteFailure;
    if (failure != null) throw failure;
    return MayaLlmResponse(text: 'provider response');
  }

  @override
  Future<void> close() async {
    closeCalls++;
    closed = true;
  }
}

final class _BlockingLibraryPort implements MayaLibraryPort {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();
  int listCalls = 0;

  @override
  Future<List<MayaLibraryItem>> listLibrary() async {
    listCalls++;
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return const <MayaLibraryItem>[
      MayaLibraryItem(
        id: 7,
        title: 'Biblioteca privada do teste',
        unreadCount: 2,
        lastChapterId: 99,
        lastChapterName: 'Capítulo 99',
      ),
    ];
  }

  @override
  Future<void> enqueueChapterDownload(int chapterId) async {}

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {}
}

final class _CredentialReadingAdapter extends _Adapter {
  _CredentialReadingAdapter(this.readCredential);

  final MayaProviderCredentialReader readCredential;
  bool receivedCredential = false;

  @override
  Future<MayaLlmResponse> complete(MayaLlmRequest request) async {
    completeCalls++;
    final credential = await readCredential();
    receivedCredential = credential != null;
    if (credential == null) {
      throw const MayaLlmException(MayaLlmFailureKind.configuration);
    }
    return MayaLlmResponse(text: 'credential-backed response');
  }
}

final class _BlockingAdapter extends _Adapter {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();
  final Completer<void> closeEntered = Completer<void>();

  @override
  Future<MayaLlmResponse> complete(MayaLlmRequest request) async {
    completeCalls++;
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return MayaLlmResponse(text: 'stale response');
  }

  @override
  Future<void> close() async {
    closeCalls++;
    closed = true;
    if (!closeEntered.isCompleted) closeEntered.complete();
  }
}

final class _FactoryCall {
  const _FactoryCall({
    required this.settings,
    required this.readCredential,
    required this.adapter,
  });

  final MayaProviderAdapterSettings settings;
  final MayaProviderCredentialReader readCredential;
  final MayaLlmProvider adapter;
}

final class _AdapterFactory {
  final List<_FactoryCall> calls = <_FactoryCall>[];
  MayaLlmProvider Function(
    MayaProviderAdapterSettings settings,
    MayaProviderCredentialReader readCredential,
  )?
  builder;
  Object? failure;
  bool probeCredentialDuringFactory = false;
  Object? credentialProbeFailure;

  Future<MayaLlmProvider> call({
    required MayaProviderAdapterSettings settings,
    required MayaProviderCredentialReader readCredential,
  }) async {
    final rawFailure = failure;
    if (rawFailure != null) throw rawFailure;
    if (probeCredentialDuringFactory) {
      try {
        await readCredential();
      } catch (error) {
        credentialProbeFailure = error;
      }
    }
    final adapter = builder?.call(settings, readCredential) ?? _Adapter();
    calls.add(
      _FactoryCall(
        settings: settings,
        readCredential: readCredential,
        adapter: adapter,
      ),
    );
    return adapter;
  }
}

final class _Fixture {
  _Fixture._({
    required this.root,
    required this.database,
    required this.credentials,
    required this.adapters,
  });

  static Future<_Fixture> create() async {
    final root = Directory.systemTemp.createTempSync(
      'yomu-provider-controller-',
    );
    return _Fixture._(
      root: root,
      database: await YomuDatabase.openForTest(root, useProcessLock: false),
      credentials: _CredentialStore(),
      adapters: _AdapterFactory(),
    );
  }

  final Directory root;
  YomuDatabase database;
  final _CredentialStore credentials;
  final _AdapterFactory adapters;
  final List<MayaProviderController> controllers = <MayaProviderController>[];
  int _clockTick = 0;

  DateTime clock() =>
      DateTime.utc(2026, 7, 16).add(Duration(milliseconds: _clockTick++));

  Future<MayaProviderController> openController({
    MayaCredentialStore? credentialStore,
  }) async {
    final controller = await MayaProviderController.open(
      database: database,
      credentialStore: credentialStore ?? credentials,
      adapterFactory: adapters.call,
      clock: clock,
    );
    controllers.add(controller);
    return controller;
  }

  Future<void> reopenDatabase() async {
    try {
      await database.close();
    } catch (_) {}
    database = await YomuDatabase.openForTest(root, useProcessLock: false);
  }

  Future<void> close() async {
    for (final controller in controllers.reversed) {
      try {
        await controller.close();
      } catch (_) {}
    }
    try {
      await database.close();
    } catch (_) {}
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  }
}

void main() {
  test(
    'open loads unset, explicit local, and cloud settings on restart',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);

      final first = await fixture.openController();
      expect(first.status, MayaProviderControllerStatus.unset);
      expect(first.settings, isNull);
      expect(first.contextPolicy.enabled, isFalse);

      await first.saveLocal();
      expect(first.status, MayaProviderControllerStatus.local);
      expect(first.settings?.mode, MayaProviderMode.local);
      expect(first.contextPolicy.enabled, isFalse);
      await first.close();

      final second = await fixture.openController();
      expect(second.status, MayaProviderControllerStatus.local);
      await second.saveCloud(
        providerId: 'openai',
        modelPolicy: MayaProviderModelPolicy.providerDefault,
        apiKey: 'sk-restart-value',
        shareRecentHistory: true,
        shareLibraryContext: false,
      );
      expect(second.status, MayaProviderControllerStatus.cloudReady);
      expect(second.contextPolicy.enabled, isTrue);
      expect(second.contextPolicy.shareRecentHistory, isTrue);
      expect(second.contextPolicy.shareLibraryContext, isFalse);
      await second.close();

      final third = await fixture.openController();
      expect(third.status, MayaProviderControllerStatus.cloudReady);
      expect(third.settings?.providerId, 'openai');
      expect(third.contextPolicy.shareRecentHistory, isTrue);
      expect(fixture.credentials.readCalls, 3);
    },
  );

  test(
    'allowlist, model rules, cloud keys, and Ollama are fail closed',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final controller = await fixture.openController();

      expect(kSupportedMayaProviderIds, const <String>{
        'openai',
        'anthropic',
        'gemini',
        'ollama',
      });
      await expectLater(
        controller.saveCloud(
          providerId: 'cohere',
          modelPolicy: MayaProviderModelPolicy.providerDefault,
          apiKey: 'secret-that-must-not-appear',
          shareRecentHistory: false,
          shareLibraryContext: false,
        ),
        throwsA(
          _controllerError(MayaProviderControllerErrorCode.unsupportedProvider),
        ),
      );
      await expectLater(
        controller.saveCloud(
          providerId: 'openai',
          modelPolicy: MayaProviderModelPolicy.explicit,
          shareRecentHistory: false,
          shareLibraryContext: false,
        ),
        throwsA(
          _controllerError(
            MayaProviderControllerErrorCode.invalidConfiguration,
          ),
        ),
      );
      await expectLater(
        controller.saveCloud(
          providerId: 'openai',
          modelPolicy: MayaProviderModelPolicy.providerDefault,
          shareRecentHistory: false,
          shareLibraryContext: false,
        ),
        throwsA(
          _controllerError(MayaProviderControllerErrorCode.missingCredential),
        ),
      );
      final disabledMissing = await fixture.database.getMayaProviderSettings();
      expect(disabledMissing?.providerId, 'openai');
      expect(disabledMissing?.isEnabled, isFalse);
      expect(controller.status, MayaProviderControllerStatus.disabled);
      expect(controller.contextPolicy.enabled, isFalse);

      final savesBeforeOllama = fixture.credentials.saveCalls;
      final readsBeforeOllama = fixture.credentials.readCalls;
      await controller.saveCloud(
        providerId: 'ollama',
        modelPolicy: MayaProviderModelPolicy.explicit,
        modelId: 'llama-test',
        apiKey: 'ignored-ollama-key',
        shareRecentHistory: false,
        shareLibraryContext: true,
      );
      expect(controller.status, MayaProviderControllerStatus.cloudReady);
      expect(fixture.credentials.saveCalls, savesBeforeOllama);
      expect(fixture.credentials.readCalls, readsBeforeOllama);
      expect(await fixture.adapters.calls.last.readCredential(), isNull);
      expect(fixture.credentials.readCalls, readsBeforeOllama);
      expect(
        controller.settings?.consentVersion,
        kCurrentMayaProviderConsentVersion,
      );
    },
  );

  test(
    'credential is factory-guarded and read only during a request',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      fixture.adapters.probeCredentialDuringFactory = true;
      late _CredentialReadingAdapter adapter;
      fixture.adapters.builder = (_, readCredential) {
        return adapter = _CredentialReadingAdapter(readCredential);
      };
      final controller = await fixture.openController();

      await controller.saveCloud(
        providerId: 'openai',
        modelPolicy: MayaProviderModelPolicy.providerDefault,
        apiKey: 'sk-jit-only',
        shareRecentHistory: false,
        shareLibraryContext: false,
      );

      expect(
        fixture.adapters.credentialProbeFailure,
        isA<MayaLlmException>().having(
          (error) => error.kind,
          'kind',
          MayaLlmFailureKind.cancelled,
        ),
      );
      expect(fixture.credentials.readCalls, 2);
      await expectLater(
        fixture.adapters.calls.single.readCredential(),
        throwsA(
          isA<MayaLlmException>().having(
            (error) => error.kind,
            'kind',
            MayaLlmFailureKind.cancelled,
          ),
        ),
      );
      expect(fixture.credentials.readCalls, 2);

      final response = await controller.complete(
        _request(contextLease: controller.contextPolicy.contextLease),
      );

      expect(response.text, 'credential-backed response');
      expect(adapter.receivedCredential, isTrue);
      expect(fixture.credentials.readCalls, 3);
      expect(
        fixture.adapters.calls.single.settings.toString(),
        isNot(contains('sk-jit-only')),
      );
    },
  );

  test('blank key edit preserves and reuses the existing credential', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final controller = await fixture.openController();

    await controller.saveCloud(
      providerId: 'anthropic',
      modelPolicy: MayaProviderModelPolicy.providerDefault,
      apiKey: 'sk-ant-existing',
      shareRecentHistory: false,
      shareLibraryContext: false,
    );
    final firstAdapter = fixture.adapters.calls.last.adapter as _Adapter;
    expect(fixture.credentials.saveCalls, 1);

    await controller.saveCloud(
      providerId: 'anthropic',
      modelPolicy: MayaProviderModelPolicy.explicit,
      modelId: 'claude-test',
      apiKey: '   ',
      shareRecentHistory: true,
      shareLibraryContext: true,
    );

    expect(fixture.credentials.saveCalls, 1);
    expect(fixture.credentials.values['anthropic'], 'sk-ant-existing');
    expect(fixture.credentials.readCalls, 3);
    expect(firstAdapter.closed, isTrue);
    expect(controller.settings?.modelId, 'claude-test');
  });

  test(
    'disabled DB barrier survives credential and persistence failures',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final controller = await fixture.openController();

      fixture.credentials.readOverride = (_, stored) =>
          stored == 'gemini-original' ? 'different-readback' : stored;
      await expectLater(
        controller.saveCloud(
          providerId: 'gemini',
          modelPolicy: MayaProviderModelPolicy.providerDefault,
          apiKey: 'gemini-original',
          shareRecentHistory: false,
          shareLibraryContext: false,
        ),
        throwsA(
          _controllerError(MayaProviderControllerErrorCode.credentialFailure),
        ),
      );
      final disabledGemini = await fixture.database.getMayaProviderSettings();
      expect(disabledGemini?.providerId, 'gemini');
      expect(disabledGemini?.isEnabled, isFalse);
      expect(controller.status, MayaProviderControllerStatus.disabled);

      fixture.credentials.readOverride = null;
      await fixture.database.close();
      await expectLater(
        controller.saveCloud(
          providerId: 'openai',
          modelPolicy: MayaProviderModelPolicy.providerDefault,
          apiKey: 'sk-rolled-back-after-db-failure',
          shareRecentHistory: true,
          shareLibraryContext: true,
        ),
        throwsA(
          _controllerError(MayaProviderControllerErrorCode.persistenceFailure),
        ),
      );
      expect(controller.status, MayaProviderControllerStatus.disabled);
      expect(controller.contextPolicy.enabled, isFalse);
      expect(fixture.credentials.values['openai'], isNull);

      await fixture.reopenDatabase();
      final reopened = await fixture.database.getMayaProviderSettings();
      expect(reopened?.providerId, 'gemini');
      expect(reopened?.isEnabled, isFalse);
    },
  );

  test('same-provider DB failure restores the prior credential', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final controller = await fixture.openController();
    await controller.saveCloud(
      providerId: 'openai',
      modelPolicy: MayaProviderModelPolicy.explicit,
      modelId: 'gpt-old',
      apiKey: 'sk-prior-value',
      shareRecentHistory: false,
      shareLibraryContext: false,
    );

    await fixture.database.close();
    await expectLater(
      controller.saveCloud(
        providerId: 'openai',
        modelPolicy: MayaProviderModelPolicy.explicit,
        modelId: 'gpt-new',
        apiKey: 'sk-new-value',
        shareRecentHistory: true,
        shareLibraryContext: true,
      ),
      throwsA(
        _controllerError(MayaProviderControllerErrorCode.persistenceFailure),
      ),
    );

    expect(fixture.credentials.values['openai'], 'sk-prior-value');
    expect(controller.settings?.modelId, 'gpt-old');
    expect(controller.status, MayaProviderControllerStatus.cloudReady);
  });

  test(
    'restart fails closed for missing credential and stale consent',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final settings = MayaProviderSettings.cloud(
        providerId: 'openai',
        modelPolicy: MayaProviderModelPolicy.providerDefault,
        shareRecentHistory: true,
        shareLibraryContext: true,
        consentVersion: kCurrentMayaProviderConsentVersion,
        consentedAtMs: 1,
        updatedAtMs: 1,
      );
      await fixture.database.setMayaProviderSettings(settings);

      final missing = await fixture.openController();
      expect(missing.status, MayaProviderControllerStatus.missingCredential);
      expect(missing.contextPolicy.enabled, isFalse);
      expect(missing.contextPolicy.shareRecentHistory, isFalse);
      expect(missing.contextPolicy.shareLibraryContext, isFalse);
      expect(fixture.adapters.calls, isEmpty);
      await expectLater(
        missing.complete(_request()),
        throwsA(
          isA<MayaLlmException>().having(
            (error) => error.kind,
            'kind',
            MayaLlmFailureKind.configuration,
          ),
        ),
      );
      await missing.close();

      await fixture.database.customStatement(
        'UPDATE maya_provider_settings SET consent_version = 99',
      );
      fixture.credentials.values['openai'] = 'sk-present-but-stale-consent';
      final stale = await fixture.openController();
      expect(stale.status, MayaProviderControllerStatus.consentRequired);
      expect(stale.contextPolicy.enabled, isFalse);
      expect(fixture.adapters.calls, isEmpty);
    },
  );

  test('switch cancels in-flight work and discards a stale response', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final blocking = _BlockingAdapter();
    addTearDown(() {
      if (!blocking.release.isCompleted) blocking.release.complete();
    });
    fixture.adapters.builder = (_, _) => blocking;
    final controller = await fixture.openController();
    await controller.saveCloud(
      providerId: 'openai',
      modelPolicy: MayaProviderModelPolicy.providerDefault,
      apiKey: 'sk-stale-test',
      shareRecentHistory: false,
      shareLibraryContext: false,
    );

    final request = _request(
      contextLease: controller.contextPolicy.contextLease,
    );
    final completion = controller.complete(request);
    await blocking.entered.future;
    final switchToLocal = controller.saveLocal();
    await blocking.closeEntered.future;
    expect(request.cancellation.isCancelled, isTrue);
    blocking.release.complete();

    await expectLater(
      completion,
      throwsA(
        isA<MayaLlmException>().having(
          (error) => error.kind,
          'kind',
          MayaLlmFailureKind.cancelled,
        ),
      ),
    );
    await switchToLocal;
    expect(controller.status, MayaProviderControllerStatus.local);
    expect(controller.contextPolicy.enabled, isFalse);
  });

  test(
    'switch invalidates a response before credential and DB writes finish',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final blocking = _BlockingAdapter();
      addTearDown(() {
        if (!blocking.release.isCompleted) blocking.release.complete();
      });
      fixture.adapters.builder = (_, _) {
        return fixture.adapters.calls.isEmpty ? blocking : _Adapter();
      };
      final controller = await fixture.openController();
      await controller.saveCloud(
        providerId: 'openai',
        modelPolicy: MayaProviderModelPolicy.providerDefault,
        apiKey: 'sk-before-pending-switch',
        shareRecentHistory: false,
        shareLibraryContext: false,
      );

      final request = _request(
        contextLease: controller.contextPolicy.contextLease,
      );
      final completion = controller.complete(request);
      await blocking.entered.future;

      final saveStarted = Completer<String>();
      final releaseSave = Completer<void>();
      addTearDown(() {
        if (!releaseSave.isCompleted) releaseSave.complete();
      });
      fixture.credentials.nextSaveStarted = saveStarted;
      fixture.credentials.blockNextSave = releaseSave;
      var switchCompleted = false;
      final switching = controller
          .saveCloud(
            providerId: 'anthropic',
            modelPolicy: MayaProviderModelPolicy.providerDefault,
            apiKey: 'sk-after-pending-switch',
            shareRecentHistory: true,
            shareLibraryContext: true,
          )
          .whenComplete(() => switchCompleted = true);

      expect(request.cancellation.isCancelled, isTrue);
      expect(controller.contextPolicy.enabled, isFalse);
      await expectLater(
        controller.complete(_request(text: 'não enviar durante a troca')),
        throwsA(
          isA<MayaLlmException>().having(
            (error) => error.kind,
            'kind',
            MayaLlmFailureKind.unavailable,
          ),
        ),
      );
      expect(blocking.completeCalls, 1);
      await blocking.closeEntered.future;
      expect(switchCompleted, isFalse);
      blocking.release.complete();
      await expectLater(
        completion,
        throwsA(
          isA<MayaLlmException>().having(
            (error) => error.kind,
            'kind',
            MayaLlmFailureKind.cancelled,
          ),
        ),
      );

      expect(await saveStarted.future, 'anthropic');
      expect(switchCompleted, isFalse);

      releaseSave.complete();
      await switching;
      expect(controller.settings?.providerId, 'anthropic');
    },
  );

  test(
    'service rejects context prepared under provider A after switch to B',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final adapters = <_Adapter>[];
      fixture.adapters.builder = (_, _) {
        final adapter = _Adapter();
        adapters.add(adapter);
        return adapter;
      };
      final controller = await fixture.openController();
      await controller.saveCloud(
        providerId: 'openai',
        modelPolicy: MayaProviderModelPolicy.explicit,
        modelId: 'gpt-policy-a',
        apiKey: 'sk-policy-a',
        shareRecentHistory: true,
        shareLibraryContext: true,
      );
      final leaseA = controller.contextPolicy.contextLease;
      expect(leaseA, isNotNull);

      final port = _BlockingLibraryPort();
      final maya = MayaService(
        store: MayaStore.inMemory(),
        libraryPort: port,
        llm: controller,
      );
      addTearDown(() async {
        if (!port.release.isCompleted) port.release.complete();
        await maya.close();
      });
      final completion = maya.sendUserMessage('mostre minha biblioteca');
      await port.entered.future;

      await controller.saveCloud(
        providerId: 'anthropic',
        modelPolicy: MayaProviderModelPolicy.explicit,
        modelId: 'claude-policy-b',
        apiKey: 'sk-policy-b',
        shareRecentHistory: false,
        shareLibraryContext: false,
      );
      final leaseB = controller.contextPolicy.contextLease;
      expect(leaseB, isNotNull);
      expect(identical(leaseA, leaseB), isFalse);

      port.release.complete();
      final turn = await completion;

      expect(turn.origin, MayaResponseOrigin.localFallback);
      expect(port.listCalls, 1);
      expect(adapters, hasLength(2));
      expect(adapters[0].completeCalls, 0);
      expect(adapters[1].completeCalls, 0);
      expect(adapters[0].request, isNull);
      expect(adapters[1].request, isNull);
    },
  );

  test(
    'service rejects stale context after same-provider consent downgrade',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final adapters = <_Adapter>[];
      fixture.adapters.builder = (_, _) {
        final adapter = _Adapter();
        adapters.add(adapter);
        return adapter;
      };
      final controller = await fixture.openController();
      await controller.saveCloud(
        providerId: 'openai',
        modelPolicy: MayaProviderModelPolicy.explicit,
        modelId: 'gpt-consent-old',
        apiKey: 'sk-consent-stable',
        shareRecentHistory: true,
        shareLibraryContext: true,
      );
      final permissiveLease = controller.contextPolicy.contextLease;
      expect(permissiveLease, isNotNull);

      final port = _BlockingLibraryPort();
      final maya = MayaService(
        store: MayaStore.inMemory(),
        libraryPort: port,
        llm: controller,
      );
      addTearDown(() async {
        if (!port.release.isCompleted) port.release.complete();
        await maya.close();
      });
      final completion = maya.sendUserMessage('use meu contexto privado');
      await port.entered.future;

      await controller.saveCloud(
        providerId: 'openai',
        modelPolicy: MayaProviderModelPolicy.explicit,
        modelId: 'gpt-consent-new',
        shareRecentHistory: false,
        shareLibraryContext: false,
      );
      final restrictedLease = controller.contextPolicy.contextLease;
      expect(restrictedLease, isNotNull);
      expect(identical(permissiveLease, restrictedLease), isFalse);

      port.release.complete();
      final turn = await completion;

      expect(turn.origin, MayaResponseOrigin.localFallback);
      expect(port.listCalls, 1);
      expect(adapters, hasLength(2));
      expect(adapters[0].completeCalls, 0);
      expect(adapters[1].completeCalls, 0);
      expect(adapters[0].request, isNull);
      expect(adapters[1].request, isNull);
    },
  );

  test(
    'concurrent saves are serialized and leave one complete snapshot',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final controller = await fixture.openController();
      final releaseFirst = Completer<void>();
      addTearDown(() {
        if (!releaseFirst.isCompleted) releaseFirst.complete();
      });
      final firstSaveStarted = Completer<String>();
      fixture.credentials.blockNextSave = releaseFirst;
      fixture.credentials.nextSaveStarted = firstSaveStarted;

      final first = controller.saveCloud(
        providerId: 'openai',
        modelPolicy: MayaProviderModelPolicy.providerDefault,
        apiKey: 'sk-first',
        shareRecentHistory: false,
        shareLibraryContext: false,
      );
      expect(await firstSaveStarted.future, 'openai');
      final second = controller.saveCloud(
        providerId: 'anthropic',
        modelPolicy: MayaProviderModelPolicy.explicit,
        modelId: 'claude-final',
        apiKey: 'sk-second',
        shareRecentHistory: true,
        shareLibraryContext: true,
      );

      expect(fixture.credentials.events, <String>[
        'read:openai',
        'save:openai',
      ]);
      releaseFirst.complete();
      await Future.wait<void>(<Future<void>>[first, second]);

      final persisted = await fixture.database.getMayaProviderSettings();
      expect(persisted?.providerId, 'anthropic');
      expect(persisted?.modelId, 'claude-final');
      expect(persisted?.shareRecentHistory, isTrue);
      expect(persisted?.shareLibraryContext, isTrue);
      expect(controller.status, MayaProviderControllerStatus.cloudReady);
      expect((fixture.adapters.calls.first.adapter as _Adapter).closed, isTrue);
    },
  );

  test(
    'remove closes, preserves settings on cleanup failure, and can retry',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final controller = await fixture.openController();
      await controller.saveCloud(
        providerId: 'openai',
        modelPolicy: MayaProviderModelPolicy.providerDefault,
        apiKey: 'sk-remove-order',
        shareRecentHistory: true,
        shareLibraryContext: false,
      );
      final adapter = fixture.adapters.calls.last.adapter as _Adapter;
      fixture.credentials.onDelete = (_) async {
        final persisted = await fixture.database.getMayaProviderSettings();
        expect(persisted?.mode, MayaProviderMode.cloud);
        expect(persisted?.isEnabled, isFalse);
        expect(adapter.closed, isTrue);
        throw StateError('raw-delete-secret-sk-remove-order');
      };

      Object? failure;
      try {
        await controller.removeProvider();
      } catch (error) {
        failure = error;
      }
      expect(
        failure,
        _controllerError(MayaProviderControllerErrorCode.credentialFailure),
      );
      expect('$failure', isNot(contains('sk-remove-order')));
      expect('$failure', isNot(contains('raw-delete')));
      expect(controller.status, MayaProviderControllerStatus.disabled);
      expect(controller.settings?.providerId, 'openai');
      expect(controller.settings?.isEnabled, isFalse);
      expect(controller.contextPolicy.enabled, isFalse);
      expect(fixture.credentials.values['openai'], 'sk-remove-order');

      fixture.credentials.onDelete = null;
      await controller.removeProvider();
      expect(controller.status, MayaProviderControllerStatus.local);
      expect(controller.contextPolicy.enabled, isFalse);
      expect(fixture.credentials.values, isEmpty);
    },
  );

  test('reset stores unset and deletes only after adapter shutdown', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final controller = await fixture.openController();
    await controller.saveCloud(
      providerId: 'gemini',
      modelPolicy: MayaProviderModelPolicy.providerDefault,
      apiKey: 'gemini-reset-key',
      shareRecentHistory: false,
      shareLibraryContext: true,
    );
    final adapter = fixture.adapters.calls.last.adapter as _Adapter;
    fixture.credentials.values['openai'] = 'old-openai-key';
    fixture.credentials.values['anthropic'] = 'old-anthropic-key';
    fixture.credentials.onDelete = (_) async {
      expect(
        (await fixture.database.getMayaProviderSettings())?.providerId,
        'gemini',
      );
      expect(adapter.closed, isTrue);
    };

    await controller.reset();
    expect(controller.status, MayaProviderControllerStatus.unset);
    expect(controller.settings, isNull);
    expect(fixture.credentials.values, isEmpty);
    expect(
      fixture.credentials.events.where((event) => event.startsWith('delete:')),
      <String>['delete:openai', 'delete:anthropic', 'delete:gemini'],
    );
  });

  test('saveLocal blocks new provider admission synchronously', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final adapter = _Adapter();
    fixture.adapters.builder = (_, _) => adapter;
    final controller = await fixture.openController();
    await controller.saveCloud(
      providerId: 'openai',
      modelPolicy: MayaProviderModelPolicy.explicit,
      modelId: 'gpt-transition',
      apiKey: 'sk-transition',
      shareRecentHistory: true,
      shareLibraryContext: true,
    );

    final transition = controller.saveLocal();
    expect(controller.contextPolicy.enabled, isFalse);
    await expectLater(
      controller.complete(_request()),
      throwsA(
        isA<MayaLlmException>().having(
          (error) => error.kind,
          'kind',
          MayaLlmFailureKind.unavailable,
        ),
      ),
    );
    expect(adapter.completeCalls, 0);
    await transition;
    expect(controller.status, MayaProviderControllerStatus.local);
  });

  test('remove blocks admission and DB failure remains retryable', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final adapter = _Adapter();
    fixture.adapters.builder = (_, _) => adapter;
    final controller = await fixture.openController();
    await controller.saveCloud(
      providerId: 'openai',
      modelPolicy: MayaProviderModelPolicy.explicit,
      modelId: 'gpt-remove',
      apiKey: 'sk-remove-db-failure',
      shareRecentHistory: true,
      shareLibraryContext: false,
    );

    await fixture.database.close();
    final removal = controller.removeProvider();
    expect(controller.contextPolicy.enabled, isFalse);
    await expectLater(
      controller.complete(_request()),
      throwsA(
        isA<MayaLlmException>().having(
          (error) => error.kind,
          'kind',
          MayaLlmFailureKind.unavailable,
        ),
      ),
    );
    await expectLater(
      removal,
      throwsA(
        _controllerError(MayaProviderControllerErrorCode.persistenceFailure),
      ),
    );
    expect(adapter.closed, isTrue);
    expect(controller.settings?.providerId, 'openai');
    expect(controller.status, MayaProviderControllerStatus.missingCredential);
    expect(fixture.credentials.values, isEmpty);

    await controller.close();
    await fixture.reopenDatabase();
    final retry = await fixture.openController();
    expect(retry.status, MayaProviderControllerStatus.missingCredential);
    await retry.removeProvider();
    expect(retry.status, MayaProviderControllerStatus.local);
    expect(
      (await fixture.database.getMayaProviderSettings())?.mode,
      MayaProviderMode.local,
    );
  });

  test('failed current-key deletion remains disabled after restart', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final controller = await fixture.openController();
    await controller.saveCloud(
      providerId: 'openai',
      modelPolicy: MayaProviderModelPolicy.explicit,
      modelId: 'gpt-remove-restart',
      apiKey: 'sk-remove-restart',
      shareRecentHistory: true,
      shareLibraryContext: true,
    );
    final adapterCallsBeforeRemoval = fixture.adapters.calls.length;
    fixture.credentials.onDelete = (providerId) async {
      if (providerId == 'openai') {
        throw StateError('raw-current-delete-failure');
      }
    };

    await expectLater(
      controller.removeProvider(),
      throwsA(
        _controllerError(MayaProviderControllerErrorCode.credentialFailure),
      ),
    );
    final persisted = await fixture.database.getMayaProviderSettings();
    expect(persisted?.mode, MayaProviderMode.cloud);
    expect(persisted?.providerId, 'openai');
    expect(persisted?.isEnabled, isFalse);
    expect(controller.settings?.isEnabled, isFalse);
    expect(controller.status, MayaProviderControllerStatus.disabled);
    expect(controller.contextPolicy.enabled, isFalse);
    expect(fixture.credentials.values['openai'], 'sk-remove-restart');

    await controller.close();
    await fixture.reopenDatabase();
    final reopened = await fixture.openController();
    expect(reopened.settings?.isEnabled, isFalse);
    expect(reopened.status, MayaProviderControllerStatus.disabled);
    expect(reopened.contextPolicy.enabled, isFalse);
    expect(fixture.adapters.calls.length, adapterCallsBeforeRemoval);
  });

  test(
    'failed credential rollback remains durably disabled after reopen',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final controller = await fixture.openController();
      await controller.saveCloud(
        providerId: 'openai',
        modelPolicy: MayaProviderModelPolicy.explicit,
        modelId: 'gpt-rollback-old',
        apiKey: 'sk-rollback-old',
        shareRecentHistory: true,
        shareLibraryContext: true,
      );
      final adapterCallsBeforeFailure = fixture.adapters.calls.length;
      fixture.credentials.onSave = (providerId, apiKey) async {
        if (providerId == 'openai' && apiKey == 'sk-rollback-old') {
          throw StateError('raw-rollback-write-failure');
        }
      };
      await fixture.database.customStatement('''
        CREATE TRIGGER fail_enabled_provider_candidate
        BEFORE UPDATE ON maya_provider_settings
        WHEN NEW.is_enabled = 1
          AND NEW.model_id = 'gpt-rollback-new'
        BEGIN
          SELECT RAISE(FAIL, 'test provider persistence failure');
        END
      ''');

      await expectLater(
        controller.saveCloud(
          providerId: 'openai',
          modelPolicy: MayaProviderModelPolicy.explicit,
          modelId: 'gpt-rollback-new',
          apiKey: 'sk-rollback-new',
          shareRecentHistory: false,
          shareLibraryContext: false,
        ),
        throwsA(
          _controllerError(MayaProviderControllerErrorCode.persistenceFailure),
        ),
      );
      await fixture.database.customStatement(
        'DROP TRIGGER fail_enabled_provider_candidate',
      );

      final persisted = await fixture.database.getMayaProviderSettings();
      expect(persisted?.mode, MayaProviderMode.cloud);
      expect(persisted?.providerId, 'openai');
      expect(persisted?.isEnabled, isFalse);
      expect(controller.settings?.isEnabled, isFalse);
      expect(controller.status, MayaProviderControllerStatus.disabled);
      expect(controller.contextPolicy.enabled, isFalse);
      expect(fixture.credentials.values['openai'], 'sk-rollback-new');

      await controller.close();
      await fixture.reopenDatabase();
      final reopened = await fixture.openController();
      expect(reopened.settings?.isEnabled, isFalse);
      expect(reopened.status, MayaProviderControllerStatus.disabled);
      expect(reopened.contextPolicy.enabled, isFalse);
      expect(fixture.adapters.calls.length, adapterCallsBeforeFailure);
    },
  );

  test(
    'API key bytes never enter SQLite, WAL, SHM, lock, or log files',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final controller = await fixture.openController();
      const secret = 'sk-file-audit-unique-7f4b2c91';

      await controller.saveCloud(
        providerId: 'openai',
        modelPolicy: MayaProviderModelPolicy.explicit,
        modelId: 'gpt-file-audit',
        apiKey: secret,
        shareRecentHistory: true,
        shareLibraryContext: true,
      );
      await fixture.database.customStatement(
        "INSERT OR REPLACE INTO app_meta(key, value, updated_at_ms) "
        "VALUES ('provider.file.audit', 'complete', 1)",
      );

      final needle = secret.codeUnits;
      final files = fixture.root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>();
      for (final file in files) {
        final bytes = await file.readAsBytes();
        expect(
          _containsBytes(bytes, needle),
          isFalse,
          reason: 'plaintext found in ${file.path}',
        );
      }
    },
  );

  test(
    'close is idempotent, aborts in-flight work, and rejects new calls',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final blocking = _BlockingAdapter();
      addTearDown(() {
        if (!blocking.release.isCompleted) blocking.release.complete();
      });
      fixture.adapters.builder = (_, _) => blocking;
      final controller = await fixture.openController();
      await controller.saveCloud(
        providerId: 'openai',
        modelPolicy: MayaProviderModelPolicy.providerDefault,
        apiKey: 'sk-close-test',
        shareRecentHistory: false,
        shareLibraryContext: false,
      );

      final request = _request(
        contextLease: controller.contextPolicy.contextLease,
      );
      final completion = controller.complete(request);
      await blocking.entered.future;
      final firstClose = controller.close();
      final secondClose = controller.close();
      expect(identical(firstClose, secondClose), isTrue);
      await blocking.closeEntered.future;
      expect(request.cancellation.isCancelled, isTrue);
      blocking.release.complete();
      await expectLater(completion, throwsA(isA<MayaLlmException>()));
      await firstClose;

      expect(controller.status, MayaProviderControllerStatus.closed);
      expect(blocking.closeCalls, 1);
      await expectLater(
        controller.complete(_request()),
        throwsA(
          isA<MayaLlmException>().having(
            (error) => error.kind,
            'kind',
            MayaLlmFailureKind.cancelled,
          ),
        ),
      );
      await expectLater(
        controller.saveLocal(),
        throwsA(_controllerError(MayaProviderControllerErrorCode.closed)),
      );
    },
  );

  test('adapter and factory failures stay typed and sanitized', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    fixture.adapters.builder = (_, _) =>
        _Adapter(rawCompleteFailure: StateError('remote-body sk-super-secret'));
    final controller = await fixture.openController();
    await controller.saveCloud(
      providerId: 'openai',
      modelPolicy: MayaProviderModelPolicy.providerDefault,
      apiKey: 'sk-super-secret',
      shareRecentHistory: false,
      shareLibraryContext: false,
    );

    Object? completeFailure;
    try {
      await controller.complete(
        _request(contextLease: controller.contextPolicy.contextLease),
      );
    } catch (error) {
      completeFailure = error;
    }
    expect(
      completeFailure,
      isA<MayaLlmException>().having(
        (error) => error.kind,
        'kind',
        MayaLlmFailureKind.providerFailure,
      ),
    );
    expect('$completeFailure', isNot(contains('sk-super-secret')));
    expect('$completeFailure', isNot(contains('remote-body')));

    fixture.adapters.failure = StateError('factory-secret-sk-super-secret');
    Object? factoryFailure;
    try {
      await controller.saveCloud(
        providerId: 'anthropic',
        modelPolicy: MayaProviderModelPolicy.providerDefault,
        apiKey: 'sk-anthropic-secret',
        shareRecentHistory: false,
        shareLibraryContext: false,
      );
    } catch (error) {
      factoryFailure = error;
    }
    expect(
      factoryFailure,
      _controllerError(MayaProviderControllerErrorCode.adapterFailure),
    );
    expect('$factoryFailure', isNot(contains('secret')));
    expect(controller.status, MayaProviderControllerStatus.adapterUnavailable);
    expect(controller.contextPolicy.enabled, isFalse);
    expect(controller.contextPolicy.shareRecentHistory, isFalse);
    expect(controller.contextPolicy.shareLibraryContext, isFalse);
    final priorAdapter = fixture.adapters.calls.single.adapter as _Adapter;
    final priorCompleteCalls = priorAdapter.completeCalls;
    await expectLater(
      controller.complete(_request(text: 'não enviar ao adapter anterior')),
      throwsA(
        isA<MayaLlmException>().having(
          (error) => error.kind,
          'kind',
          MayaLlmFailureKind.configuration,
        ),
      ),
    );
    expect(priorAdapter.completeCalls, priorCompleteCalls);
    expect(
      (await fixture.database.getMayaProviderSettings())?.providerId,
      'anthropic',
    );
  });

  test(
    'unavailable WinCred still permits Ollama and blocks cloud keys',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final controller = await fixture.openController(
        credentialStore: const UnavailableMayaCredentialStore(),
      );

      await controller.saveCloud(
        providerId: 'ollama',
        modelPolicy: MayaProviderModelPolicy.explicit,
        modelId: 'llama3.2',
        apiKey: 'ignored-for-ollama',
        shareRecentHistory: false,
        shareLibraryContext: false,
      );
      expect(controller.status, MayaProviderControllerStatus.cloudReady);
      final response = await controller.complete(
        _request(contextLease: controller.contextPolicy.contextLease),
      );
      expect(response.text, 'provider response');

      await expectLater(
        controller.saveCloud(
          providerId: 'openai',
          modelPolicy: MayaProviderModelPolicy.explicit,
          modelId: 'gpt-4.1-mini',
          apiKey: 'sk-not-persisted',
          shareRecentHistory: false,
          shareLibraryContext: false,
        ),
        throwsA(
          _controllerError(MayaProviderControllerErrorCode.credentialFailure),
        ),
      );
    },
  );
}
