import 'engine_readiness.dart';

/// Product-level lifecycle for the internal reading engine.
///
/// Implementations own startup, bounded recovery and shutdown coordination.
/// Vendor process details remain behind the reading-engine boundary.
abstract interface class EngineLifecycle implements EngineReadiness {
  /// Ensures the engine is started. Concurrent callers must share one flight.
  Future<EngineReadinessSnapshot> ensureStarted();

  /// Explicit user retry. Implementations may reset a bounded recovery budget.
  Future<EngineReadinessSnapshot> retry();

  /// Prevents new lifecycle work and publishes [EngineReadinessState.shuttingDown].
  void beginShutdown();

  /// Stops only resources whose ownership was proven by the implementation.
  Future<void> shutdown();
}
