import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yomu_storage/src/db_file_prep.dart';
import 'package:yomu_storage/src/storage_log.dart';

void main() {
  late Directory dir;
  late File db;
  late YomuStorageLog log;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('yomu-prep-');
    db = File('${dir.path}/yomu.db');
    log = YomuStorageLog(File('${dir.path}/log.txt'));
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('exact historical body (LF) is placeholder', () async {
    await db.writeAsString(kYomuPlaceholderV0Body);
    final r = await prepareDatabaseFile(dbFile: db, log: log);
    expect(r.kind, DbFileKind.placeholderV0);
    expect(db.existsSync(), isFalse);
    expect(File('${db.path}.placeholder-v0.bak').existsSync(), isTrue);
  });

  test('exact historical body with CRLF is placeholder', () async {
    final crlf = kYomuPlaceholderV0Body.replaceAll('\n', '\r\n');
    await db.writeAsBytes(utf8.encode(crlf));
    final r = await prepareDatabaseFile(dbFile: db, log: log);
    expect(r.kind, DbFileKind.placeholderV0);
  });

  test('negative: marker-only is NOT placeholder', () async {
    await db.writeAsString('$kYomuPlaceholderV0Marker\n');
    final r = await prepareDatabaseFile(dbFile: db, log: log);
    expect(r.kind, DbFileKind.unknown);
    expect(r.quarantinePath, isNotNull);
  });

  test('negative: trimRight marker is NOT placeholder', () async {
    await db.writeAsString('$kYomuPlaceholderV0Marker   \n');
    final r = await prepareDatabaseFile(dbFile: db, log: log);
    expect(r.kind, DbFileKind.unknown);
  });

  test('negative: extra blank lines is NOT placeholder', () async {
    await db.writeAsString('$kYomuPlaceholderV0Body\n');
    final r = await prepareDatabaseFile(dbFile: db, log: log);
    expect(r.kind, DbFileKind.unknown);
  });

  test('negative: partial / spaces prefix is NOT placeholder', () async {
    await db.writeAsString(' $kYomuPlaceholderV0Body');
    final r = await prepareDatabaseFile(dbFile: db, log: log);
    expect(r.kind, DbFileKind.unknown);
  });

  test('negative: second line missing is NOT placeholder', () async {
    await db.writeAsString('-- yomu sqlite placeholder v0\n');
    final r = await prepareDatabaseFile(dbFile: db, log: log);
    expect(r.kind, DbFileKind.unknown);
  });

  test('backup collision picks exclusive path without overwrite', () async {
    await File('${db.path}.placeholder-v0.bak').writeAsString('existing');
    await db.writeAsString(kYomuPlaceholderV0Body);
    final r = await prepareDatabaseFile(dbFile: db, log: log);
    expect(r.kind, DbFileKind.placeholderV0);
    expect(File('${db.path}.placeholder-v0.bak').readAsStringSync(), 'existing');
    expect(r.placeholderBakPath, isNot(equals('${db.path}.placeholder-v0.bak')));
    expect(File(r.placeholderBakPath!).existsSync(), isTrue);
  });

  test('quarantine collision never overwrites', () async {
    // Pre-create preferred-style names with exclusive create already taken.
    final pre = <File>[];
    for (var i = 0; i < 5; i++) {
      final f = File('${db.path}.unknown.pre$i.bak');
      await f.create(exclusive: true);
      await f.writeAsString('x$i');
      pre.add(f);
    }
    await db.writeAsString('garbage-not-sqlite');
    final r = await prepareDatabaseFile(dbFile: db, log: log);
    expect(r.kind, DbFileKind.unknown);
    for (final f in pre) {
      expect(f.readAsStringSync(), startsWith('x'));
    }
    expect(File(r.quarantinePath!).existsSync(), isTrue);
    final logText = await log.file.readAsString();
    expect(logText, isNot(contains('garbage-not-sqlite')));
    expect(logText, contains('bytes='));
  });

  test('large SQLite-header file is not fully loaded as placeholder', () async {
    // 4 MiB file with SQLite magic — must only touch header, not OOM on body.
    final raf = await db.open(mode: FileMode.write);
    try {
      await raf.writeFrom(kSqliteMagic);
      final chunk = List<int>.filled(1024 * 64, 0x41);
      for (var i = 0; i < 64; i++) {
        await raf.writeFrom(chunk);
      }
    } finally {
      await raf.close();
    }
    final r = await prepareDatabaseFile(dbFile: db, log: log);
    expect(r.kind, DbFileKind.sqlite);
    expect(db.existsSync(), isTrue);
  });

  test('large unknown file is streamed to exclusive quarantine (no overwrite)',
      () async {
    // 8 MiB garbage — size ≠ placeholder, so only header is read before stream.
    const totalBytes = 8 * 1024 * 1024;
    final raf = await db.open(mode: FileMode.write);
    try {
      final chunk = List<int>.filled(1024 * 64, 0x42);
      for (var i = 0; i < totalBytes ~/ chunk.length; i++) {
        await raf.writeFrom(chunk);
      }
    } finally {
      await raf.close();
    }
    expect(await db.length(), totalBytes);

    // Pre-create one colliding quarantine-style path to force exclusive suffix.
    final collide = File('${db.path}.unknown.collide.bak');
    await collide.create(exclusive: true);
    await collide.writeAsString('keep-me');

    final r = await prepareDatabaseFile(dbFile: db, log: log);
    expect(r.kind, DbFileKind.unknown);
    expect(db.existsSync(), isFalse, reason: 'original removed only after copy');
    expect(r.quarantinePath, isNotNull);
    expect(r.quarantinePath, isNot(equals(collide.path)));
    expect(collide.readAsStringSync(), 'keep-me');
    final q = File(r.quarantinePath!);
    expect(await q.length(), totalBytes);
    // Log must not embed body / must report bytes.
    final logText = await log.file.readAsString();
    expect(logText, contains('unknown_db_quarantined'));
    expect(logText, contains('bytes=$totalBytes'));
  });

  test('reserveExclusiveFile never returns existing path', () async {
    final a = await reserveExclusiveFile(
      preferred: '${dir.path}/a.bak',
      pattern: (s) => '${dir.path}/a.$s.bak',
    );
    expect(a.existsSync(), isTrue);
    final b = await reserveExclusiveFile(
      preferred: '${dir.path}/a.bak',
      pattern: (s) => '${dir.path}/a.$s.bak',
    );
    expect(b.path, isNot(equals(a.path)));
    expect(b.existsSync(), isTrue);
  });

  test('sanitizeError never dumps large payloads', () {
    final big = 'err ${'x' * 5000}';
    final s = YomuStorageLog.sanitizeError(big);
    expect(s.length, lessThanOrEqualTo(YomuStorageLog.maxErrorChars + 1));
    expect(s, isNot(contains('\n')));
  });
}
