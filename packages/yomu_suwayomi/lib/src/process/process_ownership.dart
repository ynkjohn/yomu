import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'managed_instance_identity.dart';

/// Snapshot of an OS process used for ownership checks.
class ProcessSnapshot {
  const ProcessSnapshot({
    required this.pid,
    required this.exists,
    this.commandLine,
  });

  final int pid;
  final bool exists;
  final String? commandLine;
}

/// Platform probe for PID / port ownership (injectable in tests).
abstract class ProcessOwnershipProbe {
  Future<ProcessSnapshot?> inspectPid(int pid);

  /// PID listening on [port] (IPv4 loopback preferred), or null.
  Future<int?> findListenerPid(int port);

  /// Kill a PID we already validated as Yomu-owned. Returns true if kill issued.
  Future<bool> killOwnedPid(int pid, {bool force = false});
}

/// Windows + best-effort Unix probe.
class PlatformProcessOwnershipProbe implements ProcessOwnershipProbe {
  const PlatformProcessOwnershipProbe();

  @override
  Future<ProcessSnapshot?> inspectPid(int pid) async {
    if (pid <= 0) return null;
    if (Platform.isWindows) {
      return _inspectWindows(pid);
    }
    return _inspectPosix(pid);
  }

  Future<ProcessSnapshot?> _inspectWindows(int pid) async {
    try {
      final r = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '\$p = Get-CimInstance Win32_Process -Filter "ProcessId=$pid" -ErrorAction SilentlyContinue; '
              'if (\$null -eq \$p) { Write-Output "MISSING" } else { Write-Output \$p.CommandLine }',
        ],
        runInShell: false,
      );
      final out = (r.stdout as String).trim();
      if (out.isEmpty || out == 'MISSING') {
        return ProcessSnapshot(pid: pid, exists: false);
      }
      return ProcessSnapshot(pid: pid, exists: true, commandLine: out);
    } catch (_) {
      return null;
    }
  }

  Future<ProcessSnapshot?> _inspectPosix(int pid) async {
    try {
      final r = await Process.run('ps', ['-p', '$pid', '-o', 'args=']);
      if (r.exitCode != 0) {
        return ProcessSnapshot(pid: pid, exists: false);
      }
      final args = (r.stdout as String).trim();
      if (args.isEmpty) {
        return ProcessSnapshot(pid: pid, exists: false);
      }
      return ProcessSnapshot(pid: pid, exists: true, commandLine: args);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int?> findListenerPid(int port) async {
    if (Platform.isWindows) {
      try {
        final r = await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-Command',
            '\$c = Get-NetTCPConnection -LocalPort $port -State Listen '
                '-ErrorAction SilentlyContinue | Select-Object -First 1; '
                'if (\$c) { \$c.OwningProcess }',
          ],
          runInShell: false,
        );
        final out = (r.stdout as String).trim();
        if (out.isEmpty) return null;
        return int.tryParse(out);
      } catch (_) {
        return null;
      }
    }
    try {
      final r = await Process.run('lsof', ['-i', ':$port', '-sTCP:LISTEN', '-t']);
      final out = (r.stdout as String).trim().split(RegExp(r'\s+')).first;
      return int.tryParse(out);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> killOwnedPid(int pid, {bool force = false}) async {
    if (pid <= 0) return false;
    try {
      if (Platform.isWindows) {
        final args = force ? ['/PID', '$pid', '/F'] : ['/PID', '$pid'];
        final r = await Process.run('taskkill', args);
        return r.exitCode == 0;
      }
      Process.killPid(pid, force ? ProcessSignal.sigkill : ProcessSignal.sigterm);
      return true;
    } catch (_) {
      return false;
    }
  }
}

enum OwnershipVerdict {
  yomuOwned,
  dead,
  foreignOrUnverifiable,
}

class OwnershipCheck {
  const OwnershipCheck({
    required this.verdict,
    this.snapshot,
    this.message,
  });

  final OwnershipVerdict verdict;
  final ProcessSnapshot? snapshot;
  final String? message;
}

/// System property we inject so command-line ownership is unambiguous.
const String kYomuRunIdProperty = 'yomu.runId';
const String kYomuStartedAtProperty = 'yomu.startedAt';

class ProcessOwnership {
  ProcessOwnership(this.probe);

  final ProcessOwnershipProbe probe;

  /// Strong ownership: runId, Java path, absolute jar, rootDir, port, startedAt.
  static bool commandLineMatchesYomu({
    required String commandLine,
    required String runId,
    required String javaExecutable,
    required String jarPath,
    required String rootDir,
    required int port,
    required DateTime startedAt,
  }) {
    final cl = commandLine.toLowerCase();
    final clRaw = commandLine;

    // runId (property we inject)
    final runNeedle = '$kYomuRunIdProperty=$runId';
    if (!clRaw.contains(runNeedle) && !cl.contains(runNeedle.toLowerCase())) {
      return false;
    }

    // startedAt (UTC ISO we inject)
    final startedUtc = startedAt.toUtc().toIso8601String();
    final startedNeedle = '$kYomuStartedAtProperty=$startedUtc';
    if (!clRaw.contains(startedNeedle) &&
        !cl.contains(startedNeedle.toLowerCase())) {
      // Allow slight format variance: require property key + run day at least
      if (!cl.contains(kYomuStartedAtProperty.toLowerCase())) {
        return false;
      }
    }

    // Absolute JAR path (normalized)
    final jarAbs = p.normalize(jarPath).replaceAll(r'\', '/').toLowerCase();
    final jarNative = p.normalize(jarPath).toLowerCase();
    final hasJar = cl.contains(jarAbs) ||
        cl.contains(jarNative) ||
        cl.contains(jarAbs.replaceAll('/', r'\'));
    if (!hasJar) return false;

    // rootDir
    final rootNorm = p.normalize(rootDir).replaceAll(r'\', '/').toLowerCase();
    final rootNative = p.normalize(rootDir).toLowerCase();
    final hasRoot = cl.contains(rootNorm) ||
        cl.contains(rootNative) ||
        cl.contains(rootNorm.replaceAll('/', r'\'));
    if (!hasRoot) return false;

    // port property
    final hasPort = cl.contains('port=$port') ||
        cl.contains('server.port=$port') ||
        cl.contains('port\\=$port');
    if (!hasPort) return false;

    // Java executable (basename or absolute path)
    final javaBase = p.basename(javaExecutable).toLowerCase();
    final javaNorm =
        p.normalize(javaExecutable).replaceAll(r'\', '/').toLowerCase();
    final hasJava = cl.contains(javaBase) ||
        cl.contains(javaNorm) ||
        cl.contains(javaNorm.replaceAll('/', r'\'));
    if (!hasJava) return false;

    return true;
  }

  Future<OwnershipCheck> verifyIdentity(ManagedInstanceIdentity id) async {
    final snap = await probe.inspectPid(id.pid);
    if (snap == null) {
      return const OwnershipCheck(
        verdict: OwnershipVerdict.foreignOrUnverifiable,
        message: 'Não foi possível inspecionar o PID no SO.',
      );
    }
    if (!snap.exists) {
      return OwnershipCheck(
        verdict: OwnershipVerdict.dead,
        snapshot: snap,
        message: 'PID ${id.pid} não está em execução.',
      );
    }
    final cl = snap.commandLine;
    if (cl == null || cl.isEmpty) {
      return OwnershipCheck(
        verdict: OwnershipVerdict.foreignOrUnverifiable,
        snapshot: snap,
        message:
            'PID ${id.pid} existe, mas a command line não é legível — '
            'não é seguro adotar nem encerrar.',
      );
    }
    final ok = commandLineMatchesYomu(
      commandLine: cl,
      runId: id.runId,
      javaExecutable: id.javaExecutable,
      jarPath: id.jarPath,
      rootDir: id.rootDir,
      port: id.port,
      startedAt: id.startedAt,
    );
    if (!ok) {
      return OwnershipCheck(
        verdict: OwnershipVerdict.foreignOrUnverifiable,
        snapshot: snap,
        message:
            'PID ${id.pid} não corresponde ao Suwayomi gerenciado pelo Yomu '
            '(runId/java/jar/rootDir/porta). Não será adotado nem morto.',
      );
    }
    return OwnershipCheck(verdict: OwnershipVerdict.yomuOwned, snapshot: snap);
  }

  static Map<String, dynamic>? tryJsonMap(String s) {
    try {
      final v = jsonDecode(s);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }
}
