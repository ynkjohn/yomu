import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  test(
    'resolves JRE 21 from vendor/managed (not silent if vendor missing)',
    () async {
      final vendorRoot = JavaResolver.findMonorepoVendorJreRootForTest();
      expect(
        vendorRoot,
        isNotNull,
        reason:
            'vendor/jre21 must exist — test must not pass silently without it',
      );

      final tmp = Directory.systemTemp.createTempSync('yomu-jre-res');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final paths = SuwayomiPaths(Directory(p.join(tmp.path, 'yomu')));
      await paths.ensureLayout();

      final r = await const JavaResolver().resolve(paths: paths, minMajor: 21);
      expect(r, isNotNull);
      expect(r!.versionMajor, greaterThanOrEqualTo(21));
      expect(
        r.source.contains('JAVA_HOME'),
        isFalse,
        reason:
            'must not settle on JAVA_HOME 17; got ${r.source} ${r.javaExecutable}',
      );
    },
  );

  test('packaged-only ignores environment, managed and system Java', () async {
    final tmp = Directory.systemTemp.createTempSync('yomu-jre-packaged-only');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final appDir = Directory(p.join(tmp.path, 'app'))..createSync();
    final fakeExe = File(
      p.join(appDir.path, Platform.isWindows ? 'yomu.exe' : 'yomu'),
    )..writeAsBytesSync(const [0]);
    final packagedJava = File(
      p.join(
        appDir.path,
        'jre',
        'bin',
        Platform.isWindows ? 'java.exe' : 'java',
      ),
    )..createSync(recursive: true);
    packagedJava.writeAsBytesSync(const [0]);

    final envJavaRoot = Directory(p.join(tmp.path, 'env-jdk'));
    final envJava = File(
      p.join(envJavaRoot.path, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
    )..createSync(recursive: true);
    envJava.writeAsBytesSync(const [0]);

    final paths = SuwayomiPaths(Directory(p.join(tmp.path, 'data')));
    await paths.ensureLayout();
    final managedJava = File(
      p.join(
        paths.jreDir.path,
        'bin',
        Platform.isWindows ? 'java.exe' : 'java',
      ),
    )..createSync(recursive: true);
    managedJava.writeAsBytesSync(const [0]);

    final resolver = JavaResolver(
      mode: JavaResolutionMode.packagedOnly,
      resolvedExecutableForTest: fakeExe.path,
      environmentForTest: {
        'YOMU_JAVA_HOME': envJavaRoot.path,
        'JAVA_HOME': envJavaRoot.path,
      },
      searchRootsForTest: const [],
      versionProbeForTest: (path) async => path == packagedJava.path ? 21 : 99,
    );

    final resolution = await resolver.resolve(paths: paths);
    expect(resolution, isNotNull);
    expect(resolution!.source, 'packaged-jre');
    expect(
      p.normalize(resolution.javaExecutable).toLowerCase(),
      p.normalize(packagedJava.absolute.path).toLowerCase(),
    );
  });

  test('packaged-only fails when packaged Java is absent', () async {
    final tmp = Directory.systemTemp.createTempSync('yomu-jre-no-package');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final fakeExe = File(
      p.join(tmp.path, Platform.isWindows ? 'yomu.exe' : 'yomu'),
    )..writeAsBytesSync(const [0]);
    final envRoot = Directory(p.join(tmp.path, 'env-jdk'));
    final envJava = File(
      p.join(envRoot.path, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
    )..createSync(recursive: true);
    envJava.writeAsBytesSync(const [0]);

    final paths = SuwayomiPaths(Directory(p.join(tmp.path, 'data')));
    final resolution = await JavaResolver(
      mode: JavaResolutionMode.packagedOnly,
      resolvedExecutableForTest: fakeExe.path,
      environmentForTest: {'YOMU_JAVA_HOME': envRoot.path},
      searchRootsForTest: const [],
      versionProbeForTest: (_) async => 21,
    ).resolve(paths: paths);

    expect(resolution, isNull);
  });
}
