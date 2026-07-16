import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_storage/yomu_storage.dart';

void main() {
  late Directory root;
  late YomuDatabase database;
  late File legacyFile;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('yomu-ai-migration-');
    database = await YomuDatabase.openForTest(root, useProcessLock: false);
    legacyFile = File('${root.path}${Platform.pathSeparator}maya_chat.json');
  });

  tearDown(() async {
    try {
      await database.close();
    } catch (_) {}
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  test('imports valid JSON, archives it, and reopens idempotently', () async {
    final bytes = utf8.encode(jsonEncode(_validLegacyJson()));
    await legacyFile.writeAsBytes(bytes);

    final store = await MayaStore.open(
      database: database,
      legacyFile: legacyFile,
    );
    final archive = await _archiveForMarker(database, legacyFile);

    expect(store.messages, hasLength(1));
    expect(store.proposals, hasLength(1));
    expect(
      store.proposalById('proposal-1')!.status,
      ActionProposalStatus.pending,
    );
    expect(await legacyFile.exists(), isFalse);
    expect(await archive.exists(), isTrue);
    expect(
      await database.getMeta(kLegacyMayaMigrationMetaKey),
      contains('imported'),
    );

    await database.close();
    database = await YomuDatabase.openForTest(root, useProcessLock: false);
    final reopened = await MayaStore.open(
      database: database,
      legacyFile: legacyFile,
    );
    expect(reopened.messages, hasLength(1));
    expect(reopened.proposals, hasLength(1));
    expect(await archive.exists(), isTrue);
  });

  test(
    'quarantines legacy pending external effects without redispatch',
    () async {
      await legacyFile.writeAsString(
        jsonEncode(_legacyWithPendingExternalEffects()),
      );
      final store = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
      );
      final port = _RecordingPort();
      final service = MayaService(store: store, libraryPort: port);

      for (final proposalId in const <String>[
        'proposal-download',
        'proposal-library',
      ]) {
        final migrated = store.proposalById(proposalId)!;
        expect(migrated.status, ActionProposalStatus.confirmed);
        expect(migrated.error, kMayaLegacyPendingOutcomeUncertainError);
        final retried = await service.confirmProposal(proposalId);
        expect(retried.status, ActionProposalStatus.confirmed);
      }
      expect(port.downloads, isEmpty);
      expect(port.libraryToggles, isEmpty);
      await service.close();
    },
  );

  test('sanitizes unbounded legacy exception text before validation', () async {
    await legacyFile.writeAsString(jsonEncode(_legacyWithLongError()));

    final store = await MayaStore.open(
      database: database,
      legacyFile: legacyFile,
    );
    final proposal = store.proposalById('proposal-1')!;

    expect(proposal.status, ActionProposalStatus.failed);
    expect(proposal.error, 'Falha registrada no histórico legado.');
    expect(proposal.error, isNot(contains('secret-legacy-error')));
  });

  test(
    'sanitizes legacy assistant messages that embedded exceptions',
    () async {
      await legacyFile.writeAsString(
        jsonEncode(_legacyWithRawExceptionMessages()),
      );

      final store = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
      );

      expect(store.messages.map((message) => message.text), <String>[
        'Não foi possível consultar a biblioteca naquele momento.',
        'Uma ação da Maya falhou naquele momento.',
      ]);
      expect(
        store.messages.any((message) => message.text.contains('secret-path')),
        isFalse,
      );
    },
  );

  test('records an absent source and rejects a later source', () async {
    final store = await MayaStore.open(
      database: database,
      legacyFile: legacyFile,
    );
    expect(store.messages, isEmpty);
    expect(
      await database.getMeta(kLegacyMayaMigrationMetaKey),
      contains('absent'),
    );

    await legacyFile.writeAsString(jsonEncode(_validLegacyJson()));
    await expectLater(
      MayaStore.open(database: database, legacyFile: legacyFile),
      throwsA(
        isA<LegacyMayaMigrationException>().having(
          (error) => error.code,
          'code',
          'legacy_source_appeared_after_absent_marker',
        ),
      ),
    );
    expect(await database.isMayaDataEmpty(), isTrue);
  });

  test('archives a valid empty JSON snapshot', () async {
    await legacyFile.writeAsString(
      jsonEncode(<String, Object>{
        'messages': <Object>[],
        'proposals': <Object>[],
      }),
    );
    final store = await MayaStore.open(
      database: database,
      legacyFile: legacyFile,
    );
    expect(store.messages, isEmpty);
    expect(store.proposals, isEmpty);
    expect(await legacyFile.exists(), isFalse);
    expect(
      await database.getMeta(kLegacyMayaMigrationMetaKey),
      contains('empty'),
    );
  });

  test(
    'malformed, zero-byte, oversized, and invalid records are conservative',
    () async {
      final cases = <({List<int> bytes, String code})>[
        (bytes: const <int>[], code: 'legacy_source_zero_bytes'),
        (bytes: utf8.encode('{broken'), code: 'legacy_json_invalid'),
        (
          bytes: List<int>.filled(
            LegacyMayaChatMigrator.maxLegacySourceBytes + 1,
            0x20,
          ),
          code: 'legacy_source_too_large',
        ),
        (
          bytes: utf8.encode(
            jsonEncode(<String, Object>{
              ..._validLegacyJson(),
              'unexpected': true,
            }),
          ),
          code: 'legacy_root_fields_invalid',
        ),
        (
          bytes: utf8.encode(jsonEncode(_legacyWithUnknownKind())),
          code: 'proposal_kind_invalid',
        ),
        (
          bytes: utf8.encode(jsonEncode(_legacyWithUnreferencedProposal())),
          code: 'legacy_proposal_unreferenced',
        ),
      ];

      for (final testCase in cases) {
        await legacyFile.writeAsBytes(testCase.bytes);
        await expectLater(
          LegacyMayaChatMigrator(
            database: database,
            legacyFile: legacyFile,
          ).migrate(),
          throwsA(
            isA<LegacyMayaMigrationException>().having(
              (error) => error.code,
              'code',
              testCase.code,
            ),
          ),
          reason: testCase.code,
        );
        expect(await database.isMayaDataEmpty(), isTrue);
        expect(await database.getMeta(kLegacyMayaMigrationMetaKey), isNull);
        expect(await legacyFile.exists(), isTrue);
      }
    },
  );

  test('transaction crash rolls rows and marker back', () async {
    await legacyFile.writeAsString(jsonEncode(_validLegacyJson()));
    await expectLater(
      LegacyMayaChatMigrator(
        database: database,
        legacyFile: legacyFile,
        hooks: LegacyMayaMigrationHooks(
          afterRowsInsertedBeforeMarker: () async {
            throw StateError('simulated-crash');
          },
        ),
      ).migrate(),
      throwsStateError,
    );

    expect(await database.isMayaDataEmpty(), isTrue);
    expect(await database.getMeta(kLegacyMayaMigrationMetaKey), isNull);
    expect(await legacyFile.exists(), isTrue);
  });

  test(
    'restart after commit completes archive without duplicate rows',
    () async {
      await legacyFile.writeAsString(jsonEncode(_validLegacyJson()));
      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
          hooks: LegacyMayaMigrationHooks(
            afterCommitBeforeArchive: () async {
              throw StateError('simulated-crash');
            },
          ),
        ).migrate(),
        throwsStateError,
      );
      expect((await database.countMayaData()).messageCount, 1);
      expect((await database.countMayaData()).proposalCount, 1);
      expect(await legacyFile.exists(), isTrue);

      await LegacyMayaChatMigrator(
        database: database,
        legacyFile: legacyFile,
      ).migrate();
      expect((await database.countMayaData()).messageCount, 1);
      expect((await database.countMayaData()).proposalCount, 1);
      expect(await legacyFile.exists(), isFalse);
    },
  );

  test(
    'restart resumes an archive captured before fingerprint verification',
    () async {
      final bytes = utf8.encode(jsonEncode(_validLegacyJson()));
      await legacyFile.writeAsBytes(bytes);

      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
          hooks: LegacyMayaMigrationHooks(
            afterArchiveSourceCapturedBeforeVerify: () async {
              throw StateError('simulated-crash-after-capture');
            },
          ),
        ).migrate(),
        throwsStateError,
      );
      final capture = await _singleArchiveCapture(legacyFile);
      final archive = await _archiveForMarker(database, legacyFile);
      expect(await legacyFile.exists(), isFalse);
      expect(await capture.exists(), isTrue);
      expect((await database.countMayaData()).messageCount, 1);

      await LegacyMayaChatMigrator(
        database: database,
        legacyFile: legacyFile,
      ).migrate();

      expect(await capture.exists(), isFalse);
      expect(await archive.readAsBytes(), bytes);
      expect((await database.countMayaData()).messageCount, 1);
    },
  );

  test(
    'restart revalidates SQLite before finalizing a captured source',
    () async {
      final bytes = utf8.encode(jsonEncode(_validLegacyJson()));
      await legacyFile.writeAsBytes(bytes);
      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
          hooks: LegacyMayaMigrationHooks(
            afterArchiveSourceCapturedBeforeVerify: () async {
              throw StateError('simulated-crash-after-capture');
            },
          ),
        ).migrate(),
        throwsStateError,
      );
      final capture = await _singleArchiveCapture(legacyFile);
      final archive = await _archiveForMarker(database, legacyFile);
      await database.customStatement(
        "UPDATE maya_messages SET text = 'tampered-after-capture'",
      );

      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
        ).migrate(),
        throwsStateError,
      );

      expect(await capture.readAsBytes(), bytes);
      expect(await archive.exists(), isFalse);
      expect(await legacyFile.exists(), isFalse);
    },
  );

  test(
    'restart accepts an archive published before the completion check',
    () async {
      final bytes = utf8.encode(jsonEncode(_validLegacyJson()));
      await legacyFile.writeAsBytes(bytes);
      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
          hooks: LegacyMayaMigrationHooks(
            afterArchiveSourceCapturedBeforeVerify: () async {
              throw StateError('simulated-crash-before-publish');
            },
          ),
        ).migrate(),
        throwsStateError,
      );
      final capture = await _singleArchiveCapture(legacyFile);
      final archive = await _archiveForMarker(database, legacyFile);
      await capture.rename(archive.path);

      await LegacyMayaChatMigrator(
        database: database,
        legacyFile: legacyFile,
      ).migrate();

      expect(await capture.exists(), isFalse);
      expect(await archive.readAsBytes(), bytes);
      expect(await legacyFile.exists(), isFalse);
      expect((await database.countMayaData()).messageCount, 1);
    },
  );

  test('multiple archive captures are preserved and block restart', () async {
    final bytes = utf8.encode(jsonEncode(_validLegacyJson()));
    await legacyFile.writeAsBytes(bytes);
    await expectLater(
      LegacyMayaChatMigrator(
        database: database,
        legacyFile: legacyFile,
        hooks: LegacyMayaMigrationHooks(
          afterArchiveSourceCapturedBeforeVerify: () async {
            throw StateError('simulated-crash-with-capture');
          },
        ),
      ).migrate(),
      throwsStateError,
    );
    final first = await _singleArchiveCapture(legacyFile);
    final marker =
        jsonDecode((await database.getMeta(kLegacyMayaMigrationMetaKey))!)
            as Map<String, dynamic>;
    final second = File(
      '${legacyFile.path}.migrating-v1.${marker['fingerprint']}.'
      '${marker['archiveNonce']}.${'e' * 32}.tmp',
    );
    await first.copy(second.path);

    await expectLater(
      LegacyMayaChatMigrator(
        database: database,
        legacyFile: legacyFile,
      ).migrate(),
      throwsA(
        isA<LegacyMayaMigrationException>().having(
          (error) => error.code,
          'code',
          'legacy_archive_capture_conflict',
        ),
      ),
    );

    expect(await first.readAsBytes(), bytes);
    expect(await second.readAsBytes(), bytes);
    expect(
      await (await _archiveForMarker(database, legacyFile)).exists(),
      isFalse,
    );
  });

  test(
    'restart safely finalizes a semantic pre-nonce marker after publish crash',
    () async {
      final bytes = utf8.encode(jsonEncode(_validLegacyJson()));
      await legacyFile.writeAsBytes(bytes);
      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
          hooks: LegacyMayaMigrationHooks(
            afterArchiveSourceCapturedBeforeVerify: () async {
              throw StateError('simulated-old-version-crash');
            },
          ),
        ).migrate(),
        throwsStateError,
      );
      final markerRaw = await database.getMeta(kLegacyMayaMigrationMetaKey);
      final marker = Map<String, dynamic>.from(
        jsonDecode(markerRaw!) as Map<dynamic, dynamic>,
      );
      final fingerprint = marker['fingerprint']! as String;
      await database.setMeta(
        kLegacyMayaMigrationMetaKey,
        jsonEncode(<String, Object?>{
          'fingerprint': fingerprint,
          'archiveNonce': null,
          'state': marker['state'],
          'version': 1,
        }),
      );
      final currentCapture = await _singleArchiveCapture(legacyFile);
      final legacyCapture = File(
        '${legacyFile.path}.migrating-v1.$fingerprint.tmp',
      );
      await currentCapture.rename(legacyCapture.path);
      final legacyArchive = File(
        '${legacyFile.path}.migrated-v1.$fingerprint.bak',
      );

      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
          hooks: LegacyMayaMigrationHooks(
            beforeArchiveCapturePublished: () async {
              throw StateError('simulated-pre-nonce-publish-crash');
            },
          ),
        ).migrate(),
        throwsStateError,
      );
      expect(await legacyCapture.readAsBytes(), bytes);
      expect(await legacyArchive.exists(), isFalse);

      await LegacyMayaChatMigrator(
        database: database,
        legacyFile: legacyFile,
      ).migrate();

      expect(await legacyCapture.exists(), isFalse);
      expect(await legacyArchive.readAsBytes(), bytes);
      expect((await database.countMayaData()).messageCount, 1);
    },
  );

  test(
    'archive capture preserves a source that reappears during archival',
    () async {
      final original = utf8.encode(jsonEncode(_validLegacyJson()));
      final replacement = utf8.encode(
        jsonEncode(<String, Object>{
          'messages': <Object>[],
          'proposals': <Object>[],
        }),
      );
      await legacyFile.writeAsBytes(original);

      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
          hooks: LegacyMayaMigrationHooks(
            afterArchiveSourceCapturedBeforeVerify: () async {
              await legacyFile.writeAsBytes(replacement);
            },
          ),
        ).migrate(),
        throwsA(
          isA<LegacyMayaMigrationException>().having(
            (error) => error.code,
            'code',
            'legacy_source_reappeared_during_archive',
          ),
        ),
      );

      final archive = await _archiveForMarker(database, legacyFile);
      expect(await archive.readAsBytes(), original);
      expect(await legacyFile.readAsBytes(), replacement);
      expect((await database.countMayaData()).messageCount, 1);
    },
  );

  test(
    'archive published after capture never replaces a race winner',
    () async {
      final bytes = utf8.encode(jsonEncode(_validLegacyJson()));
      await legacyFile.writeAsBytes(bytes);
      late File capture;
      late File archive;

      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
          hooks: LegacyMayaMigrationHooks(
            beforeArchiveCapturePublished: () async {
              capture = await _singleArchiveCapture(legacyFile);
              archive = await _archiveForMarker(database, legacyFile);
              await archive.writeAsString('race-winner');
            },
          ),
        ).migrate(),
        throwsA(
          isA<LegacyMayaMigrationException>().having(
            (error) => error.code,
            'code',
            'legacy_archive_conflict',
          ),
        ),
      );

      expect(await archive.readAsString(), 'race-winner');
      expect(await capture.readAsBytes(), bytes);
      expect(await legacyFile.exists(), isFalse);
      expect((await database.countMayaData()).messageCount, 1);
    },
  );

  test(
    'oversized reappeared source preserves a changed archive capture',
    () async {
      final bytes = utf8.encode(jsonEncode(_validLegacyJson()));
      await legacyFile.writeAsBytes(bytes);
      late File capture;
      final oversized = List<int>.filled(
        LegacyMayaChatMigrator.maxLegacySourceBytes + 1,
        0x41,
      );

      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
          hooks: LegacyMayaMigrationHooks(
            afterArchiveSourceCapturedBeforeVerify: () async {
              capture = await _singleArchiveCapture(legacyFile);
              await capture.writeAsString('changed-capture');
              await legacyFile.writeAsBytes(oversized);
            },
          ),
        ).migrate(),
        throwsA(
          isA<LegacyMayaMigrationException>().having(
            (error) => error.code,
            'code',
            'legacy_source_changed_before_archive',
          ),
        ),
      );

      expect(await capture.readAsString(), 'changed-capture');
      expect(await legacyFile.length(), oversized.length);
      expect(
        await (await _archiveForMarker(database, legacyFile)).exists(),
        isFalse,
      );
      expect((await database.countMayaData()).messageCount, 1);
    },
  );

  test(
    'changed source after commit blocks archive and preserves rows',
    () async {
      await legacyFile.writeAsString(jsonEncode(_validLegacyJson()));
      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
          hooks: LegacyMayaMigrationHooks(
            afterCommitBeforeArchive: () async {
              throw StateError('simulated-crash');
            },
          ),
        ).migrate(),
        throwsStateError,
      );
      await legacyFile.writeAsString(
        jsonEncode(<String, Object>{
          'messages': <Object>[],
          'proposals': <Object>[],
        }),
      );

      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
        ).migrate(),
        throwsA(
          isA<LegacyMayaMigrationException>().having(
            (error) => error.code,
            'code',
            'legacy_source_changed_after_migration',
          ),
        ),
      );
      expect((await database.countMayaData()).messageCount, 1);
      expect(await legacyFile.exists(), isTrue);
    },
  );

  test(
    'archive conflict after commit remains blocked and restartable',
    () async {
      final bytes = utf8.encode(jsonEncode(_validLegacyJson()));
      await legacyFile.writeAsBytes(bytes);
      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
          hooks: LegacyMayaMigrationHooks(
            afterCommitBeforeArchive: () async {
              throw StateError('simulated-crash');
            },
          ),
        ).migrate(),
        throwsStateError,
      );
      final archive = await _archiveForMarker(database, legacyFile);
      await archive.writeAsString('conflict');

      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
        ).migrate(),
        throwsA(
          isA<LegacyMayaMigrationException>().having(
            (error) => error.code,
            'code',
            'legacy_archive_conflict',
          ),
        ),
      );
      expect(await legacyFile.exists(), isTrue);
      expect(await archive.readAsString(), 'conflict');
    },
  );

  test(
    'full readback mismatch blocks archive on this and later runs',
    () async {
      final bytes = utf8.encode(jsonEncode(_validLegacyJson()));
      await legacyFile.writeAsBytes(bytes);

      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
          hooks: LegacyMayaMigrationHooks(
            afterRowsInsertedBeforeMarker: () async {
              await database.customStatement(
                "UPDATE maya_messages SET text = 'tampered'",
              );
            },
          ),
        ).migrate(),
        throwsStateError,
      );
      final archive = await _archiveForMarker(database, legacyFile);
      expect(await database.getMeta(kLegacyMayaMigrationMetaKey), isNotNull);
      expect(await legacyFile.exists(), isTrue);
      expect(await archive.exists(), isFalse);

      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
        ).migrate(),
        throwsStateError,
      );
      expect(await legacyFile.exists(), isTrue);
      expect(await archive.exists(), isFalse);
    },
  );

  test('archive without marker blocks a reset database', () async {
    final archive = File('${legacyFile.path}.migrated-v1.${'a' * 64}.bak');
    await archive.writeAsString('preserve');

    await expectLater(
      LegacyMayaChatMigrator(
        database: database,
        legacyFile: legacyFile,
      ).migrate(),
      throwsA(
        isA<LegacyMayaMigrationException>().having(
          (error) => error.code,
          'code',
          'legacy_archive_without_marker',
        ),
      ),
    );
    expect(await archive.exists(), isTrue);
    expect(await database.getMeta(kLegacyMayaMigrationMetaKey), isNull);
  });

  test(
    'orphan archive capture without marker blocks a reset database',
    () async {
      final capture = File(
        '${legacyFile.path}.migrating-v1.${'a' * 64}.${'b' * 32}.'
        '${'c' * 32}.tmp',
      );
      await capture.writeAsString('preserve-orphan-capture');

      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
        ).migrate(),
        throwsA(
          isA<LegacyMayaMigrationException>().having(
            (error) => error.code,
            'code',
            'legacy_staging_without_marker',
          ),
        ),
      );

      expect(await capture.readAsString(), 'preserve-orphan-capture');
      expect(await database.getMeta(kLegacyMayaMigrationMetaKey), isNull);
    },
  );

  test(
    'archive clear capture without marker blocks a reset database',
    () async {
      final capture = File(
        '${legacyFile.path}.migrated-v1.${'a' * 64}.${'b' * 32}.bak.'
        'clearing.${'c' * 32}.tmp',
      );
      await capture.writeAsString('preserve-clear-capture');

      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
        ).migrate(),
        throwsA(
          isA<LegacyMayaMigrationException>().having(
            (error) => error.code,
            'code',
            'legacy_staging_without_marker',
          ),
        ),
      );

      expect(await capture.readAsString(), 'preserve-clear-capture');
      expect(await database.getMeta(kLegacyMayaMigrationMetaKey), isNull);
    },
  );

  test('source clear capture blocks an existing absent marker', () async {
    await LegacyMayaChatMigrator(
      database: database,
      legacyFile: legacyFile,
    ).migrate();
    final capture = File(
      '${legacyFile.path}.clearing-v1.${'a' * 64}.source.${'b' * 32}.tmp',
    );
    await capture.writeAsString('preserve-clear-capture');

    await expectLater(
      LegacyMayaChatMigrator(
        database: database,
        legacyFile: legacyFile,
      ).migrate(),
      throwsA(
        isA<LegacyMayaMigrationException>().having(
          (error) => error.code,
          'code',
          'legacy_source_appeared_after_absent_marker',
        ),
      ),
    );

    expect(await capture.readAsString(), 'preserve-clear-capture');
    expect(
      await database.getMeta(kLegacyMayaMigrationMetaKey),
      contains('absent'),
    );
  });

  test(
    'semantically invalid marker is rejected without filesystem changes',
    () async {
      final invalid = jsonEncode(<String, Object?>{
        'version': 1,
        'state': 'absent',
        'fingerprint': null,
        'archiveNonce': 'invalid',
      });
      await database.setMeta(kLegacyMayaMigrationMetaKey, invalid);

      await expectLater(
        LegacyMayaChatMigrator(
          database: database,
          legacyFile: legacyFile,
        ).migrate(),
        throwsStateError,
      );

      expect(await database.getMeta(kLegacyMayaMigrationMetaKey), invalid);
      expect(await legacyFile.exists(), isFalse);
    },
  );

  test(
    'clear removes deterministic legacy archive before SQLite/cache',
    () async {
      final bytes = utf8.encode(jsonEncode(_validLegacyJson()));
      await legacyFile.writeAsBytes(bytes);
      final store = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
      );
      final archive = await _archiveForMarker(database, legacyFile);
      expect(await archive.exists(), isTrue);

      await store.clear();

      expect(await archive.exists(), isFalse);
      expect(await database.isMayaDataEmpty(), isTrue);
      expect(store.messages, isEmpty);
      expect(store.proposals, isEmpty);
    },
  );

  test(
    'changed residual source blocks clear and preserves SQLite/cache',
    () async {
      await legacyFile.writeAsString(jsonEncode(_validLegacyJson()));
      final store = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
      );
      await legacyFile.writeAsString(
        jsonEncode(<String, Object>{
          'messages': <Object>[],
          'proposals': <Object>[],
        }),
      );

      await expectLater(
        store.clear(),
        throwsA(
          isA<LegacyMayaMigrationException>().having(
            (error) => error.code,
            'code',
            'legacy_source_changed_before_clear',
          ),
        ),
      );
      expect((await database.countMayaData()).messageCount, 1);
      expect(store.messages, hasLength(1));
      expect(await legacyFile.exists(), isTrue);
    },
  );

  test(
    'clear capture preserves a source that reappears during cleanup',
    () async {
      final original = utf8.encode(jsonEncode(_validLegacyJson()));
      final replacement = utf8.encode(
        jsonEncode(<String, Object>{
          'messages': <Object>[],
          'proposals': <Object>[],
        }),
      );
      await legacyFile.writeAsBytes(original);
      final store = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
        migrationHooks: LegacyMayaMigrationHooks(
          afterClearSourceCapturedBeforeVerify: () async {
            await legacyFile.writeAsBytes(replacement);
          },
        ),
      );
      final archive = await _archiveForMarker(database, legacyFile);
      await legacyFile.writeAsBytes(original);

      await expectLater(
        store.clear(),
        throwsA(
          isA<LegacyMayaMigrationException>().having(
            (error) => error.code,
            'code',
            'legacy_source_reappeared_during_clear',
          ),
        ),
      );

      expect(await legacyFile.readAsBytes(), replacement);
      expect(await archive.exists(), isTrue);
      expect((await database.countMayaData()).messageCount, 1);
      expect(store.messages, hasLength(1));
    },
  );

  test(
    'oversized reappeared source preserves a changed clear capture',
    () async {
      final original = utf8.encode(jsonEncode(_validLegacyJson()));
      await legacyFile.writeAsBytes(original);
      late File capture;
      final oversized = List<int>.filled(
        LegacyMayaChatMigrator.maxLegacySourceBytes + 1,
        0x42,
      );
      final store = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
        migrationHooks: LegacyMayaMigrationHooks(
          afterClearSourceCapturedBeforeVerify: () async {
            capture = await _singleClearCapture(legacyFile);
            await capture.writeAsString('changed-clear-capture');
            await legacyFile.writeAsBytes(oversized);
          },
        ),
      );
      final archive = await _archiveForMarker(database, legacyFile);
      await legacyFile.writeAsBytes(original);

      await expectLater(
        store.clear(),
        throwsA(
          isA<LegacyMayaMigrationException>().having(
            (error) => error.code,
            'code',
            'legacy_source_changed_before_clear',
          ),
        ),
      );

      expect(await capture.readAsString(), 'changed-clear-capture');
      expect(await legacyFile.length(), oversized.length);
      expect(await archive.exists(), isTrue);
      expect((await database.countMayaData()).messageCount, 1);
      expect(store.messages, hasLength(1));
    },
  );

  test(
    'clear resumes a source captured before fingerprint verification',
    () async {
      final original = utf8.encode(jsonEncode(_validLegacyJson()));
      await legacyFile.writeAsBytes(original);
      final store = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
        migrationHooks: LegacyMayaMigrationHooks(
          afterClearSourceCapturedBeforeVerify: () async {
            throw StateError('simulated-clear-crash');
          },
        ),
      );
      await legacyFile.writeAsBytes(original);

      await expectLater(
        store.clear(),
        throwsA(
          isA<LegacyMayaMigrationException>().having(
            (error) => error.code,
            'code',
            'legacy_cleanup_failed',
          ),
        ),
      );
      final capture = await _singleClearCapture(legacyFile);
      expect(await legacyFile.exists(), isFalse);
      expect(await capture.exists(), isTrue);
      expect((await database.countMayaData()).messageCount, 1);

      await database.close();
      database = await YomuDatabase.openForTest(root, useProcessLock: false);
      final reopened = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
      );
      await reopened.clear();

      expect(await capture.exists(), isFalse);
      expect(await database.isMayaDataEmpty(), isTrue);
      expect(reopened.messages, isEmpty);
    },
  );

  test('clear resumes an archive captured before deletion', () async {
    final bytes = utf8.encode(jsonEncode(_validLegacyJson()));
    await legacyFile.writeAsBytes(bytes);
    final store = await MayaStore.open(
      database: database,
      legacyFile: legacyFile,
    );
    final archive = await _archiveForMarker(database, legacyFile);
    final capture = File('${archive.path}.clearing.${'a' * 32}.tmp');
    await archive.rename(capture.path);

    await store.clear();

    expect(await capture.exists(), isFalse);
    expect(await archive.exists(), isFalse);
    expect((await database.countMayaData()).messageCount, 0);
    expect((await database.countMayaData()).proposalCount, 0);
    expect(store.messages, isEmpty);
    expect(store.proposals, isEmpty);
  });

  test(
    'multiple archive clear captures block deletion and preserve data',
    () async {
      final bytes = utf8.encode(jsonEncode(_validLegacyJson()));
      await legacyFile.writeAsBytes(bytes);
      final store = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
      );
      final archive = await _archiveForMarker(database, legacyFile);
      final first = File('${archive.path}.clearing.${'a' * 32}.tmp');
      final second = File('${archive.path}.clearing.${'b' * 32}.tmp');
      await archive.copy(first.path);
      await archive.copy(second.path);

      await expectLater(
        store.clear(),
        throwsA(
          isA<LegacyMayaMigrationException>().having(
            (error) => error.code,
            'code',
            'legacy_clear_capture_conflict',
          ),
        ),
      );

      expect(await archive.readAsBytes(), bytes);
      expect(await first.readAsBytes(), bytes);
      expect(await second.readAsBytes(), bytes);
      expect((await database.countMayaData()).messageCount, 1);
      expect(store.messages, hasLength(1));
    },
  );

  test(
    'stale store cannot clear a proposal confirmed by another store',
    () async {
      await legacyFile.writeAsString(jsonEncode(_validLegacyJson()));
      final first = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
      );
      final second = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
      );
      final archive = await _archiveForMarker(database, legacyFile);
      expect(
        await first.confirmPending('proposal-1', DateTime.utc(2026, 7, 14)),
        isTrue,
      );

      await expectLater(second.clear(), throwsStateError);

      final persisted = (await database.loadMayaSnapshot()).proposals.single;
      expect(persisted.status, 'confirmed');
      expect(await archive.exists(), isTrue);
      expect(
        second.proposalById('proposal-1')!.status,
        ActionProposalStatus.confirmed,
      );
    },
  );

  test(
    'closed SQLite before clear preserves legacy backup, DB, and cache',
    () async {
      final bytes = utf8.encode(jsonEncode(_validLegacyJson()));
      await legacyFile.writeAsBytes(bytes);
      final store = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
      );
      final archive = await _archiveForMarker(database, legacyFile);
      expect(await archive.exists(), isTrue);
      await database.close();

      await expectLater(store.clear(), throwsA(anything));
      expect(await archive.exists(), isTrue);
      expect(store.messages, hasLength(1));
      expect(store.proposals, hasLength(1));

      database = await YomuDatabase.openForTest(root, useProcessLock: false);
      expect((await database.countMayaData()).messageCount, 1);
      expect((await database.countMayaData()).proposalCount, 1);
    },
  );
}

Future<File> _archiveForMarker(YomuDatabase database, File legacyFile) async {
  final raw = await database.getMeta(kLegacyMayaMigrationMetaKey);
  final marker = jsonDecode(raw!) as Map<String, dynamic>;
  final fingerprint = marker['fingerprint']! as String;
  final nonce = marker['archiveNonce'] as String?;
  return File(
    nonce == null
        ? '${legacyFile.path}.migrated-v1.$fingerprint.bak'
        : '${legacyFile.path}.migrated-v1.$fingerprint.$nonce.bak',
  );
}

Future<File> _singleArchiveCapture(File legacyFile) {
  return _singleMatchingFile(
    legacyFile.parent,
    RegExp(
      '^${RegExp.escape(legacyFile.path)}'
      r'\.migrating-v1\.[0-9a-f]{64}(?:\.[0-9a-f]{32}\.[0-9a-f]{32})?\.tmp$',
    ),
  );
}

Future<File> _singleClearCapture(File legacyFile) {
  return _singleMatchingFile(
    legacyFile.parent,
    RegExp(
      '^${RegExp.escape(legacyFile.path)}'
      r'\.clearing-v1\.[0-9a-f]{64}\.source\.[0-9a-f]{32}\.tmp$',
    ),
  );
}

Future<File> _singleMatchingFile(Directory directory, RegExp pattern) async {
  final matches = <File>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is File && pattern.hasMatch(entity.path)) matches.add(entity);
  }
  expect(matches, hasLength(1));
  return matches.single;
}

Map<String, Object> _validLegacyJson() {
  final createdAt = DateTime.utc(2026, 7, 14);
  return <String, Object>{
    'messages': <Object>[
      MayaMessage(
        id: 'message-1',
        role: MayaRole.assistant,
        text: 'Posso abrir esta obra.',
        createdAt: createdAt,
        proposalIds: const <String>['proposal-1'],
      ).toJson(),
    ],
    'proposals': <Object>[
      ActionProposal(
        id: 'proposal-1',
        kind: MayaActionKind.openManga,
        title: 'Abrir obra',
        description: 'Abrir a obra selecionada.',
        payload: const <String, Object>{'mangaId': 7, 'title': 'Yomu'},
        status: ActionProposalStatus.pending,
        createdAt: createdAt,
      ).toJson(),
    ],
  };
}

Map<String, Object> _legacyWithUnknownKind() {
  final root = _validLegacyJson();
  final proposals = List<Object>.from(root['proposals']! as List<Object>);
  final proposal = Map<String, Object?>.from(
    proposals.single as Map<String, Object?>,
  );
  proposal['kind'] = 'unknown';
  root['proposals'] = <Object>[proposal];
  return root;
}

Map<String, Object> _legacyWithUnreferencedProposal() {
  final root = _validLegacyJson();
  final messages = List<Object>.from(root['messages']! as List<Object>);
  final message = Map<String, Object?>.from(
    messages.single as Map<String, Object?>,
  );
  message['proposalIds'] = <String>[];
  root['messages'] = <Object>[message];
  return root;
}

Map<String, Object> _legacyWithLongError() {
  final root = _validLegacyJson();
  final proposals = List<Object>.from(root['proposals']! as List<Object>);
  final proposal = Map<String, Object?>.from(
    proposals.single as Map<String, Object?>,
  );
  proposal['status'] = ActionProposalStatus.failed.name;
  proposal['error'] = 'secret-legacy-error-${'x' * 1000}';
  root['proposals'] = <Object>[proposal];
  return root;
}

Map<String, Object> _legacyWithRawExceptionMessages() {
  final createdAt = DateTime.utc(2026, 7, 14);
  return <String, Object>{
    'messages': <Object>[
      MayaMessage(
        id: 'm-err-1',
        role: MayaRole.assistant,
        text:
            r'Não consegui consultar a biblioteca. Detalhe: secret-path C:\Users\private',
        createdAt: createdAt,
      ).toJson(),
      MayaMessage(
        id: 'm-fail-1',
        role: MayaRole.assistant,
        text: r'Falhou: baixar — secret-path C:\Users\private',
        createdAt: createdAt,
      ).toJson(),
    ],
    'proposals': <Object>[],
  };
}

Map<String, Object> _legacyWithPendingExternalEffects() {
  final createdAt = DateTime.utc(2026, 7, 14);
  return <String, Object>{
    'messages': <Object>[
      MayaMessage(
        id: 'message-download',
        role: MayaRole.assistant,
        text: 'Posso baixar este capítulo.',
        createdAt: createdAt,
        proposalIds: const <String>['proposal-download'],
      ).toJson(),
      MayaMessage(
        id: 'message-library',
        role: MayaRole.assistant,
        text: 'Posso alterar a biblioteca.',
        createdAt: createdAt,
        proposalIds: const <String>['proposal-library'],
      ).toJson(),
    ],
    'proposals': <Object>[
      ActionProposal(
        id: 'proposal-download',
        kind: MayaActionKind.downloadChapter,
        title: 'Baixar capítulo',
        description: 'Enfileirar capítulo.',
        payload: const <String, Object>{'chapterId': 99},
        status: ActionProposalStatus.pending,
        createdAt: createdAt,
      ).toJson(),
      ActionProposal(
        id: 'proposal-library',
        kind: MayaActionKind.setInLibrary,
        title: 'Alterar biblioteca',
        description: 'Adicionar obra à biblioteca.',
        payload: const <String, Object>{'mangaId': 7, 'inLibrary': true},
        status: ActionProposalStatus.pending,
        createdAt: createdAt,
      ).toJson(),
    ],
  };
}

class _RecordingPort implements MayaLibraryPort {
  final List<int> downloads = <int>[];
  final Map<int, bool> libraryToggles = <int, bool>{};

  @override
  Future<void> enqueueChapterDownload(int chapterId) async {
    downloads.add(chapterId);
  }

  @override
  Future<List<MayaLibraryItem>> listLibrary() async => const [];

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {
    libraryToggles[mangaId] = inLibrary;
  }
}
