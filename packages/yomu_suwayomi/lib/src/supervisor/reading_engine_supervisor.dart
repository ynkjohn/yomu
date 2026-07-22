import 'dart:async';

import 'package:yomu_core/yomu_core.dart';

import '../compatibility/suwayomi_compatibility_probe.dart';
import '../process/suwayomi_process_failure.dart';
import 'managed_reading_engine_process.dart';

typedef SupervisorNow = DateTime Function();
typedef SupervisorDelay = Future<void> Function(Duration duration);

final class ReadingEngineSupervisorPolicy {
  const ReadingEngineSupervisorPolicy({
    this.startupTimeout = const Duration(minutes: 3),
    this.healthInterval = const Duration(seconds: 15),
    this.failureConfirmationDelay = const Duration(seconds: 1),
    this.recoveryBackoffs = const [
      Duration(seconds: 1),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ],
    this.healthyBudgetReset = const Duration(minutes: 10),
  });

  final Duration startupTimeout;
  final Duration healthInterval;
  final Duration failureConfirmationDelay;
  final List<Duration> recoveryBackoffs;
  final Duration healthyBudgetReset;
}

/// Single source of readiness for startup, health, recovery and shutdown.
final class ReadingEngineSupervisor
    implements EngineLifecycle, EngineDiagnostics {
  ReadingEngineSupervisor({
    required ManagedReadingEngineProcess process,
    ReadingEngineSupervisorPolicy policy =
        const ReadingEngineSupervisorPolicy(),
    SupervisorNow? now,
    SupervisorDelay? delay,
  }) : _process = process,
       _policy = policy,
       _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed {
    _diagnostics = _buildDiagnostics();
    _processSubscription = _process.interruptions.listen((_) {
      if (_current.isReady && !_shuttingDown) {
        unawaited(_confirmFailureAndRecover(firstProofAlreadyFailed: true));
      }
    });
  }

  final ManagedReadingEngineProcess _process;
  final ReadingEngineSupervisorPolicy _policy;
  final SupervisorNow _now;
  final SupervisorDelay _delay;
  final StreamController<EngineReadinessSnapshot> _readinessController =
      StreamController<EngineReadinessSnapshot>.broadcast(sync: true);
  final StreamController<EngineDiagnosticsSnapshot> _diagnosticsController =
      StreamController<EngineDiagnosticsSnapshot>.broadcast(sync: true);

  late final StreamSubscription<Object?> _processSubscription;
  late EngineDiagnosticsSnapshot _diagnostics;
  EngineReadinessSnapshot _current = const EngineReadinessSnapshot(
    state: EngineReadinessState.initializing,
  );
  EngineCompatibilityStatus _compatibility = EngineCompatibilityStatus.unknown;
  EngineOwnershipStatus _ownership = EngineOwnershipStatus.none;
  SuwayomiCompatibilityResult? _compatibilityResult;
  DateTime? _lastHealthCheck;
  DateTime? _healthySince;
  Future<void> _operationTail = Future<void>.value();
  Future<EngineReadinessSnapshot>? _ensureFlight;
  Future<EngineReadinessSnapshot>? _retryFlight;
  Future<void>? _shutdownFlight;
  Future<void>? _failureCheck;
  Future<void>? _recoveryFlight;
  final Completer<void> _shutdownSignal = Completer<void>();
  int _generation = 0;
  int _automaticRecoveries = 0;
  bool _manualBudgetResetUsed = false;
  bool _shuttingDown = false;
  bool _closed = false;

  @override
  EngineReadinessSnapshot get current => _current;

  @override
  Stream<EngineReadinessSnapshot> get changes => _readinessController.stream;

  @override
  EngineDiagnosticsSnapshot get diagnostics => _diagnostics;

  @override
  Stream<EngineDiagnosticsSnapshot> get diagnosticChanges =>
      _diagnosticsController.stream;

  @override
  Future<EngineReadinessSnapshot> ensureStarted() {
    if (_shuttingDown || _closed) return Future.value(_current);
    if (_current.isReady) return Future.value(_current);
    final existing = _ensureFlight;
    if (existing != null) return existing;
    final flight = _serialized(_ensureStartedBody);
    _ensureFlight = flight;
    unawaited(
      flight.then<void>(
        (_) {
          if (identical(_ensureFlight, flight)) _ensureFlight = null;
        },
        onError: (Object _, StackTrace __) {
          if (identical(_ensureFlight, flight)) _ensureFlight = null;
        },
      ),
    );
    return flight;
  }

  Future<EngineReadinessSnapshot> _ensureStartedBody() async {
    if (_shuttingDown) return _current;
    final generation = _generation;
    _publish(
      const EngineReadinessSnapshot(state: EngineReadinessState.starting),
    );
    return _runStartOperation(
      operation: () => _process.start(timeout: _policy.startupTimeout),
      generation: generation,
      allowAutomaticRecovery: true,
    );
  }

  @override
  Future<EngineReadinessSnapshot> retry() {
    if (_shuttingDown || _closed) return Future.value(_current);
    if (_current.isReady) return Future.value(_current);
    final existing = _retryFlight;
    if (existing != null) return existing;
    if (_automaticRecoveries >= _policy.recoveryBackoffs.length) {
      if (_manualBudgetResetUsed) return Future.value(_current);
      _automaticRecoveries = 0;
      _manualBudgetResetUsed = true;
    }
    final flight = _serialized(_retryBody);
    _retryFlight = flight;
    unawaited(
      flight.then<void>(
        (_) {
          if (identical(_retryFlight, flight)) _retryFlight = null;
        },
        onError: (Object _, StackTrace __) {
          if (identical(_retryFlight, flight)) _retryFlight = null;
        },
      ),
    );
    return flight;
  }

  Future<EngineReadinessSnapshot> _retryBody() async {
    if (_shuttingDown) return _current;
    final generation = ++_generation;
    _publish(
      const EngineReadinessSnapshot(state: EngineReadinessState.starting),
    );
    return _runStartOperation(
      operation: _process.recover,
      generation: generation,
      allowAutomaticRecovery: true,
    );
  }

  Future<EngineReadinessSnapshot> _runStartOperation({
    required Future<Result<SuwayomiStatus>> Function() operation,
    required int generation,
    required bool allowAutomaticRecovery,
  }) async {
    try {
      final work = () async {
        final result = await operation();
        return _handleStartResult(
          result,
          generation: generation,
          allowAutomaticRecovery: allowAutomaticRecovery,
        );
      }();
      return await work.timeout(_policy.startupTimeout);
    } on TimeoutException {
      if (!_isCurrent(generation)) return _current;
      _generation++;
      const failure = EngineFailure(
        kind: EngineFailureKind.temporarilyUnavailable,
        code: 'engine_start_timeout',
        message: 'Recursos de leitura temporariamente indisponíveis.',
        retryable: true,
      );
      _publishFailure(failure);
      if (allowAutomaticRecovery) _scheduleAutomaticRecovery();
      return _current;
    } catch (_) {
      if (!_isCurrent(generation)) return _current;
      _generation++;
      _publishFailure(_unexpectedFailure('engine_start_unclassified'));
      return _current;
    }
  }

  Future<EngineReadinessSnapshot> _handleStartResult(
    Result<SuwayomiStatus> result, {
    required int generation,
    required bool allowAutomaticRecovery,
  }) async {
    if (!_isCurrent(generation)) return _current;
    Object? cause;
    final started = result.when(
      ok: (_) => true,
      err: (_, error) {
        cause = error;
        return false;
      },
    );
    if (!started) {
      final failure = _mapProcessFailure(cause);
      _publishFailure(failure);
      if (failure.retryable && allowAutomaticRecovery) {
        _scheduleAutomaticRecovery();
      }
      return _current;
    }

    if (!_isCurrent(generation)) return _current;
    _ownership = EngineOwnershipStatus.owned;
    final compatibility = await _process.checkCompatibility();
    if (!_isCurrent(generation)) return _current;
    if (!compatibility.compatible) {
      final failure = _mapCompatibilityFailure(compatibility.failure);
      _compatibility = failure.kind == EngineFailureKind.incompatible
          ? EngineCompatibilityStatus.incompatible
          : EngineCompatibilityStatus.unknown;
      _publishFailure(failure);
      if (failure.retryable && allowAutomaticRecovery) {
        _scheduleAutomaticRecovery();
      }
      return _current;
    }
    _compatibility = EngineCompatibilityStatus.compatible;
    _compatibilityResult = compatibility;
    _markHealthy();
    return _current;
  }

  void _markHealthy() {
    final now = _now();
    _lastHealthCheck = now;
    _healthySince ??= now;
    if (now.difference(_healthySince!) >= _policy.healthyBudgetReset) {
      _automaticRecoveries = 0;
      _manualBudgetResetUsed = false;
      _healthySince = now;
    }
    _publish(const EngineReadinessSnapshot(state: EngineReadinessState.ready));
    _startHealthMonitor();
  }

  void _startHealthMonitor() {
    final generation = ++_generation;
    unawaited(_healthMonitor(generation));
  }

  Future<void> _healthMonitor(int generation) async {
    while (!_shuttingDown && generation == _generation && _current.isReady) {
      if (!await _wait(_policy.healthInterval, generation) ||
          !_current.isReady) {
        return;
      }
      await _confirmFailureAndRecover(firstProofAlreadyFailed: false);
    }
  }

  Future<EngineReadinessSnapshot> checkNow() async {
    if (_shuttingDown || _closed || !_current.isReady) return _current;
    await _confirmFailureAndRecover(firstProofAlreadyFailed: false);
    return _current;
  }

  Future<void> _confirmFailureAndRecover({
    required bool firstProofAlreadyFailed,
  }) {
    final existing = _failureCheck;
    if (existing != null) return existing;
    final generation = _generation;
    final check = _serialized(() async {
      if (_shuttingDown || generation != _generation || !_current.isReady) {
        return;
      }
      if (!firstProofAlreadyFailed) {
        final healthy = await _safeHealthCheck();
        if (healthy) {
          _markHealthy();
          return;
        }
      }
      if (!await _wait(_policy.failureConfirmationDelay, generation) ||
          !_current.isReady) {
        return;
      }
      if (await _safeHealthCheck()) {
        _markHealthy();
        return;
      }
      _healthySince = null;
      _publish(
        const EngineReadinessSnapshot(
          state: EngineReadinessState.temporarilyUnavailable,
          failure: EngineFailure(
            kind: EngineFailureKind.temporarilyUnavailable,
            code: 'engine_health_failed',
            message: 'Recursos de leitura temporariamente indisponíveis.',
            retryable: true,
          ),
        ),
      );
      _scheduleAutomaticRecovery();
    });
    _failureCheck = check;
    unawaited(
      check.then<void>(
        (_) {
          if (identical(_failureCheck, check)) _failureCheck = null;
        },
        onError: (Object _, StackTrace __) {
          if (identical(_failureCheck, check)) _failureCheck = null;
        },
      ),
    );
    return check;
  }

  void _scheduleAutomaticRecovery() {
    if (_shuttingDown || _closed || _recoveryFlight != null) return;
    final generation = ++_generation;
    final recovery = _serialized(() => _recoverAutomatically(generation));
    _recoveryFlight = recovery;
    unawaited(
      recovery.then<void>(
        (_) {
          if (identical(_recoveryFlight, recovery)) _recoveryFlight = null;
        },
        onError: (Object _, StackTrace __) {
          if (identical(_recoveryFlight, recovery)) _recoveryFlight = null;
        },
      ),
    );
  }

  Future<void> _recoverAutomatically(int generation) async {
    while (!_shuttingDown && generation == _generation) {
      if (_automaticRecoveries >= _policy.recoveryBackoffs.length) {
        _publish(
          const EngineReadinessSnapshot(
            state: EngineReadinessState.actionRequired,
            failure: EngineFailure(
              kind: EngineFailureKind.actionRequired,
              code: 'engine_recovery_exhausted',
              message: 'O motor interno precisa de atenção.',
              retryable: true,
            ),
          ),
        );
        return;
      }
      final attempt = ++_automaticRecoveries;
      final backoff = _policy.recoveryBackoffs[attempt - 1];
      _publish(
        EngineReadinessSnapshot(
          state: EngineReadinessState.recovering,
          attempt: attempt,
          nextRetryAt: _now().add(backoff),
        ),
      );
      if (!await _wait(backoff, generation)) return;
      Result<SuwayomiStatus> result;
      try {
        result = await _process.recover();
      } catch (_) {
        if (_isCurrent(generation)) {
          _publishFailure(_unexpectedFailure('engine_recovery_unclassified'));
        }
        return;
      }
      if (!_isCurrent(generation)) return;
      Object? cause;
      final restarted = result.when(
        ok: (_) => true,
        err: (_, error) {
          cause = error;
          return false;
        },
      );
      if (!restarted) {
        final failure = _mapProcessFailure(cause);
        _publishFailure(failure);
        if (!failure.retryable) return;
        continue;
      }
      _ownership = EngineOwnershipStatus.owned;
      SuwayomiCompatibilityResult compatibility;
      try {
        compatibility = await _process.checkCompatibility();
      } catch (_) {
        if (_isCurrent(generation)) {
          _publishFailure(
            _unexpectedFailure('engine_compatibility_unclassified'),
          );
        }
        return;
      }
      if (!_isCurrent(generation)) return;
      if (compatibility.compatible) {
        _compatibility = EngineCompatibilityStatus.compatible;
        _compatibilityResult = compatibility;
        _markHealthy();
        return;
      }
      final failure = _mapCompatibilityFailure(compatibility.failure);
      _compatibility = failure.kind == EngineFailureKind.incompatible
          ? EngineCompatibilityStatus.incompatible
          : EngineCompatibilityStatus.unknown;
      _publishFailure(failure);
      if (!failure.retryable) return;
    }
  }

  void _publishFailure(EngineFailure failure) {
    _healthySince = null;
    _publish(
      EngineReadinessSnapshot(
        state: failure.retryable
            ? EngineReadinessState.temporarilyUnavailable
            : EngineReadinessState.actionRequired,
        failure: failure,
        attempt: _automaticRecoveries,
      ),
    );
  }

  EngineFailure _mapProcessFailure(Object? cause) {
    if (cause is! SuwayomiProcessFailure) {
      _ownership = EngineOwnershipStatus.inconclusive;
      return const EngineFailure(
        kind: EngineFailureKind.actionRequired,
        code: 'engine_start_unclassified',
        message: 'O motor interno precisa de atenção.',
        retryable: false,
      );
    }
    return switch (cause.kind) {
      SuwayomiProcessFailureKind.launchFailed ||
      SuwayomiProcessFailureKind.readinessTimeout => const EngineFailure(
        kind: EngineFailureKind.temporarilyUnavailable,
        code: 'engine_start_temporarily_unavailable',
        message: 'Recursos de leitura temporariamente indisponíveis.',
        retryable: true,
      ),
      SuwayomiProcessFailureKind.runtimeIncompatible => const EngineFailure(
        kind: EngineFailureKind.incompatible,
        code: 'engine_runtime_incompatible',
        message: 'O motor interno não é compatível com esta instalação.',
        retryable: false,
      ),
      SuwayomiProcessFailureKind.foreignPort => _terminalOwnershipFailure(
        EngineOwnershipStatus.foreign,
        'engine_foreign_process',
      ),
      SuwayomiProcessFailureKind.ownershipUnverifiable ||
      SuwayomiProcessFailureKind.stopUnconfirmed => _terminalOwnershipFailure(
        EngineOwnershipStatus.inconclusive,
        'engine_ownership_unverifiable',
      ),
      SuwayomiProcessFailureKind.rootMismatch => _terminalOwnershipFailure(
        EngineOwnershipStatus.inconclusive,
        'engine_root_mismatch',
      ),
      SuwayomiProcessFailureKind.artifactMissing ||
      SuwayomiProcessFailureKind.artifactInvalid ||
      SuwayomiProcessFailureKind.runtimeMissing ||
      SuwayomiProcessFailureKind.unexpected => const EngineFailure(
        kind: EngineFailureKind.actionRequired,
        code: 'engine_installation_invalid',
        message: 'A instalação do motor interno precisa ser reparada.',
        retryable: false,
      ),
    };
  }

  EngineFailure _unexpectedFailure(String code) {
    _ownership = EngineOwnershipStatus.inconclusive;
    return EngineFailure(
      kind: EngineFailureKind.actionRequired,
      code: code,
      message: 'O motor interno precisa de atenção.',
      retryable: false,
    );
  }

  EngineFailure _terminalOwnershipFailure(
    EngineOwnershipStatus ownership,
    String code,
  ) {
    _ownership = ownership;
    return EngineFailure(
      kind: EngineFailureKind.actionRequired,
      code: code,
      message: 'O motor interno precisa de atenção.',
      retryable: false,
    );
  }

  EngineFailure _mapCompatibilityFailure(
    SuwayomiCompatibilityFailure? failure,
  ) {
    if (failure?.kind == SuwayomiCompatibilityFailureKind.unavailable) {
      return const EngineFailure(
        kind: EngineFailureKind.temporarilyUnavailable,
        code: 'engine_compatibility_unavailable',
        message: 'Recursos de leitura temporariamente indisponíveis.',
        retryable: true,
      );
    }
    return const EngineFailure(
      kind: EngineFailureKind.incompatible,
      code: 'engine_incompatible',
      message: 'O motor interno não é compatível com esta versão do Yomu.',
      retryable: false,
    );
  }

  void _publish(EngineReadinessSnapshot next) {
    if (_closed) return;
    _current = next;
    _diagnostics = _buildDiagnostics();
    if (!_readinessController.isClosed) _readinessController.add(next);
    if (!_diagnosticsController.isClosed) {
      _diagnosticsController.add(_diagnostics);
    }
  }

  EngineDiagnosticsSnapshot _buildDiagnostics() => _process.diagnostics(
    readiness: _current,
    compatibility: _compatibility,
    ownership: _ownership,
    lastHealthCheck: _lastHealthCheck,
    compatibilityResult: _compatibilityResult,
  );

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<bool> _wait(Duration duration, int generation) async {
    await Future.any<void>([_delay(duration), _shutdownSignal.future]);
    return !_shuttingDown && generation == _generation;
  }

  bool _isCurrent(int generation) =>
      !_shuttingDown && !_closed && generation == _generation;

  Future<bool> _safeHealthCheck() async {
    try {
      return await _process.checkHealth();
    } catch (_) {
      return false;
    }
  }

  @override
  void beginShutdown() {
    if (_shuttingDown || _closed) return;
    _shuttingDown = true;
    _generation++;
    _process.beginShutdown();
    if (!_shutdownSignal.isCompleted) _shutdownSignal.complete();
    _publish(
      const EngineReadinessSnapshot(state: EngineReadinessState.shuttingDown),
    );
  }

  @override
  Future<void> shutdown() {
    final existing = _shutdownFlight;
    if (existing != null) return existing;
    beginShutdown();
    final shutdown = _serialized(() async {
      await _process.shutdown();
      await _processSubscription.cancel();
      _closed = true;
      await _readinessController.close();
      await _diagnosticsController.close();
    });
    _shutdownFlight = shutdown;
    return shutdown;
  }
}
