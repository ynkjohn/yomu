import 'dart:async';

import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_storage/yomu_storage.dart';

import 'maya_credential_store.dart';

const Set<String> kSupportedMayaProviderIds = <String>{
  'openai',
  'anthropic',
  'gemini',
  'ollama',
};
const List<String> _cloudCredentialProviderIds = <String>[
  'openai',
  'anthropic',
  'gemini',
];
const int kCurrentMayaProviderConsentVersion = 1;

enum MayaProviderControllerStatus {
  unset,
  local,
  disabled,
  cloudReady,
  unsupportedProvider,
  consentRequired,
  missingCredential,
  credentialUnavailable,
  adapterUnavailable,
  closed,
}

enum MayaProviderControllerErrorCode {
  closed,
  unsupportedProvider,
  invalidConfiguration,
  missingCredential,
  credentialFailure,
  persistenceFailure,
  adapterFailure,
}

/// Sanitized controller failure. Raw database, provider and credential errors
/// are intentionally not retained as causes or included in [toString].
final class MayaProviderControllerException implements Exception {
  const MayaProviderControllerException(this.code);

  final MayaProviderControllerErrorCode code;

  String get message => switch (code) {
    MayaProviderControllerErrorCode.closed =>
      'O controlador de providers da Maya foi encerrado.',
    MayaProviderControllerErrorCode.unsupportedProvider =>
      'O provider selecionado não é suportado.',
    MayaProviderControllerErrorCode.invalidConfiguration =>
      'A configuração do provider é inválida.',
    MayaProviderControllerErrorCode.missingCredential =>
      'A credencial do provider não está configurada.',
    MayaProviderControllerErrorCode.credentialFailure =>
      'Não foi possível validar a credencial do provider.',
    MayaProviderControllerErrorCode.persistenceFailure =>
      'Não foi possível salvar a configuração do provider.',
    MayaProviderControllerErrorCode.adapterFailure =>
      'Não foi possível iniciar o provider selecionado.',
  };

  @override
  String toString() => message;
}

/// Non-secret settings supplied to an injected provider adapter factory.
final class MayaProviderAdapterSettings {
  const MayaProviderAdapterSettings({
    required this.providerId,
    required this.modelPolicy,
    required this.modelId,
  });

  final String providerId;
  final MayaProviderModelPolicy modelPolicy;
  final String? modelId;

  @override
  String toString() =>
      'MayaProviderAdapterSettings(providerId: $providerId, '
      'modelPolicy: ${modelPolicy.name}, modelConfigured: ${modelId != null})';
}

/// Reads the current credential only while an adapter request is admitted.
///
/// Factories receive this capability instead of secret material. Cloud
/// adapters must invoke it immediately before each network request and must
/// not retain the returned value. Ollama always resolves to `null` without
/// touching the credential store.
typedef MayaProviderCredentialReader = Future<String?> Function();

typedef MayaProviderAdapterFactory =
    Future<MayaLlmProvider> Function({
      required MayaProviderAdapterSettings settings,
      required MayaProviderCredentialReader readCredential,
    });

/// Persistent provider coordinator used as the single [MayaLlmProvider]
/// exposed to [MayaService].
///
/// Mutations are serialized. Configuration is committed before a new adapter
/// becomes active, while generation invalidation prevents a response from an
/// old adapter being accepted after switch, reset, removal or shutdown.
final class MayaProviderController implements MayaLlmProvider {
  MayaProviderController._({
    required YomuDatabase database,
    required MayaCredentialStore credentialStore,
    required MayaProviderAdapterFactory adapterFactory,
    required DateTime Function() clock,
  }) : _database = database,
       _credentialStore = credentialStore,
       _adapterFactory = adapterFactory,
       _clock = clock;

  static Future<MayaProviderController> open({
    required YomuDatabase database,
    required MayaCredentialStore credentialStore,
    required MayaProviderAdapterFactory adapterFactory,
    DateTime Function()? clock,
  }) async {
    final controller = MayaProviderController._(
      database: database,
      credentialStore: credentialStore,
      adapterFactory: adapterFactory,
      clock: clock ?? _utcNow,
    );
    await controller._load();
    return controller;
  }

  final YomuDatabase _database;
  final MayaCredentialStore _credentialStore;
  final MayaProviderAdapterFactory _adapterFactory;
  final DateTime Function() _clock;

  Future<void> _mutationTail = Future<void>.value();
  Future<void>? _closeFuture;
  MayaProviderSettings? _settings;
  MayaLlmProvider? _adapter;
  _MayaProviderCredentialAccess? _credentialAccess;
  _MayaProviderContextLease? _contextLease;
  MayaProviderControllerStatus _status = MayaProviderControllerStatus.unset;
  final Set<MayaLlmCancellationToken> _activeRequests =
      <MayaLlmCancellationToken>{};
  final Set<Future<void>> _activeRequestDrains = <Future<void>>{};
  int _generation = 0;
  int _pendingMutations = 0;
  bool _accepting = true;

  MayaProviderControllerStatus get status => _status;

  MayaProviderSettings? get settings => _settings;

  bool get isClosed => !_accepting;

  @override
  MayaLlmContextPolicy get contextPolicy {
    final current = _settings;
    final providerId = current?.providerId;
    final lease = _contextLease;
    if (!_accepting ||
        _pendingMutations != 0 ||
        _status != MayaProviderControllerStatus.cloudReady ||
        current == null ||
        current.mode != MayaProviderMode.cloud ||
        !current.isEnabled ||
        current.consentVersion != kCurrentMayaProviderConsentVersion ||
        providerId == null ||
        !kSupportedMayaProviderIds.contains(providerId) ||
        lease == null) {
      return const MayaLlmContextPolicy.disabled();
    }
    return MayaLlmContextPolicy(
      enabled: true,
      shareRecentHistory: current.shareRecentHistory,
      shareLibraryContext: current.shareLibraryContext,
      contextLease: lease,
    );
  }

  /// Save and activate a cloud provider.
  ///
  /// A disabled candidate snapshot is made durable before any credential is
  /// changed. For OpenAI, Anthropic and Gemini a non-blank key is then saved
  /// and read back before the active snapshot is committed. A blank key keeps
  /// an existing credential. Ollama never reads or writes a credential.
  Future<void> saveCloud({
    required String providerId,
    required MayaProviderModelPolicy modelPolicy,
    String? modelId,
    String? apiKey,
    required bool shareRecentHistory,
    required bool shareLibraryContext,
  }) {
    return _enqueueMutation(() async {
      _requireSupportedProvider(providerId);
      final nowMs = _clock().toUtc().millisecondsSinceEpoch;

      late final MayaProviderSettings candidate;
      try {
        candidate = MayaProviderSettings.cloud(
          providerId: providerId,
          modelPolicy: modelPolicy,
          modelId: modelId,
          isEnabled: true,
          shareRecentHistory: shareRecentHistory,
          shareLibraryContext: shareLibraryContext,
          consentVersion: kCurrentMayaProviderConsentVersion,
          consentedAtMs: nowMs,
          updatedAtMs: nowMs,
        );
      } catch (_) {
        throw const MayaProviderControllerException(
          MayaProviderControllerErrorCode.invalidConfiguration,
        );
      }

      final disabled = _disabledCloudSnapshot(candidate, nowMs);
      await _persist(disabled);
      _settings = disabled;
      _status = MayaProviderControllerStatus.disabled;
      await _stopActive();

      _MayaCredentialMutation? credentialMutation;
      try {
        credentialMutation = await _prepareCredential(
          providerId: providerId,
          candidateKey: apiKey,
        );
      } on MayaProviderControllerException {
        _settings = disabled;
        _status = MayaProviderControllerStatus.disabled;
        rethrow;
      }
      try {
        await _persist(candidate);
      } on MayaProviderControllerException {
        await credentialMutation?.rollback();
        _settings = disabled;
        _status = MayaProviderControllerStatus.disabled;
        rethrow;
      }
      credentialMutation?.commit();
      await _replaceActive(candidate, throwOnAdapterFailure: true);
    });
  }

  /// Persist an explicit local choice without deleting any saved credential.
  Future<void> saveLocal() {
    return _enqueueMutation(() async {
      final local = MayaProviderSettings.local(
        updatedAtMs: _clock().toUtc().millisecondsSinceEpoch,
      );
      await _persist(local);
      await _stopActive();
      _settings = local;
      _status = MayaProviderControllerStatus.local;
    });
  }

  /// Remove every Maya cloud credential, then persist local or unset state.
  ///
  /// A disabled cloud snapshot is durable before adapter shutdown and cleanup.
  /// Therefore cleanup/finalization failures remain retryable without allowing
  /// restart to reactivate the previous cloud configuration.
  Future<void> removeProvider({bool resetToUnset = false}) {
    return _enqueueMutation(() async {
      final previous = _settings;
      if (previous?.mode == MayaProviderMode.cloud) {
        final disabled = _disabledCloudSnapshot(
          previous!,
          _clock().toUtc().millisecondsSinceEpoch,
        );
        try {
          await _persist(disabled);
        } on MayaProviderControllerException {
          await _stopActive();
          var cleanupFailed = false;
          try {
            await _deleteCloudCredentials(previous.providerId);
          } on MayaProviderControllerException {
            cleanupFailed = true;
          }
          _status = _inactiveStatusFor(
            previous,
            credentialUnavailable: cleanupFailed,
          );
          rethrow;
        }
        _settings = disabled;
        _status = MayaProviderControllerStatus.disabled;
      }
      await _stopActive();
      try {
        await _deleteCloudCredentials(previous?.providerId);
      } on MayaProviderControllerException {
        _status = _inactiveStatusFor(_settings, credentialUnavailable: true);
        rethrow;
      }

      // The cloud row is already disabled before cleanup starts. If final
      // persistence fails, restart remains fail-closed and a later removal can
      // retry the idempotent cleanup/finalization step.
      _status = _inactiveStatusFor(_settings, credentialUnavailable: false);
      MayaProviderSettings? replacement;
      if (resetToUnset) {
        await _resetPersistence();
      } else {
        replacement = MayaProviderSettings.local(
          updatedAtMs: _clock().toUtc().millisecondsSinceEpoch,
        );
        await _persist(replacement);
      }

      _settings = replacement;
      _status = replacement == null
          ? MayaProviderControllerStatus.unset
          : MayaProviderControllerStatus.local;
    });
  }

  Future<void> reset() => removeProvider(resetToUnset: true);

  @override
  Future<MayaLlmResponse> complete(MayaLlmRequest request) async {
    if (!_accepting) {
      throw const MayaLlmException(MayaLlmFailureKind.cancelled);
    }
    if (_pendingMutations != 0) {
      throw const MayaLlmException(MayaLlmFailureKind.unavailable);
    }
    final adapter = _adapter;
    final credentialAccess = _credentialAccess;
    final contextLease = _contextLease;
    if (_status != MayaProviderControllerStatus.cloudReady ||
        adapter == null ||
        credentialAccess == null ||
        contextLease == null) {
      throw const MayaLlmException(MayaLlmFailureKind.configuration);
    }
    if (!identical(request.contextLease, contextLease)) {
      throw const MayaLlmException(MayaLlmFailureKind.cancelled);
    }

    final admittedGeneration = _generation;
    final cancellation = request.cancellation;
    final drained = Completer<void>();
    final drainFuture = drained.future;
    cancellation.throwIfCancelled();
    credentialAccess.enterRequest();
    _activeRequests.add(cancellation);
    _activeRequestDrains.add(drainFuture);
    try {
      final response = await adapter.complete(request);
      cancellation.throwIfCancelled();
      if (!_accepting ||
          admittedGeneration != _generation ||
          !identical(adapter, _adapter) ||
          !identical(credentialAccess, _credentialAccess)) {
        throw const MayaLlmException(MayaLlmFailureKind.cancelled);
      }
      return response;
    } on MayaLlmException {
      rethrow;
    } catch (_) {
      throw const MayaLlmException(MayaLlmFailureKind.providerFailure);
    } finally {
      _activeRequests.remove(cancellation);
      _activeRequestDrains.remove(drainFuture);
      credentialAccess.leaveRequest();
      drained.complete();
    }
  }

  @override
  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    _accepting = false;
    _invalidateGeneration();
    return _closeFuture = _mutationTail.then((_) async {
      await _stopActive();
      _settings = null;
      _status = MayaProviderControllerStatus.closed;
    });
  }

  Future<void> _load() async {
    MayaProviderSettings? persisted;
    try {
      persisted = await _database.getMayaProviderSettings();
    } catch (_) {
      throw const MayaProviderControllerException(
        MayaProviderControllerErrorCode.persistenceFailure,
      );
    }

    if (persisted == null) {
      _settings = null;
      _status = MayaProviderControllerStatus.unset;
      return;
    }
    if (persisted.mode == MayaProviderMode.local) {
      _settings = persisted;
      _status = MayaProviderControllerStatus.local;
      return;
    }
    await _loadCloud(persisted);
  }

  Future<void> _loadCloud(MayaProviderSettings persisted) async {
    _settings = persisted;
    if (!persisted.isEnabled) {
      _status = MayaProviderControllerStatus.disabled;
      return;
    }
    final providerId = persisted.providerId;
    if (providerId == null || !kSupportedMayaProviderIds.contains(providerId)) {
      _status = MayaProviderControllerStatus.unsupportedProvider;
      return;
    }
    if (persisted.consentVersion != kCurrentMayaProviderConsentVersion) {
      _status = MayaProviderControllerStatus.consentRequired;
      return;
    }
    if (!_validPersistedModel(persisted)) {
      _status = MayaProviderControllerStatus.adapterUnavailable;
      return;
    }

    if (providerId != 'ollama') {
      String? credential;
      try {
        credential = await _credentialStore.read(providerId: providerId);
      } catch (_) {
        _status = MayaProviderControllerStatus.credentialUnavailable;
        return;
      }
      if (credential == null) {
        _status = MayaProviderControllerStatus.missingCredential;
        return;
      }
    }
    await _replaceActive(persisted, throwOnAdapterFailure: false);
  }

  Future<_MayaCredentialMutation?> _prepareCredential({
    required String providerId,
    required String? candidateKey,
  }) async {
    if (providerId == 'ollama') return null;

    final supplied = candidateKey != null && candidateKey.trim().isNotEmpty;
    if (!supplied) {
      try {
        final existing = await _credentialStore.read(providerId: providerId);
        if (existing == null) {
          await _deactivateIfActiveProvider(
            providerId,
            status: MayaProviderControllerStatus.missingCredential,
          );
          throw const MayaProviderControllerException(
            MayaProviderControllerErrorCode.missingCredential,
          );
        }
        return null;
      } on MayaProviderControllerException {
        rethrow;
      } catch (_) {
        await _deactivateIfActiveProvider(
          providerId,
          status: MayaProviderControllerStatus.credentialUnavailable,
        );
        throw const MayaProviderControllerException(
          MayaProviderControllerErrorCode.credentialFailure,
        );
      }
    }

    String? previousCredential;
    try {
      previousCredential = await _credentialStore.read(providerId: providerId);
    } catch (_) {
      throw const MayaProviderControllerException(
        MayaProviderControllerErrorCode.credentialFailure,
      );
    }
    final mutation = _MayaCredentialMutation(
      credentialStore: _credentialStore,
      providerId: providerId,
      previousCredential: previousCredential,
    );
    try {
      await _credentialStore.save(providerId: providerId, apiKey: candidateKey);
      final readback = await _credentialStore.read(providerId: providerId);
      if (readback != candidateKey) throw StateError('credential readback');
      return mutation;
    } catch (_) {
      final restored = await mutation.rollback();
      if (!restored) {
        await _deactivateIfActiveProvider(
          providerId,
          status: MayaProviderControllerStatus.credentialUnavailable,
        );
      }
      throw const MayaProviderControllerException(
        MayaProviderControllerErrorCode.credentialFailure,
      );
    }
  }

  Future<void> _deleteCloudCredentials(String? currentProviderId) async {
    final ordered = <String>[
      for (final providerId in _cloudCredentialProviderIds)
        if (providerId != currentProviderId) providerId,
      if (_cloudCredentialProviderIds.contains(currentProviderId))
        currentProviderId!,
    ];
    var failed = false;
    for (final providerId in ordered) {
      try {
        await _credentialStore.delete(providerId: providerId);
      } catch (_) {
        // A vault implementation may report an error after committing the
        // delete. The readback below remains the source of truth.
      }
      try {
        final readback = await _credentialStore.read(providerId: providerId);
        if (readback != null) failed = true;
      } catch (_) {
        failed = true;
      }
    }
    if (failed) {
      throw const MayaProviderControllerException(
        MayaProviderControllerErrorCode.credentialFailure,
      );
    }
  }

  Future<void> _deactivateIfActiveProvider(
    String providerId, {
    required MayaProviderControllerStatus status,
  }) async {
    final current = _settings;
    if (current?.mode != MayaProviderMode.cloud ||
        current?.providerId != providerId) {
      return;
    }
    await _stopActive();
    _status = status;
  }

  Future<void> _persist(MayaProviderSettings settings) async {
    try {
      await _database.setMayaProviderSettings(settings);
    } catch (_) {
      throw const MayaProviderControllerException(
        MayaProviderControllerErrorCode.persistenceFailure,
      );
    }
  }

  Future<void> _resetPersistence() async {
    try {
      await _database.resetMayaProviderSettings();
    } catch (_) {
      throw const MayaProviderControllerException(
        MayaProviderControllerErrorCode.persistenceFailure,
      );
    }
  }

  Future<void> _replaceActive(
    MayaProviderSettings settings, {
    required bool throwOnAdapterFailure,
  }) async {
    if (!settings.isEnabled) {
      throw const MayaProviderControllerException(
        MayaProviderControllerErrorCode.invalidConfiguration,
      );
    }
    await _stopActive();
    _settings = settings;
    final credentialAccess = _MayaProviderCredentialAccess(
      credentialStore: _credentialStore,
      providerId: settings.providerId!,
    );
    try {
      final adapter = await _adapterFactory(
        settings: MayaProviderAdapterSettings(
          providerId: settings.providerId!,
          modelPolicy: settings.modelPolicy!,
          modelId: settings.modelId,
        ),
        readCredential: credentialAccess.read,
      );
      _adapter = adapter;
      _credentialAccess = credentialAccess;
      _status = MayaProviderControllerStatus.cloudReady;
      _refreshContextLeaseIfReady();
    } catch (_) {
      credentialAccess.invalidate();
      _adapter = null;
      _credentialAccess = null;
      _status = MayaProviderControllerStatus.adapterUnavailable;
      if (throwOnAdapterFailure) {
        throw const MayaProviderControllerException(
          MayaProviderControllerErrorCode.adapterFailure,
        );
      }
    }
  }

  Future<void> _stopActive() async {
    _invalidateGeneration();
    final old = _adapter;
    final oldCredentialAccess = _credentialAccess;
    _adapter = null;
    _credentialAccess = null;
    oldCredentialAccess?.invalidate();
    if (old != null) {
      try {
        await old.close();
      } catch (_) {
        // Adapter shutdown is a best-effort untrusted boundary. Generation
        // invalidation already prevents acceptance of a late response.
      }
    }
    final drains = _activeRequestDrains.toList(growable: false);
    if (drains.isNotEmpty) await Future.wait<void>(drains);
  }

  void _invalidateGeneration() {
    _generation++;
    _contextLease = null;
    for (final cancellation in _activeRequests.toList(growable: false)) {
      cancellation.cancel();
    }
  }

  Future<T> _enqueueMutation<T>(Future<T> Function() operation) {
    if (!_accepting) {
      return Future<T>.error(
        const MayaProviderControllerException(
          MayaProviderControllerErrorCode.closed,
        ),
      );
    }
    _pendingMutations++;
    _invalidateGeneration();
    final completer = Completer<T>();
    _mutationTail = _mutationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _pendingMutations--;
        _refreshContextLeaseIfReady();
      }
    });
    return completer.future;
  }

  static void _requireSupportedProvider(String providerId) {
    if (!kSupportedMayaProviderIds.contains(providerId)) {
      throw const MayaProviderControllerException(
        MayaProviderControllerErrorCode.unsupportedProvider,
      );
    }
  }

  static bool _validPersistedModel(MayaProviderSettings settings) {
    return switch (settings.modelPolicy) {
      MayaProviderModelPolicy.providerDefault => settings.modelId == null,
      MayaProviderModelPolicy.explicit =>
        settings.modelId != null && settings.modelId!.trim().isNotEmpty,
      null => false,
    };
  }

  static MayaProviderControllerStatus _inactiveStatusFor(
    MayaProviderSettings? settings, {
    required bool credentialUnavailable,
  }) {
    if (settings == null) return MayaProviderControllerStatus.unset;
    if (settings.mode == MayaProviderMode.local) {
      return MayaProviderControllerStatus.local;
    }
    if (!settings.isEnabled) {
      return MayaProviderControllerStatus.disabled;
    }
    final providerId = settings.providerId;
    if (providerId == null || !kSupportedMayaProviderIds.contains(providerId)) {
      return MayaProviderControllerStatus.unsupportedProvider;
    }
    if (settings.consentVersion != kCurrentMayaProviderConsentVersion) {
      return MayaProviderControllerStatus.consentRequired;
    }
    if (!_validPersistedModel(settings) || providerId == 'ollama') {
      return MayaProviderControllerStatus.adapterUnavailable;
    }
    return credentialUnavailable
        ? MayaProviderControllerStatus.credentialUnavailable
        : MayaProviderControllerStatus.missingCredential;
  }

  void _refreshContextLeaseIfReady() {
    if (_accepting &&
        _pendingMutations == 0 &&
        _status == MayaProviderControllerStatus.cloudReady &&
        _adapter != null &&
        _credentialAccess != null &&
        _settings?.isEnabled == true) {
      _contextLease ??= _MayaProviderContextLease();
    } else {
      _contextLease = null;
    }
  }

  static MayaProviderSettings _disabledCloudSnapshot(
    MayaProviderSettings settings,
    int nowMs,
  ) {
    if (settings.mode != MayaProviderMode.cloud) {
      throw ArgumentError.value(settings.mode, 'settings.mode');
    }
    final updatedAtMs = nowMs < settings.updatedAtMs
        ? settings.updatedAtMs
        : nowMs;
    return MayaProviderSettings.cloud(
      providerId: settings.providerId!,
      modelPolicy: settings.modelPolicy!,
      modelId: settings.modelId,
      isEnabled: false,
      shareRecentHistory: settings.shareRecentHistory,
      shareLibraryContext: settings.shareLibraryContext,
      consentVersion: settings.consentVersion!,
      consentedAtMs: settings.consentedAtMs!,
      updatedAtMs: updatedAtMs,
    );
  }
}

DateTime _utcNow() => DateTime.now().toUtc();

final class _MayaProviderContextLease {}

final class _MayaCredentialMutation {
  _MayaCredentialMutation({
    required MayaCredentialStore credentialStore,
    required this.providerId,
    required String? previousCredential,
  }) : _credentialStore = credentialStore,
       _previousCredential = previousCredential;

  final MayaCredentialStore _credentialStore;
  final String providerId;
  String? _previousCredential;
  bool _active = true;

  void commit() {
    _active = false;
    _previousCredential = null;
  }

  Future<bool> rollback() async {
    if (!_active) return true;
    _active = false;
    final previous = _previousCredential;
    _previousCredential = null;
    try {
      if (previous == null) {
        await _credentialStore.delete(providerId: providerId);
      } else {
        await _credentialStore.save(providerId: providerId, apiKey: previous);
      }
    } catch (_) {
      // Read back even after an operation error: Windows Credential Manager
      // may have committed the mutation before reporting a boundary failure.
    }
    try {
      final readback = await _credentialStore.read(providerId: providerId);
      return readback == previous;
    } catch (_) {
      return false;
    }
  }
}

final class _MayaProviderCredentialAccess {
  _MayaProviderCredentialAccess({
    required MayaCredentialStore credentialStore,
    required this.providerId,
  }) : _credentialStore = credentialStore;

  final MayaCredentialStore _credentialStore;
  final String providerId;
  int _activeRequests = 0;
  bool _valid = true;

  void enterRequest() {
    if (!_valid) {
      throw const MayaLlmException(MayaLlmFailureKind.cancelled);
    }
    _activeRequests++;
  }

  void leaveRequest() {
    if (_activeRequests > 0) _activeRequests--;
  }

  void invalidate() {
    _valid = false;
  }

  Future<String?> read() async {
    if (providerId == 'ollama') return null;
    if (!_valid || _activeRequests == 0) {
      throw const MayaLlmException(MayaLlmFailureKind.cancelled);
    }
    try {
      return await _credentialStore.read(providerId: providerId);
    } catch (_) {
      throw const MayaLlmException(MayaLlmFailureKind.unavailable);
    }
  }
}
