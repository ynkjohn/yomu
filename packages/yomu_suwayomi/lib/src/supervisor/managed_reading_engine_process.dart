import 'package:yomu_core/yomu_core.dart';

import '../compatibility/suwayomi_compatibility_probe.dart';
import '../process/process_ownership.dart';
import '../process/suwayomi_process_manager.dart';

abstract interface class ManagedReadingEngineProcess {
  Stream<Object?> get interruptions;

  void beginShutdown();

  Future<Result<SuwayomiStatus>> start({required Duration timeout});

  Future<Result<SuwayomiStatus>> recover();

  Future<bool> checkHealth();

  Future<SuwayomiCompatibilityResult> checkCompatibility();

  EngineDiagnosticsSnapshot diagnostics({
    required EngineReadinessSnapshot readiness,
    required EngineCompatibilityStatus compatibility,
    required EngineOwnershipStatus ownership,
    required DateTime? lastHealthCheck,
    required SuwayomiCompatibilityResult? compatibilityResult,
  });

  Future<void> shutdown();
}

final class SuwayomiManagedReadingEngineProcess
    implements ManagedReadingEngineProcess {
  SuwayomiManagedReadingEngineProcess({
    required this.manager,
    required this.probe,
  });

  final SuwayomiProcessManager manager;
  final SuwayomiCompatibilityProbe probe;

  @override
  Stream<Object?> get interruptions => manager.statusStream.where(
    (status) =>
        status.state == SuwayomiProcessState.crashed ||
        status.state == SuwayomiProcessState.unhealthy,
  );

  @override
  void beginShutdown() => manager.beginShutdown();

  @override
  Future<Result<SuwayomiStatus>> start({required Duration timeout}) =>
      manager.start(readyTimeout: timeout);

  @override
  Future<Result<SuwayomiStatus>> recover() => manager.restart();

  @override
  Future<bool> checkHealth() async {
    final ownership = await manager.verifyCurrentOwnership();
    if (ownership.verdict != OwnershipVerdict.yomuOwned) return false;
    return probe.checkPinnedHealth();
  }

  @override
  Future<SuwayomiCompatibilityResult> checkCompatibility() => probe.run();

  @override
  EngineDiagnosticsSnapshot diagnostics({
    required EngineReadinessSnapshot readiness,
    required EngineCompatibilityStatus compatibility,
    required EngineOwnershipStatus ownership,
    required DateTime? lastHealthCheck,
    required SuwayomiCompatibilityResult? compatibilityResult,
  }) {
    final identity = manager.identity;
    final manifest = manager.manifest;
    return EngineDiagnosticsSnapshot(
      readiness: readiness,
      engineName: 'Suwayomi',
      engineVersion:
          compatibilityResult?.engineVersion ??
          manifest.suwayomi.displayVersion,
      protocolVersion:
          compatibilityResult?.protocolVersion ??
          manifest.compatibility.restApiVersion,
      capabilities:
          compatibilityResult?.capabilities ??
          manifest.compatibility.capabilities,
      runtimeName: manifest.jre?.vendor ?? 'Java',
      runtimeVersion: manifest.jre?.version,
      processId: identity?.pid ?? manager.status.pid,
      host: manager.host,
      port: manager.port,
      artifactPath:
          identity?.jarPath ??
          manager.paths.jarFile(manifest.suwayomi.jarFile).absolute.path,
      dataRoot: manager.managedRootDir,
      compatibility: compatibility,
      ownership: ownership,
      lastHealthCheck: lastHealthCheck,
    );
  }

  @override
  Future<void> shutdown() async {
    await manager.shutdown();
    await manager.closeAfterShutdown();
  }
}
