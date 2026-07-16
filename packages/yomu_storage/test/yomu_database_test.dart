import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift_dev/api/migrations_native.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yomu_storage/yomu_storage.dart';

import 'generated/schema.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('yomu-storage-p1-');
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

  test('create schema v2, app_meta, sessions, reopen, WAL, FK', () async {
    final db = await YomuDatabase.openForTest(root);
    expect(db.schemaVersion, 2);

    await db.setMeta('p0.probe', 'ok');
    expect(await db.getMeta('p0.probe'), 'ok');
    await db.insertDeviceSession(
      _newSession(
        sessionId: 'clean-session',
        tokenHash: _hash('a'),
        deviceName: 'iPhone',
      ),
    );
    expect(
      (await db.getDeviceSessionById('clean-session'))?.tokenHash,
      _hash('a'),
    );

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
    expect(await db2.getDeviceSessionById('clean-session'), isNotNull);
    expect(File(path).existsSync(), isTrue);
    final header = await File(path).openRead(0, 16).first;
    expect(String.fromCharCodes(header.take(15)), 'SQLite format 3');
    await db2.close();
  });

  test('migrates real schema v1 to v2 and preserves app_meta', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final v1 = await verifier.schemaAt(1);
    addTearDown(v1.close);
    v1.rawDatabase.execute(
      'INSERT INTO app_meta(key, value, updated_at_ms) VALUES (?, ?, ?)',
      ['p0.preserved', 'yes', 123456],
    );

    final paths = YomuStoragePaths(root);
    await paths.ensureLayout();
    v1.rawDatabase.execute('VACUUM INTO ?', [paths.databaseFile.path]);

    final db = await YomuDatabase.openForTest(root);
    await db.validateDatabaseSchema();
    expect(await db.getMeta('p0.preserved'), 'yes');
    expect(
      (await db
              .customSelect(
                "SELECT updated_at_ms FROM app_meta WHERE key = 'p0.preserved'",
              )
              .getSingle())
          .read<int>('updated_at_ms'),
      123456,
    );
    expect(await db.listDeviceSessions(), isEmpty);
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .single,
      2,
    );

    await db.insertDeviceSession(
      _newSession(
        sessionId: 'post-migration',
        tokenHash: _hash('b'),
        deviceName: 'Migrated iPhone',
      ),
    );
    expect(await db.getDeviceSessionById('post-migration'), isNotNull);
    await db.close();
  });

  test('device session constraints, queries, updates, and deletes', () async {
    final db = await YomuDatabase.openForTest(root);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final active = _newSession(
      sessionId: 'active',
      tokenHash: _hash('c'),
      deviceName: 'iPhone',
      createdAtMs: now - 1000,
      expiresAtMs: now + 100000,
    );
    final expired = _newSession(
      sessionId: 'expired',
      tokenHash: _hash('d'),
      deviceName: 'Old iPhone',
      createdAtMs: now - 200000,
      expiresAtMs: now - 1,
    );
    await db.insertDeviceSession(active);
    await db.insertDeviceSession(expired);

    expect(
      (await db.getDeviceSessionByTokenHash(active.tokenHash))?.sessionId,
      active.sessionId,
    );
    expect((await db.listActiveDeviceSessions(now)).map((s) => s.sessionId), [
      'active',
    ]);

    expect(
      db.insertDeviceSession(
        _newSession(
          sessionId: active.sessionId,
          tokenHash: _hash('e'),
          deviceName: 'Duplicate id',
        ),
      ),
      throwsA(anything),
    );
    expect(
      db.insertDeviceSession(
        _newSession(
          sessionId: 'duplicate-hash',
          tokenHash: active.tokenHash,
          deviceName: 'Duplicate hash',
        ),
      ),
      throwsA(anything),
    );
    expect(
      db.insertDeviceSession(
        _newSession(
          sessionId: 'plaintext',
          tokenHash: 'plaintext-token',
          deviceName: 'Invalid token storage',
        ),
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.toString(),
          'message',
          isNot(contains('plaintext-token')),
        ),
      ),
    );
    expect(
      (await db.listDeviceSessions()).map((s) => s.tokenHash),
      isNot(contains('plaintext-token')),
    );
    await expectLater(
      db.customStatement(
        'INSERT INTO device_sessions('
        'session_id, token_hash, device_name, created_at_ms, expires_at_ms'
        ') VALUES (?, NULL, ?, ?, ?)',
        ['null-hash', 'Invalid', now, now + 1],
      ),
      throwsA(anything),
    );

    expect(await db.updateDeviceSessionLastSeen('active', now), isTrue);
    expect((await db.getDeviceSessionById('active'))?.lastSeenAtMs, now);
    expect(await db.updateDeviceSessionLastSeen('active', null), isTrue);
    expect((await db.getDeviceSessionById('active'))?.lastSeenAtMs, isNull);
    expect(await db.updateDeviceSessionLastSeen('missing', now), isFalse);

    expect(await db.deleteDeviceSession('missing'), isFalse);
    expect(await db.deleteDeviceSession('expired'), isTrue);
    expect(await db.deleteDeviceSessionsByDeviceName('iPhone'), 1);
    expect(await db.listDeviceSessions(), isEmpty);

    await db.insertDeviceSession(active);
    await db.insertDeviceSession(expired);
    expect(await db.deleteAllDeviceSessions(), 2);
    expect(await db.listDeviceSessions(), isEmpty);
    await db.close();
  });

  test('SQLite enforces lowercase SHA-256 token hashes', () async {
    final db = await YomuDatabase.openForTest(root);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    Future<void> rawInsert(String sessionId, String tokenHash) {
      return db.customStatement(
        'INSERT INTO device_sessions('
        'session_id, token_hash, device_name, created_at_ms, expires_at_ms'
        ') VALUES (?, ?, ?, ?, ?)',
        [sessionId, tokenHash, 'Raw SQL', now, now + 1000],
      );
    }

    await expectLater(
      rawInsert('plaintext', 'plaintext-token'),
      throwsA(anything),
    );
    await expectLater(rawInsert('uppercase', _hash('A')), throwsA(anything));
    await expectLater(
      rawInsert('short', List<String>.filled(63, 'a').join()),
      throwsA(anything),
    );

    final validHash = _hash('1');
    await rawInsert('valid', validHash);
    expect((await db.getDeviceSessionById('valid'))?.tokenHash, validHash);
    await db.close();
  });

  test(
    'runInTransaction commits atomically and rolls back on failure',
    () async {
      final db = await YomuDatabase.openForTest(root);
      final committed = _newSession(
        sessionId: 'committed',
        tokenHash: _hash('f'),
        deviceName: 'Committed',
      );
      await db.runInTransaction((tx) async {
        await tx.insertDeviceSession(committed);
        await tx.setMeta('p1.import', 'committed');
      });
      expect(await db.getDeviceSessionById('committed'), isNotNull);
      expect(await db.getMeta('p1.import'), 'committed');

      final rolledBack = _newSession(
        sessionId: 'rolled-back',
        tokenHash: _hash('0'),
        deviceName: 'Rolled back',
      );
      await expectLater(
        db.runInTransaction<void>((tx) async {
          await tx.insertDeviceSession(rolledBack);
          await tx.setMeta('p1.rollback', 'must-not-persist');
          throw StateError('rollback probe');
        }),
        throwsStateError,
      );
      expect(await db.getDeviceSessionById('rolled-back'), isNull);
      expect(await db.getMeta('p1.rollback'), isNull);
      await db.close();
    },
  );

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

  test(
    'two concurrent open calls serialize; second fails if instance held',
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
    },
  );

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

  test(
    'injected failure after executor closes isolate and releases lock',
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
    },
  );

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
    expect(
      result.exitCode,
      isNot(0),
      reason: '${result.stdout}${result.stderr}',
    );
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

NewDeviceSession _newSession({
  required String sessionId,
  required String tokenHash,
  required String deviceName,
  int? createdAtMs,
  int? expiresAtMs,
  int? lastSeenAtMs,
}) {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  return NewDeviceSession(
    sessionId: sessionId,
    tokenHash: tokenHash,
    deviceName: deviceName,
    createdAtMs: createdAtMs ?? now,
    expiresAtMs: expiresAtMs ?? now + const Duration(days: 30).inMilliseconds,
    lastSeenAtMs: lastSeenAtMs,
  );
}

String _hash(String hexDigit) => List<String>.filled(64, hexDigit).join();
