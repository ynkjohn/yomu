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
    return ManagedInstanceIdentity(
      runId: '${json['runId']}',
      pid: json['pid'] is int ? json['pid'] as int : int.parse('${json['pid']}'),
      startedAt: DateTime.tryParse('${json['startedAt']}') ?? DateTime.now().toUtc(),
      javaExecutable: '${json['javaExecutable']}',
      jarPath: '${json['jarPath']}',
      rootDir: '${json['rootDir']}',
      port: json['port'] is int ? json['port'] as int : int.parse('${json['port']}'),
    );
  }

  /// Atomic replace: write temp, then swap without deleting the live file first.
  ///
  /// Windows: rename live → .bak, rename .tmp → live, delete .bak.
  /// On failure after moving live away, restore from .bak.
  Future<void> save(File file) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    final bak = File('${file.path}.bak');
    await tmp.writeAsString(jsonEncode(toJson()), flush: true);

    if (!file.existsSync()) {
      await tmp.rename(file.path);
      return;
    }

    if (bak.existsSync()) {
      await bak.delete();
    }
    await file.rename(bak.path);
    try {
      await tmp.rename(file.path);
    } catch (e) {
      // Restore previous identity if swap failed.
      if (bak.existsSync() && !file.existsSync()) {
        await bak.rename(file.path);
      }
      rethrow;
    }
    if (bak.existsSync()) {
      await bak.delete();
    }
  }

  static Future<ManagedInstanceIdentity?> load(File file) async {
    if (!file.existsSync()) return null;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      return ManagedInstanceIdentity.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
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
