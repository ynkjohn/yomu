import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  test('resolves vendor JRE 21 even when JAVA_HOME is 17 and cwd is deep',
      () async {
    final monorepo = Directory.current.path;
    // Walk up until we see packages/yomu_suwayomi
    var dir = Directory.current;
    String? repoRoot;
    for (var i = 0; i < 8; i++) {
      if (Directory(p.join(dir.path, 'packages', 'yomu_suwayomi')).existsSync()) {
        repoRoot = dir.path;
        break;
      }
      dir = dir.parent;
    }
    expect(repoRoot, isNotNull, reason: 'run from monorepo');

    final vendorJava = File(
      p.join(
        repoRoot!,
        'packages',
        'yomu_suwayomi',
        'vendor',
        'jre21',
        'bin',
        Platform.isWindows ? 'java.exe' : 'java',
      ),
    );
    if (!vendorJava.existsSync()) {
      // Skip when vendor JRE not checked out on CI machine.
      return;
    }

    final deep = Directory(
      p.join(
        repoRoot,
        'apps',
        'yomu_desktop',
        'build',
        'windows',
        'x64',
        'runner',
        'Debug',
      ),
    );
    await deep.create(recursive: true);
    final prev = Directory.current;
    Directory.current = deep;
    addTearDown(() => Directory.current = prev);

    final tmp = Directory.systemTemp.createTempSync('yomu-jre-res');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final paths = SuwayomiPaths(Directory(p.join(tmp.path, 'yomu')));
    await paths.ensureLayout();

    final r = await const JavaResolver().resolve(paths: paths, minMajor: 21);
    expect(r, isNotNull);
    expect(r!.versionMajor, greaterThanOrEqualTo(21));
    expect(
      r.source.contains('vendor') || r.source.contains('bundled'),
      isTrue,
      reason: 'should not settle on JAVA_HOME 17; got ${r.source} ${r.javaExecutable}',
    );
  });
}
