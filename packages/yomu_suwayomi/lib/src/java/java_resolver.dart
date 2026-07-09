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
/// Priority:
/// 1. [YOMU_JAVA_HOME] — **explicit override** (optional; only if version ≥ min)
/// 2. Packaged JRE next to the executable (`{exeDir}/jre`) — Release distribution
/// 3. Managed app-support JRE (`runtime/jre`)
/// 4. Monorepo `vendor/jre21` (dev)
/// 5. JAVA_HOME / PATH (system; never preferred over packaged 21)
class JavaResolver {
  const JavaResolver();

  Future<JavaResolution?> resolve({
    required SuwayomiPaths paths,
    int minMajor = 21,
  }) async {
    await ensureManagedJre(paths);

    final candidates = <({String exe, String source})>[];
    final seen = <String>{};

    void add(String? exe, String source) {
      if (exe == null || exe.isEmpty) return;
      final norm = p.normalize(File(exe).absolute.path);
      if (!File(norm).existsSync()) return;
      final key = norm.toLowerCase();
      if (!seen.add(key)) return;
      candidates.add((exe: norm, source: source));
    }

    // 1) Explicit override first (documented as override, not "force").
    final yomuJava = Platform.environment['YOMU_JAVA_HOME'];
    if (yomuJava != null && yomuJava.isNotEmpty) {
      add(
        p.join(yomuJava, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
        'YOMU_JAVA_HOME',
      );
    }

    // 2) Packaged beside executable (installer / Release layout).
    add(_packagedBesideExecutable(), 'packaged-jre');

    // 3) Managed runtime under app support.
    add(_bundledJava(paths), 'managed-jre');

    // 4) Dev monorepo vendor.
    for (final v in _findVendorJreExecutables()) {
      add(v, 'vendor-jre21');
    }

    // 5) System fallbacks.
    final fromEnv = Platform.environment['JAVA_HOME'];
    if (fromEnv != null && fromEnv.isNotEmpty) {
      add(
        p.join(fromEnv, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
        'JAVA_HOME',
      );
    }
    add(await _whichJava(), 'PATH');

    JavaResolution? bestTooOld;
    final tried = <String>[];

    // Prefer first candidate that meets minMajor (order = priority).
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
      if (bestTooOld == null || v > bestTooOld.versionMajor) {
        bestTooOld = JavaResolution(
          javaExecutable: c.exe,
          versionMajor: v,
          source: '${c.source}(too-old)',
        );
      }
    }

    if (bestTooOld != null) {
      return JavaResolution(
        javaExecutable: bestTooOld.javaExecutable,
        versionMajor: bestTooOld.versionMajor,
        source: '${bestTooOld.source}; tried=[${tried.join(', ')}]',
      );
    }
    return null;
  }

  /// Seeds managed JRE from packaged-next-to-exe or monorepo vendor.
  Future<void> ensureManagedJre(SuwayomiPaths paths) async {
    final destJava = File(
      p.join(paths.jreDir.path, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
    );
    if (destJava.existsSync()) return;

    String? seedRoot;
    final packaged = _packagedBesideExecutable();
    if (packaged != null) {
      seedRoot = p.dirname(p.dirname(packaged)); // .../jre/bin/java → jre
    } else {
      seedRoot = _findVendorJreRoot();
    }
    if (seedRoot == null) return;

    try {
      await paths.jreDir.create(recursive: true);
      await _copyDir(Directory(seedRoot), paths.jreDir);
    } catch (_) {}
  }

  /// `{exeDir}/jre/bin/java(.exe)` for Release bundles.
  String? _packagedBesideExecutable() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final java = p.join(
        exeDir,
        'jre',
        'bin',
        Platform.isWindows ? 'java.exe' : 'java',
      );
      if (File(java).existsSync()) return java;
    } catch (_) {}
    return null;
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

  List<String> _findVendorJreExecutables() {
    final out = <String>[];
    final javaName = Platform.isWindows ? 'java.exe' : 'java';
    for (final root in _searchRoots()) {
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
      if (File(p.join(jreRoot, 'bin', javaName)).existsSync()) return jreRoot;
    }
    return null;
  }

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

    final seen = <String>{};
    return roots.where((r) => seen.add(r.toLowerCase())).toList();
  }

  String? _bundledJava(SuwayomiPaths paths) {
    final candidates = [
      p.join(paths.jreDir.path, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
      p.join(paths.jreDir.path, 'Contents', 'Home', 'bin', 'java'),
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
      final text = '${result.stderr}\n${result.stdout}';
      final m21 = RegExp(r'version "(\d+)').firstMatch(text);
      if (m21 != null) {
        final major = int.tryParse(m21.group(1)!);
        if (major != null && major >= 2) return major;
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

  /// Test helper: path to monorepo vendor JRE root, or null.
  static String? findMonorepoVendorJreRootForTest() {
    return const JavaResolver()._findVendorJreRoot();
  }
}
