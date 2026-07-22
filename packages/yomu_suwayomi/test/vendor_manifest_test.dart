import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  test('unified engine manifest parses independent of cwd', () {
    final file = VendorManifest.resolveRuntimeFile();
    expect(file.existsSync(), isTrue, reason: file.path);

    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final manifest = VendorManifest.fromJson(json);

    expect(manifest.noticesFile, 'THIRD_PARTY_NOTICES.md');
    expect(manifest.suwayomi.jarFile, 'Suwayomi-Server-v2.3.2238.jar');
    expect(manifest.suwayomi.minJre, 21);
    expect(manifest.suwayomi.downloadUrl, startsWith('https://'));
    expect(manifest.suwayomi.sha256, hasLength(64));
    expect(
      manifest.suwayomi.sourceCommit,
      'a1770cb0553e37c1f660a88c23afd7badde11328',
    );
    expect(manifest.suwayomi.sourceSha256, hasLength(64));
    expect(manifest.compatibility.restApiVersion, 'v1');
    expect(manifest.compatibility.graphqlPath, '/api/graphql');
    expect(manifest.compatibility.capabilities, contains('downloads'));
    expect(
      manifest.compatibility.requiredMutationFields,
      contains('updateChapter'),
    );

    final jre = manifest.jre!;
    expect(jre.version, '21.0.11+10');
    expect(jre.executable, 'bin/java.exe');
    expect(jre.requiredNoticePaths, contains('legal/java.base/LICENSE'));
    expect(jre.source.archiveFile, 'OpenJDK21U-jdk-sources_21.0.11_10.tar.gz');
    expect(
      jre.source.sha256,
      '891a3dd2341c37580fb81b56c4262f135e90c8f2acb059adb6ff0fdd76ae4385',
    );
    expect(
      jre.source.distributionPolicy,
      'GPL-2.0-section-3a-same-download-location',
    );
    expect(jre.source.requiredEntries, anyElement(contains('/make/')));
    expect(
      jre.source.openJdkSourceCommit,
      '254494ad7d75b37f1c033245fb4dbd460d0347b5',
    );
    expect(jre.source.build.commit, 'a612825ee82a20ac872d60958c349854c1f29a8e');
    expect(
      jre.source.build.requiredEntries,
      anyElement(endsWith('/makejdk-any-platform.sh')),
    );
    expect(jre.source.build.requiredEntries, anyElement(endsWith('/NOTICE')));
    expect(jre.source.provenance.sha256, hasLength(64));
  });

  test('runtime manifest resolves beside packaged executable first', () async {
    final root = Directory.systemTemp.createTempSync('yomu-manifest-bundle-');
    addTearDown(() => root.deleteSync(recursive: true));

    final exe = File('${root.path}${Platform.pathSeparator}yomu_desktop.exe');
    await exe.writeAsBytes(const [0]);
    final engine = Directory('${root.path}${Platform.pathSeparator}engine');
    await engine.create();
    final manifestFile = File(
      '${engine.path}${Platform.pathSeparator}${VendorManifest.fileName}',
    );
    await manifestFile.writeAsString(
      File(VendorManifest.resolveRuntimeFile().path).readAsStringSync(),
    );

    final resolved = VendorManifest.resolveRuntimeFile(
      resolvedExecutableForTest: exe.path,
      currentDirectoryForTest: Directory.systemTemp,
    );
    expect(resolved.absolute.path, manifestFile.absolute.path);

    final loaded = await VendorManifest.loadForRuntime(
      resolvedExecutableForTest: exe.path,
      currentDirectoryForTest: Directory.systemTemp,
    );
    expect(loaded.jre!.source.sha256, hasLength(64));
  });

  test('packaged-only manifest resolution never falls back to repository', () {
    final root = Directory.systemTemp.createTempSync('yomu-manifest-missing-');
    addTearDown(() => root.deleteSync(recursive: true));
    final exe = File('${root.path}${Platform.pathSeparator}yomu_desktop.exe')
      ..writeAsBytesSync(const [0]);

    expect(
      () => VendorManifest.resolveRuntimeFile(
        packagedOnly: true,
        resolvedExecutableForTest: exe.path,
        currentDirectoryForTest: Directory.current,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('manifest rejects missing corresponding-source metadata', () {
    final json =
        jsonDecode(
              File(VendorManifest.resolveRuntimeFile().path).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final jre = json['jre'] as Map<String, dynamic>;
    jre.remove('source');

    expect(
      () => VendorManifest.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('manifest rejects missing or malformed compatibility contract', () {
    final missing =
        jsonDecode(
              File(VendorManifest.resolveRuntimeFile().path).readAsStringSync(),
            )
            as Map<String, dynamic>;
    missing.remove('compatibility');
    expect(
      () => VendorManifest.fromJson(missing),
      throwsA(isA<FormatException>()),
    );

    final malformed =
        jsonDecode(
              File(VendorManifest.resolveRuntimeFile().path).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final compatibility = malformed['compatibility'] as Map<String, dynamic>;
    compatibility['graphqlPath'] = 'http://127.0.0.1:14567/api/graphql';
    expect(
      () => VendorManifest.fromJson(malformed),
      throwsA(isA<FormatException>()),
    );
  });

  test('manifest rejects malformed artifact hashes', () {
    final json =
        jsonDecode(
              File(VendorManifest.resolveRuntimeFile().path).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final jre = json['jre'] as Map<String, dynamic>;
    jre['sha256'] = 'not-a-sha';

    expect(
      () => VendorManifest.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('manifest rejects path traversal and non-HTTPS artifact URLs', () {
    final traversal =
        jsonDecode(
              File(VendorManifest.resolveRuntimeFile().path).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final traversalSuwayomi = traversal['suwayomi'] as Map<String, dynamic>;
    traversalSuwayomi['jarFile'] = '../engine.jar';
    expect(
      () => VendorManifest.fromJson(traversal),
      throwsA(isA<FormatException>()),
    );

    final insecure =
        jsonDecode(
              File(VendorManifest.resolveRuntimeFile().path).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final insecureJre = insecure['jre'] as Map<String, dynamic>;
    insecureJre['downloadUrl'] = 'http://example.invalid/jre.zip';
    expect(
      () => VendorManifest.fromJson(insecure),
      throwsA(isA<FormatException>()),
    );
  });
}
