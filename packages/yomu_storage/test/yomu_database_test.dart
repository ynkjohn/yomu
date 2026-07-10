import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yomu_storage/yomu_storage.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('yomu-storage-p0-');
    YomuDatabase.debugAfterCreated = null;
  });

  tearDown(() async {
    YomuDatabase.debugAfterCreated = null;
    try {
      if (YomuDatabase.instance != null) {
        await YomuDatabase.instance!.close();
      }
    } catch (_) {}
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('create schema v1, app_meta, reopen, WAL, FK capabilities', () async {
    final db = await YomuDatabase.openForTest(root);
    expect(db.schemaVersion, 1);

    await db.setMeta('p0.probe', 'ok');
    expect(await db.getMeta('p0.probe'), 'ok');

    final version = await db.sqliteVersion();
    expect(version, isNotEmpty);
    expect(int.tryParse(version.split('.').first), greaterThanOrEqualTo(3));

    expect(await db.journalMode(), 'wal');
    expect(await db.foreignKeysEnabled(), isTrue);
    expect(await db.foreignKeysEnforcedWithTempTables(), isTrue);

    final path = db.paths.databaseFile.path;
    await db.close();

    final db2 = await YomuDatabase.openForTest(root);
    expect(await db2.getMeta('p0.probe'), 'ok');
    expect(File(path).existsSync(), isTrue);
    final header = await File(path).openRead(0, 16).first;
    expect(String.fromCharCodes(header.take(15)), 'SQLite format 3');
    await db2.close();
  });

  test('placeholder v0 exact body renamed then SQLite created', () async {
    final paths = YomuStoragePaths(root);
    await paths.ensureLayout();
    await paths.databaseFile.writeAsString(kYomuPlaceholderV0Body, flush: true);

    final db = await YomuDatabase.openForTest(root);
    expect(
      File('${paths.databaseFile.path}.placeholder-v0.bak').existsSync(),
      isTrue,
    );
    expect(await db.journalMode(), 'wal');
    await db.close();
  });

  test('unknown non-SQLite file is quarantined not overwritten', () async {
    final paths = YomuStoragePaths(root);
    await paths.ensureLayout();
    await paths.databaseFile.writeAsString('not a database payload\n');

    final db = await YomuDatabase.openForTest(root);
    final quarantines = paths.dataDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).contains('unknown'))
        .toList();
    expect(quarantines, isNotEmpty);
    final logText = await paths.storageLogFile.readAsString();
    expect(logText, contains('unknown_db_quarantined'));
    expect(logText, isNot(contains('not a database payload')));
    await db.close();
  });

  test('two concurrent open calls serialize; second fails if instance held',
      () async {
    final f1 = YomuDatabase.open(root);
    final f2 = YomuDatabase.open(root);
    final results = await Future.wait([
      f1.then<Object>((d) => d).catchError((Object e) => e),
      f2.then<Object>((d) => d).catchError((Object e) => e),
    ]);
    final dbs = results.whereType<YomuDatabase>().toList();
    final errs = results.whereType<StateError>().toList();
    expect(dbs.length, 1);
    expect(errs.length, 1);
    await dbs.single.close();
  });

  test('close is idempotent and concurrent close shares result', () async {
    final db = await YomuDatabase.open(root);
    final c1 = db.close();
    final c2 = db.close();
    await Future.wait([c1, c2]);
    await db.close();
    expect(YomuDatabase.instance, isNull);
  });

  test('open during close waits then succeeds', () async {
    final db = await YomuDatabase.open(root);
    final closing = db.close();
    final reopened = YomuDatabase.open(root);
    await closing;
    final db2 = await reopened;
    expect(db2, isNot(same(db)));
    expect(YomuDatabase.instance, same(db2));
    await db2.close();
  });

  test('injected failure after executor closes isolate and releases lock',
      () async {
    YomuDatabase.debugAfterCreated = (_) async {
      throw StateError('injected_after_create');
    };
    await expectLater(
      YomuDatabase.open(root),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('injected_after_create'),
        ),
      ),
    );
    expect(YomuDatabase.instance, isNull);

    YomuDatabase.debugAfterCreated = null;
    final db = await YomuDatabase.open(root);
    expect(db, isNotNull);
    await db.close();
  });

  test('second process acquire fails within timeout budget', () async {
    final db = await YomuDatabase.openForTest(root, useProcessLock: true);
    final lockPath = db.paths.lockFile.path;
    final packageRoot = _findPackageRoot();

    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'yomu_storage:lock_probe', lockPath, 'try'],
      workingDirectory: packageRoot,
      runInShell: false,
    );
    expect(result.exitCode, isNot(0), reason: '${result.stdout}${result.stderr}');
    final out = '${result.stdout}${result.stderr}';
    expect(out, anyOf(contains('LOCK_FAIL'), contains('LOCK_TIMEOUT')));
    // Budget is measured in the helper around acquire only (not Process.run).
    final acquireMs = _parseAcquireMs(out);
    // lock_probe uses 800ms acquireTimeout; pure acquire must stay near that.
    expect(acquireMs, lessThan(2000), reason: 'ACQUIRE_MS=$acquireMs out=$out');

    await db.close();

    final result2 = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'yomu_storage:lock_probe', lockPath, 'try'],
      workingDirectory: packageRoot,
      runInShell: false,
    );
    expect(result2.exitCode, 0, reason: '${result2.stdout}${result2.stderr}');
    final out2 = '${result2.stdout}';
    expect(out2, contains('LOCK_OK'));
    final acquireOkMs = _parseAcquireMs(out2);
    expect(acquireOkMs, lessThan(2000), reason: 'ACQUIRE_MS=$acquireOkMs');
  });

  test('crash of lock holder helper allows SO re-acquire', () async {
    final packageRoot = _findPackageRoot();
    final lockPath = YomuStoragePaths(root).lockFile.path;
    await YomuStoragePaths(root).ensureLayout();

    final proc = await Process.start(
      Platform.resolvedExecutable,
      ['run', 'yomu_storage:lock_probe', lockPath, 'hold'],
      workingDirectory: packageRoot,
      runInShell: false,
    );
    final lines = <String>[];
    final sub = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(lines.add);

    // Wait until helper reports HELD (not Yomu/Java).
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!lines.any((l) => l.contains('HELD'))) {
      if (DateTime.now().isAfter(deadline)) {
        proc.kill();
        fail('helper never printed HELD: $lines stderr pending');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    // Abruptly end only this Dart helper (never Yomu/Java).
    // On Windows kill() may return false even when TerminateProcess runs;
    // always wait for exit instead of trusting the bool.
    proc.kill(ProcessSignal.sigkill);
    try {
      await proc.exitCode.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      proc.kill();
      await proc.exitCode.timeout(const Duration(seconds: 5));
    }
    await sub.cancel();

    final lock = YomuProcessLock(
      File(lockPath),
      acquireTimeout: const Duration(seconds: 3),
    );
    await lock.acquire();
    await lock.release();
  });

  test('YomuAlreadyRunningException message is clear', () {
    final e = YomuAlreadyRunningException(r'C:\tmp\yomu.lock');
    expect(e.toString(), contains('Yomu já está em execução'));
  });
}

String _findPackageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: yomu_storage')) {
      return dir.path;
    }
    dir = dir.parent;
  }
  return Directory.current.path;
}

/// Parse `ACQUIRE_MS=<n>` printed by [lock_probe] around acquire only.
int _parseAcquireMs(String out) {
  final m = RegExp(r'ACQUIRE_MS=(\d+)').firstMatch(out);
  expect(m, isNotNull, reason: 'missing ACQUIRE_MS in: $out');
  return int.parse(m!.group(1)!);
}
