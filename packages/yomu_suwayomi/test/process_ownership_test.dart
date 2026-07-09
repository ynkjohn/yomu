import 'package:test/test.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  final started = DateTime.utc(2026, 7, 9, 12, 0, 0);

  group('commandLineMatchesYomu (strong)', () {
    test('accepts full ownership markers', () {
      const runId = 'aabbccdd';
      const cl =
          r'C:\jre\bin\java.exe '
          r'-Dyomu.runId=aabbccdd '
          r'-Dyomu.startedAt=2026-07-09T12:00:00.000Z '
          r'-Dsuwayomi.tachidesk.config.server.rootDir=C:/Users/me/yomu/data/suwayomi '
          r'-Dsuwayomi.tachidesk.config.server.port=14567 '
          r'-jar C:\Users\me\yomu\runtime\suwayomi\Suwayomi-Server-v2.3.2238.jar';
      expect(
        ProcessOwnership.commandLineMatchesYomu(
          commandLine: cl,
          runId: runId,
          javaExecutable: r'C:\jre\bin\java.exe',
          jarPath:
              r'C:\Users\me\yomu\runtime\suwayomi\Suwayomi-Server-v2.3.2238.jar',
          rootDir: r'C:\Users\me\yomu\data\suwayomi',
          port: 14567,
          startedAt: started,
        ),
        isTrue,
      );
    });

    test('rejects missing runId', () {
      const cl =
          r'java -Dyomu.startedAt=2026-07-09T12:00:00.000Z '
          r'-Dsuwayomi.tachidesk.config.server.rootDir=C:/data '
          r'-Dsuwayomi.tachidesk.config.server.port=14567 '
          r'-jar C:/data/Suwayomi-Server-v2.3.2238.jar';
      expect(
        ProcessOwnership.commandLineMatchesYomu(
          commandLine: cl,
          runId: 'aabbccdd',
          javaExecutable: 'java',
          jarPath: r'C:\data\Suwayomi-Server-v2.3.2238.jar',
          rootDir: r'C:\data',
          port: 14567,
          startedAt: started,
        ),
        isFalse,
      );
    });

    test('rejects wrong jar path', () {
      const cl =
          r'java -Dyomu.runId=aabbccdd -Dyomu.startedAt=2026-07-09T12:00:00.000Z '
          r'-Dsuwayomi.tachidesk.config.server.rootDir=C:/data '
          r'-Dsuwayomi.tachidesk.config.server.port=14567 -jar C:/other/x.jar';
      expect(
        ProcessOwnership.commandLineMatchesYomu(
          commandLine: cl,
          runId: 'aabbccdd',
          javaExecutable: 'java',
          jarPath: r'C:\data\Suwayomi-Server-v2.3.2238.jar',
          rootDir: r'C:\data',
          port: 14567,
          startedAt: started,
        ),
        isFalse,
      );
    });
  });
}
