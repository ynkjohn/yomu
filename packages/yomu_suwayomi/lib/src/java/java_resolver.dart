import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/suwayomi_paths.dart';

class JavaResolution {
  const JavaResolution({
    required this.javaExecutable,
    required this.versionMajor,
    required this.source,
  });

  final String javaExecutable;
  final int versionMajor;
  final String source;
}

/// Locates a JRE/JDK suitable for Suwayomi (default min 21).
class JavaResolver {
  const JavaResolver();

  Future<JavaResolution?> resolve({
    required SuwayomiPaths paths,
    int minMajor = 21,
  }) async {
    final candidates = <({String exe, String source})>[];

    final bundled = _bundledJava(paths);
    if (bundled != null) {
      candidates.add((exe: bundled, source: 'bundled'));
    }

    final devJre = _devVendorJre();
    if (devJre != null) {
      candidates.add((exe: devJre, source: 'dev-vendor-jre21'));
    }

    final fromEnv = Platform.environment['JAVA_HOME'];
    if (fromEnv != null && fromEnv.isNotEmpty) {
      final exe = p.join(
        fromEnv,
        'bin',
        Platform.isWindows ? 'java.exe' : 'java',
      );
      if (File(exe).existsSync()) {
        candidates.add((exe: exe, source: 'JAVA_HOME'));
      }
    }

    final onPath = await _whichJava();
    if (onPath != null) {
      candidates.add((exe: onPath, source: 'PATH'));
    }

    JavaResolution? tooOld;
    for (final c in candidates) {
      final v = await _probeMajor(c.exe);
      if (v == null) continue;
      if (v >= minMajor) {
        return JavaResolution(
          javaExecutable: c.exe,
          versionMajor: v,
          source: c.source,
        );
      }
      tooOld ??= JavaResolution(
        javaExecutable: c.exe,
        versionMajor: v,
        source: '${c.source}(too-old)',
      );
    }

    return tooOld;
  }

  /// Monorepo dev helper: `packages/yomu_suwayomi/vendor/jre21`.
  String? _devVendorJre() {
    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      final exe = p.join(
        dir.path,
        'packages',
        'yomu_suwayomi',
        'vendor',
        'jre21',
        'bin',
        Platform.isWindows ? 'java.exe' : 'java',
      );
      if (File(exe).existsSync()) return exe;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  String? _bundledJava(SuwayomiPaths paths) {
    final candidates = [
      p.join(paths.jreDir.path, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
      p.join(
        paths.jreDir.path,
        'Contents',
        'Home',
        'bin',
        'java',
      ),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  Future<String?> _whichJava() async {
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        ['java'],
        runInShell: true,
      );
      if (result.exitCode != 0) return null;
      final lines = (result.stdout as String)
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);
      return lines.isEmpty ? null : lines.first;
    } catch (_) {
      return null;
    }
  }

  Future<int?> _probeMajor(String javaExecutable) async {
    try {
      final result = await Process.run(javaExecutable, ['-version']);
      // java -version writes to stderr.
      final text = '${result.stderr}\n${result.stdout}';
      final match = RegExp(r'version "(\d+)').firstMatch(text);
      if (match == null) return null;
      return int.tryParse(match.group(1)!);
    } catch (_) {
      return null;
    }
  }
}
