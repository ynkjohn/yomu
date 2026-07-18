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

enum JavaResolutionMode { development, packagedOnly }

/// Locates a JRE/JDK suitable for Suwayomi (default min 21).
///
/// Priority:
/// 1. [YOMU_JAVA_HOME] — **explicit override** (optional; only if version ≥ min)
/// 2. Packaged JRE next to the executable (`{exeDir}/jre`) — Release distribution
/// 3. Managed app-support JRE (`runtime/jre`)
/// 4. Monorepo `vendor/jre21` (dev)
/// 5. JAVA_HOME / PATH (system; never preferred over packaged 21)
class JavaResolver {
  const JavaResolver({
    this.mode = JavaResolutionMode.development,
    this.resolvedExecutableForTest,
    this.environmentForTest,
    this.versionProbeForTest,
    this.searchRootsForTest,
  });

  final JavaResolutionMode mode;

  /// Fake [Platform.resolvedExecutable] (isolated bundle tests).
  final String? resolvedExecutableForTest;

  /// Fake env (must omit [YOMU_JAVA_HOME] when testing packaged-jre win).
  final Map<String, String>? environmentForTest;

  /// Optional major-version probe override (tests).
  final Future<int?> Function(String javaExecutable)? versionProbeForTest;

  /// Optional monorepo search roots override (empty = no vendor walk).
  final List<String>? searchRootsForTest;

  Map<String, String> get _env => environmentForTest ?? Platform.environment;

  Future<JavaResolution?> resolve({
    required SuwayomiPaths paths,
    int minMajor = 21,
  }) async {
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

    if (mode == JavaResolutionMode.development) {
      // Explicit development override first.
      final yomuJava = _env['YOMU_JAVA_HOME'];
      if (yomuJava != null && yomuJava.isNotEmpty) {
        add(
          p.join(yomuJava, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
          'YOMU_JAVA_HOME',
        );
      }
    }

    // Packaged beside executable is the only candidate in packaged mode.
    add(_packagedBesideExecutable(), 'packaged-jre');

    if (mode == JavaResolutionMode.development) {
      // Backward-compatible managed runtime, local vendor and system fallbacks
      // are development conveniences only. Release/Profile never inspect them.
      add(_bundledJava(paths), 'managed-jre');
      for (final v in _findVendorJreExecutables()) {
        add(v, 'vendor-jre21');
      }
      final fromEnv = _env['JAVA_HOME'];
      if (fromEnv != null && fromEnv.isNotEmpty) {
        add(
          p.join(fromEnv, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
          'JAVA_HOME',
        );
      }
      if (environmentForTest == null) {
        add(await _whichJava(), 'PATH');
      }
    }

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

  /// `{exeDir}/jre/bin/java(.exe)` for Release bundles.
  String? _packagedBesideExecutable() {
    try {
      final exePath = resolvedExecutableForTest ?? Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;
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
    if (searchRootsForTest != null) {
      return List<String>.from(searchRootsForTest!);
    }

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
      final exe = resolvedExecutableForTest ?? Platform.resolvedExecutable;
      walk(File(exe).parent.path, 14);
    } catch (_) {}

    final seen = <String>{};
    return roots.where((r) => seen.add(r.toLowerCase())).toList();
  }

  String? _bundledJava(SuwayomiPaths paths) {
    final candidates = [
      p.join(
        paths.jreDir.path,
        'bin',
        Platform.isWindows ? 'java.exe' : 'java',
      ),
      p.join(paths.jreDir.path, 'Contents', 'Home', 'bin', 'java'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  Future<String?> _whichJava() async {
    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        'java',
      ], runInShell: true);
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
    final override = versionProbeForTest;
    if (override != null) return override(javaExecutable);
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
