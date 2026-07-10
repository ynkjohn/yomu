import 'dart:convert';
import 'dart:io';

/// Identity of a Suwayomi JVM started by Yomu (persisted across app restarts).
class ManagedInstanceIdentity {
  const ManagedInstanceIdentity({
    required this.runId,
    required this.pid,
    required this.startedAt,
    required this.javaExecutable,
    required this.jarPath,
    required this.rootDir,
    required this.port,
  });

  final String runId;
  final int pid;
  final DateTime startedAt;
  final String javaExecutable;
  final String jarPath;
  final String rootDir;
  final int port;

  /// Reject epoch-zero / unparseable sentinels.
  bool get hasValidStartedAt {
    if (startedAt.millisecondsSinceEpoch <= 0) return false;
    // Reject "now" fallback from corrupt files older than absurd future
    if (startedAt.isAfter(DateTime.now().toUtc().add(const Duration(days: 1)))) {
      return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'runId': runId,
        'pid': pid,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'javaExecutable': javaExecutable,
        'jarPath': jarPath,
        'rootDir': rootDir,
        'port': port,
      };

  factory ManagedInstanceIdentity.fromJson(Map<String, dynamic> json) {
    final startedRaw = json['startedAt'];
    final started = DateTime.tryParse('${startedRaw ?? ''}');
    if (started == null) {
      throw const FormatException('startedAt missing or invalid');
    }
    return ManagedInstanceIdentity(
      runId: '${json['runId']}',
      pid: json['pid'] is int ? json['pid'] as int : int.parse('${json['pid']}'),
      startedAt: started.toUtc(),
      javaExecutable: '${json['javaExecutable']}',
      jarPath: '${json['jarPath']}',
      rootDir: '${json['rootDir']}',
      port: json['port'] is int ? json['port'] as int : int.parse('${json['port']}'),
    );
  }

  /// Crash-safe replace with .bak recovery.
  Future<void> save(File file) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    final bak = File('${file.path}.bak');
    await tmp.writeAsString(jsonEncode(toJson()), flush: true);

    if (!file.existsSync()) {
      await tmp.rename(file.path);
      return;
    }

    // Move live -> bak only after tmp is durable.
    if (bak.existsSync()) await bak.delete();
    await file.rename(bak.path);
    try {
      await tmp.rename(file.path);
    } catch (e) {
      if (bak.existsSync() && !file.existsSync()) {
        await bak.rename(file.path);
      }
      if (tmp.existsSync()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
      rethrow;
    }
    if (bak.existsSync()) await bak.delete();
  }

  static Future<ManagedInstanceIdentity?> load(File file) async {
    Future<ManagedInstanceIdentity?> tryFile(File f) async {
      if (!f.existsSync()) return null;
      try {
        final raw = jsonDecode(await f.readAsString());
        if (raw is! Map) return null;
        final id = ManagedInstanceIdentity.fromJson(Map<String, dynamic>.from(raw));
        if (!id.hasValidStartedAt) return null;
        return id;
      } catch (_) {
        return null;
      }
    }

    final primary = await tryFile(file);
    if (primary != null) return primary;

    // Recovery from interrupted atomic write.
    final bak = File('${file.path}.bak');
    final recovered = await tryFile(bak);
    if (recovered != null) {
      try {
        await recovered.save(file);
      } catch (_) {}
      return recovered;
    }
    return null;
  }

  static Future<void> clear(File file) async {
    for (final f in [
      file,
      File('${file.path}.tmp'),
      File('${file.path}.bak'),
    ]) {
      if (f.existsSync()) await f.delete();
    }
  }
}
