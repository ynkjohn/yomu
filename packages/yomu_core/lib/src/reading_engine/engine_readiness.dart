/// Product-level lifecycle exposed by the internal reading engine.
enum EngineReadinessState {
  initializing,
  starting,
  ready,
  recovering,
  temporarilyUnavailable,
  actionRequired,
  shuttingDown,
}

/// Stable failure categories. Vendor errors must be mapped before crossing the
/// reading-engine boundary.
enum EngineFailureKind {
  temporarilyUnavailable,
  actionRequired,
  incompatible,
  operationRejected,
  unknown,
}

/// Sanitized engine failure suitable for UI and Yomu Core responses.
final class EngineFailure {
  const EngineFailure({
    required this.kind,
    required this.code,
    required this.message,
    required this.retryable,
  });

  final EngineFailureKind kind;
  final String code;
  final String message;
  final bool retryable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EngineFailure &&
          kind == other.kind &&
          code == other.code &&
          message == other.message &&
          retryable == other.retryable;

  @override
  int get hashCode => Object.hash(kind, code, message, retryable);
}

/// Domain exception thrown by reading-engine capabilities.
final class EngineException implements Exception {
  const EngineException(this.failure);

  final EngineFailure failure;

  @override
  String toString() => 'EngineException(${failure.code}): ${failure.message}';
}

/// Public readiness snapshot. Operational implementation details belong in
/// diagnostics, not in this product-level state.
final class EngineReadinessSnapshot {
  const EngineReadinessSnapshot({
    required this.state,
    this.failure,
    this.attempt = 0,
    this.nextRetryAt,
  });

  final EngineReadinessState state;
  final EngineFailure? failure;
  final int attempt;
  final DateTime? nextRetryAt;

  bool get isReady => state == EngineReadinessState.ready;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EngineReadinessSnapshot &&
          state == other.state &&
          failure == other.failure &&
          attempt == other.attempt &&
          nextRetryAt == other.nextRetryAt;

  @override
  int get hashCode => Object.hash(state, failure, attempt, nextRetryAt);
}

abstract interface class EngineReadiness {
  EngineReadinessSnapshot get current;

  Stream<EngineReadinessSnapshot> get changes;
}
