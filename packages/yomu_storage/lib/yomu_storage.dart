/// Yomu SQLite storage (Drift).
///
/// **P0:** foundation only — process lock, schemaVersion **1**, [AppMeta] flags.
/// **P1:** sessions will require **schemaVersion 2** (not implemented here).
///
/// Suwayomi keeps its own database for library/progress/downloads.
///
/// ## SQLite on Windows (P0)
///
/// - Dependency pin: `sqlite3` **2.9.4** (transitive via drift 2.28.0).
/// - **No** `sqlite3_flutter_libs`.
/// - On Windows, `package:sqlite3` 2.x loads the OS library
///   **`winsqlite3.dll`** (system SQLite). Confirm with
///   `SELECT sqlite_version()` after open (see package tests).
/// - P0 enables `PRAGMA journal_mode=WAL` and `PRAGMA foreign_keys=ON`.
library;

export 'src/db_file_prep.dart'
    show
        kYomuPlaceholderV0Body,
        kYomuPlaceholderV0Marker,
        prepareDatabaseFile,
        isExactPlaceholderV0,
        DbFileKind,
        DbFilePrepResult;
export 'src/storage_log.dart' show YomuStorageLog;
export 'src/storage_paths.dart';
export 'src/yomu_database.dart';
export 'src/yomu_process_lock.dart';
