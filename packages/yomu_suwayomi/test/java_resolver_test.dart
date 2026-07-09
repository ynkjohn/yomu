import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  test('resolves JRE 21 from vendor/managed (not silent if vendor missing)',
      () async {
    final vendorRoot = JavaResolver.findMonorepoVendorJreRootForTest();
    expect(
      vendorRoot,
      isNotNull,
      reason: 'vendor/jre21 must exist — test must not pass silently without it',
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
  });
}
