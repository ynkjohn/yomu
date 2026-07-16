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
    root = Directory.systemTemp.createTempSync('yomu-storage-p2a-');
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

  test('create schema v3, reopen, WAL, FK, and empty Maya data', () async {
    final db = await YomuDatabase.openForTest(root);
    expect(db.schemaVersion, 3);
    await db.validateDatabaseSchema();

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
    expect(await db.isMayaDataEmpty(), isTrue);

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

  test(
    'migrates real schema v1 through v2 to v3 and preserves app_meta',
    () async {
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
      expect(await db.isMayaDataEmpty(), isTrue);
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        3,
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
    },
  );

  test(
    'migrates real schema v2 to v3 and preserves meta and sessions',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final v2 = await verifier.schemaAt(2);
      addTearDown(v2.close);
      v2.rawDatabase.execute(
        'INSERT INTO app_meta(key, value, updated_at_ms) VALUES (?, ?, ?)',
        ['p1.preserved', 'yes', 222333],
      );
      v2.rawDatabase.execute(
        'INSERT INTO device_sessions('
        'session_id, token_hash, device_name, created_at_ms, expires_at_ms'
        ') VALUES (?, ?, ?, ?, ?)',
        ['v2-session', _hash('2'), 'iPhone', 1000, 2000],
      );

      final paths = YomuStoragePaths(root);
      await paths.ensureLayout();
      v2.rawDatabase.execute('VACUUM INTO ?', [paths.databaseFile.path]);

      final db = await YomuDatabase.openForTest(root);
      await db.validateDatabaseSchema();
      expect(await db.getMeta('p1.preserved'), 'yes');
      expect(
        (await db.getDeviceSessionById('v2-session'))?.tokenHash,
        _hash('2'),
      );
      expect(await db.isMayaDataEmpty(), isTrue);
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        3,
      );
      await db.close();
    },
  );

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

  test(
    'Maya append and load preserve explicit message/proposal order',
    () async {
      final db = await YomuDatabase.openForTest(root);
      await db.appendMayaTurn(
        messages: [
          _newMayaMessage(
            messageId: 'user-1',
            role: 'user',
            text: 'primeiro na conversa',
            createdAtMs: 2000,
          ),
          _newMayaMessage(
            messageId: 'assistant-1',
            text: 'segundo na conversa',
            createdAtMs: 1000,
          ),
        ],
        proposals: [
          _newMayaProposal(
            proposalId: 'proposal-1',
            messageId: 'assistant-1',
            proposalOrder: 1,
            createdAtMs: 1000,
          ),
          _newMayaProposal(
            proposalId: 'proposal-0',
            messageId: 'assistant-1',
            proposalOrder: 0,
            createdAtMs: 1000,
          ),
        ],
      );
      await db.appendMayaTurn(
        messages: [
          _newMayaMessage(
            messageId: 'assistant-2',
            text: 'terceiro apesar do timestamp',
            createdAtMs: 500,
          ),
        ],
        proposals: const [],
      );

      final snapshot = await db.loadMayaSnapshot();
      expect(snapshot.messages.map((m) => m.messageId), [
        'user-1',
        'assistant-1',
        'assistant-2',
      ]);
      expect(snapshot.messages.map((m) => m.sortOrder), [0, 1, 2]);
      expect(snapshot.messages.map((m) => m.content), [
        'primeiro na conversa',
        'segundo na conversa',
        'terceiro apesar do timestamp',
      ]);
      expect(snapshot.proposals.map((p) => p.proposalId), [
        'proposal-0',
        'proposal-1',
      ]);
      expect((await db.countMayaData()).messageCount, 3);
      expect((await db.countMayaData()).proposalCount, 2);
      await db.close();
    },
  );

  test(
    'Maya schema enforces enums, pairing, temporal state, FK, and cascade',
    () async {
      final db = await YomuDatabase.openForTest(root);

      Future<void> rawMessage({
        required String id,
        required int order,
        required String role,
        required int createdAtMs,
      }) {
        return db.customStatement(
          'INSERT INTO maya_messages('
          'message_id, sort_order, role, text, created_at_ms'
          ') VALUES (?, ?, ?, ?, ?)',
          [id, order, role, 'text', createdAtMs],
        );
      }

      Future<void> rawProposal({
        required String id,
        String? messageId = 'assistant',
        int? proposalOrder = 0,
        String kind = 'openManga',
        String status = 'pending',
        int createdAtMs = 100,
        int? confirmedAtMs,
        int? completedAtMs,
      }) {
        return db.customStatement(
          'INSERT INTO maya_action_proposals('
          'proposal_id, message_id, proposal_order, kind, title, description, '
          'payload_json, status, created_at_ms, confirmed_at_ms, '
          'completed_at_ms, error'
          ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            id,
            messageId,
            proposalOrder,
            kind,
            'title',
            'description',
            '{}',
            status,
            createdAtMs,
            confirmedAtMs,
            completedAtMs,
            null,
          ],
        );
      }

      await rawMessage(
        id: 'assistant',
        order: 0,
        role: 'assistant',
        createdAtMs: 100,
      );
      await rawProposal(id: 'valid');

      await expectLater(
        rawMessage(id: 'bad-role', order: 1, role: 'tool', createdAtMs: 100),
        throwsA(anything),
      );
      await expectLater(
        rawMessage(id: 'bad-order', order: -1, role: 'user', createdAtMs: 100),
        throwsA(anything),
      );
      await expectLater(
        rawMessage(id: 'bad-time', order: 1, role: 'user', createdAtMs: -1),
        throwsA(anything),
      );
      await expectLater(
        rawProposal(id: 'bad-kind', kind: 'deleteManga', proposalOrder: 1),
        throwsA(anything),
      );
      await expectLater(
        rawProposal(id: 'bad-status', status: 'unknown', proposalOrder: 1),
        throwsA(anything),
      );
      await expectLater(
        rawProposal(
          id: 'bad-pair',
          messageId: 'assistant',
          proposalOrder: null,
        ),
        throwsA(anything),
      );
      await expectLater(
        rawProposal(id: 'bad-fk', messageId: 'missing', proposalOrder: 0),
        throwsA(anything),
      );
      await expectLater(
        rawProposal(
          id: 'pending-confirmed',
          proposalOrder: 1,
          confirmedAtMs: 100,
        ),
        throwsA(anything),
      );
      await expectLater(
        rawProposal(
          id: 'confirmed-without-time',
          proposalOrder: 1,
          status: 'confirmed',
        ),
        throwsA(anything),
      );
      await expectLater(
        rawProposal(
          id: 'executed-backwards',
          proposalOrder: 1,
          status: 'executed',
          confirmedAtMs: 200,
          completedAtMs: 150,
        ),
        throwsA(anything),
      );
      await expectLater(rawProposal(id: 'duplicate-order'), throwsA(anything));

      await db.customStatement(
        "DELETE FROM maya_messages WHERE message_id = 'assistant'",
      );
      expect((await db.countMayaData()).proposalCount, 0);
      await db.close();
    },
  );

  test(
    'Maya import commits marker with rows and rolls back crash hook',
    () async {
      final db = await YomuDatabase.openForTest(root);
      final messages = [
        _newMayaMessage(
          messageId: 'legacy-message',
          text: 'legacy',
          createdAtMs: 100,
        ),
      ];
      final proposals = [
        _newMayaProposal(
          proposalId: 'legacy-proposal',
          messageId: 'legacy-message',
          proposalOrder: 0,
          createdAtMs: 100,
        ),
      ];

      await expectLater(
        db.importMayaSnapshot(
          messages: messages,
          proposals: proposals,
          markerKey: 'migration.maya.test',
          markerValue: 'fingerprint',
          afterRowsInsertedBeforeMarker: () async {
            throw StateError('simulated crash');
          },
        ),
        throwsStateError,
      );
      expect(await db.isMayaDataEmpty(), isTrue);
      expect(await db.getMeta('migration.maya.test'), isNull);

      await db.importMayaSnapshot(
        messages: messages,
        proposals: proposals,
        markerKey: 'migration.maya.test',
        markerValue: 'fingerprint',
      );
      expect(await db.getMeta('migration.maya.test'), 'fingerprint');
      expect((await db.countMayaData()).messageCount, 1);
      expect((await db.countMayaData()).proposalCount, 1);
      await expectLater(
        db.importMayaSnapshot(messages: const [], proposals: const []),
        throwsStateError,
      );
      await db.close();
    },
  );

  test(
    'Maya proposal CAS, uncertain outcome, rollback, and clear are atomic',
    () async {
      final db = await YomuDatabase.openForTest(root);
      await db.appendMayaTurn(
        messages: [
          _newMayaMessage(
            messageId: 'proposal-message',
            text: 'proposal',
            createdAtMs: 100,
          ),
        ],
        proposals: [
          _newMayaProposal(
            proposalId: 'execute-me',
            messageId: 'proposal-message',
            proposalOrder: 0,
            createdAtMs: 100,
          ),
          _newMayaProposal(
            proposalId: 'reject-me',
            messageId: 'proposal-message',
            proposalOrder: 1,
            createdAtMs: 100,
          ),
          _newMayaProposal(
            proposalId: 'fail-me',
            messageId: 'proposal-message',
            proposalOrder: 2,
            createdAtMs: 100,
          ),
          _newMayaProposal(
            proposalId: 'race-me',
            messageId: 'proposal-message',
            proposalOrder: 3,
            createdAtMs: 100,
          ),
          _newMayaProposal(
            proposalId: 'standalone',
            messageId: null,
            proposalOrder: null,
            createdAtMs: 90,
          ),
        ],
      );

      expect(await db.confirmMayaProposal('execute-me', 110), isTrue);
      expect(await db.confirmMayaProposal('execute-me', 111), isFalse);
      final concurrentConfirm = await Future.wait([
        db.confirmMayaProposal('race-me', 112),
        db.confirmMayaProposal('race-me', 113),
      ]);
      expect(concurrentConfirm.where((updated) => updated), hasLength(1));
      expect(
        await db.markConfirmedMayaProposalOutcomeUncertain(
          'execute-me',
          error: 'outcome_unknown',
          outcomeMessage: _newMayaMessage(
            messageId: 'uncertain-message',
            text: 'resultado incerto',
            createdAtMs: 120,
          ),
        ),
        isTrue,
      );
      var snapshot = await db.loadMayaSnapshot();
      var executing = snapshot.proposals.singleWhere(
        (proposal) => proposal.proposalId == 'execute-me',
      );
      expect(executing.status, 'confirmed');
      expect(executing.confirmedAtMs, 110);
      expect(executing.completedAtMs, isNull);
      expect(executing.error, 'outcome_unknown');
      expect(snapshot.messages.last.messageId, 'uncertain-message');

      await expectLater(
        db.completeConfirmedMayaProposal(
          'execute-me',
          status: 'executed',
          completedAtMs: 130,
          outcomeMessage: _newMayaMessage(
            messageId: 'proposal-message',
            text: 'duplicate id forces rollback',
            createdAtMs: 130,
          ),
        ),
        throwsA(anything),
      );
      executing = (await db.loadMayaSnapshot()).proposals.singleWhere(
        (proposal) => proposal.proposalId == 'execute-me',
      );
      expect(executing.status, 'confirmed');
      expect(executing.completedAtMs, isNull);

      expect(
        await db.completeConfirmedMayaProposal(
          'execute-me',
          status: 'executed',
          completedAtMs: 140,
          outcomeMessage: _newMayaMessage(
            messageId: 'executed-message',
            text: 'executed',
            createdAtMs: 140,
          ),
        ),
        isTrue,
      );
      expect(
        await db.completeConfirmedMayaProposal(
          'execute-me',
          status: 'executed',
          completedAtMs: 150,
        ),
        isFalse,
      );
      expect(
        await db.resolvePendingMayaProposal(
          'reject-me',
          status: 'rejected',
          completedAtMs: 125,
          outcomeMessage: _newMayaMessage(
            messageId: 'rejected-message',
            text: 'rejected',
            createdAtMs: 125,
          ),
        ),
        isTrue,
      );
      expect(
        await db.resolvePendingMayaProposal(
          'fail-me',
          status: 'failed',
          completedAtMs: 126,
          error: 'validation_failed',
        ),
        isTrue,
      );

      snapshot = await db.loadMayaSnapshot();
      expect(
        snapshot.proposals
            .singleWhere((proposal) => proposal.proposalId == 'execute-me')
            .status,
        'executed',
      );
      expect(
        snapshot.proposals
            .singleWhere((proposal) => proposal.proposalId == 'reject-me')
            .status,
        'rejected',
      );
      expect(
        snapshot.proposals
            .singleWhere((proposal) => proposal.proposalId == 'fail-me')
            .status,
        'failed',
      );
      expect(
        snapshot.proposals
            .singleWhere((proposal) => proposal.proposalId == 'standalone')
            .messageId,
        isNull,
      );

      expect(await db.clearMayaData(), isFalse);
      expect(await db.isMayaDataEmpty(), isFalse);
      expect(
        await db.completeConfirmedMayaProposal(
          'race-me',
          status: 'executed',
          completedAtMs: 150,
        ),
        isTrue,
      );
      expect(await db.clearMayaData(), isTrue);
      expect(await db.isMayaDataEmpty(), isTrue);
      await db.close();
    },
  );

  test('Maya clear preserves a durable confirmed proposal', () async {
    final db = await YomuDatabase.openForTest(root);
    await db.appendMayaTurn(
      messages: [
        _newMayaMessage(
          messageId: 'confirmed-message',
          text: 'proposal',
          createdAtMs: 100,
        ),
      ],
      proposals: [
        _newMayaProposal(
          proposalId: 'confirmed-proposal',
          messageId: 'confirmed-message',
          proposalOrder: 0,
          status: 'confirmed',
          createdAtMs: 100,
          confirmedAtMs: 110,
        ),
      ],
    );

    expect(await db.clearMayaData(), isFalse);
    final snapshot = await db.loadMayaSnapshot();
    expect(snapshot.messages, hasLength(1));
    expect(snapshot.proposals, hasLength(1));
    expect(snapshot.proposals.single.status, 'confirmed');
    await db.close();
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

NewMayaMessage _newMayaMessage({
  required String messageId,
  String role = 'assistant',
  required String text,
  required int createdAtMs,
}) {
  return NewMayaMessage(
    messageId: messageId,
    role: role,
    text: text,
    createdAtMs: createdAtMs,
  );
}

NewMayaProposal _newMayaProposal({
  required String proposalId,
  required String? messageId,
  required int? proposalOrder,
  String kind = 'openManga',
  String status = 'pending',
  required int createdAtMs,
  int? confirmedAtMs,
  int? completedAtMs,
  String? error,
}) {
  return NewMayaProposal(
    proposalId: proposalId,
    messageId: messageId,
    proposalOrder: proposalOrder,
    kind: kind,
    title: 'title',
    description: 'description',
    payloadJson: '{"mangaId":1,"title":"Title"}',
    status: status,
    createdAtMs: createdAtMs,
    confirmedAtMs: confirmedAtMs,
    completedAtMs: completedAtMs,
    error: error,
  );
}

String _hash(String hexDigit) => List<String>.filled(64, hexDigit).join();
