import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

class _FakeProbe implements ProcessOwnershipProbe {
  _FakeProbe({this.listenerPid, this.snapshots = const {}});

  int? listenerPid;
  Map<int, ProcessSnapshot> snapshots;
  final killed = <int>[];

  @override
  Future<ProcessSnapshot?> inspectPid(int pid) async => snapshots[pid];

  @override
  Future<int?> findListenerPid(int port) async => listenerPid;

  @override
  Future<bool> killOwnedPid(int pid, {bool force = false}) async {
    killed.add(pid);
    listenerPid = null;
    snapshots[pid] = ProcessSnapshot(pid: pid, exists: false);
    return true;
  }
}

VendorManifest _manifest() => const VendorManifest(
      suwayomi: SuwayomiArtifact(
        version: 'v0',
        revision: 'r0',
        jarFile: 'Suwayomi-Server-v2.3.2238.jar',
        downloadUrl: 'https://example.com/x.jar',
        sha256: 'abc',
        minJre: 21,
      ),
    );

void main() {
  test('foreign listener on port is not adopted and not killed', () async {
    final root = Directory.systemTemp.createTempSync('yomu-life');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = SuwayomiPaths(root);
    await paths.ensureLayout();

    final probe = _FakeProbe(
      listenerPid: 99999,
      snapshots: {
        99999: const ProcessSnapshot(
          pid: 99999,
          exists: true,
          commandLine: 'java -jar random-suwayomi.jar',
        ),
      },
    );

    final manager = SuwayomiProcessManager(
      paths: paths,
      manifest: _manifest(),
      ownershipProbe: probe,
      port: 14567,
    );

    final result = await manager.start(
      readyTimeout: const Duration(milliseconds: 100),
    );
    var failed = false;
    result.when(
      ok: (_) => fail('should not start'),
      err: (m, _) {
        failed = true;
        expect(m.toLowerCase(), contains('ownership'));
      },
    );
    expect(failed, isTrue);
    expect(probe.killed, isEmpty);
    expect(manager.status.state, SuwayomiProcessState.crashed);
  });

  test('validated Yomu orphan is killed before start attempt', () async {
    final root = Directory.systemTemp.createTempSync('yomu-orphan');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = SuwayomiPaths(root);
    await paths.ensureLayout();

    final jarPath = p.join(paths.runtimeDir.path, 'Suwayomi-Server-v2.3.2238.jar');
    final rootDir = paths.dataDir.absolute.path;
    final cl =
        'java -Dsuwayomi.tachidesk.config.server.rootDir=${rootDir.replaceAll(r'\', '/')} '
        '-Dsuwayomi.tachidesk.config.server.port=14567 '
        '-jar $jarPath';

    final id = ManagedInstanceIdentity(
      runId: 'abc',
      pid: 4242,
      startedAt: DateTime.now(),
      javaExecutable: 'java',
      jarPath: jarPath,
      rootDir: rootDir,
      port: 14567,
    );
    await id.save(paths.instanceIdentity);

    final probe = _FakeProbe(
      listenerPid: 4242,
      snapshots: {
        4242: ProcessSnapshot(pid: 4242, exists: true, commandLine: cl),
      },
    );

    final manager = SuwayomiProcessManager(
      paths: paths,
      manifest: _manifest(),
      ownershipProbe: probe,
      port: 14567,
    );

    // Will proceed past orphan kill then fail on Java/JAR — kill must have happened.
    await manager.start(readyTimeout: const Duration(milliseconds: 200));
    expect(probe.killed, contains(4242));
  });

  test('stop without process and foreign identity stays unhealthy', () async {
    final root = Directory.systemTemp.createTempSync('yomu-stop');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = SuwayomiPaths(root);
    await paths.ensureLayout();

    final id = ManagedInstanceIdentity(
      runId: 'x',
      pid: 777,
      startedAt: DateTime.now(),
      javaExecutable: 'java',
      jarPath: r'C:\yomu\Suwayomi-Server-v2.3.2238.jar',
      rootDir: r'C:\yomu\data',
      port: 14567,
    );
    await id.save(paths.instanceIdentity);

    final probe = _FakeProbe(
      listenerPid: 777,
      snapshots: {
        777: const ProcessSnapshot(
          pid: 777,
          exists: true,
          commandLine: 'java -jar not-ours.jar',
        ),
      },
    );

    final manager = SuwayomiProcessManager(
      paths: paths,
      manifest: _manifest(),
      ownershipProbe: probe,
      port: 14567,
    );

    await manager.stop();
    expect(probe.killed, isEmpty);
    expect(manager.status.state, SuwayomiProcessState.unhealthy);
  });
}
