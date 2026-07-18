import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  test(
    'packaged-only installs verified JAR atomically without network',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'yomu-artifact-install-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final engineDir = Directory(p.join(root.path, 'bundle', 'engine'))
        ..createSync(recursive: true);
      final bytes = List<int>.generate(256, (index) => index);
      final hash = sha256.convert(bytes).toString();
      final seed = File(p.join(engineDir.path, 'engine.jar'))
        ..writeAsBytesSync(bytes);
      expect(seed.existsSync(), isTrue);

      var requests = 0;
      final paths = SuwayomiPaths(Directory(p.join(root.path, 'data')));
      final manager = SuwayomiProcessManager(
        paths: paths,
        manifest: _manifest(hash),
        packagedArtifactsOnly: true,
        allowArtifactDownload: false,
        packagedEngineDirectoryForTest: engineDir,
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('unexpected', 500);
        }),
      );
      addTearDown(manager.dispose);

      final result = await manager.ensureJar();
      final installed = result.when(
        ok: (file) => file,
        err: (message, _) => throw StateError(message),
      );

      expect(requests, 0);
      expect(await installed.readAsBytes(), bytes);
      expect(
        await sha256.bind(installed.openRead()).first,
        sha256.convert(bytes),
      );
      expect(paths.vendorManifestCopy.existsSync(), isTrue);
      expect(
        paths.runtimeDir.listSync().whereType<File>().where(
          (file) => file.path.contains('.tmp-'),
        ),
        isEmpty,
      );
    },
  );

  test('packaged-only fails closed when bundled JAR is missing', () async {
    final root = Directory.systemTemp.createTempSync('yomu-artifact-missing-');
    addTearDown(() => root.deleteSync(recursive: true));
    final engineDir = Directory(p.join(root.path, 'bundle', 'engine'))
      ..createSync(recursive: true);
    var requests = 0;
    final manager = SuwayomiProcessManager(
      paths: SuwayomiPaths(Directory(p.join(root.path, 'data'))),
      manifest: _manifest(sha256.convert(const [1]).toString()),
      packagedArtifactsOnly: true,
      allowArtifactDownload: false,
      packagedEngineDirectoryForTest: engineDir,
      httpClient: MockClient((_) async {
        requests++;
        return http.Response.bytes(const [1], 200);
      }),
    );
    addTearDown(manager.dispose);

    final result = await manager.ensureJar();
    final message = result.when(
      ok: (_) => throw StateError('unexpected success'),
      err: (message, _) => message,
    );

    expect(message, contains('Repare ou reinstale'));
    expect(requests, 0);
  });

  test('packaged-only rejects corrupt seed before replacing runtime', () async {
    final root = Directory.systemTemp.createTempSync('yomu-artifact-corrupt-');
    addTearDown(() => root.deleteSync(recursive: true));
    final engineDir = Directory(p.join(root.path, 'bundle', 'engine'))
      ..createSync(recursive: true);
    File(p.join(engineDir.path, 'engine.jar')).writeAsBytesSync(const [9, 9]);

    const expectedBytes = [1, 2, 3];
    final paths = SuwayomiPaths(Directory(p.join(root.path, 'data')));
    await paths.ensureLayout();
    final runtime = paths.jarFile('engine.jar')
      ..writeAsBytesSync(expectedBytes);
    final manager = SuwayomiProcessManager(
      paths: paths,
      manifest: _manifest(sha256.convert(expectedBytes).toString()),
      packagedArtifactsOnly: true,
      allowArtifactDownload: false,
      packagedEngineDirectoryForTest: engineDir,
    );
    addTearDown(manager.dispose);

    final result = await manager.ensureJar();
    expect(
      result.when(
        ok: (_) => false,
        err: (message, _) => message.contains('inválido'),
      ),
      isTrue,
    );
    expect(await runtime.readAsBytes(), expectedBytes);
  });
}

VendorManifest _manifest(String hash) => VendorManifest(
  suwayomi: SuwayomiArtifact(
    version: 'v-test',
    revision: 'r-test',
    jarFile: 'engine.jar',
    downloadUrl: 'https://example.invalid/engine.jar',
    sha256: hash,
    minJre: 21,
  ),
);
