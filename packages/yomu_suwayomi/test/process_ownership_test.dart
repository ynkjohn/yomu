import 'package:test/test.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  group('commandLineMatchesYomu', () {
    test('accepts jar + rootDir + port props', () {
      const cl =
          r'C:\jre\bin\java.exe -Dsuwayomi.tachidesk.config.server.rootDir=C:/Users/me/yomu/data/suwayomi '
          r'-Dsuwayomi.tachidesk.config.server.port=14567 '
          r'-jar C:\Users\me\yomu\runtime\suwayomi\Suwayomi-Server-v2.3.2238.jar';
      expect(
        ProcessOwnership.commandLineMatchesYomu(
          commandLine: cl,
          jarPath:
              r'C:\Users\me\yomu\runtime\suwayomi\Suwayomi-Server-v2.3.2238.jar',
          rootDir: r'C:\Users\me\yomu\data\suwayomi',
          port: 14567,
        ),
        isTrue,
      );
    });

    test('rejects different jar', () {
      const cl =
          r'java -Dsuwayomi.tachidesk.config.server.rootDir=C:/data '
          r'-Dsuwayomi.tachidesk.config.server.port=14567 -jar other.jar';
      expect(
        ProcessOwnership.commandLineMatchesYomu(
          commandLine: cl,
          jarPath: r'C:\data\Suwayomi-Server-v2.3.2238.jar',
          rootDir: r'C:\data',
          port: 14567,
        ),
        isFalse,
      );
    });

    test('rejects wrong rootDir', () {
      const cl =
          r'java -Dsuwayomi.tachidesk.config.server.rootDir=C:/other '
          r'-jar Suwayomi-Server-v2.3.2238.jar';
      expect(
        ProcessOwnership.commandLineMatchesYomu(
          commandLine: cl,
          jarPath: r'C:\x\Suwayomi-Server-v2.3.2238.jar',
          rootDir: r'C:\managed',
          port: 14567,
        ),
        isFalse,
      );
    });
  });
}
