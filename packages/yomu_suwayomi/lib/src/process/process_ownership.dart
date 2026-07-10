import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'managed_instance_identity.dart';

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

abstract class ProcessOwnershipProbe {
  Future<ProcessSnapshot?> inspectPid(int pid);
  Future<int?> findListenerPid(int port);
  Future<bool> killOwnedPid(int pid, {bool force = false});
}

class PlatformProcessOwnershipProbe implements ProcessOwnershipProbe {
  const PlatformProcessOwnershipProbe();

  @override
  Future<ProcessSnapshot?> inspectPid(int pid) async {
    if (pid <= 0) return null;
    if (Platform.isWindows) {
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
    try {
      final r = await Process.run('ps', ['-p', '$pid', '-o', 'args=']);
      if (r.exitCode != 0) return ProcessSnapshot(pid: pid, exists: false);
      final args = (r.stdout as String).trim();
      if (args.isEmpty) return ProcessSnapshot(pid: pid, exists: false);
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
      return Process.killPid(
        pid,
        force ? ProcessSignal.sigkill : ProcessSignal.sigterm,
      );
    } catch (_) {
      return false;
    }
  }
}

enum OwnershipVerdict { yomuOwned, dead, foreignOrUnverifiable }

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

const String kYomuRunIdProperty = 'yomu.runId';
const String kYomuStartedAtProperty = 'yomu.startedAt';

class ProcessOwnership {
  ProcessOwnership(this.probe);

  final ProcessOwnershipProbe probe;

  /// Split a process command line into real argv-style tokens (quoted groups).
  static List<String> tokenizeCommandLine(String commandLine) {
    final tokens = <String>[];
    final buf = StringBuffer();
    var inDouble = false;
    var inSingle = false;
    for (var i = 0; i < commandLine.length; i++) {
      final c = commandLine[i];
      if (c == '"' && !inSingle) {
        inDouble = !inDouble;
        continue;
      }
      if (c == "'" && !inDouble && !Platform.isWindows) {
        inSingle = !inSingle;
        continue;
      }
      if (!inDouble && !inSingle && (c == ' ' || c == '\t')) {
        if (buf.isNotEmpty) {
          tokens.add(buf.toString());
          buf.clear();
        }
        continue;
      }
      buf.write(c);
    }
    if (buf.isNotEmpty) tokens.add(buf.toString());
    return tokens;
  }

  static String _normPath(String path) {
    return p.normalize(path).replaceAll(r'\', '/');
  }

  static bool _pathEquals(String a, String b) {
    final na = _normPath(a);
    final nb = _normPath(b);
    if (Platform.isWindows) {
      return na.toLowerCase() == nb.toLowerCase();
    }
    return na == nb;
  }

  static const String _kRootDirProp = 'suwayomi.tachidesk.config.server.rootDir';
  static const String _kPortProp = 'suwayomi.tachidesk.config.server.port';

  /// Exact token match:
  /// - first token = absolute Java
  /// - exactly one `-jar`, with expected absolute JAR as the next token
  /// - Yomu ownership `-D` props appear exactly once each, before `-jar`
  /// - duplicate property keys rejected even if one value is correct
  static bool commandLineMatchesYomu({
    required String commandLine,
    required String runId,
    required String javaExecutable,
    required String jarPath,
    required String rootDir,
    required int port,
    required DateTime startedAt,
  }) {
    final tokens = tokenizeCommandLine(commandLine);
    if (tokens.isEmpty) return false;

    final javaAbs = File(javaExecutable).absolute.path;
    if (!_pathEquals(tokens.first, javaAbs)) return false;

    final jarAbs = File(jarPath).absolute.path;
    final rootAbs = Directory(rootDir).absolute.path;
    final rootSlash = _normPath(rootAbs);
    final startedUtc = startedAt.toUtc().toIso8601String();

    // Exactly one -jar token; JAR path is the immediate next token.
    final jarIdxs = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i] == '-jar') jarIdxs.add(i);
    }
    if (jarIdxs.length != 1) return false;
    final jarIdx = jarIdxs.first;
    if (jarIdx + 1 >= tokens.length) return false;
    if (!_pathEquals(tokens[jarIdx + 1], jarAbs)) return false;

    // Ownership props: collect every -Dkey=value for the Yomu keys.
    final seen = <String, List<({int index, String value})>>{
      kYomuRunIdProperty: [],
      kYomuStartedAtProperty: [],
      _kRootDirProp: [],
      _kPortProp: [],
    };

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (!t.startsWith('-D')) continue;
      final eq = t.indexOf('=');
      if (eq <= 2) continue;
      final key = t.substring(2, eq);
      final value = t.substring(eq + 1);
      final list = seen[key];
      if (list != null) {
        list.add((index: i, value: value));
      }
    }

    bool propOk(String key, bool Function(String value) valueOk) {
      final list = seen[key]!;
      // Exactly once in the whole command line.
      if (list.length != 1) return false;
      final hit = list.single;
      // Must appear before -jar.
      if (hit.index >= jarIdx) return false;
      return valueOk(hit.value);
    }

    if (!propOk(kYomuRunIdProperty, (v) => v == runId)) return false;
    if (!propOk(kYomuStartedAtProperty, (v) => v == startedUtc)) return false;
    if (!propOk(_kPortProp, (v) => v == '$port')) return false;
    if (!propOk(_kRootDirProp, (v) {
      return _pathEquals(v, rootAbs) ||
          _pathEquals(v, rootSlash) ||
          _pathEquals(v, rootAbs.replaceAll('/', r'\'));
    })) {
      return false;
    }

    return true;
  }

  Future<OwnershipCheck> verifyIdentity(ManagedInstanceIdentity id) async {
    if (!id.hasValidStartedAt) {
      return const OwnershipCheck(
        verdict: OwnershipVerdict.foreignOrUnverifiable,
        message: 'Identidade com startedAt inválido — não será usada.',
      );
    }
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
            'PID ${id.pid} não corresponde aos tokens exatos Yomu '
            '(runId/startedAt/java/jar/rootDir/porta).',
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
