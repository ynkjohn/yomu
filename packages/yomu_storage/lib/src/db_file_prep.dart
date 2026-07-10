import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'storage_log.dart';

/// Exact first-line marker (documentation only — matching uses full body).
const String kYomuPlaceholderV0Marker = '-- yomu sqlite placeholder v0';

/// Full historical placeholder body (legacy stub).
///
/// Recognition is **exact** after optional CRLF→LF normalization only.
const String kYomuPlaceholderV0Body =
    '-- yomu sqlite placeholder v0\n'
    '-- Real Drift migrations in a later phase.\n';

/// SQLite main-database magic (16 bytes including NUL).
final Uint8List kSqliteMagic = Uint8List.fromList([
  ...utf8.encode('SQLite format 3'),
  0,
]);

final int kPlaceholderLfBytes = utf8.encode(kYomuPlaceholderV0Body).length;
final int kPlaceholderCrlfBytes =
    utf8.encode(kYomuPlaceholderV0Body.replaceAll('\n', '\r\n')).length;

enum DbFileKind { missing, placeholderV0, sqlite, unknown }

class DbFilePrepResult {
  const DbFilePrepResult({
    required this.kind,
    this.quarantinePath,
    this.placeholderBakPath,
  });

  final DbFileKind kind;
  final String? quarantinePath;
  final String? placeholderBakPath;
}

/// Prepare [dbFile] so Drift may open a real SQLite database at that path.
///
/// Reads only header/size unless the file length can match the exact
/// placeholder LF/CRLF bodies. Unknown files are quarantined by **streaming**
/// to an exclusively created destination; original is removed only after
/// the copy is flushed and closed.
Future<DbFilePrepResult> prepareDatabaseFile({
  required File dbFile,
  required YomuStorageLog log,
}) async {
  if (!dbFile.existsSync()) {
    return const DbFilePrepResult(kind: DbFileKind.missing);
  }

  final length = await dbFile.length();
  final header = await _readPrefix(dbFile, kSqliteMagic.length);

  if (isSqliteHeader(header)) {
    return const DbFilePrepResult(kind: DbFileKind.sqlite);
  }

  // Only load full body when size can be the historical placeholder.
  if (length == kPlaceholderLfBytes || length == kPlaceholderCrlfBytes) {
    final body = await _readExact(dbFile, length);
    if (isExactPlaceholderV0(body)) {
      final bak = await reserveExclusiveFile(
        preferred: '${dbFile.path}.placeholder-v0.bak',
        pattern: (suffix) => '${dbFile.path}.placeholder-v0.$suffix.bak',
      );
      await streamCopyFile(dbFile, bak);
      await dbFile.delete();
      await log.append(
        'placeholder_v0_renamed path=${dbFile.path} bak=${bak.path}',
      );
      return DbFilePrepResult(
        kind: DbFileKind.placeholderV0,
        placeholderBakPath: bak.path,
      );
    }
  }

  final quarantine = await reserveExclusiveFile(
    preferred: null,
    pattern: (suffix) => '${dbFile.path}.unknown.$suffix.bak',
  );
  await streamCopyFile(dbFile, quarantine);
  await dbFile.delete();
  await log.append(
    'unknown_db_quarantined path=${dbFile.path} '
    'quarantine=${quarantine.path} bytes=$length',
  );
  return DbFilePrepResult(
    kind: DbFileKind.unknown,
    quarantinePath: quarantine.path,
  );
}

/// Exact body match: optional CRLF→LF only (no trim, no partial marker).
bool isExactPlaceholderV0(List<int> bytes) {
  late final String asString;
  try {
    asString = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    return false;
  }
  final normalized = asString.replaceAll('\r\n', '\n');
  return normalized == kYomuPlaceholderV0Body;
}

bool isSqliteHeader(List<int> bytes) {
  if (bytes.length < kSqliteMagic.length) return false;
  for (var i = 0; i < kSqliteMagic.length; i++) {
    if (bytes[i] != kSqliteMagic[i]) return false;
  }
  return true;
}

Future<List<int>> _readPrefix(File file, int maxBytes) async {
  final raf = await file.open(mode: FileMode.read);
  try {
    final n = maxBytes;
    final buf = await raf.read(n);
    return buf;
  } finally {
    await raf.close();
  }
}

Future<List<int>> _readExact(File file, int length) async {
  final raf = await file.open(mode: FileMode.read);
  try {
    final buf = await raf.read(length);
    if (buf.length != length) {
      throw StateError('short read ${buf.length} != $length');
    }
    return buf;
  } finally {
    await raf.close();
  }
}

/// Create an empty file at a unique path with [File.create] `exclusive: true`.
///
/// Never returns a path that already existed; never uses exists+rename races.
Future<File> reserveExclusiveFile({
  required String? preferred,
  required String Function(String suffix) pattern,
}) async {
  final rnd = Random.secure();
  if (preferred != null) {
    final f = File(preferred);
    try {
      await f.create(exclusive: true);
      return f;
    } on FileSystemException {
      // fall through to patterned names
    }
  }
  final base = DateTime.now().toUtc().microsecondsSinceEpoch;
  for (var i = 0; i < 10000; i++) {
    final suffix = '${base}_${i}_${rnd.nextInt(0x7fffffff)}';
    final f = File(pattern(suffix));
    try {
      await f.parent.create(recursive: true);
      await f.create(exclusive: true);
      return f;
    } on FileSystemException {
      continue;
    }
  }
  throw StateError('could not reserve exclusive backup path');
}

/// Stream copy [source] → [dest] (dest must already exist / be writable).
/// Flushes and closes before returning. Does not delete [source].
Future<void> streamCopyFile(File source, File dest) async {
  final reader = source.openRead();
  final sink = dest.openWrite(mode: FileMode.writeOnly);
  try {
    await sink.addStream(reader);
    await sink.flush();
  } finally {
    await sink.close();
  }
}
