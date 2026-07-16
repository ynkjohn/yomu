import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'db_file_prep.dart';
import 'storage_log.dart';
import 'storage_paths.dart';
import 'yomu_process_lock.dart';

part 'yomu_database.g.dart';

final RegExp _lowercaseSha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// Domain flags / migration markers only.
///
/// **Do not** store Drift [schemaVersion] here — that lives solely on
/// [YomuDatabase.schemaVersion].
class AppMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Plain-Dart input for a new persisted session.
///
/// Keeping this separate from Drift companions lets authentication code use
/// storage without importing Drift.
@immutable
class NewDeviceSession {
  const NewDeviceSession({
    required this.sessionId,
    required this.tokenHash,
    required this.deviceName,
    required this.createdAtMs,
    required this.expiresAtMs,
    this.lastSeenAtMs,
  });

  final String sessionId;
  final String tokenHash;
  final String deviceName;
  final int createdAtMs;
  final int expiresAtMs;
  final int? lastSeenAtMs;
}

/// Persisted device sessions owned by Yomu.
///
/// Authentication tokens must be irreversibly hashed before reaching this
/// table. The storage layer intentionally has no plaintext-token API.
@DataClassName('StoredDeviceSession')
class DeviceSessions extends Table {
  TextColumn get sessionId => text()();
  TextColumn get tokenHash => text().unique()();
  TextColumn get deviceName => text()();
  IntColumn get createdAtMs => integer()();
  IntColumn get expiresAtMs => integer()();
  IntColumn get lastSeenAtMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {sessionId};

  @override
  List<String> get customConstraints => const [
    "CHECK (length(token_hash) = 64 AND token_hash NOT GLOB '*[^0-9a-f]*')",
  ];
}

/// Plain-Dart input for a Maya message.
///
/// SQL `sort_order` is deliberately assigned by storage so concurrent append
/// operations cannot create duplicate or unstable ordering.
@immutable
class NewMayaMessage {
  const NewMayaMessage({
    required this.messageId,
    required this.role,
    required this.text,
    required this.createdAtMs,
  });

  final String messageId;
  final String role;
  final String text;
  final int createdAtMs;
}

/// Plain-Dart input for a Maya action proposal.
///
/// Storage intentionally keeps enum values as strings so this package never
/// depends on `yomu_ai`. The database checks the supported values.
@immutable
class NewMayaProposal {
  const NewMayaProposal({
    required this.proposalId,
    required this.messageId,
    required this.proposalOrder,
    required this.kind,
    required this.title,
    required this.description,
    required this.payloadJson,
    required this.status,
    required this.createdAtMs,
    this.confirmedAtMs,
    this.completedAtMs,
    this.error,
  });

  final String proposalId;
  final String? messageId;
  final int? proposalOrder;
  final String kind;
  final String title;
  final String description;

  /// Canonical JSON object validated by the domain adapter before storage.
  final String payloadJson;
  final String status;
  final int createdAtMs;
  final int? confirmedAtMs;
  final int? completedAtMs;

  /// Caller-sanitized diagnostic text; never persist raw exception output.
  final String? error;
}

/// Ordered Maya messages plus their persisted action proposals.
@immutable
class MayaStorageSnapshot {
  const MayaStorageSnapshot({required this.messages, required this.proposals});

  final List<StoredMayaMessage> messages;
  final List<StoredMayaProposal> proposals;
}

/// Lightweight persisted-row counts used by migration and lifecycle checks.
@immutable
class MayaDataCounts {
  const MayaDataCounts({
    required this.messageCount,
    required this.proposalCount,
  });

  final int messageCount;
  final int proposalCount;

  bool get isEmpty => messageCount == 0 && proposalCount == 0;
}

/// Whether Maya remains fully local or may use a configured cloud provider.
enum MayaProviderMode { local, cloud }

/// How the model is selected for a cloud Maya provider.
enum MayaProviderModelPolicy { providerDefault, explicit }

const int kMayaProviderIdMaxChars = 64;
const int kMayaProviderModelIdMaxChars = 200;

/// Typed, non-secret Maya provider preferences.
///
/// A missing database row means that the user has never configured a provider.
/// In that state callers must preserve the legacy local/offline behavior. API
/// keys and other credentials never belong in this object or in Yomu SQLite.
@immutable
class MayaProviderSettings {
  const MayaProviderSettings._({
    required this.mode,
    required this.isEnabled,
    required this.providerId,
    required this.modelPolicy,
    required this.modelId,
    required this.shareRecentHistory,
    required this.shareLibraryContext,
    required this.consentVersion,
    required this.consentedAtMs,
    required this.updatedAtMs,
  });

  factory MayaProviderSettings.local({required int updatedAtMs}) {
    _requireNonNegativeTimestamp(updatedAtMs, 'updatedAtMs');
    return MayaProviderSettings._(
      mode: MayaProviderMode.local,
      isEnabled: false,
      providerId: null,
      modelPolicy: null,
      modelId: null,
      shareRecentHistory: false,
      shareLibraryContext: false,
      consentVersion: null,
      consentedAtMs: null,
      updatedAtMs: updatedAtMs,
    );
  }

  factory MayaProviderSettings.cloud({
    required String providerId,
    required MayaProviderModelPolicy modelPolicy,
    String? modelId,
    bool isEnabled = true,
    required bool shareRecentHistory,
    required bool shareLibraryContext,
    required int consentVersion,
    required int consentedAtMs,
    required int updatedAtMs,
  }) {
    final normalizedProviderId = _requireBoundedSettingId(
      providerId,
      'providerId',
      kMayaProviderIdMaxChars,
    );
    final normalizedModelId = switch (modelPolicy) {
      MayaProviderModelPolicy.providerDefault =>
        modelId == null
            ? null
            : throw ArgumentError.value(
                modelId,
                'modelId',
                'must be null when modelPolicy is providerDefault',
              ),
      MayaProviderModelPolicy.explicit => _requireBoundedSettingId(
        modelId,
        'modelId',
        kMayaProviderModelIdMaxChars,
      ),
    };
    if (consentVersion <= 0) {
      throw ArgumentError.value(
        consentVersion,
        'consentVersion',
        'must be positive',
      );
    }
    _requireNonNegativeTimestamp(consentedAtMs, 'consentedAtMs');
    _requireNonNegativeTimestamp(updatedAtMs, 'updatedAtMs');
    if (consentedAtMs > updatedAtMs) {
      throw ArgumentError.value(
        consentedAtMs,
        'consentedAtMs',
        'must not be after updatedAtMs',
      );
    }
    return MayaProviderSettings._(
      mode: MayaProviderMode.cloud,
      isEnabled: isEnabled,
      providerId: normalizedProviderId,
      modelPolicy: modelPolicy,
      modelId: normalizedModelId,
      shareRecentHistory: shareRecentHistory,
      shareLibraryContext: shareLibraryContext,
      consentVersion: consentVersion,
      consentedAtMs: consentedAtMs,
      updatedAtMs: updatedAtMs,
    );
  }

  int get settingsId => 1;

  final MayaProviderMode mode;

  /// Durable admission switch. A cloud snapshot may remain configured while
  /// disabled so restart cannot reactivate it during recovery or cleanup.
  final bool isEnabled;
  final String? providerId;
  final MayaProviderModelPolicy? modelPolicy;
  final String? modelId;
  final bool shareRecentHistory;
  final bool shareLibraryContext;
  final int? consentVersion;
  final int? consentedAtMs;
  final int updatedAtMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MayaProviderSettings &&
          mode == other.mode &&
          isEnabled == other.isEnabled &&
          providerId == other.providerId &&
          modelPolicy == other.modelPolicy &&
          modelId == other.modelId &&
          shareRecentHistory == other.shareRecentHistory &&
          shareLibraryContext == other.shareLibraryContext &&
          consentVersion == other.consentVersion &&
          consentedAtMs == other.consentedAtMs &&
          updatedAtMs == other.updatedAtMs;

  @override
  int get hashCode => Object.hash(
    mode,
    isEnabled,
    providerId,
    modelPolicy,
    modelId,
    shareRecentHistory,
    shareLibraryContext,
    consentVersion,
    consentedAtMs,
    updatedAtMs,
  );
}

String _requireBoundedSettingId(Object? value, String name, int maxChars) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maxChars ||
      value.trim() != value) {
    throw ArgumentError.value(
      value,
      name,
      'must be non-empty, trimmed, and at most $maxChars characters',
    );
  }
  return value;
}

void _requireNonNegativeTimestamp(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must be non-negative');
  }
}

/// Yomu-owned Maya chat messages. Ordering is explicit and never inferred
/// from timestamps, which may collide or arrive out of order.
@DataClassName('StoredMayaMessage')
class MayaMessages extends Table {
  TextColumn get messageId => text()();
  IntColumn get sortOrder => integer().unique()();
  TextColumn get role => text()();
  TextColumn get content => text().named('text')();
  IntColumn get createdAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {messageId};

  @override
  List<String> get customConstraints => const [
    "CHECK (role IN ('system', 'user', 'assistant'))",
    'CHECK (sort_order >= 0)',
    'CHECK (created_at_ms >= 0)',
  ];
}

/// Yomu-owned ActionProposal audit state.
///
/// Suwayomi identifiers inside [payloadJson] are an intention snapshot only;
/// they are never catalog or reading facts and have no cross-database FK.
@DataClassName('StoredMayaProposal')
class MayaActionProposals extends Table {
  TextColumn get proposalId => text()();
  TextColumn get messageId => text().nullable().references(
    MayaMessages,
    #messageId,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get proposalOrder => integer().nullable()();
  TextColumn get kind => text()();
  TextColumn get title => text()();
  TextColumn get description => text()();
  TextColumn get payloadJson => text()();
  TextColumn get status => text()();
  IntColumn get createdAtMs => integer()();
  IntColumn get confirmedAtMs => integer().nullable()();
  IntColumn get completedAtMs => integer().nullable()();
  TextColumn get error => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {proposalId};

  @override
  List<String> get customConstraints => const [
    "CHECK (kind IN ('openManga', 'downloadChapter', 'setInLibrary'))",
    "CHECK (status IN ('pending', 'confirmed', 'rejected', 'executed', 'failed'))",
    'CHECK (created_at_ms >= 0)',
    'CHECK (proposal_order IS NULL OR proposal_order >= 0)',
    'CHECK ((message_id IS NULL AND proposal_order IS NULL) OR '
        '(message_id IS NOT NULL AND proposal_order IS NOT NULL))',
    'CHECK (confirmed_at_ms IS NULL OR confirmed_at_ms >= created_at_ms)',
    'CHECK (completed_at_ms IS NULL OR completed_at_ms >= created_at_ms)',
    'CHECK (confirmed_at_ms IS NULL OR completed_at_ms IS NULL OR '
        'completed_at_ms >= confirmed_at_ms)',
    "CHECK ((status = 'pending' AND confirmed_at_ms IS NULL AND "
        "completed_at_ms IS NULL) OR "
        "(status = 'confirmed' AND confirmed_at_ms IS NOT NULL AND "
        "completed_at_ms IS NULL) OR "
        "(status = 'rejected' AND confirmed_at_ms IS NULL AND "
        "completed_at_ms IS NOT NULL) OR "
        "(status = 'executed' AND confirmed_at_ms IS NOT NULL AND "
        "completed_at_ms IS NOT NULL) OR "
        "(status = 'failed' AND completed_at_ms IS NOT NULL))",
    'UNIQUE (message_id, proposal_order)',
  ];
}

/// Singleton, non-secret provider configuration for Maya.
///
/// The absence of row `settings_id = 1` is semantically distinct from an
/// explicit `local` row. Credentials remain in the operating-system vault.
@DataClassName('StoredMayaProviderSettings')
class MayaProviderSettingsTable extends Table {
  @override
  String get tableName => 'maya_provider_settings';

  IntColumn get settingsId => integer()();
  TextColumn get mode => text()();
  BoolColumn get isEnabled => boolean()();
  TextColumn get providerId => text().nullable()();
  TextColumn get modelPolicy => text().nullable()();
  TextColumn get modelId => text().nullable()();
  BoolColumn get shareRecentHistory => boolean()();
  BoolColumn get shareLibraryContext => boolean()();
  IntColumn get consentVersion => integer().nullable()();
  IntColumn get consentedAtMs => integer().nullable()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {settingsId};

  @override
  List<String> get customConstraints => const [
    'CHECK (settings_id = 1)',
    "CHECK (mode IN ('local', 'cloud'))",
    "CHECK (model_policy IS NULL OR model_policy IN ('provider_default', 'explicit'))",
    'CHECK (updated_at_ms >= 0)',
    'CHECK (consented_at_ms IS NULL OR consented_at_ms >= 0)',
    'CHECK (consented_at_ms IS NULL OR consented_at_ms <= updated_at_ms)',
    'CHECK (provider_id IS NULL OR '
        '(length(provider_id) BETWEEN 1 AND 64 AND provider_id = trim(provider_id)))',
    'CHECK (model_id IS NULL OR '
        '(length(model_id) BETWEEN 1 AND 200 AND model_id = trim(model_id)))',
    "CHECK ((mode = 'local' AND is_enabled = 0 AND provider_id IS NULL AND "
        'model_policy IS NULL AND model_id IS NULL AND '
        'share_recent_history = 0 AND share_library_context = 0 AND '
        'consent_version IS NULL AND consented_at_ms IS NULL) OR '
        "(mode = 'cloud' AND provider_id IS NOT NULL AND "
        'model_policy IS NOT NULL AND consent_version IS NOT NULL AND '
        'consent_version > 0 AND consented_at_ms IS NOT NULL AND '
        "((model_policy = 'provider_default' AND model_id IS NULL) OR "
        "(model_policy = 'explicit' AND model_id IS NOT NULL))))",
  ];
}

/// Single-process Yomu SQLite database (Drift).
///
/// Schema v1 contains [AppMeta]. Schema v2 adds [DeviceSessions]. Schema v3
/// adds [MayaMessages] and [MayaActionProposals]. Schema v4 adds the non-secret
/// singleton [MayaProviderSettingsTable].
@DriftDatabase(
  tables: [
    AppMeta,
    DeviceSessions,
    MayaMessages,
    MayaActionProposals,
    MayaProviderSettingsTable,
  ],
)
class YomuDatabase extends _$YomuDatabase {
  YomuDatabase._(
    super.e,
    this.paths,
    this._lock,
    this._log, {
    required this.ownsProcessLock,
  });

  final YomuStoragePaths paths;
  final YomuProcessLock _lock;
  final YomuStorageLog _log;

  /// Whether this instance holds a process-wide exclusive lock to release.
  final bool ownsProcessLock;

  static YomuDatabase? _instance;

  /// Serializes [open] / [openForTest] (production path) and [close].
  static Future<void> _lifecycleChain = Future<void>.value();

  static Future<void>? _instanceCloseFuture;

  bool _closed = false;
  Future<void>? _closeFuture;

  /// The sole open production instance in this process, if any.
  static YomuDatabase? get instance => _instance;

  /// Test hook: invoked after DB object exists, before the first SELECT.
  /// May throw to force cleanup paths.
  @visibleForTesting
  static Future<void> Function(YomuDatabase db)? debugAfterCreated;

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 1 || from >= to || to != 4) {
        throw StateError('Unsupported Yomu database migration: $from -> $to');
      }
      // Run forward steps in order so an installation may safely upgrade from
      // the P0 binary (v1) directly to the current schema without skipping the
      // v2 session table.
      if (from < 2) {
        await m.createTable(deviceSessions);
      }
      if (from < 3) {
        await m.createTable(mayaMessages);
        await m.createTable(mayaActionProposals);
      }
      if (from < 4) {
        await m.createTable(mayaProviderSettingsTable);
      }
    },
  );

  static Future<T> _serializedLifecycle<T>(Future<T> Function() op) {
    final c = Completer<T>();
    _lifecycleChain = _lifecycleChain.then((_) async {
      try {
        c.complete(await op());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  /// Open the unique process-local database under [yomuRoot] (`…/yomu`).
  ///
  /// Order: exclusive lock → prepare file → SQLite isolate.
  /// Concurrent [open] calls are serialized; concurrent [close] is shared.
  static Future<YomuDatabase> open(Directory yomuRoot) {
    return _serializedLifecycle(
      () => _openBody(yomuRoot, registerAsInstance: true, useProcessLock: true),
    );
  }

  /// Unit-test open (temp dirs). Still serializes with production lifecycle mutex
  /// when [registerAsInstance] is true.
  @visibleForTesting
  static Future<YomuDatabase> openForTest(
    Directory yomuRoot, {
    bool useProcessLock = true,
    bool registerAsInstance = false,
    bool useLifecycleMutex = true,
  }) {
    Future<YomuDatabase> body() => _openBody(
      yomuRoot,
      registerAsInstance: registerAsInstance,
      useProcessLock: useProcessLock,
    );
    if (useLifecycleMutex) {
      return _serializedLifecycle(body);
    }
    return body();
  }

  static Future<YomuDatabase> _openBody(
    Directory yomuRoot, {
    required bool registerAsInstance,
    required bool useProcessLock,
  }) async {
    // Wait for any in-flight close of the previous production instance.
    final closing = _instanceCloseFuture;
    if (closing != null) {
      await closing;
    }
    if (registerAsInstance && _instance != null) {
      throw StateError(
        'YomuDatabase already open in this process — use YomuDatabase.instance',
      );
    }

    final paths = YomuStoragePaths(yomuRoot);
    await paths.ensureLayout();
    final log = YomuStorageLog(paths.storageLogFile);
    final lock = YomuProcessLock(paths.lockFile);
    var lockHeld = false;
    QueryExecutor? executor;
    YomuDatabase? db;

    try {
      if (useProcessLock) {
        await lock.acquire();
        lockHeld = true;
      }

      await prepareDatabaseFile(dbFile: paths.databaseFile, log: log);

      executor = NativeDatabase.createInBackground(
        paths.databaseFile,
        setup: (rawDb) {
          rawDb.execute('PRAGMA journal_mode=WAL;');
          rawDb.execute('PRAGMA foreign_keys=ON;');
        },
      );

      db = YomuDatabase._(
        executor,
        paths,
        lock,
        log,
        ownsProcessLock: useProcessLock,
      );
      // Transfer lock ownership to db — open path must not double-release.
      lockHeld = false;

      final hook = debugAfterCreated;
      if (hook != null) {
        await hook(db);
      }

      // Force migrations / connection.
      await db.customSelect('SELECT 1').getSingle();

      try {
        await log.append(
          'db_opened path=${paths.databaseFile.path} '
          'schemaVersion=${db.schemaVersion}',
        );
      } catch (_) {
        // Log failure must not leave a half-open DB registered.
        rethrow;
      }

      if (registerAsInstance) {
        _instance = db;
      }
      return db;
    } catch (e, st) {
      final err = YomuStorageLog.sanitizeError(e);
      try {
        await log.append('db_open_failed error=$err');
      } catch (_) {}

      // Close executor/isolate fully before releasing lock.
      if (db != null) {
        try {
          await db._closeInternal(clearInstance: registerAsInstance);
        } catch (_) {}
      } else if (executor != null) {
        try {
          await executor.close();
        } catch (_) {}
      }
      if (lockHeld) {
        try {
          await lock.release();
        } catch (_) {}
      }
      // ignore: avoid_print
      stderr.writeln('YomuDatabase.open failed: $err');
      // Preserve stack for tests without dumping unbounded content.
      Error.throwWithStackTrace(e, st);
    }
  }

  /// SQLite library version string (`SELECT sqlite_version()`).
  Future<String> sqliteVersion() async {
    final row = await customSelect('SELECT sqlite_version() AS v').getSingle();
    return row.read<String>('v');
  }

  /// Current journal mode (expect `wal` after open).
  Future<String> journalMode() async {
    final row = await customSelect('PRAGMA journal_mode').getSingle();
    return row.data.values.first.toString().toLowerCase();
  }

  /// Whether foreign_keys pragma is enabled on this connection (`1` / `0`).
  Future<bool> foreignKeysEnabled() async {
    final row = await customSelect('PRAGMA foreign_keys').getSingle();
    final v = row.data.values.first;
    if (v is bool) return v;
    if (v is int) return v != 0;
    return '$v' == '1' || '$v'.toLowerCase() == 'true';
  }

  /// Prove FK enforcement with temporary tables, without touching app data.
  Future<bool> foreignKeysEnforcedWithTempTables() async {
    await customStatement('DROP TABLE IF EXISTS _p0_fk_child');
    await customStatement('DROP TABLE IF EXISTS _p0_fk_parent');
    await customStatement(
      'CREATE TEMP TABLE _p0_fk_parent (id INTEGER PRIMARY KEY)',
    );
    await customStatement(
      'CREATE TEMP TABLE _p0_fk_child ('
      'id INTEGER PRIMARY KEY, '
      'parent_id INTEGER NOT NULL REFERENCES _p0_fk_parent(id)'
      ')',
    );
    await customStatement('INSERT INTO _p0_fk_parent(id) VALUES (1)');
    try {
      await customStatement(
        'INSERT INTO _p0_fk_child(id, parent_id) VALUES (1, 999)',
      );
      return false; // insert should have failed
    } catch (_) {
      return true;
    } finally {
      try {
        await customStatement('DROP TABLE IF EXISTS _p0_fk_child');
        await customStatement('DROP TABLE IF EXISTS _p0_fk_parent');
      } catch (_) {}
    }
  }

  Future<void> setMeta(String key, String value) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await into(appMeta).insertOnConflictUpdate(
      AppMetaCompanion.insert(key: key, value: value, updatedAtMs: now),
    );
  }

  Future<String?> getMeta(String key) async {
    final row = await (select(
      appMeta,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// Run [action] atomically on this database connection.
  ///
  /// Importers use this to persist domain rows and their [AppMeta] marker in
  /// the same transaction.
  Future<T> runInTransaction<T>(
    Future<T> Function(YomuDatabase database) action,
  ) {
    return transaction(() => action(this));
  }

  /// Load the complete Maya snapshot with stable explicit ordering.
  Future<MayaStorageSnapshot> loadMayaSnapshot() async {
    final messages = await (select(
      mayaMessages,
    )..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).get();

    final proposalQuery = select(mayaActionProposals).join([
      leftOuterJoin(
        mayaMessages,
        mayaMessages.messageId.equalsExp(mayaActionProposals.messageId),
      ),
    ]);
    proposalQuery.orderBy([
      // Associated proposals first, in parent-message and proposal order.
      OrderingTerm.asc(mayaActionProposals.messageId.isNull()),
      OrderingTerm.asc(mayaMessages.sortOrder),
      OrderingTerm.asc(mayaActionProposals.proposalOrder),
      // Standalone proposals remain deterministic too.
      OrderingTerm.asc(mayaActionProposals.createdAtMs),
      OrderingTerm.asc(mayaActionProposals.proposalId),
    ]);
    final proposalRows = await proposalQuery.get();
    final proposals = proposalRows
        .map((row) => row.readTable(mayaActionProposals))
        .toList(growable: false);

    return MayaStorageSnapshot(
      messages: List.unmodifiable(messages),
      proposals: List.unmodifiable(proposals),
    );
  }

  /// Import a legacy Maya snapshot exactly once.
  ///
  /// Existing Maya rows are never replaced. Optional [markerKey] and
  /// [markerValue] are written in the same SQLite transaction as all imported
  /// rows, which lets the caller make a fingerprint marker authoritative over
  /// a still-present source file after a crash.
  Future<void> importMayaSnapshot({
    required List<NewMayaMessage> messages,
    required List<NewMayaProposal> proposals,
    String? markerKey,
    String? markerValue,
    Future<void> Function()? afterRowsInsertedBeforeMarker,
  }) {
    if ((markerKey == null) != (markerValue == null)) {
      throw ArgumentError(
        'markerKey and markerValue must either both be set or both be null',
      );
    }
    return transaction(() async {
      final existing = await countMayaData();
      if (!existing.isEmpty) {
        throw StateError('Maya storage is not empty');
      }
      await _insertMayaMessages(messages, firstSortOrder: 0);
      await _insertMayaProposals(proposals);
      await afterRowsInsertedBeforeMarker?.call();
      if (markerKey != null) {
        await setMeta(markerKey, markerValue!);
      }
    });
  }

  /// Append one complete Maya turn atomically and allocate contiguous ordering.
  Future<void> appendMayaTurn({
    required List<NewMayaMessage> messages,
    required List<NewMayaProposal> proposals,
  }) {
    if (messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'must not be empty');
    }
    return transaction(() async {
      final firstSortOrder = await _nextMayaSortOrder();
      await _insertMayaMessages(messages, firstSortOrder: firstSortOrder);
      await _insertMayaProposals(proposals);
    });
  }

  /// Compare-and-set a proposal from pending to the durable confirmation
  /// barrier. A crash after this returns leaves `confirmed`, which callers must
  /// never automatically execute again.
  Future<bool> confirmMayaProposal(String proposalId, int confirmedAtMs) async {
    final count =
        await (update(mayaActionProposals)..where(
              (t) =>
                  t.proposalId.equals(proposalId) & t.status.equals('pending'),
            ))
            .write(
              MayaActionProposalsCompanion(
                status: const Value('confirmed'),
                confirmedAtMs: Value(confirmedAtMs),
                completedAtMs: const Value(null),
                error: const Value(null),
              ),
            );
    return count == 1;
  }

  /// Resolve a confirmed proposal and optionally append its audit message in
  /// the same transaction. [status] must be `executed` or `failed`. A `failed`
  /// transition is only valid when the caller knows no external effect was
  /// applied; ambiguous post-dispatch outcomes must remain `confirmed` through
  /// [markConfirmedMayaProposalOutcomeUncertain].
  Future<bool> completeConfirmedMayaProposal(
    String proposalId, {
    required String status,
    required int completedAtMs,
    String? error,
    NewMayaMessage? outcomeMessage,
  }) {
    if (status != 'executed' && status != 'failed') {
      throw ArgumentError.value(status, 'status', 'must be executed or failed');
    }
    return transaction(() async {
      final count =
          await (update(mayaActionProposals)..where(
                (t) =>
                    t.proposalId.equals(proposalId) &
                    t.status.equals('confirmed'),
              ))
              .write(
                MayaActionProposalsCompanion(
                  status: Value(status),
                  completedAtMs: Value(completedAtMs),
                  error: Value(error),
                ),
              );
      if (count != 1) return false;
      if (outcomeMessage != null) {
        await _appendMayaMessage(outcomeMessage);
      }
      return true;
    });
  }

  /// Resolve a proposal before an external effect starts. [status] must be
  /// `rejected` or `failed`; the optional message is committed atomically.
  Future<bool> resolvePendingMayaProposal(
    String proposalId, {
    required String status,
    required int completedAtMs,
    String? error,
    NewMayaMessage? outcomeMessage,
  }) {
    if (status != 'rejected' && status != 'failed') {
      throw ArgumentError.value(status, 'status', 'must be rejected or failed');
    }
    return transaction(() async {
      final count =
          await (update(mayaActionProposals)..where(
                (t) =>
                    t.proposalId.equals(proposalId) &
                    t.status.equals('pending'),
              ))
              .write(
                MayaActionProposalsCompanion(
                  status: Value(status),
                  confirmedAtMs: const Value(null),
                  completedAtMs: Value(completedAtMs),
                  error: Value(error),
                ),
              );
      if (count != 1) return false;
      if (outcomeMessage != null) {
        await _appendMayaMessage(outcomeMessage);
      }
      return true;
    });
  }

  /// Record diagnostic context while deliberately retaining the durable
  /// `confirmed` state. This never makes the proposal executable again.
  Future<bool> markConfirmedMayaProposalOutcomeUncertain(
    String proposalId, {
    String? error,
    NewMayaMessage? outcomeMessage,
  }) {
    return transaction(() async {
      final count =
          await (update(mayaActionProposals)..where(
                (t) =>
                    t.proposalId.equals(proposalId) &
                    t.status.equals('confirmed'),
              ))
              .write(MayaActionProposalsCompanion(error: Value(error)));
      if (count != 1) return false;
      if (outcomeMessage != null) {
        await _appendMayaMessage(outcomeMessage);
      }
      return true;
    });
  }

  /// Remove all Maya messages and proposals in one transaction unless a
  /// durable confirmation barrier exists.
  ///
  /// The check and deletes share the same transaction so a stale MayaStore
  /// cannot erase a proposal confirmed by another store instance.
  Future<bool> clearMayaData() {
    return transaction(() async {
      if (await hasConfirmedMayaProposal()) return false;

      // Delete proposals explicitly because standalone proposals have no FK
      // parent and therefore are not reached by message cascade.
      await delete(mayaActionProposals).go();
      await delete(mayaMessages).go();
      return true;
    });
  }

  Future<bool> hasConfirmedMayaProposal() async {
    final confirmed =
        await (selectOnly(mayaActionProposals)
              ..addColumns([mayaActionProposals.proposalId])
              ..where(mayaActionProposals.status.equals('confirmed'))
              ..limit(1))
            .getSingleOrNull();
    return confirmed != null;
  }

  Future<MayaDataCounts> countMayaData() async {
    final row = await customSelect(
      'SELECT '
      '(SELECT COUNT(*) FROM maya_messages) AS message_count, '
      '(SELECT COUNT(*) FROM maya_action_proposals) AS proposal_count',
      readsFrom: {mayaMessages, mayaActionProposals},
    ).getSingle();
    return MayaDataCounts(
      messageCount: row.read<int>('message_count'),
      proposalCount: row.read<int>('proposal_count'),
    );
  }

  Future<bool> isMayaDataEmpty() async => (await countMayaData()).isEmpty;

  Future<int> _nextMayaSortOrder() async {
    final row = await customSelect(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_sort_order '
      'FROM maya_messages',
      readsFrom: {mayaMessages},
    ).getSingle();
    return row.read<int>('next_sort_order');
  }

  Future<void> _insertMayaMessages(
    List<NewMayaMessage> messages, {
    required int firstSortOrder,
  }) async {
    for (var index = 0; index < messages.length; index++) {
      await _insertMayaMessage(
        messages[index],
        sortOrder: firstSortOrder + index,
      );
    }
  }

  Future<void> _insertMayaMessage(
    NewMayaMessage message, {
    required int sortOrder,
  }) {
    return into(mayaMessages).insert(
      MayaMessagesCompanion.insert(
        messageId: message.messageId,
        sortOrder: sortOrder,
        role: message.role,
        content: message.text,
        createdAtMs: message.createdAtMs,
      ),
    );
  }

  Future<void> _appendMayaMessage(NewMayaMessage message) async {
    await _insertMayaMessage(message, sortOrder: await _nextMayaSortOrder());
  }

  Future<void> _insertMayaProposals(List<NewMayaProposal> proposals) async {
    for (final proposal in proposals) {
      await into(mayaActionProposals).insert(
        MayaActionProposalsCompanion.insert(
          proposalId: proposal.proposalId,
          messageId: Value(proposal.messageId),
          proposalOrder: Value(proposal.proposalOrder),
          kind: proposal.kind,
          title: proposal.title,
          description: proposal.description,
          payloadJson: proposal.payloadJson,
          status: proposal.status,
          createdAtMs: proposal.createdAtMs,
          confirmedAtMs: Value(proposal.confirmedAtMs),
          completedAtMs: Value(proposal.completedAtMs),
          error: Value(proposal.error),
        ),
      );
    }
  }

  /// Returns null when Maya provider preferences have never been configured.
  Future<MayaProviderSettings?> getMayaProviderSettings() async {
    final row = await select(mayaProviderSettingsTable).getSingleOrNull();
    if (row == null) return null;
    return _decodeMayaProviderSettings(row);
  }

  /// Atomically replaces the complete non-secret Maya provider snapshot.
  Future<void> setMayaProviderSettings(MayaProviderSettings settings) async {
    await into(mayaProviderSettingsTable).insertOnConflictUpdate(
      MayaProviderSettingsTableCompanion.insert(
        settingsId: Value(settings.settingsId),
        mode: settings.mode.name,
        isEnabled: settings.isEnabled,
        providerId: Value(settings.providerId),
        modelPolicy: Value(switch (settings.modelPolicy) {
          MayaProviderModelPolicy.providerDefault => 'provider_default',
          MayaProviderModelPolicy.explicit => 'explicit',
          null => null,
        }),
        modelId: Value(settings.modelId),
        shareRecentHistory: settings.shareRecentHistory,
        shareLibraryContext: settings.shareLibraryContext,
        consentVersion: Value(settings.consentVersion),
        consentedAtMs: Value(settings.consentedAtMs),
        updatedAtMs: settings.updatedAtMs,
      ),
    );
  }

  /// Restores the semantically distinct, never-configured state.
  Future<bool> resetMayaProviderSettings() async {
    final deleted = await (delete(
      mayaProviderSettingsTable,
    )..where((t) => t.settingsId.equals(1))).go();
    return deleted > 0;
  }

  Future<List<StoredDeviceSession>> listDeviceSessions() {
    return (select(
      deviceSessions,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)])).get();
  }

  Future<List<StoredDeviceSession>> listActiveDeviceSessions(int nowMs) {
    return (select(deviceSessions)
          ..where((t) => t.expiresAtMs.isBiggerThanValue(nowMs))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)]))
        .get();
  }

  Future<StoredDeviceSession?> getDeviceSessionById(String sessionId) {
    return (select(
      deviceSessions,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
  }

  Future<StoredDeviceSession?> getDeviceSessionByTokenHash(String tokenHash) {
    return (select(
      deviceSessions,
    )..where((t) => t.tokenHash.equals(tokenHash))).getSingleOrNull();
  }

  /// Strict insert: primary-key or token-hash conflicts fail instead of
  /// replacing an existing (possibly revoked) session.
  Future<void> insertDeviceSession(NewDeviceSession session) async {
    if (!_lowercaseSha256Pattern.hasMatch(session.tokenHash)) {
      throw ArgumentError('tokenHash must be a lowercase SHA-256 digest');
    }
    await into(deviceSessions).insert(
      DeviceSessionsCompanion.insert(
        sessionId: session.sessionId,
        tokenHash: session.tokenHash,
        deviceName: session.deviceName,
        createdAtMs: session.createdAtMs,
        expiresAtMs: session.expiresAtMs,
        lastSeenAtMs: Value(session.lastSeenAtMs),
      ),
    );
  }

  Future<bool> deleteDeviceSession(String sessionId) async {
    final count = await (delete(
      deviceSessions,
    )..where((t) => t.sessionId.equals(sessionId))).go();
    return count == 1;
  }

  Future<int> deleteDeviceSessionsByDeviceName(String deviceName) {
    return (delete(
      deviceSessions,
    )..where((t) => t.deviceName.equals(deviceName))).go();
  }

  Future<int> deleteAllDeviceSessions() {
    return delete(deviceSessions).go();
  }

  Future<bool> updateDeviceSessionLastSeen(
    String sessionId,
    int? lastSeenAtMs,
  ) async {
    final count =
        await (update(deviceSessions)
              ..where((t) => t.sessionId.equals(sessionId)))
            .write(DeviceSessionsCompanion(lastSeenAtMs: Value(lastSeenAtMs)));
    return count == 1;
  }

  /// Close DB executor and release process lock. Idempotent; concurrent calls
  /// share one Future. New [open] waits until this completes when this was
  /// the production instance.
  @override
  Future<void> close() {
    return _closeInternal(clearInstance: true);
  }

  Future<void> _closeInternal({required bool clearInstance}) {
    if (_closeFuture != null) return _closeFuture!;
    if (_closed) return Future<void>.value();

    final c = Completer<void>();
    _closeFuture = c.future;
    if (clearInstance && identical(_instance, this)) {
      _instanceCloseFuture = _closeFuture;
    }

    () async {
      try {
        if (!_closed) {
          try {
            await super.close();
          } catch (_) {}
          _closed = true;
        }
        if (ownsProcessLock) {
          try {
            await _lock.release();
          } catch (_) {}
        }
        if (clearInstance && identical(_instance, this)) {
          _instance = null;
        }
        try {
          await _log.append('db_closed path=${paths.databaseFile.path}');
        } catch (_) {}
        c.complete();
      } catch (e, st) {
        c.completeError(e, st);
      } finally {
        if (identical(_instanceCloseFuture, _closeFuture)) {
          _instanceCloseFuture = null;
        }
      }
    }();

    return _closeFuture!;
  }
}

MayaProviderSettings _decodeMayaProviderSettings(
  StoredMayaProviderSettings row,
) {
  final mode = switch (row.mode) {
    'local' => MayaProviderMode.local,
    'cloud' => MayaProviderMode.cloud,
    _ => throw StateError('Invalid persisted Maya provider mode.'),
  };
  if (mode == MayaProviderMode.local) {
    return MayaProviderSettings.local(updatedAtMs: row.updatedAtMs);
  }

  final modelPolicy = switch (row.modelPolicy) {
    'provider_default' => MayaProviderModelPolicy.providerDefault,
    'explicit' => MayaProviderModelPolicy.explicit,
    _ => throw StateError('Invalid persisted Maya model policy.'),
  };
  return MayaProviderSettings.cloud(
    providerId: row.providerId!,
    modelPolicy: modelPolicy,
    modelId: row.modelId,
    isEnabled: row.isEnabled,
    shareRecentHistory: row.shareRecentHistory,
    shareLibraryContext: row.shareLibraryContext,
    consentVersion: row.consentVersion!,
    consentedAtMs: row.consentedAtMs!,
    updatedAtMs: row.updatedAtMs,
  );
}

/// Convenience: yomu root = `{appSupport}/yomu`.
Future<YomuDatabase> openYomuDatabaseAtAppSupport(Directory appSupport) {
  final root = Directory(p.join(appSupport.path, 'yomu'));
  return YomuDatabase.open(root);
}
