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

  String goodCl({
    required String javaAbs,
    required String jarAbs,
    required String rootAbs,
    required String runId,
  }) {
    final rootSlash = rootAbs.replaceAll(r'\', '/');
    return '"$javaAbs" -D$kYomuRunIdProperty=$runId '
        '-D$kYomuStartedAtProperty=${started.toIso8601String()} '
        '-Dsuwayomi.tachidesk.config.server.rootDir=$rootSlash '
        '-Dsuwayomi.tachidesk.config.server.port=14567 '
        '-jar "$jarAbs"';
  }

  group('commandLineMatchesYomu token-exact', () {
    test('accepts full absolute tokens (quoted)', () {
      const runId = 'aabbccdd';
      final javaAbs = File(javaPath).absolute.path;
      final jarAbs = File(jarPath).absolute.path;
      final rootAbs = Directory(rootDir).absolute.path;
      expect(
        ProcessOwnership.commandLineMatchesYomu(
          commandLine: goodCl(
            javaAbs: javaAbs,
            jarAbs: jarAbs,
            rootAbs: rootAbs,
            runId: runId,
          ),
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
          '"$javaAbs" -D$kYomuRunIdProperty=$runId '
          '-D$kYomuStartedAtProperty=2020-01-01T00:00:00.000Z '
          '-Dsuwayomi.tachidesk.config.server.rootDir=${rootAbs.replaceAll(r'\', '/')} '
          '-Dsuwayomi.tachidesk.config.server.port=14567 '
          '-jar "$jarAbs"';
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

    test('rejects java.exe.evil suffix as first token', () {
      const runId = 'aabbccdd';
      final javaAbs = File(javaPath).absolute.path;
      final jarAbs = File(jarPath).absolute.path;
      final rootAbs = Directory(rootDir).absolute.path;
      final cl = goodCl(
        javaAbs: '$javaAbs.evil',
        jarAbs: jarAbs,
        rootAbs: rootAbs,
        runId: runId,
      );
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

    test('rejects jar path with .evil suffix token', () {
      const runId = 'aabbccdd';
      final javaAbs = File(javaPath).absolute.path;
      final jarAbs = File(jarPath).absolute.path;
      final rootAbs = Directory(rootDir).absolute.path;
      final cl = goodCl(
        javaAbs: javaAbs,
        jarAbs: '$jarAbs.evil',
        rootAbs: rootAbs,
        runId: runId,
      );
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

    test('rejects decoy substring props (value suffix / similar prefix)', () {
      const runId = 'aabbccdd';
      final javaAbs = File(javaPath).absolute.path;
      final jarAbs = File(jarPath).absolute.path;
      final rootAbs = Directory(rootDir).absolute.path;
      final rootSlash = rootAbs.replaceAll(r'\', '/');

      // Value has decoy suffix — exact token must fail.
      final decoyValue =
          '"$javaAbs" -D$kYomuRunIdProperty=$runId.evil '
          '-D$kYomuStartedAtProperty=${started.toIso8601String()} '
          '-Dsuwayomi.tachidesk.config.server.rootDir=$rootSlash '
          '-Dsuwayomi.tachidesk.config.server.port=14567 '
          '-jar "$jarAbs"';
      expect(
        ProcessOwnership.commandLineMatchesYomu(
          commandLine: decoyValue,
          runId: runId,
          javaExecutable: javaAbs,
          jarPath: jarAbs,
          rootDir: rootAbs,
          port: 14567,
          startedAt: started,
        ),
        isFalse,
      );

      // Similar property name prefix (not exact -Dkey=).
      final decoyKey =
          '"$javaAbs" -D$kYomuRunIdProperty.extra=$runId '
          '-D$kYomuStartedAtProperty=${started.toIso8601String()} '
          '-Dsuwayomi.tachidesk.config.server.rootDir=$rootSlash '
          '-Dsuwayomi.tachidesk.config.server.port=14567 '
          '-jar "$jarAbs"';
      expect(
        ProcessOwnership.commandLineMatchesYomu(
          commandLine: decoyKey,
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

    test('rejects basename-only jar and decoy -jar arguments', () {
      const runId = 'aabbccdd';
      final javaAbs = File(javaPath).absolute.path;
      final jarAbs = File(jarPath).absolute.path;
      final rootAbs = Directory(rootDir).absolute.path;
      final rootSlash = rootAbs.replaceAll(r'\', '/');
      final cl =
          '"$javaAbs" -D$kYomuRunIdProperty=$runId '
          '-D$kYomuStartedAtProperty=${started.toIso8601String()} '
          '-Dsuwayomi.tachidesk.config.server.rootDir=$rootSlash '
          '-Dsuwayomi.tachidesk.config.server.port=14567 '
          '-jar Suwayomi-Server-v2.3.2238.jar '
          '--decoy $jarAbs';
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

    test('tokenizeCommandLine respects quotes', () {
      final tokens = ProcessOwnership.tokenizeCommandLine(
        r'"C:\Program Files\java.exe" -jar "C:\a b\app.jar"',
      );
      expect(tokens, [
        r'C:\Program Files\java.exe',
        '-jar',
        r'C:\a b\app.jar',
      ]);
    });

    test('a) evil -jar then props then expected -jar is false', () {
      const runId = 'aabbccdd';
      final javaAbs = File(javaPath).absolute.path;
      final jarAbs = File(jarPath).absolute.path;
      final rootAbs = Directory(rootDir).absolute.path;
      final rootSlash = rootAbs.replaceAll(r'\', '/');
      final cl =
          '"$javaAbs" -jar evil.jar '
          '-D$kYomuRunIdProperty=$runId '
          '-D$kYomuStartedAtProperty=${started.toIso8601String()} '
          '-Dsuwayomi.tachidesk.config.server.rootDir=$rootSlash '
          '-Dsuwayomi.tachidesk.config.server.port=14567 '
          '-jar "$jarAbs"';
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

    test('b) correct prop then same prop with evil value is false', () {
      const runId = 'aabbccdd';
      final javaAbs = File(javaPath).absolute.path;
      final jarAbs = File(jarPath).absolute.path;
      final rootAbs = Directory(rootDir).absolute.path;
      final rootSlash = rootAbs.replaceAll(r'\', '/');
      final cl =
          '"$javaAbs" -D$kYomuRunIdProperty=$runId '
          '-D$kYomuRunIdProperty=evil '
          '-D$kYomuStartedAtProperty=${started.toIso8601String()} '
          '-Dsuwayomi.tachidesk.config.server.rootDir=$rootSlash '
          '-Dsuwayomi.tachidesk.config.server.port=14567 '
          '-jar "$jarAbs"';
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

    test('c) legitimate current command line is true', () {
      const runId = 'aabbccdd';
      final javaAbs = File(javaPath).absolute.path;
      final jarAbs = File(jarPath).absolute.path;
      final rootAbs = Directory(rootDir).absolute.path;
      expect(
        ProcessOwnership.commandLineMatchesYomu(
          commandLine: goodCl(
            javaAbs: javaAbs,
            jarAbs: jarAbs,
            rootAbs: rootAbs,
            runId: runId,
          ),
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
  });
}
