import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

/// Real out-of-monorepo bundle: copy JRE+PWA beside a fake exe under systemTemp,
/// resolve with JAVA_HOME=17 and empty YOMU_JAVA_HOME, confirm
/// `{exeDir}/jre/bin/java.exe`, run that binary, and serve PWA from `{exeDir}/pwa`.
void main() {
  test(
    'isolated bundle: {exeDir}/jre/bin/java.exe + PWA (JAVA_HOME 17, no YOMU_JAVA_HOME)',
    () async {
      final vendorRoot = JavaResolver.findMonorepoVendorJreRootForTest();
      expect(
        vendorRoot,
        isNotNull,
        reason: 'vendor/jre21 required — run tool/fetch_jre21_windows.ps1',
      );

      final stage = Directory.systemTemp.createTempSync('yomu-bundle-iso-');
      addTearDown(() {
        try {
          stage.deleteSync(recursive: true);
        } catch (_) {}
      });

      // Must not live under the monorepo packages tree.
      final monorepoPkg = p.normalize(
        p.join(Directory.current.path, 'packages'),
      );
      expect(
        p.isWithin(monorepoPkg, stage.path),
        isFalse,
        reason: 'stage outside monorepo packages: ${stage.path}',
      );

      final appDir = Directory(p.join(stage.path, 'app'));
      await appDir.create(recursive: true);
      final fakeExe = File(
        p.join(appDir.path, Platform.isWindows ? 'yomu_desktop.exe' : 'yomu'),
      );
      await fakeExe.writeAsBytes([0]);

      final jreDest = Directory(p.join(appDir.path, 'jre'));
      await _copyDir(Directory(vendorRoot!), jreDest);
      final expectedJava = File(
        p.join(
          appDir.path,
          'jre',
          'bin',
          Platform.isWindows ? 'java.exe' : 'java',
        ),
      );
      expect(expectedJava.existsSync(), isTrue);
      final expectedNorm = p.normalize(expectedJava.absolute.path);
      if (Platform.isWindows) {
        expect(
          expectedNorm.toLowerCase().replaceAll('/', r'\').endsWith(
                r'jre\bin\java.exe',
              ),
          isTrue,
          reason: 'exact layout {exeDir}/jre/bin/java.exe, got $expectedNorm',
        );
      }

      final pwaSrc = _findPwaSource();
      expect(pwaSrc, isNotNull);
      final pwaDest = Directory(p.join(appDir.path, 'pwa'));
      await pwaDest.create(recursive: true);
      await File(p.join(pwaSrc!, 'index.html'))
          .copy(p.join(pwaDest.path, 'index.html'));

      final jdk17 = Directory(p.join(stage.path, 'jdk17'));
      final jdk17Java = File(
        p.join(
          jdk17.path,
          'bin',
          Platform.isWindows ? 'java.exe' : 'java',
        ),
      );
      await jdk17Java.create(recursive: true);
      await jdk17Java.writeAsBytes([0]);

      final dataRoot = Directory(p.join(stage.path, 'data', 'yomu'));
      final paths = SuwayomiPaths(dataRoot);
      await paths.ensureLayout();

      final resolver = JavaResolver(
        resolvedExecutableForTest: fakeExe.path,
        searchRootsForTest: const [],
        environmentForTest: {
          'JAVA_HOME': jdk17.path,
          // YOMU_JAVA_HOME intentionally empty/absent
        },
        versionProbeForTest: (exe) async {
          final n = exe.toLowerCase().replaceAll(r'\', '/');
          if (n.contains('/jre/bin/java')) return 21;
          if (n.contains('/jdk17/')) return 17;
          return null;
        },
      );

      final r = await resolver.resolve(paths: paths, minMajor: 21);
      expect(r, isNotNull);
      expect(r!.versionMajor, greaterThanOrEqualTo(21));
      expect(r.source, 'packaged-jre');
      expect(
        p.normalize(r.javaExecutable).toLowerCase(),
        expectedNorm.toLowerCase(),
      );
      expect(r.javaExecutable.toLowerCase().contains('jdk17'), isFalse);

      // Live binary from the isolated copy.
      final probe = await Process.run(expectedJava.path, ['-version']);
      final verText = '${probe.stderr}\n${probe.stdout}';
      expect(verText, contains(RegExp(r'version "2[1-9]')));

      // Serve PWA from {exeDir}/pwa (same path production uses).
      final indexFile = File(p.join(pwaDest.path, 'index.html'));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((req) async {
        if (req.uri.path == '/' || req.uri.path == '/index.html') {
          req.response.headers.contentType = ContentType.html;
          await req.response.addStream(indexFile.openRead());
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
      final client = HttpClient();
      addTearDown(client.close);
      final res = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}/'))
          .then((r) => r.close());
      expect(res.statusCode, 200);
      final body = await res.transform(utf8.decoder).join();
      expect(body.toLowerCase(), contains('yomu'));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

String? _findPwaSource() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final cand = Directory(p.join(dir.path, 'apps', 'yomu_mobile_pwa'));
    if (File(p.join(cand.path, 'index.html')).existsSync()) return cand.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
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
