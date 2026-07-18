import 'package:yomu_core/yomu_core.dart';

import '../process/suwayomi_process_manager.dart';

/// Maps the managed process lifecycle to the product-level readiness contract.
///
/// Process details and upstream messages deliberately never cross this adapter.
final class SuwayomiEngineReadinessAdapter implements EngineReadiness {
  SuwayomiEngineReadinessAdapter.fromManager(SuwayomiProcessManager manager)
    : this(status: () => manager.status, statusChanges: manager.statusStream);

  SuwayomiEngineReadinessAdapter({
    required SuwayomiStatus Function() status,
    required Stream<SuwayomiStatus> statusChanges,
  }) : _status = status,
       _statusChanges = statusChanges;

  final SuwayomiStatus Function() _status;
  final Stream<SuwayomiStatus> _statusChanges;

  @override
  EngineReadinessSnapshot get current => _map(_status());

  @override
  Stream<EngineReadinessSnapshot> get changes =>
      _statusChanges.map(_map).distinct();

  static EngineReadinessSnapshot _map(SuwayomiStatus status) {
    return switch (status.state) {
      SuwayomiProcessState.stopped => const EngineReadinessSnapshot(
        state: EngineReadinessState.actionRequired,
        failure: EngineFailure(
          kind: EngineFailureKind.actionRequired,
          code: 'engine_action_required',
          message: 'Recursos de leitura não estão disponíveis no momento.',
          retryable: true,
        ),
      ),
      SuwayomiProcessState.starting => const EngineReadinessSnapshot(
        state: EngineReadinessState.starting,
      ),
      SuwayomiProcessState.running => const EngineReadinessSnapshot(
        state: EngineReadinessState.ready,
      ),
      SuwayomiProcessState.unhealthy => const EngineReadinessSnapshot(
        state: EngineReadinessState.temporarilyUnavailable,
        failure: EngineFailure(
          kind: EngineFailureKind.temporarilyUnavailable,
          code: 'engine_temporarily_unavailable',
          message: 'Recursos de leitura temporariamente indisponíveis.',
          retryable: true,
        ),
      ),
      SuwayomiProcessState.crashed => const EngineReadinessSnapshot(
        state: EngineReadinessState.temporarilyUnavailable,
        failure: EngineFailure(
          kind: EngineFailureKind.temporarilyUnavailable,
          code: 'engine_interrupted',
          message: 'Os recursos de leitura foram interrompidos.',
          retryable: true,
        ),
      ),
      SuwayomiProcessState.stopping => const EngineReadinessSnapshot(
        state: EngineReadinessState.shuttingDown,
      ),
    };
  }
}
