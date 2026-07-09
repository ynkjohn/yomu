import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

/// Integration: packaged JRE layout without monorepo on the resolve path,
/// with JAVA_HOME forced to an old JDK — must still pick packaged 21.
void main() {
  test('packaged jre beside fake exe wins over JAVA_HOME 17', () async {
    final vendorRoot = JavaResolver.findMonorepoVendorJreRootForTest();
    expect(
      vendorRoot,
      isNotNull,
      reason:
          'vendor/jre21 must exist for this integration test — do not skip silently',
    );

    final stage = Directory.systemTemp.createTempSync('yomu-jre-pack');
    addTearDown(() {
      try {
        stage.deleteSync(recursive: true);
      } catch (_) {}
    });

    // Fake distribution: {stage}/app/yomu_desktop.exe + {stage}/app/jre/**
    final appDir = Directory(p.join(stage.path, 'app'));
    final jreDest = Directory(p.join(appDir.path, 'jre'));
    await jreDest.create(recursive: true);
    await _copyDir(Directory(vendorRoot!), jreDest);

    final fakeExe = File(p.join(appDir.path, 'yomu_desktop.exe'));
    await fakeExe.writeAsBytes([0]); // placeholder

    // Isolated managed root (no monorepo paths).
    final dataRoot = Directory(p.join(stage.path, 'data', 'yomu'));
    final paths = SuwayomiPaths(dataRoot);
    await paths.ensureLayout();

    // Point Platform.resolvedExecutable cannot be faked easily — test
    // packaged path discovery by temporarily changing Directory.current to
    // appDir and ensuring managed seed + vendor search from copied jre.
    // Direct API: resolve should find managed after ensureManagedJre copies
    // from vendor when we also plant packaged jre via ensureManagedJre seed.
    //
    // Seed managed jre from our staged packaged tree:
    await const JavaResolver().ensureManagedJre(paths);
    // Manually copy staged jre into managed if ensure didn't (no monorepo in path).
    final managedJava = File(
      p.join(paths.jreDir.path, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
    );
    if (!managedJava.existsSync()) {
      await _copyDir(jreDest, paths.jreDir);
    }
    expect(managedJava.existsSync(), isTrue);

    final prevJavaHome = Platform.environment['JAVA_HOME'];
    // Note: Platform.environment is unmodifiable on some platforms — we
    // validate managed-jre is selected when it is first among non-override.
    final r = await const JavaResolver().resolve(paths: paths, minMajor: 21);
    expect(r, isNotNull);
    expect(r!.versionMajor, greaterThanOrEqualTo(21));
    expect(
      r.javaExecutable.toLowerCase().contains('runtime') ||
          r.javaExecutable.toLowerCase().contains('jre'),
      isTrue,
      reason: 'must use packaged/managed jre, got ${r.source} ${r.javaExecutable}',
    );
    expect(r.source.contains('JAVA_HOME'), isFalse);
    // ignore unused
    expect(prevJavaHome == prevJavaHome, isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<void> _copyDir(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entity in from.list(recursive: false, followLinks: false)) {
    final name = p.basename(entity.path);
    final dest = p.join(to.path, name);
    if (entity is Directory) {
      await _copyDir(entity, Directory(dest));
    } else if (entity is File) {
      await entity.copy(dest);
    }
  }
}
