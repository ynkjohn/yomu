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
  bool keepListenerAfterKill = false;

  @override
  Future<ProcessSnapshot?> inspectPid(int pid) async => snapshots[pid];

  @override
  Future<int?> findListenerPid(int port) async => listenerPid;

  @override
  Future<bool> killOwnedPid(int pid, {bool force = false}) async {
    killed.add(pid);
    if (!keepListenerAfterKill) {
      listenerPid = null;
      snapshots[pid] = ProcessSnapshot(pid: pid, exists: false);
    }
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

String _ownedCmd({
  required String javaAbs,
  required String jarAbs,
  required String rootAbs,
  required String runId,
  required DateTime started,
  int port = 14567,
}) {
  return '$javaAbs -D$kYomuRunIdProperty=$runId '
      '-D$kYomuStartedAtProperty=${started.toUtc().toIso8601String()} '
      '-Dsuwayomi.tachidesk.config.server.rootDir=${rootAbs.replaceAll(r'\', '/')} '
      '-Dsuwayomi.tachidesk.config.server.port=$port '
      '-jar $jarAbs';
}

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
  });

  test('owned identity not healthy: kill with ownership, preserve if port stuck',
      () async {
    final root = Directory.systemTemp.createTempSync('yomu-stop-id');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = SuwayomiPaths(root);
    await paths.ensureLayout();

    final javaAbs = File(p.join(root.path, 'java', 'bin', 'java.exe'))
      ..createSync(recursive: true);
    final jarAbs = File(
      p.join(paths.runtimeDir.path, 'Suwayomi-Server-v2.3.2238.jar'),
    )..createSync(recursive: true);
    final rootAbs = paths.dataDir.absolute.path;
    final started = DateTime.utc(2026, 7, 9, 11);
    const runId = 'feedface';
    // Isolated port so a real Suwayomi on 14567 cannot make health succeed.
    const testPort = 24567;
    final cl = _ownedCmd(
      javaAbs: javaAbs.absolute.path,
      jarAbs: jarAbs.absolute.path,
      rootAbs: rootAbs,
      runId: runId,
      started: started,
      port: testPort,
    );

    final id = ManagedInstanceIdentity(
      runId: runId,
      pid: 5555,
      startedAt: started,
      javaExecutable: javaAbs.absolute.path,
      jarPath: jarAbs.absolute.path,
      rootDir: rootAbs,
      port: testPort,
    );
    await id.save(paths.instanceIdentity);

    final probe = _FakeProbe(
      listenerPid: 5555,
      snapshots: {
        5555: ProcessSnapshot(pid: 5555, exists: true, commandLine: cl),
      },
    )..keepListenerAfterKill = true;

    final manager = SuwayomiProcessManager(
      paths: paths,
      manifest: _manifest(),
      ownershipProbe: probe,
      port: testPort,
    );

    final result = await manager.start(
      readyTimeout: const Duration(milliseconds: 400),
    );
    expect(probe.killed, contains(5555));
    result.when(
      ok: (_) => fail('expected error while port still held'),
      err: (m, _) {
        expect(m.toLowerCase(), contains('identidade'));
      },
    );
    expect(paths.instanceIdentity.existsSync(), isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('stop incomplete keeps identity file for retry', () async {
    final root = Directory.systemTemp.createTempSync('yomu-stop-id2');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = SuwayomiPaths(root);
    await paths.ensureLayout();

    final javaAbs = File(p.join(root.path, 'java', 'bin', 'java.exe'))
      ..createSync(recursive: true);
    final jarAbs = File(
      p.join(paths.runtimeDir.path, 'Suwayomi-Server-v2.3.2238.jar'),
    )..createSync(recursive: true);
    final rootAbs = paths.dataDir.absolute.path;
    final started = DateTime.utc(2026, 7, 9, 11);
    const runId = 'feedface';
    final cl = _ownedCmd(
      javaAbs: javaAbs.absolute.path,
      jarAbs: jarAbs.absolute.path,
      rootAbs: rootAbs,
      runId: runId,
      started: started,
    );

    final id = ManagedInstanceIdentity(
      runId: runId,
      pid: 5555,
      startedAt: started,
      javaExecutable: javaAbs.absolute.path,
      jarPath: jarAbs.absolute.path,
      rootDir: rootAbs,
      port: 14567,
    );
    await id.save(paths.instanceIdentity);

    final probe = _FakeProbe(
      listenerPid: 5555,
      snapshots: {
        5555: ProcessSnapshot(pid: 5555, exists: true, commandLine: cl),
      },
    )..keepListenerAfterKill = true;

    final manager = SuwayomiProcessManager(
      paths: paths,
      manifest: _manifest(),
      ownershipProbe: probe,
      port: 14567,
    );

    await manager.stop();
    expect(manager.status.state, SuwayomiProcessState.unhealthy);
    expect(paths.instanceIdentity.existsSync(), isTrue);
    final reloaded = await ManagedInstanceIdentity.load(paths.instanceIdentity);
    expect(reloaded?.runId, runId);
  });

  test('identity save is atomic (temp + rename without delete-first)', () async {
    final root = Directory.systemTemp.createTempSync('yomu-atomic');
    addTearDown(() => root.deleteSync(recursive: true));
    final file = File(p.join(root.path, 'id.json'));
    final id1 = ManagedInstanceIdentity(
      runId: 'aa',
      pid: 1,
      startedAt: DateTime.utc(2026, 1, 1),
      javaExecutable: r'C:\j\java.exe',
      jarPath: r'C:\j.jar',
      rootDir: r'C:\data',
      port: 14567,
    );
    await id1.save(file);
    final id2 = ManagedInstanceIdentity(
      runId: 'bb',
      pid: 2,
      startedAt: DateTime.utc(2026, 1, 2),
      javaExecutable: r'C:\j\java.exe',
      jarPath: r'C:\j.jar',
      rootDir: r'C:\data',
      port: 14567,
    );
    await id2.save(file);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
    final loaded = await ManagedInstanceIdentity.load(file);
    expect(loaded?.runId, 'bb');
  });

  test('stop without process and foreign identity stays unhealthy', () async {
    final root = Directory.systemTemp.createTempSync('yomu-stop');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = SuwayomiPaths(root);
    await paths.ensureLayout();

    final id = ManagedInstanceIdentity(
      runId: 'x',
      pid: 777,
      startedAt: DateTime.now().toUtc(),
      javaExecutable: r'C:\yomu\java.exe',
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
