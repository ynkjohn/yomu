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

/// Domain flags / migration markers only.
///
/// **Do not** store Drift [schemaVersion] here — that lives solely on
/// [YomuDatabase.schemaVersion] (P0 = 1; **P1 will be schemaVersion 2**).
class AppMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Single-process Yomu SQLite database (Drift).
///
/// P0 tables: [AppMeta] only.
/// P1 (sessions) **must** bump [schemaVersion] to **2**.
@DriftDatabase(tables: [AppMeta])
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
  int get schemaVersion => 1;

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
    return _serializedLifecycle(() => _openBody(
          yomuRoot,
          registerAsInstance: true,
          useProcessLock: true,
        ));
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

  /// Prove FK enforcement without adding P1 tables to the schema.
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
      AppMetaCompanion.insert(
        key: key,
        value: value,
        updatedAtMs: now,
      ),
    );
  }

  Future<String?> getMeta(String key) async {
    final row = await (select(appMeta)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
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

/// Convenience: yomu root = `{appSupport}/yomu`.
Future<YomuDatabase> openYomuDatabaseAtAppSupport(Directory appSupport) {
  final root = Directory(p.join(appSupport.path, 'yomu'));
  return YomuDatabase.open(root);
}
