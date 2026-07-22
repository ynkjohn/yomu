import 'dart:collection';

import 'engine_readiness.dart';

enum EngineCompatibilityStatus { unknown, compatible, incompatible }

enum EngineOwnershipStatus { none, owned, foreign, inconclusive }

/// Technical support snapshot. Common product UI should consume readiness only.
final class EngineDiagnosticsSnapshot {
  EngineDiagnosticsSnapshot({
    required this.readiness,
    required this.engineName,
    required this.compatibility,
    required this.ownership,
    this.engineVersion,
    this.protocolVersion,
    Iterable<String> capabilities = const [],
    this.runtimeName,
    this.runtimeVersion,
    this.processId,
    this.host,
    this.port,
    this.artifactPath,
    this.dataRoot,
    this.lastHealthCheck,
  }) : capabilities = UnmodifiableListView<String>(
         List<String>.from(capabilities),
       );

  final EngineReadinessSnapshot readiness;
  final String engineName;
  final String? engineVersion;
  final String? protocolVersion;
  final List<String> capabilities;
  final String? runtimeName;
  final String? runtimeVersion;
  final int? processId;
  final String? host;
  final int? port;
  final String? artifactPath;
  final String? dataRoot;
  final EngineCompatibilityStatus compatibility;
  final EngineOwnershipStatus ownership;
  final DateTime? lastHealthCheck;
}

abstract interface class EngineDiagnostics {
  EngineDiagnosticsSnapshot get diagnostics;

  Stream<EngineDiagnosticsSnapshot> get diagnosticChanges;
}
