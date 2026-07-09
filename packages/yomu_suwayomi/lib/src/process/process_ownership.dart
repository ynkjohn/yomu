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
        final args = force
            ? ['/PID', '$pid', '/F']
            : ['/PID', '$pid'];
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

/// Result of validating whether a process belongs to Yomu-managed Suwayomi.
enum OwnershipVerdict {
  /// PID alive and command line matches jar + rootDir + port.
  yomuOwned,

  /// PID missing or dead.
  dead,

  /// Process exists but is not our managed instance (or cannot prove ownership).
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

class ProcessOwnership {
  ProcessOwnership(this.probe);

  final ProcessOwnershipProbe probe;

  /// True if [commandLine] matches jar path/name, rootDir property, and port.
  static bool commandLineMatchesYomu({
    required String commandLine,
    required String jarPath,
    required String rootDir,
    required int port,
  }) {
    final cl = commandLine.toLowerCase();
    final jarName = p.basename(jarPath).toLowerCase();
    final jarNorm = jarPath.replaceAll(r'\', '/').toLowerCase();
    final rootNorm = rootDir.replaceAll(r'\', '/').toLowerCase();
    final rootNative = rootDir.toLowerCase();

    final hasJar = cl.contains(jarName) || cl.contains(jarNorm);
    final hasRoot = cl.contains(rootNorm) ||
        cl.contains(rootNative) ||
        cl.contains(rootNorm.replaceAll('/', r'\'));
    final hasPort = cl.contains('port=$port') ||
        cl.contains('port\\=$port') ||
        cl.contains(':$port');

    // Require jar + rootDir; port is strong signal when present.
    if (!hasJar || !hasRoot) return false;
    // If port appears in cmdline (our -D props), require match; otherwise jar+root enough.
    if (cl.contains('suwayomi.tachidesk.config.server.port') && !hasPort) {
      return false;
    }
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
      jarPath: id.jarPath,
      rootDir: id.rootDir,
      port: id.port,
    );
    if (!ok) {
      return OwnershipCheck(
        verdict: OwnershipVerdict.foreignOrUnverifiable,
        snapshot: snap,
        message:
            'PID ${id.pid} não corresponde ao Suwayomi gerenciado pelo Yomu '
            '(jar/rootDir/porta). Não será adotado nem morto.',
      );
    }
    return OwnershipCheck(verdict: OwnershipVerdict.yomuOwned, snapshot: snap);
  }

  /// Decode helper for tests.
  static Map<String, dynamic>? tryJsonMap(String s) {
    try {
      final v = jsonDecode(s);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }
}
