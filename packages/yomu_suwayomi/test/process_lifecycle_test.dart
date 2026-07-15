import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

class _FixedJavaResolver extends JavaResolver {
  _FixedJavaResolver(this.exe);
  final String exe;

  @override
  Future<JavaResolution?> resolve({
    required SuwayomiPaths paths,
    int minMajor = 21,
  }) async {
    return JavaResolution(
      javaExecutable: exe,
      versionMajor: 21,
      source: 'test-fixed',
    );
  }
}

class _FakeProbe implements ProcessOwnershipProbe {
  _FakeProbe({
    this.listenerPid,
    Map<int, ProcessSnapshot> snapshots = const {},
    this.killSucceeds = true,
  }) : snapshots = Map<int, ProcessSnapshot>.from(snapshots);

  int? listenerPid;
  Map<int, ProcessSnapshot> snapshots;
  final killed = <int>[];
  bool keepListenerAfterKill = false;
  bool killSucceeds;
  Future<ProcessSnapshot?> Function(int pid)? inspectPidForTest;
  Future<bool> Function(int pid, bool force)? killOwnedPidForTest;
  int inspectCount = 0;

  @override
  Future<ProcessSnapshot?> inspectPid(int pid) async {
    inspectCount++;
    final override = inspectPidForTest;
    if (override != null) return override(pid);
    return snapshots[pid];
  }

  @override
  Future<int?> findListenerPid(int port) async => listenerPid;

  @override
  Future<bool> killOwnedPid(int pid, {bool force = false}) async {
    killed.add(pid);
    final override = killOwnedPidForTest;
    if (override != null) return override(pid, force);
    if (!killSucceeds) return false;
    if (!keepListenerAfterKill) {
      listenerPid = null;
      snapshots[pid] = ProcessSnapshot(pid: pid, exists: false);
    }
    return true;
  }
}

class _FakeProcess implements Process {
  _FakeProcess({required this.pid});

  @override
  final int pid;

  bool killSucceeds = false;
  int killCalls = 0;
  final Completer<int> _exit = Completer<int>();

  void completeExit([int code = 0]) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  IOSink get stdin => throw UnsupportedError('stdin is unused by this test');

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killCalls++;
    return killSucceeds;
  }
}

class _ToggleHttpClient extends http.BaseClient {
  _ToggleHttpClient({this.unhealthyRequestsRemaining = 0});

  bool healthy = true;
  int unhealthyRequestsRemaining;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (unhealthyRequestsRemaining > 0) {
      unhealthyRequestsRemaining--;
      return http.StreamedResponse(Stream<List<int>>.value(const <int>[]), 503);
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(const <int>[]),
      healthy ? 200 : 503,
    );
  }
}

class _StopFixture {
  _StopFixture({
    required this.root,
    required this.paths,
    required this.manager,
    required this.probe,
    required this.process,
    required this.httpClient,
    required this.identity,
    required this.ownedCommandLine,
  });

  final Directory root;
  final SuwayomiPaths paths;
  final SuwayomiProcessManager manager;
  final _FakeProbe probe;
  final _FakeProcess process;
  final _ToggleHttpClient httpClient;
  final ManagedInstanceIdentity identity;
  final String ownedCommandLine;

  Future<void> dispose() async {
    httpClient.healthy = false;
    probe.inspectPidForTest = null;
    probe.killOwnedPidForTest = null;
    probe.listenerPid = null;
    probe.snapshots[identity.pid] = ProcessSnapshot(
      pid: identity.pid,
      exists: false,
    );
    process.killSucceeds = true;
    process.completeExit();
    await Future<void>.delayed(Duration.zero);
    await manager.dispose();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  }
}

Future<_StopFixture> _startWithFakeProcess({required int pid}) async {
  final root = Directory.systemTemp.createTempSync('yomu-stop-handle');
  final paths = SuwayomiPaths(root);
  await paths.ensureLayout();

  final jarBytes = <int>[1, 2, 3, 4, pid & 0xff];
  final jarHash = sha256.convert(jarBytes).toString();
  final jar = paths.jarFile('Suwayomi-Server-v2.3.2238.jar');
  await jar.writeAsBytes(jarBytes);

  final java = File(p.join(root.path, 'java', 'bin', 'java.exe'));
  await java.create(recursive: true);
  await java.writeAsBytes(const <int>[0]);

  final manifest = VendorManifest(
    suwayomi: SuwayomiArtifact(
      version: 'v0',
      revision: 'r0',
      jarFile: 'Suwayomi-Server-v2.3.2238.jar',
      downloadUrl: 'https://example.com/x.jar',
      sha256: jarHash,
      minJre: 21,
    ),
  );
  final probe = _FakeProbe();
  final process = _FakeProcess(pid: pid);
  final httpClient = _ToggleHttpClient(unhealthyRequestsRemaining: 3);
  final manager = SuwayomiProcessManager(
    paths: paths,
    manifest: manifest,
    javaResolver: _FixedJavaResolver(java.absolute.path),
    ownershipProbe: probe,
    httpClient: httpClient,
    port: 24000 + (pid % 1000),
    processStartForTest:
        (
          executable,
          arguments, {
          String? workingDirectory,
          Map<String, String>? environment,
          bool runInShell = false,
        }) async => process,
  );

  final result = await manager.start(
    readyTimeout: const Duration(milliseconds: 200),
  );
  result.when(
    ok: (_) {},
    err: (message, error) {
      throw StateError('fake process did not start: $message ($error)');
    },
  );

  final identity = manager.identity!;
  final ownedCommandLine = _ownedCmd(
    javaAbs: identity.javaExecutable,
    jarAbs: identity.jarPath,
    rootAbs: identity.rootDir,
    runId: identity.runId,
    started: identity.startedAt,
    port: identity.port,
  );
  probe.listenerPid = pid;
  probe.snapshots[pid] = ProcessSnapshot(
    pid: pid,
    exists: true,
    commandLine: ownedCommandLine,
  );

  return _StopFixture(
    root: root,
    paths: paths,
    manager: manager,
    probe: probe,
    process: process,
    httpClient: httpClient,
    identity: identity,
    ownedCommandLine: ownedCommandLine,
  );
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

  test(
    'owned identity not healthy: kill with ownership, preserve if port stuck',
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
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

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

  test(
    'identity save is atomic (temp + rename without delete-first)',
    () async {
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
    },
  );

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

  test(
    'healthy reattach reuses owned identity without second start race',
    () async {
      final root = Directory.systemTemp.createTempSync('yomu-reattach');
      addTearDown(() => root.deleteSync(recursive: true));
      final paths = SuwayomiPaths(root);
      await paths.ensureLayout();

      const testPort = 24601;
      final health = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        testPort,
      );
      addTearDown(health.close);
      health.listen((req) async {
        // SuwayomiClient.isHealthy probes root/about-like paths.
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write('{"ok":true}');
        await req.response.close();
      });

      final javaAbs = File(p.join(root.path, 'java', 'bin', 'java.exe'))
        ..createSync(recursive: true);
      final jarAbs = File(
        p.join(paths.runtimeDir.path, 'Suwayomi-Server-v2.3.2238.jar'),
      )..createSync(recursive: true);
      final rootAbs = paths.dataDir.absolute.path;
      final started = DateTime.utc(2026, 7, 9, 12);
      const runId = 'reattach1';
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
        pid: 4242,
        startedAt: started,
        javaExecutable: javaAbs.absolute.path,
        jarPath: jarAbs.absolute.path,
        rootDir: rootAbs,
        port: testPort,
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
        port: testPort,
      );

      final result = await manager.start(
        readyTimeout: const Duration(seconds: 5),
      );
      result.when(
        ok: (s) {
          expect(s.state, SuwayomiProcessState.running);
          expect(s.pid, 4242);
          expect(s.message!.toLowerCase(), contains('reaproveitado'));
        },
        err: (m, _) => fail('expected reattach ok: $m'),
      );
      expect(probe.killed, isEmpty);
      expect(manager.identity?.runId, runId);
    },
  );

  test('kill=false on owned stop keeps identity and unhealthy', () async {
    final root = Directory.systemTemp.createTempSync('yomu-killfalse');
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
    const runId = 'killfalse';
    const testPort = 24602;
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
      pid: 8888,
      startedAt: started,
      javaExecutable: javaAbs.absolute.path,
      jarPath: jarAbs.absolute.path,
      rootDir: rootAbs,
      port: testPort,
    );
    await id.save(paths.instanceIdentity);

    final probe = _FakeProbe(
      listenerPid: 8888,
      snapshots: {
        8888: ProcessSnapshot(pid: 8888, exists: true, commandLine: cl),
      },
      killSucceeds: false,
    )..keepListenerAfterKill = true;

    final manager = SuwayomiProcessManager(
      paths: paths,
      manifest: _manifest(),
      ownershipProbe: probe,
      port: testPort,
    );

    await manager.stop();
    expect(probe.killed, contains(8888));
    expect(manager.status.state, isNot(SuwayomiProcessState.stopped));
    expect(paths.instanceIdentity.existsSync(), isTrue);
  });

  test(
    'handle kill=false + inspect null refuses PID fallback and preserves state',
    () async {
      final fixture = await _startWithFakeProcess(pid: 9101);
      addTearDown(fixture.dispose);
      fixture.httpClient.healthy = false;
      fixture.probe.inspectPidForTest = (_) async => null;

      await fixture.manager.stop();

      expect(fixture.process.killCalls, 1);
      expect(fixture.probe.killed, isEmpty);
      expect(fixture.manager.status.state, SuwayomiProcessState.unhealthy);
      expect(fixture.manager.identity?.runId, fixture.identity.runId);
      expect(fixture.paths.instanceIdentity.existsSync(), isTrue);

      await fixture.manager.stop();
      expect(
        fixture.process.killCalls,
        2,
        reason: 'the Process handle must remain available for a retry',
      );
    },
  );

  test(
    'handle kill=false + identity mismatch never taskkills reused PID',
    () async {
      final fixture = await _startWithFakeProcess(pid: 9102);
      addTearDown(fixture.dispose);
      fixture.httpClient.healthy = false;
      fixture.probe.inspectPidForTest = (pid) async => ProcessSnapshot(
        pid: pid,
        exists: true,
        commandLine: 'java -jar foreign-or-reused-pid.jar',
      );

      await fixture.manager.stop();

      expect(fixture.process.killCalls, 1);
      expect(fixture.probe.killed, isEmpty);
      expect(fixture.manager.status.state, SuwayomiProcessState.unhealthy);
      expect(fixture.manager.identity?.runId, fixture.identity.runId);
      expect(fixture.paths.instanceIdentity.existsSync(), isTrue);
    },
  );

  test(
    'owned PID fallback still requires a readable dead confirmation',
    () async {
      final fixture = await _startWithFakeProcess(pid: 9103);
      addTearDown(fixture.dispose);
      fixture.httpClient.healthy = false;
      var inspections = 0;
      fixture.probe.inspectPidForTest = (pid) async {
        inspections++;
        if (inspections == 1) {
          return ProcessSnapshot(
            pid: pid,
            exists: true,
            commandLine: fixture.ownedCommandLine,
          );
        }
        return null;
      };
      fixture.probe.killOwnedPidForTest = (pid, force) async {
        fixture.probe.listenerPid = null;
        return true;
      };

      await fixture.manager.stop();

      expect(fixture.probe.killed, [fixture.identity.pid]);
      expect(inspections, 2, reason: 'pre-kill proof + post-kill confirmation');
      expect(fixture.manager.status.state, SuwayomiProcessState.unhealthy);
      expect(fixture.manager.identity?.runId, fixture.identity.runId);
      expect(fixture.paths.instanceIdentity.existsSync(), isTrue);
    },
  );

  test(
    'owned PID fallback clears handle and identity only after confirmed death',
    () async {
      final fixture = await _startWithFakeProcess(pid: 9104);
      addTearDown(fixture.dispose);
      fixture.httpClient.healthy = false;
      var fallbackSent = false;
      fixture.probe.inspectPidForTest = (pid) async {
        if (fallbackSent) return ProcessSnapshot(pid: pid, exists: false);
        return ProcessSnapshot(
          pid: pid,
          exists: true,
          commandLine: fixture.ownedCommandLine,
        );
      };
      fixture.probe.killOwnedPidForTest = (pid, force) async {
        fallbackSent = true;
        fixture.probe.listenerPid = null;
        return true;
      };

      await fixture.manager.stop();

      expect(fixture.probe.killed, [fixture.identity.pid]);
      expect(fixture.probe.inspectCount, greaterThanOrEqualTo(2));
      expect(fixture.manager.status.state, SuwayomiProcessState.stopped);
      expect(fixture.manager.identity, isNull);
      expect(fixture.paths.instanceIdentity.existsSync(), isFalse);

      await fixture.manager.stop();
      expect(
        fixture.process.killCalls,
        1,
        reason: 'confirmed stop must release the in-memory Process handle',
      );
    },
  );

  test('identity .bak recovery after primary corruption', () async {
    final root = Directory.systemTemp.createTempSync('yomu-bak');
    addTearDown(() => root.deleteSync(recursive: true));
    final file = File(p.join(root.path, 'id.json'));
    final id = ManagedInstanceIdentity(
      runId: 'bakrun',
      pid: 9,
      startedAt: DateTime.utc(2026, 3, 1),
      javaExecutable: r'C:\j\java.exe',
      jarPath: r'C:\j.jar',
      rootDir: r'C:\data',
      port: 14567,
    );
    await id.save(file);
    // Simulate crash mid-replace: primary gone/corrupt, bak holds last good.
    final bak = File('${file.path}.bak');
    await file.copy(bak.path);
    await file.writeAsString('{not-json');
    final loaded = await ManagedInstanceIdentity.load(file);
    expect(loaded?.runId, 'bakrun');
    // Primary should be restored from bak.
    final again = await ManagedInstanceIdentity.load(file);
    expect(again?.runId, 'bakrun');
  });

  test('identity rejects invalid startedAt', () async {
    final root = Directory.systemTemp.createTempSync('yomu-started');
    addTearDown(() => root.deleteSync(recursive: true));
    final file = File(p.join(root.path, 'id.json'));
    await file.writeAsString(
      '{"runId":"x","pid":1,"startedAt":"not-a-date",'
      '"javaExecutable":"j","jarPath":"j","rootDir":"r","port":1}',
    );
    expect(await ManagedInstanceIdentity.load(file), isNull);

    await file.writeAsString(
      '{"runId":"x","pid":1,"startedAt":"1970-01-01T00:00:00.000Z",'
      '"javaExecutable":"j","jarPath":"j","rootDir":"r","port":1}',
    );
    // Epoch zero ms is invalid for our guard.
    final epoch = ManagedInstanceIdentity(
      runId: 'e',
      pid: 1,
      startedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      javaExecutable: 'j',
      jarPath: 'j',
      rootDir: 'r',
      port: 1,
    );
    expect(epoch.hasValidStartedAt, isFalse);
  });

  test('command line rejects basename-only jar match', () {
    final started = DateTime.utc(2026, 7, 9, 12);
    final ok = ProcessOwnership.commandLineMatchesYomu(
      commandLine:
          r'C:\wrong\java.exe -Dyomu.runId=aa '
          r'-Dyomu.startedAt=2026-07-09T12:00:00.000Z '
          r'-Dsuwayomi.tachidesk.config.server.rootDir=C:/data '
          r'-Dsuwayomi.tachidesk.config.server.port=14567 '
          r'-jar Suwayomi-Server-v2.3.2238.jar',
      runId: 'aa',
      javaExecutable: r'C:\yomu\jre\bin\java.exe',
      jarPath: r'C:\yomu\Suwayomi-Server-v2.3.2238.jar',
      rootDir: r'C:\data',
      port: 14567,
      startedAt: started,
    );
    expect(ok, isFalse);
  });

  test(
    'identity.save fail + kill=false: Process.start once; second start refused',
    () async {
      final root = Directory.systemTemp.createTempSync('yomu-savefail');
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      });
      final paths = SuwayomiPaths(root);
      await paths.ensureLayout();

      final jarBytes = [1, 2, 3, 4, 5, 9];
      final hash = sha256.convert(jarBytes).toString();
      final jar = File(
        p.join(paths.runtimeDir.path, 'Suwayomi-Server-v2.3.2238.jar'),
      );
      await jar.writeAsBytes(jarBytes);

      final javaStub = File(p.join(root.path, 'java', 'bin', 'java.exe'))
        ..createSync(recursive: true);
      await javaStub.writeAsBytes([0]);

      final manifest = VendorManifest(
        suwayomi: SuwayomiArtifact(
          version: 'v0',
          revision: 'r0',
          jarFile: 'Suwayomi-Server-v2.3.2238.jar',
          downloadUrl: 'https://example.com/x.jar',
          sha256: hash,
          minJre: 21,
        ),
      );

      var startCount = 0;
      final startedProcs = <Process>[];
      addTearDown(() async {
        for (final proc in startedProcs) {
          try {
            proc.kill(ProcessSignal.sigkill);
            await proc.exitCode.timeout(const Duration(seconds: 3));
          } catch (_) {}
        }
      });

      const testPort = 24603;
      final probe = _FakeProbe(killSucceeds: false);

      final manager = SuwayomiProcessManager(
        paths: paths,
        manifest: manifest,
        javaResolver: _FixedJavaResolver(javaStub.absolute.path),
        ownershipProbe: probe,
        port: testPort,
        identitySaveForTest: (id, file) async {
          throw StateError('disk full — identity save forced fail');
        },
        killAndConfirmExitForTest: (proc, {required int pid}) async {
          // kill=false / timeout → orphan (do not reap).
          return true;
        },
        processStartForTest:
            (
              executable,
              arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
              bool runInShell = false,
            }) async {
              startCount++;
              // Long-lived process so handle stays valid (not Yomu/Java).
              final proc = await Process.start('powershell', [
                '-NoProfile',
                '-Command',
                'Start-Sleep -Seconds 120',
              ], runInShell: false);
              startedProcs.add(proc);
              return proc;
            },
      );

      final first = await manager.start(
        readyTimeout: const Duration(milliseconds: 200),
      );
      var firstFailed = false;
      first.when(
        ok: (_) => fail('expected save-fail error'),
        err: (m, _) {
          firstFailed = true;
          expect(m.toLowerCase(), contains('identidade'));
        },
      );
      expect(firstFailed, isTrue);
      expect(startCount, 1);
      expect(manager.identity, isNotNull);
      expect(manager.status.state, SuwayomiProcessState.unhealthy);

      // No identity file required — memory blocks second spawn.
      if (paths.instanceIdentity.existsSync()) {
        await paths.instanceIdentity.delete();
      }

      final second = await manager.start(
        readyTimeout: const Duration(milliseconds: 200),
      );
      second.when(
        ok: (_) => fail('second start must be refused'),
        err: (m, _) {
          final low = m.toLowerCase();
          expect(
            low.contains('memória') ||
                low.contains('recusado') ||
                low.contains('identidade') ||
                low.contains('inspecionar') ||
                low.contains('não revalid'),
            isTrue,
            reason: 'refuse message: $m',
          );
        },
      );
      expect(startCount, 1, reason: 'Process.start must run only once');

      await manager.stop();
      expect(
        manager.status.state,
        SuwayomiProcessState.unhealthy,
        reason: 'unconfirmed exit must never be reported as stopped',
      );
      expect(manager.identity, isNotNull);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
