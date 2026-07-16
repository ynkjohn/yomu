import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';
import 'package:yomu_local_server/yomu_local_server.dart';
import 'package:yomu_storage/yomu_storage.dart';

void main() {
  test('pairing exposes bearer once and revokes by session id', () async {
    final store = DeviceAuthStore.inMemory(random: Random(1));
    addTearDown(store.close);
    final pairing = store.startPairing(ttl: const Duration(minutes: 1));

    final claimed = await store.claimPairing(
      code: pairing.code,
      deviceName: 'A',
    );
    final token = claimed.bearerToken!;
    final session = claimed.session!;

    expect(claimed.result, PairingClaimResult.success);
    expect(token, isNotEmpty);
    expect(session.sessionId, isNotEmpty);
    expect(await store.authenticate('Bearer $token'), same(session));
    expect(await store.revoke(session.sessionId), isTrue);
    expect(await store.authenticate(token), isNull);

    final repeated = await store.claimPairing(
      code: pairing.code,
      deviceName: 'B',
    );
    expect(repeated.result, PairingClaimResult.invalidOrExpired);
  });

  test(
    'revokeDevice and pairing rate limit preserve existing semantics',
    () async {
      final store = DeviceAuthStore.inMemory(
        maxFailedAttemptsPerPairingIp: 3,
        random: Random(2),
      );
      addTearDown(store.close);
      final pairing = store.startPairing();
      for (var attempt = 0; attempt < 3; attempt++) {
        await store.claimPairing(
          code: '000000',
          deviceName: 'X',
          clientKey: '10.0.0.1',
        );
      }
      expect(store.isRateLimitedFor('10.0.0.1'), isTrue);
      expect(store.isRateLimitedFor('10.0.0.2'), isFalse);

      final claimed = await store.claimPairing(
        code: pairing.code,
        deviceName: 'Phone',
        clientKey: '10.0.0.2',
      );
      expect(claimed.result, PairingClaimResult.success);
      expect(await store.revokeDevice('Phone'), 1);
      expect(await store.authenticate(claimed.bearerToken), isNull);
    },
  );

  test(
    'valid legacy JSON migrates transactionally and stores only hash',
    () async {
      final fixture = await _DatabaseFixture.create();
      DeviceAuthStore? store;
      addTearDown(() async {
        await store?.close();
        await fixture.dispose();
      });
      const token = 'legacy-plaintext-token';
      final now = DateTime(2026, 7, 15, 12);
      await fixture.legacyFile.writeAsString(
        jsonEncode({
          'sessions': [
            {
              'token': token,
              'deviceName': 'Legacy Phone',
              'createdAt': now
                  .subtract(const Duration(days: 1))
                  .toIso8601String(),
              'expiresAt': now.add(const Duration(days: 10)).toIso8601String(),
              'lastSeenAt': now
                  .subtract(const Duration(hours: 2))
                  .toIso8601String(),
            },
          ],
        }),
        flush: true,
      );

      store = await DeviceAuthStore.open(
        database: fixture.database,
        legacyFile: fixture.legacyFile,
        clock: () => now,
        random: Random(3),
      );

      expect(await fixture.legacyFile.exists(), isFalse);
      final rows = await fixture.database.listDeviceSessions();
      expect(rows, hasLength(1));
      expect(
        rows.single.tokenHash,
        sha256.convert(utf8.encode(token)).toString(),
      );
      expect(rows.single.tokenHash == token, isFalse);
      expect(store.sessions.single.sessionId, rows.single.sessionId);
      expect(await store.authenticate(token), isNotNull);
      expect(
        await fixture.database.getMeta(kLegacyDeviceSessionsMigrationMetaKey),
        isNotNull,
      );

      await fixture.database.customStatement('PRAGMA wal_checkpoint(FULL)');
      expect(
        await _databaseFilesContain(fixture.database.paths.databaseFile, token),
        isFalse,
      );
    },
  );

  test(
    'real schema v1 upgrades through v2/v3 to v4 then imports JSON preserving app_meta',
    () async {
      final root = await Directory.systemTemp.createTemp('yomu-auth-v1-');
      final paths = YomuStoragePaths(root);
      await paths.ensureLayout();
      final raw = sqlite.sqlite3.open(paths.databaseFile.path);
      raw.execute(
        'CREATE TABLE app_meta ('
        'key TEXT NOT NULL PRIMARY KEY, '
        'value TEXT NOT NULL, '
        'updated_at_ms INTEGER NOT NULL'
        ')',
      );
      raw.execute('PRAGMA user_version = 1');
      raw.execute(
        'INSERT INTO app_meta(key, value, updated_at_ms) VALUES (?, ?, ?)',
        ['p0.preserved', 'yes', 123456],
      );
      raw.dispose();

      const token = 'v1-real-database-token';
      final now = DateTime.now();
      final legacyFile = File(
        '${root.path}${Platform.pathSeparator}device_sessions.json',
      );
      await legacyFile.writeAsString(
        jsonEncode({
          'sessions': [
            {
              'token': token,
              'deviceName': 'Migrated Phone',
              'createdAt': now
                  .subtract(const Duration(days: 1))
                  .toIso8601String(),
              'expiresAt': now.add(const Duration(days: 30)).toIso8601String(),
              'lastSeenAt': null,
            },
          ],
        }),
        flush: true,
      );

      YomuDatabase? database;
      DeviceAuthStore? store;
      try {
        database = await YomuDatabase.openForTest(
          root,
          useProcessLock: false,
          useLifecycleMutex: false,
        );
        expect(
          (await database.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          4,
        );
        expect(await database.getMeta('p0.preserved'), 'yes');
        expect(
          (await database
                  .customSelect(
                    "SELECT updated_at_ms FROM app_meta WHERE key = 'p0.preserved'",
                  )
                  .getSingle())
              .read<int>('updated_at_ms'),
          123456,
        );

        store = await DeviceAuthStore.open(
          database: database,
          legacyFile: legacyFile,
        );
        expect(await store.authenticate(token), isNotNull);
        expect(await database.listDeviceSessions(), hasLength(1));
        expect(await database.getMeta('p0.preserved'), 'yes');
        expect(await legacyFile.exists(), isFalse);
      } finally {
        await store?.close();
        await database?.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'SQLite pairing survives restart and individual revoke does not',
    () async {
      final root = await Directory.systemTemp.createTemp('yomu-auth-restart-');
      final legacyFile = File(
        '${root.path}${Platform.pathSeparator}device_sessions.json',
      );
      YomuDatabase? database;
      DeviceAuthStore? store;
      try {
        database = await YomuDatabase.openForTest(
          root,
          useProcessLock: false,
          useLifecycleMutex: false,
        );
        store = await DeviceAuthStore.open(
          database: database,
          legacyFile: legacyFile,
        );
        final pairing = store.startPairing();
        final claimed = await store.claimPairing(
          code: pairing.code,
          deviceName: 'Persistent Phone',
        );
        final token = claimed.bearerToken!;
        final sessionId = claimed.session!.sessionId;
        await store.close();
        store = null;
        await database.close();
        database = null;

        database = await YomuDatabase.openForTest(
          root,
          useProcessLock: false,
          useLifecycleMutex: false,
        );
        store = await DeviceAuthStore.open(
          database: database,
          legacyFile: legacyFile,
        );
        expect((await store.authenticate(token))?.sessionId, sessionId);
        expect(await store.revoke(sessionId), isTrue);
        await store.close();
        store = null;
        await database.close();
        database = null;

        database = await YomuDatabase.openForTest(
          root,
          useProcessLock: false,
          useLifecycleMutex: false,
        );
        store = await DeviceAuthStore.open(
          database: database,
          legacyFile: legacyFile,
        );
        expect(await store.authenticate(token), isNull);
        expect(await database.listDeviceSessions(), isEmpty);
      } finally {
        await store?.close();
        await database?.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test('opening auth removes an expired persisted row', () async {
    final fixture = await _DatabaseFixture.create();
    DeviceAuthStore? store;
    addTearDown(() async {
      await store?.close();
      await fixture.dispose();
    });
    const token = 'already-expired-token';
    final now = DateTime.now();
    await fixture.database.insertDeviceSession(
      NewDeviceSession(
        sessionId: 'expired-session',
        tokenHash: sha256.convert(utf8.encode(token)).toString(),
        deviceName: 'Old Phone',
        createdAtMs: now
            .subtract(const Duration(days: 40))
            .millisecondsSinceEpoch,
        expiresAtMs: now
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch,
      ),
    );

    store = await DeviceAuthStore.open(
      database: fixture.database,
      legacyFile: fixture.legacyFile,
      clock: () => now,
    );
    expect(store.sessions, isEmpty);
    expect(await store.authenticate(token), isNull);
    expect(await fixture.database.listDeviceSessions(), isEmpty);
  });

  test(
    'missing source and valid empty source are marked without sessions',
    () async {
      final absent = await _DatabaseFixture.create();
      DeviceAuthStore? absentStore;
      try {
        absentStore = await DeviceAuthStore.open(
          database: absent.database,
          legacyFile: absent.legacyFile,
        );
        expect(absentStore.sessions, isEmpty);
        final absentMarker = await absent.database.getMeta(
          kLegacyDeviceSessionsMigrationMetaKey,
        );
        expect(absentMarker, contains('absent'));
        await absentStore.close();
        absentStore = null;
        await absent.writeValidLegacy(token: 'late-stale-token');
        await expectLater(
          DeviceAuthStore.open(
            database: absent.database,
            legacyFile: absent.legacyFile,
          ),
          throwsA(isA<LegacyDeviceSessionsMigrationException>()),
        );
        expect(await absent.legacyFile.exists(), isTrue);
        expect(await absent.database.listDeviceSessions(), isEmpty);
      } finally {
        await absentStore?.close();
        await absent.dispose();
      }

      final empty = await _DatabaseFixture.create();
      DeviceAuthStore? emptyStore;
      try {
        await empty.legacyFile.writeAsString('{"sessions":[]}', flush: true);
        emptyStore = await DeviceAuthStore.open(
          database: empty.database,
          legacyFile: empty.legacyFile,
        );
        expect(emptyStore.sessions, isEmpty);
        expect(await empty.legacyFile.exists(), isFalse);
        expect(
          await empty.database.getMeta(kLegacyDeviceSessionsMigrationMetaKey),
          contains('empty'),
        );
      } finally {
        await emptyStore?.close();
        await empty.dispose();
      }
    },
  );

  test(
    'malformed or invalid legacy JSON rolls back and preserves source',
    () async {
      for (final contents in <String>[
        '',
        '{not-json',
        '{}',
        jsonEncode({
          'sessions': [
            {
              'token': 'do-not-echo-this-token',
              'createdAt': '2026-07-15T12:00:00',
              'expiresAt': 'invalid',
            },
          ],
        }),
      ]) {
        final fixture = await _DatabaseFixture.create();
        try {
          await fixture.legacyFile.writeAsString(contents, flush: true);
          Object? failure;
          try {
            await DeviceAuthStore.open(
              database: fixture.database,
              legacyFile: fixture.legacyFile,
            );
          } catch (error) {
            failure = error;
          }
          expect(failure, isA<LegacyDeviceSessionsMigrationException>());
          expect('$failure'.contains('do-not-echo-this-token'), isFalse);
          expect(await fixture.legacyFile.exists(), isTrue);
          expect(await fixture.database.listDeviceSessions(), isEmpty);
          expect(
            await fixture.database.getMeta(
              kLegacyDeviceSessionsMigrationMetaKey,
            ),
            isNull,
          );
        } finally {
          await fixture.dispose();
        }
      }
    },
  );

  test(
    'oversized legacy source is blocked without reading or deleting it',
    () async {
      final fixture = await _DatabaseFixture.create();
      addTearDown(fixture.dispose);
      await fixture.legacyFile.writeAsBytes(
        List<int>.filled(
          LegacyDeviceSessionMigrator.maxLegacySourceBytes + 1,
          0x20,
        ),
        flush: true,
      );

      Object? failure;
      try {
        await DeviceAuthStore.open(
          database: fixture.database,
          legacyFile: fixture.legacyFile,
        );
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<LegacyDeviceSessionsMigrationException>());
      expect(
        (failure! as LegacyDeviceSessionsMigrationException).code,
        'legacy_source_too_large',
      );
      expect(await fixture.legacyFile.exists(), isTrue);
      expect(await fixture.database.listDeviceSessions(), isEmpty);
      expect(
        await fixture.database.getMeta(kLegacyDeviceSessionsMigrationMetaKey),
        isNull,
      );
    },
  );

  test(
    'last active duplicate wins and expired entries are discarded',
    () async {
      final fixture = await _DatabaseFixture.create();
      DeviceAuthStore? store;
      addTearDown(() async {
        await store?.close();
        await fixture.dispose();
      });
      final now = DateTime(2026, 7, 15, 12);
      await fixture.legacyFile.writeAsString(
        jsonEncode({
          'sessions': [
            {
              'token': 'duplicate',
              'deviceName': 'First',
              'createdAt': now
                  .subtract(const Duration(days: 3))
                  .toIso8601String(),
              'expiresAt': now.add(const Duration(days: 3)).toIso8601String(),
            },
            {
              'token': 'expired',
              'deviceName': 'Expired',
              'createdAt': now
                  .subtract(const Duration(days: 5))
                  .toIso8601String(),
              'expiresAt': now
                  .subtract(const Duration(days: 1))
                  .toIso8601String(),
            },
            {
              'token': 'duplicate',
              'deviceName': 'Last',
              'createdAt': now
                  .subtract(const Duration(days: 2))
                  .toIso8601String(),
              // Missing expiresAt intentionally uses createdAt + 30 days.
            },
          ],
        }),
        flush: true,
      );

      store = await DeviceAuthStore.open(
        database: fixture.database,
        legacyFile: fixture.legacyFile,
        clock: () => now,
        random: Random(4),
      );

      expect(store.sessions, hasLength(1));
      expect(store.sessions.single.deviceName, 'Last');
      expect(await store.authenticate('duplicate'), isNotNull);
      expect(await store.authenticate('expired'), isNull);
    },
  );

  test(
    'crash inside migration transaction rolls back and is restartable',
    () async {
      final fixture = await _DatabaseFixture.create();
      DeviceAuthStore? store;
      addTearDown(() async {
        await store?.close();
        await fixture.dispose();
      });
      await fixture.writeValidLegacy(token: 'transaction-crash-token');

      await expectLater(
        DeviceAuthStore.open(
          database: fixture.database,
          legacyFile: fixture.legacyFile,
          migrationHooks: LegacyDeviceSessionsMigrationHooks(
            afterRowsInsertedBeforeMarker: () async =>
                throw StateError('crash'),
          ),
        ),
        throwsA(isA<LegacyDeviceSessionsMigrationException>()),
      );
      expect(await fixture.database.listDeviceSessions(), isEmpty);
      expect(
        await fixture.database.getMeta(kLegacyDeviceSessionsMigrationMetaKey),
        isNull,
      );
      expect(await fixture.legacyFile.exists(), isTrue);

      store = await DeviceAuthStore.open(
        database: fixture.database,
        legacyFile: fixture.legacyFile,
      );
      expect(store.sessions, hasLength(1));
    },
  );

  test(
    'post-commit crash never resurrects a subsequently revoked session',
    () async {
      final fixture = await _DatabaseFixture.create();
      DeviceAuthStore? store;
      addTearDown(() async {
        await store?.close();
        await fixture.dispose();
      });
      const token = 'post-commit-token';
      await fixture.writeValidLegacy(token: token);

      await expectLater(
        DeviceAuthStore.open(
          database: fixture.database,
          legacyFile: fixture.legacyFile,
          migrationHooks: LegacyDeviceSessionsMigrationHooks(
            afterCommitBeforeCleanup: () async => throw StateError('crash'),
          ),
        ),
        throwsA(isA<LegacyDeviceSessionsMigrationException>()),
      );
      final committed = await fixture.database.listDeviceSessions();
      expect(committed, hasLength(1));
      expect(await fixture.legacyFile.exists(), isTrue);
      await fixture.database.deleteDeviceSession(committed.single.sessionId);

      store = await DeviceAuthStore.open(
        database: fixture.database,
        legacyFile: fixture.legacyFile,
      );
      expect(store.sessions, isEmpty);
      expect(await store.authenticate(token), isNull);
      expect(await fixture.legacyFile.exists(), isFalse);
    },
  );

  test(
    'changed legacy source after marker blocks instead of reimporting',
    () async {
      final fixture = await _DatabaseFixture.create();
      DeviceAuthStore? store;
      addTearDown(() async {
        await store?.close();
        await fixture.dispose();
      });
      await fixture.writeValidLegacy(token: 'first-token');
      store = await DeviceAuthStore.open(
        database: fixture.database,
        legacyFile: fixture.legacyFile,
      );
      await store.close();
      store = null;
      await fixture.writeValidLegacy(token: 'stale-different-token');

      await expectLater(
        DeviceAuthStore.open(
          database: fixture.database,
          legacyFile: fixture.legacyFile,
        ),
        throwsA(isA<LegacyDeviceSessionsMigrationException>()),
      );
      expect(await fixture.legacyFile.exists(), isTrue);
      expect(await fixture.database.listDeviceSessions(), hasLength(1));
    },
  );

  test(
    'issue and revokeAll are serialized and stay revoked after reload',
    () async {
      final fixture = await _DatabaseFixture.create();
      DeviceAuthStore? store;
      addTearDown(() async {
        await store?.close();
        await fixture.dispose();
      });
      final issueEntered = Completer<void>();
      final releaseIssue = Completer<void>();
      store = await DeviceAuthStore.open(
        database: fixture.database,
        legacyFile: fixture.legacyFile,
        testHooks: DeviceAuthTestHooks(
          beforeDatabaseMutation: (kind) async {
            if (kind == DeviceAuthMutationKind.issue) {
              issueEntered.complete();
              await releaseIssue.future;
            }
          },
        ),
      );
      final pairing = store.startPairing();
      final claim = store.claimPairing(code: pairing.code, deviceName: 'Phone');
      await issueEntered.future;
      final revokeAll = store.revokeAll();
      releaseIssue.complete();
      final outcome = await claim;
      await revokeAll;

      expect(outcome.result, PairingClaimResult.success);
      expect(store.sessions, isEmpty);
      expect(await store.authenticate(outcome.bearerToken), isNull);
      expect(await fixture.database.listDeviceSessions(), isEmpty);

      await store.close();
      store = await DeviceAuthStore.open(
        database: fixture.database,
        legacyFile: fixture.legacyFile,
      );
      expect(store.sessions, isEmpty);
    },
  );

  test(
    'authenticate and individual revoke execute in admission order',
    () async {
      final fixture = await _DatabaseFixture.create();
      DeviceAuthStore? store;
      addTearDown(() async {
        await store?.close();
        await fixture.dispose();
      });
      final authenticateEntered = Completer<void>();
      final releaseAuthenticate = Completer<void>();
      store = await DeviceAuthStore.open(
        database: fixture.database,
        legacyFile: fixture.legacyFile,
        testHooks: DeviceAuthTestHooks(
          beforeDatabaseMutation: (kind) async {
            if (kind == DeviceAuthMutationKind.authenticate) {
              authenticateEntered.complete();
              await releaseAuthenticate.future;
            }
          },
        ),
      );
      final pairing = store.startPairing();
      final claimed = await store.claimPairing(
        code: pairing.code,
        deviceName: 'Phone',
      );
      final authenticating = store.authenticate(claimed.bearerToken);
      await authenticateEntered.future;
      final revoking = store.revoke(claimed.session!.sessionId);
      releaseAuthenticate.complete();

      expect(await authenticating, isNotNull);
      expect(await revoking, isTrue);
      expect(await store.authenticate(claimed.bearerToken), isNull);
      expect(await fixture.database.listDeviceSessions(), isEmpty);
    },
  );

  test('close drains admitted write and rejects late mutations', () async {
    final fixture = await _DatabaseFixture.create();
    DeviceAuthStore? store;
    addTearDown(() async {
      await store?.close();
      await fixture.dispose();
    });
    final issueEntered = Completer<void>();
    final releaseIssue = Completer<void>();
    store = await DeviceAuthStore.open(
      database: fixture.database,
      legacyFile: fixture.legacyFile,
      testHooks: DeviceAuthTestHooks(
        beforeDatabaseMutation: (kind) async {
          if (kind == DeviceAuthMutationKind.issue) {
            issueEntered.complete();
            await releaseIssue.future;
          }
        },
      ),
    );
    final pairing = store.startPairing();
    final claim = store.claimPairing(code: pairing.code, deviceName: 'Phone');
    await issueEntered.future;
    final closing = store.close();
    expect(store.close(), same(closing));
    expect(
      () => store!.startPairing(),
      throwsA(isA<DeviceAuthClosedException>()),
    );
    await expectLater(
      store.revokeAll(),
      throwsA(isA<DeviceAuthClosedException>()),
    );
    releaseIssue.complete();
    final outcome = await claim;
    await closing;

    expect(outcome.result, PairingClaimResult.success);
    expect(store.isClosed, isTrue);
    final rows = await fixture.database.listDeviceSessions();
    expect(rows, hasLength(1));
    expect(
      rows.single.tokenHash,
      sha256.convert(utf8.encode(outcome.bearerToken!)).toString(),
    );
    expect(rows.single.tokenHash == outcome.bearerToken, isFalse);
    await fixture.database.customStatement('PRAGMA wal_checkpoint(FULL)');
    expect(
      await _databaseFilesContain(
        fixture.database.paths.databaseFile,
        outcome.bearerToken!,
      ),
      isFalse,
    );
  });
}

class _DatabaseFixture {
  _DatabaseFixture._(this.root, this.database, this.legacyFile);

  final Directory root;
  final YomuDatabase database;
  final File legacyFile;

  static Future<_DatabaseFixture> create() async {
    final root = await Directory.systemTemp.createTemp('yomu-auth-p1-');
    final database = await YomuDatabase.openForTest(
      root,
      useProcessLock: false,
      useLifecycleMutex: false,
    );
    return _DatabaseFixture._(
      root,
      database,
      File('${root.path}${Platform.pathSeparator}device_sessions.json'),
    );
  }

  Future<void> writeValidLegacy({required String token}) {
    final now = DateTime.now();
    return legacyFile.writeAsString(
      jsonEncode({
        'sessions': [
          {
            'token': token,
            'deviceName': 'Phone',
            'createdAt': now
                .subtract(const Duration(days: 1))
                .toIso8601String(),
            'expiresAt': now.add(const Duration(days: 30)).toIso8601String(),
            'lastSeenAt': null,
          },
        ],
      }),
      flush: true,
    );
  }

  Future<void> dispose() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

Future<bool> _databaseFilesContain(File databaseFile, String plaintext) async {
  for (final path in <String>[
    databaseFile.path,
    '${databaseFile.path}-wal',
    '${databaseFile.path}-shm',
  ]) {
    final file = File(path);
    if (!await file.exists()) continue;
    final bytes = await file.readAsBytes();
    if (_containsBytes(bytes, utf8.encode(plaintext))) return true;
  }
  return false;
}

bool _containsBytes(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  for (var offset = 0; offset <= haystack.length - needle.length; offset++) {
    var matches = true;
    for (var index = 0; index < needle.length; index++) {
      if (haystack[offset + index] != needle[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
