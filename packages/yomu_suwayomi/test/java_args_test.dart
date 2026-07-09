import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  test('JVM -D props come before -jar and include rootDir + runId', () {
    final root = Directory.systemTemp.createTempSync('yomu-args');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = SuwayomiPaths(root);
    final manager = SuwayomiProcessManager(
      paths: paths,
      manifest: const VendorManifest(
        suwayomi: SuwayomiArtifact(
          version: 'v0',
          revision: 'r0',
          jarFile: 'x.jar',
          downloadUrl: 'https://example.com/x.jar',
          sha256: 'abc',
          minJre: 21,
        ),
      ),
      port: kYomuSuwayomiPort,
    );
    final jar = File(p.join(root.path, 'x.jar'));
    final started = DateTime.utc(2026, 1, 1);
    final args = manager.buildJavaArgs(
      jar,
      runId: 'deadbeef',
      startedAt: started,
    );

    final jarIndex = args.indexOf('-jar');
    expect(jarIndex, greaterThan(0));
    final dashD = args.where((a) => a.startsWith('-D')).toList();
    for (final d in dashD) {
      expect(args.indexOf(d), lessThan(jarIndex), reason: d);
    }
    expect(
      args.any((a) => a.startsWith('-D$kSuwayomiRootDirProperty=')),
      isTrue,
    );
    expect(
      args,
      contains('-Dsuwayomi.tachidesk.config.server.port=$kYomuSuwayomiPort'),
    );
    expect(args, contains('-Dsuwayomi.tachidesk.config.server.ip=127.0.0.1'));
    expect(args, contains('-D$kYomuRunIdProperty=deadbeef'));
    expect(
      args,
      contains('-D$kYomuStartedAtProperty=${started.toUtc().toIso8601String()}'),
    );
    expect(args.last, jar.absolute.path);
  });
}
