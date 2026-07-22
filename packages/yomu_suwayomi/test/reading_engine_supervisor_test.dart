import 'dart:async';
import 'dart:collection';

import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  test('default supervisor policy pins approved timings', () {
    const policy = ReadingEngineSupervisorPolicy();
    expect(policy.startupTimeout, const Duration(minutes: 3));
    expect(policy.healthInterval, const Duration(seconds: 15));
    expect(policy.failureConfirmationDelay, const Duration(seconds: 1));
    expect(policy.recoveryBackoffs, const [
      Duration(seconds: 1),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ]);
    expect(policy.healthyBudgetReset, const Duration(minutes: 10));
  });

  test(
    'concurrent slow startup is single-flight with three-minute cap',
    () async {
      final process = _FakeProcess()..holdStart = true;
      final delays = _ManualDelays();
      final supervisor = _supervisor(process, delays);

      final first = supervisor.ensureStarted();
      final second = supervisor.ensureStarted();
      expect(identical(first, second), isTrue);
      await _flush();
      expect(process.startCalls, 1);
      expect(process.startTimeouts.single, const Duration(minutes: 3));
      expect(await _isComplete(first), isFalse);

      process.completeStart(const Ok(_running));
      expect((await first).state, EngineReadinessState.ready);
      expect(await second, same(supervisor.current));
      await supervisor.shutdown();
    },
  );

  test('startup deadline covers start and compatibility', () async {
    final process = _FakeProcess()..holdCompatibility = true;
    final delays = _ManualDelays();
    final supervisor = _supervisor(
      process,
      delays,
      policy: const ReadingEngineSupervisorPolicy(
        startupTimeout: Duration(milliseconds: 10),
        healthInterval: Duration(seconds: 30),
      ),
    );

    final result = await supervisor.ensureStarted().timeout(
      const Duration(seconds: 1),
    );

    expect(result.isReady, isFalse);
    expect(process.startTimeouts.single, const Duration(milliseconds: 10));
    supervisor.beginShutdown();
    process.completeCompatibility();
    await supervisor.shutdown();
  });

  test(
    'foreign port is actionRequired and never enters automatic recovery',
    () async {
      final process = _FakeProcess()
        ..startResults.add(
          const Err(
            'foreign',
            SuwayomiProcessFailure(
              kind: SuwayomiProcessFailureKind.foreignPort,
              code: 'engine_foreign_port',
              message: 'foreign',
            ),
          ),
        );
      final delays = _ManualDelays();
      final supervisor = _supervisor(process, delays);

      final result = await supervisor.ensureStarted();

      expect(result.state, EngineReadinessState.actionRequired);
      expect(result.failure!.code, 'engine_foreign_process');
      expect(process.recoverCalls, 0);
      expect(delays.requested, isEmpty);
      await supervisor.shutdown();
    },
  );

  test('health failure needs a second proof before recovery', () async {
    final process = _FakeProcess()..healthResults.addAll([false, true]);
    final delays = _ManualDelays();
    final supervisor = _supervisor(process, delays);
    await supervisor.ensureStarted();

    delays.complete(const Duration(seconds: 30));
    await _pump();
    expect(process.healthCalls, 1);
    delays.complete(const Duration(seconds: 1));
    await _flush();

    expect(process.healthCalls, 2);
    expect(process.recoverCalls, 0);
    expect(supervisor.current.state, EngineReadinessState.ready);
    await supervisor.shutdown();
  });

  test(
    'crash uses 1s, 5s and 15s recovery budget then requires action',
    () async {
      const retryable = Err<SuwayomiStatus>(
        'timeout',
        SuwayomiProcessFailure(
          kind: SuwayomiProcessFailureKind.readinessTimeout,
          code: 'engine_start_timeout',
          message: 'timeout',
        ),
      );
      final process = _FakeProcess()
        ..healthResults.add(false)
        ..recoverResults.addAll([retryable, retryable, retryable]);
      final delays = _ManualDelays();
      final supervisor = _supervisor(process, delays);
      await supervisor.ensureStarted();

      process.interrupt();
      await _flush();
      delays.complete(const Duration(seconds: 1)); // confirmation
      await _flush();
      delays.complete(const Duration(seconds: 1)); // recovery 1
      await _flush();
      delays.complete(const Duration(seconds: 5));
      await _flush();
      delays.complete(const Duration(seconds: 15));
      await _flush();

      expect(process.recoverCalls, 3);
      expect(supervisor.current.state, EngineReadinessState.actionRequired);
      expect(supervisor.current.failure!.code, 'engine_recovery_exhausted');
      await supervisor.shutdown();
    },
  );

  test(
    'shutdown cancels pending backoff and never starts a late recovery',
    () async {
      final process = _FakeProcess()..healthResults.add(false);
      final delays = _ManualDelays();
      final supervisor = _supervisor(process, delays);
      await supervisor.ensureStarted();
      process.interrupt();
      await _flush();
      delays.complete(const Duration(seconds: 1)); // confirmation
      await _flush();
      expect(delays.pending(const Duration(seconds: 1)), 1);

      await supervisor.shutdown();
      delays.complete(const Duration(seconds: 1));
      await _flush();

      expect(process.recoverCalls, 0);
      expect(process.shutdownCalls, 1);
    },
  );

  test('shutdown during active start never publishes late readiness', () async {
    final process = _FakeProcess()..holdStart = true;
    final delays = _ManualDelays();
    final supervisor = _supervisor(process, delays);
    final states = <EngineReadinessState>[];
    final subscription = supervisor.changes.listen(
      (value) => states.add(value.state),
    );

    final start = supervisor.ensureStarted();
    await _flush();
    supervisor.beginShutdown();
    process.completeStart(const Ok(_running));
    expect((await start).state, EngineReadinessState.shuttingDown);
    await supervisor.shutdown();

    expect(states.last, EngineReadinessState.shuttingDown);
    expect(states, isNot(contains(EngineReadinessState.ready)));
    expect(process.compatibilityCalls, 0);
    expect(process.beginShutdownCalls, 1);
    await subscription.cancel();
  });

  test('shutdown during active recovery ignores its late result', () async {
    final process = _FakeProcess()
      ..healthResults.add(false)
      ..holdRecover = true;
    final delays = _ManualDelays();
    final supervisor = _supervisor(process, delays);
    await supervisor.ensureStarted();
    process.interrupt();
    await _flush();
    delays.complete(const Duration(seconds: 1));
    await _flush();
    delays.complete(const Duration(seconds: 1));
    await _flush();
    expect(process.recoverCalls, 1);

    supervisor.beginShutdown();
    process.completeRecover(const Ok(_running));
    await supervisor.shutdown();

    expect(supervisor.current.state, EngineReadinessState.shuttingDown);
    expect(process.compatibilityCalls, 1, reason: 'startup compatibility only');
  });

  test('manual retry resets an exhausted budget only once', () async {
    const retryable = Err<SuwayomiStatus>(
      'timeout',
      SuwayomiProcessFailure(
        kind: SuwayomiProcessFailureKind.readinessTimeout,
        code: 'engine_start_timeout',
        message: 'timeout',
      ),
    );
    final process = _FakeProcess()
      ..startResults.add(retryable)
      ..recoverResults.addAll([
        retryable,
        retryable,
        retryable,
        retryable,
        retryable,
        retryable,
        retryable,
      ]);
    final delays = _ManualDelays();
    final supervisor = _supervisor(process, delays);
    await supervisor.ensureStarted();
    for (final delay in const [
      Duration(seconds: 1),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ]) {
      delays.complete(delay);
      await _pump();
    }
    expect(supervisor.current.state, EngineReadinessState.actionRequired);

    await supervisor.retry();
    for (final delay in const [
      Duration(seconds: 1),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ]) {
      delays.complete(delay);
      await _pump();
    }
    expect(supervisor.current.state, EngineReadinessState.actionRequired);
    final calls = process.recoverCalls;

    await supervisor.retry();
    expect(process.recoverCalls, calls);
    await supervisor.shutdown();
  });

  test(
    'ten healthy minutes reset automatic and manual recovery budgets',
    () async {
      const retryable = Err<SuwayomiStatus>(
        'timeout',
        SuwayomiProcessFailure(
          kind: SuwayomiProcessFailureKind.readinessTimeout,
          code: 'engine_start_timeout',
          message: 'timeout',
        ),
      );
      var now = DateTime.utc(2026, 7, 22, 12);
      final process = _FakeProcess()
        ..healthResults.addAll([false, true, false])
        ..recoverResults.addAll([retryable, retryable, const Ok(_running)]);
      final delays = _ManualDelays();
      final supervisor = _supervisor(process, delays, now: () => now);
      await supervisor.ensureStarted();

      process.interrupt();
      await _flush();
      delays.complete(const Duration(seconds: 1)); // failure confirmation
      await _flush();
      for (final delay in const [
        Duration(seconds: 1),
        Duration(seconds: 5),
        Duration(seconds: 15),
      ]) {
        delays.complete(delay);
        await _pump();
      }
      expect(supervisor.current.state, EngineReadinessState.ready);

      now = now.add(const Duration(minutes: 10));
      await supervisor.checkNow();
      expect(supervisor.current.state, EngineReadinessState.ready);

      process.interrupt();
      await _flush();
      delays.complete(const Duration(seconds: 1));
      await _flush();

      expect(supervisor.current.state, EngineReadinessState.recovering);
      expect(supervisor.current.attempt, 1);
      await supervisor.shutdown();
    },
  );

  test('terminal startup failures never schedule automatic recovery', () async {
    const failures = <SuwayomiProcessFailure>[
      SuwayomiProcessFailure(
        kind: SuwayomiProcessFailureKind.artifactMissing,
        code: 'artifact_missing',
        message: 'missing',
      ),
      SuwayomiProcessFailure(
        kind: SuwayomiProcessFailureKind.artifactInvalid,
        code: 'artifact_invalid',
        message: 'invalid',
      ),
      SuwayomiProcessFailure(
        kind: SuwayomiProcessFailureKind.runtimeIncompatible,
        code: 'runtime_incompatible',
        message: 'runtime',
      ),
      SuwayomiProcessFailure(
        kind: SuwayomiProcessFailureKind.rootMismatch,
        code: 'root_mismatch',
        message: 'root',
      ),
      SuwayomiProcessFailure(
        kind: SuwayomiProcessFailureKind.ownershipUnverifiable,
        code: 'ownership',
        message: 'ownership',
      ),
    ];

    for (final failure in failures) {
      final process = _FakeProcess()
        ..startResults.add(Err<SuwayomiStatus>('failed', failure));
      final delays = _ManualDelays();
      final supervisor = _supervisor(process, delays);

      final result = await supervisor.ensureStarted();

      expect(result.state, EngineReadinessState.actionRequired);
      expect(process.recoverCalls, 0);
      expect(delays.requested, isEmpty);
      await supervisor.shutdown();
    }
  });

  test(
    'incompatible capabilities require action without recovery loop',
    () async {
      final process = _FakeProcess()
        ..compatibility = const SuwayomiCompatibilityResult.incompatible(
          SuwayomiCompatibilityFailure(
            SuwayomiCompatibilityFailureKind.capabilityMismatch,
            'missing_capability',
          ),
        );
      final delays = _ManualDelays();
      final supervisor = _supervisor(process, delays);

      final result = await supervisor.ensureStarted();

      expect(result.state, EngineReadinessState.actionRequired);
      expect(result.failure!.code, 'engine_incompatible');
      expect(process.recoverCalls, 0);
      expect(delays.requested, isEmpty);
      await supervisor.shutdown();
    },
  );

  test('unexpected start and compatibility errors are sanitized', () async {
    for (final process in <_FakeProcess>[
      _FakeProcess()..startError = StateError('secret start path'),
      _FakeProcess()..compatibilityError = StateError('secret schema'),
    ]) {
      final delays = _ManualDelays();
      final supervisor = _supervisor(process, delays);

      final result = await supervisor.ensureStarted();

      expect(result.state, EngineReadinessState.actionRequired);
      expect(result.failure!.message, 'O motor interno precisa de atenção.');
      expect(result.failure!.message, isNot(contains('secret')));
      expect(process.recoverCalls, 0);
      await supervisor.shutdown();
    }
  });

  test('health and recovery throws become sanitized failure', () async {
    final process = _FakeProcess()
      ..healthError = StateError('secret health')
      ..recoverError = StateError('secret recovery');
    final delays = _ManualDelays();
    final supervisor = _supervisor(process, delays);
    await supervisor.ensureStarted();

    final check = supervisor.checkNow();
    await _flush();
    delays.complete(const Duration(seconds: 1));
    await check;
    await _flush();
    delays.complete(const Duration(seconds: 1));
    await _flush();

    expect(supervisor.current.state, EngineReadinessState.actionRequired);
    expect(supervisor.current.failure!.code, 'engine_recovery_unclassified');
    expect(supervisor.current.failure!.message, isNot(contains('secret')));
    await supervisor.shutdown();
  });
}

ReadingEngineSupervisor _supervisor(
  _FakeProcess process,
  _ManualDelays delays, {
  SupervisorNow? now,
  ReadingEngineSupervisorPolicy? policy,
}) => ReadingEngineSupervisor(
  process: process,
  delay: delays.call,
  now: now,
  policy:
      policy ??
      const ReadingEngineSupervisorPolicy(
        healthInterval: Duration(seconds: 30),
      ),
);

const _running = SuwayomiStatus(state: SuwayomiProcessState.running);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await _flush();
  }
}

Future<bool> _isComplete(Future<Object?> future) async {
  var complete = false;
  future.then<void>((_) => complete = true, onError: (_) => complete = true);
  await _flush();
  return complete;
}

final class _ManualDelays {
  final requested = <Duration>[];
  final Map<Duration, ListQueue<Completer<void>>> _pending = {};

  Future<void> call(Duration duration) {
    requested.add(duration);
    final completer = Completer<void>();
    (_pending[duration] ??= ListQueue()).add(completer);
    return completer.future;
  }

  int pending(Duration duration) => _pending[duration]?.length ?? 0;

  void complete(Duration duration) {
    final queue = _pending[duration];
    if (queue == null || queue.isEmpty) {
      fail('No pending delay for $duration. Requested: $requested');
    }
    queue.removeFirst().complete();
  }
}

final class _FakeProcess implements ManagedReadingEngineProcess {
  final StreamController<Object?> _interruptions =
      StreamController<Object?>.broadcast(sync: true);
  final ListQueue<Result<SuwayomiStatus>> startResults = ListQueue();
  final ListQueue<Result<SuwayomiStatus>> recoverResults = ListQueue();
  final ListQueue<bool> healthResults = ListQueue();
  final List<Duration> startTimeouts = [];
  int startCalls = 0;
  int recoverCalls = 0;
  int healthCalls = 0;
  int shutdownCalls = 0;
  int beginShutdownCalls = 0;
  int compatibilityCalls = 0;
  bool holdStart = false;
  bool holdRecover = false;
  bool holdCompatibility = false;
  Completer<Result<SuwayomiStatus>>? _heldStart;
  Completer<Result<SuwayomiStatus>>? _heldRecover;
  Completer<SuwayomiCompatibilityResult>? _heldCompatibility;
  Object? startError;
  Object? recoverError;
  Object? healthError;
  Object? compatibilityError;
  SuwayomiCompatibilityResult compatibility =
      SuwayomiCompatibilityResult.compatible(
        engineVersion: 'v2.3.2238-r2238',
        protocolVersion: 'v1',
        capabilities: const ['library'],
      );

  @override
  Stream<Object?> get interruptions => _interruptions.stream;

  @override
  void beginShutdown() {
    beginShutdownCalls++;
  }

  void interrupt() => _interruptions.add(null);

  void completeStart(Result<SuwayomiStatus> result) =>
      _heldStart!.complete(result);

  void completeRecover(Result<SuwayomiStatus> result) =>
      _heldRecover!.complete(result);

  void completeCompatibility() => _heldCompatibility!.complete(compatibility);

  @override
  Future<Result<SuwayomiStatus>> start({required Duration timeout}) {
    startCalls++;
    startTimeouts.add(timeout);
    if (startError != null) return Future.error(startError!);
    if (holdStart) {
      _heldStart = Completer<Result<SuwayomiStatus>>();
      return _heldStart!.future;
    }
    return Future.value(
      startResults.isEmpty ? const Ok(_running) : startResults.removeFirst(),
    );
  }

  @override
  Future<Result<SuwayomiStatus>> recover() {
    recoverCalls++;
    if (recoverError != null) return Future.error(recoverError!);
    if (holdRecover) {
      _heldRecover = Completer<Result<SuwayomiStatus>>();
      return _heldRecover!.future;
    }
    return Future.value(
      recoverResults.isEmpty
          ? const Ok(_running)
          : recoverResults.removeFirst(),
    );
  }

  @override
  Future<bool> checkHealth() async {
    healthCalls++;
    if (healthError != null) throw healthError!;
    return healthResults.isEmpty ? true : healthResults.removeFirst();
  }

  @override
  Future<SuwayomiCompatibilityResult> checkCompatibility() async {
    compatibilityCalls++;
    if (compatibilityError != null) throw compatibilityError!;
    if (holdCompatibility) {
      _heldCompatibility = Completer<SuwayomiCompatibilityResult>();
      return _heldCompatibility!.future;
    }
    return compatibility;
  }

  @override
  EngineDiagnosticsSnapshot diagnostics({
    required EngineReadinessSnapshot readiness,
    required EngineCompatibilityStatus compatibility,
    required EngineOwnershipStatus ownership,
    required DateTime? lastHealthCheck,
    required SuwayomiCompatibilityResult? compatibilityResult,
  }) => EngineDiagnosticsSnapshot(
    readiness: readiness,
    engineName: 'Fake',
    compatibility: compatibility,
    ownership: ownership,
    lastHealthCheck: lastHealthCheck,
  );

  @override
  Future<void> shutdown() async {
    shutdownCalls++;
  }
}
