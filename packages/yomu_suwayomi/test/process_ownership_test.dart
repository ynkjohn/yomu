import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  final started = DateTime.utc(2026, 7, 9, 12, 0, 0);
  final tmp = Directory.systemTemp.createTempSync('own-exact');
  final javaPath = p.join(tmp.path, 'bin', 'java.exe');
  final jarPath = p.join(tmp.path, 'Suwayomi-Server-v2.3.2238.jar');
  final rootDir = p.join(tmp.path, 'data', 'suwayomi');
  File(javaPath).createSync(recursive: true);
  File(jarPath).createSync(recursive: true);
  Directory(rootDir).createSync(recursive: true);

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('commandLineMatchesYomu exact', () {
    test('accepts full absolute markers', () {
      const runId = 'aabbccdd';
      final javaAbs = File(javaPath).absolute.path;
      final jarAbs = File(jarPath).absolute.path;
      final rootAbs = Directory(rootDir).absolute.path;
      final cl =
          '$javaAbs -D$kYomuRunIdProperty=$runId '
          '-D$kYomuStartedAtProperty=${started.toIso8601String()} '
          '-Dsuwayomi.tachidesk.config.server.rootDir=${rootAbs.replaceAll(r'\', '/')} '
          '-Dsuwayomi.tachidesk.config.server.port=14567 '
          '-jar $jarAbs';
      expect(
        ProcessOwnership.commandLineMatchesYomu(
          commandLine: cl,
          runId: runId,
          javaExecutable: javaAbs,
          jarPath: jarAbs,
          rootDir: rootAbs,
          port: 14567,
          startedAt: started,
        ),
        isTrue,
      );
    });

    test('rejects wrong startedAt', () {
      const runId = 'aabbccdd';
      final javaAbs = File(javaPath).absolute.path;
      final jarAbs = File(jarPath).absolute.path;
      final rootAbs = Directory(rootDir).absolute.path;
      final cl =
          '$javaAbs -D$kYomuRunIdProperty=$runId '
          '-D$kYomuStartedAtProperty=2020-01-01T00:00:00.000Z '
          '-Dsuwayomi.tachidesk.config.server.rootDir=${rootAbs.replaceAll(r'\', '/')} '
          '-Dsuwayomi.tachidesk.config.server.port=14567 '
          '-jar $jarAbs';
      expect(
        ProcessOwnership.commandLineMatchesYomu(
          commandLine: cl,
          runId: runId,
          javaExecutable: javaAbs,
          jarPath: jarAbs,
          rootDir: rootAbs,
          port: 14567,
          startedAt: started,
        ),
        isFalse,
      );
    });
  });
}
