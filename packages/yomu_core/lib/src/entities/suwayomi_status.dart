/// Lifecycle of the managed Suwayomi-Server process.
enum SuwayomiProcessState {
  stopped,
  starting,
  running,
  unhealthy,
  crashed,
  stopping,
}

/// Snapshot shown in the desktop status bar and health API.
class SuwayomiStatus {
  const SuwayomiStatus({
    required this.state,
    this.version,
    this.baseUrl,
    this.message,
    this.pid,
    this.lastHealthCheck,
  });

  final SuwayomiProcessState state;
  final String? version;
  final String? baseUrl;
  final String? message;
  final int? pid;
  final DateTime? lastHealthCheck;

  bool get isReady => state == SuwayomiProcessState.running;

  SuwayomiStatus copyWith({
    SuwayomiProcessState? state,
    String? version,
    String? baseUrl,
    String? message,
    int? pid,
    DateTime? lastHealthCheck,
  }) {
    return SuwayomiStatus(
      state: state ?? this.state,
      version: version ?? this.version,
      baseUrl: baseUrl ?? this.baseUrl,
      message: message ?? this.message,
      pid: pid ?? this.pid,
      lastHealthCheck: lastHealthCheck ?? this.lastHealthCheck,
    );
  }

  Map<String, Object?> toJson() => {
        'state': state.name,
        'version': version,
        'baseUrl': baseUrl,
        'message': message,
        'pid': pid,
        'lastHealthCheck': lastHealthCheck?.toIso8601String(),
        'isReady': isReady,
      };
}
