enum SuwayomiProcessFailureKind {
  artifactMissing,
  artifactInvalid,
  runtimeMissing,
  runtimeIncompatible,
  foreignPort,
  ownershipUnverifiable,
  rootMismatch,
  launchFailed,
  readinessTimeout,
  stopUnconfirmed,
  unexpected,
}

final class SuwayomiProcessFailure implements Exception {
  const SuwayomiProcessFailure({
    required this.kind,
    required this.code,
    required this.message,
    this.cause,
  });

  final SuwayomiProcessFailureKind kind;
  final String code;
  final String message;
  final Object? cause;

  bool get retryable => switch (kind) {
    SuwayomiProcessFailureKind.launchFailed ||
    SuwayomiProcessFailureKind.readinessTimeout => true,
    _ => false,
  };

  @override
  String toString() => 'SuwayomiProcessFailure($code)';
}
