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
///
/// Order: managed app-support JRE → monorepo/vendor JRE 21 → YOMU_JAVA_HOME
/// → JAVA_HOME → PATH. Never picks a too-old runtime if a newer candidate exists.
class JavaResolver {
  const JavaResolver();

  Future<JavaResolution?> resolve({
    required SuwayomiPaths paths,
    int minMajor = 21,
  }) async {
    // Best-effort: seed app-support JRE from monorepo vendor once.
    await ensureManagedJre(paths);

    final candidates = <({String exe, String source})>[];
    final seen = <String>{};

    void add(String? exe, String source) {
      if (exe == null || exe.isEmpty) return;
      final norm = p.normalize(exe);
      if (!File(norm).existsSync()) return;
      final key = norm.toLowerCase();
      if (seen.contains(key)) return;
      seen.add(key);
      candidates.add((exe: norm, source: source));
    }

    add(_bundledJava(paths), 'bundled');
    for (final v in _findVendorJreExecutables()) {
      add(v, 'vendor-jre21');
    }

    final yomuJava = Platform.environment['YOMU_JAVA_HOME'];
    if (yomuJava != null && yomuJava.isNotEmpty) {
      add(
        p.join(
          yomuJava,
          'bin',
          Platform.isWindows ? 'java.exe' : 'java',
        ),
        'YOMU_JAVA_HOME',
      );
    }

    final fromEnv = Platform.environment['JAVA_HOME'];
    if (fromEnv != null && fromEnv.isNotEmpty) {
      add(
        p.join(
          fromEnv,
          'bin',
          Platform.isWindows ? 'java.exe' : 'java',
        ),
        'JAVA_HOME',
      );
    }

    final onPath = await _whichJava();
    add(onPath, 'PATH');

    JavaResolution? bestTooOld;
    final tried = <String>[];

    for (final c in candidates) {
      final v = await _probeMajor(c.exe);
      if (v == null) {
        tried.add('${c.source}: unreadable');
        continue;
      }
      tried.add('${c.source}: $v');
      if (v >= minMajor) {
        return JavaResolution(
          javaExecutable: c.exe,
          versionMajor: v,
          source: c.source,
        );
      }
      // Keep the newest too-old for a clearer error (prefer reporting 17 over 11).
      if (bestTooOld == null || v > bestTooOld.versionMajor) {
        bestTooOld = JavaResolution(
          javaExecutable: c.exe,
          versionMajor: v,
          source: '${c.source}(too-old)',
        );
      }
    }

    // Attach search hint to too-old result message at call site via source.
    if (bestTooOld != null) {
      return JavaResolution(
        javaExecutable: bestTooOld.javaExecutable,
        versionMajor: bestTooOld.versionMajor,
        source: '${bestTooOld.source}; tried=[${tried.join(', ')}]',
      );
    }
    return null;
  }

  /// Copies monorepo `vendor/jre21` into managed `runtime/jre` if missing.
  Future<void> ensureManagedJre(SuwayomiPaths paths) async {
    final destJava = File(
      p.join(paths.jreDir.path, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
    );
    if (destJava.existsSync()) return;

    final vendorRoot = _findVendorJreRoot();
    if (vendorRoot == null) return;

    try {
      await paths.jreDir.create(recursive: true);
      await _copyDir(Directory(vendorRoot), paths.jreDir);
    } catch (_) {
      // Non-fatal; resolve() still searches vendor path directly.
    }
  }

  Future<void> _copyDir(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list(recursive: false, followLinks: false)) {
      final name = p.basename(entity.path);
      final destPath = p.join(to.path, name);
      if (entity is Directory) {
        await _copyDir(entity, Directory(destPath));
      } else if (entity is File) {
        await entity.copy(destPath);
      }
    }
  }

  /// Absolute paths to java.exe under any discovered vendor/jre21.
  List<String> _findVendorJreExecutables() {
    final roots = _searchRoots();
    final out = <String>[];
    final javaName = Platform.isWindows ? 'java.exe' : 'java';
    for (final root in roots) {
      final exe = p.join(
        root,
        'packages',
        'yomu_suwayomi',
        'vendor',
        'jre21',
        'bin',
        javaName,
      );
      if (File(exe).existsSync()) out.add(exe);
      // Also: root itself is vendor/jre21
      final direct = p.join(root, 'bin', javaName);
      if (File(direct).existsSync() &&
          p.basename(p.dirname(root)).toLowerCase().contains('jre')) {
        out.add(direct);
      }
    }
    return out;
  }

  String? _findVendorJreRoot() {
    final javaName = Platform.isWindows ? 'java.exe' : 'java';
    for (final root in _searchRoots()) {
      final jreRoot = p.join(
        root,
        'packages',
        'yomu_suwayomi',
        'vendor',
        'jre21',
      );
      if (File(p.join(jreRoot, 'bin', javaName)).existsSync()) {
        return jreRoot;
      }
    }
    return null;
  }

  /// Walk cwd, executable dir, and parents far enough for Flutter Debug builds.
  List<String> _searchRoots() {
    final roots = <String>[];
    void walk(String start, int maxUp) {
      var dir = Directory(p.normalize(start));
      for (var i = 0; i < maxUp; i++) {
        roots.add(dir.path);
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }

    walk(Directory.current.path, 14);
    try {
      walk(File(Platform.resolvedExecutable).parent.path, 14);
    } catch (_) {}

    // Dedup preserve order
    final seen = <String>{};
    return roots.where((r) => seen.add(r.toLowerCase())).toList();
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
      // "21.0.11" or "1.8.0_xxx"
      final m21 = RegExp(r'version "(\d+)').firstMatch(text);
      if (m21 != null) {
        final major = int.tryParse(m21.group(1)!);
        if (major != null && major >= 2) return major; // skip 1.x style below
        if (major == 1) {
          final legacy = RegExp(r'version "1\.(\d+)').firstMatch(text);
          if (legacy != null) return int.tryParse(legacy.group(1)!);
        }
        return major;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
