import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Exclusive process lock for a single desktop writer on Yomu storage.
///
/// Ownership is the open [RandomAccessFile] with an OS exclusive lock —
/// not mere existence of the lock path. Crash leaves the file on disk;
/// the OS releases the lock; we never auto-delete the lock file.
///
/// Acquisition uses exclusive [RandomAccessFile.lock] with a short
/// [acquireTimeout] so a second instance fails quickly (does not hang).
class YomuProcessLock {
  YomuProcessLock(
    this.lockFile, {
    this.acquireTimeout = const Duration(milliseconds: 750),
  });

  /// Typically `{yomuRoot}/runtime/yomu.lock`.
  final File lockFile;

  /// Max wait for exclusive lock before [YomuAlreadyRunningException].
  final Duration acquireTimeout;

  RandomAccessFile? _handle;

  bool get isHeld => _handle != null;

  /// Acquire exclusive lock, keeping [RandomAccessFile] open for the process life.
  ///
  /// Throws [YomuAlreadyRunningException] if another process holds the lock
  /// (or if acquisition exceeds [acquireTimeout]).
  Future<void> acquire() async {
    if (_handle != null) {
      throw StateError('YomuProcessLock already acquired');
    }
    await lockFile.parent.create(recursive: true);
    if (!lockFile.existsSync()) {
      await lockFile.writeAsString(
        'Yomu process lock — do not delete while the app is running.\n',
        flush: true,
      );
    }
    final raf = await lockFile.open(mode: FileMode.append);
    try {
      await raf.lock(FileLock.exclusive).timeout(acquireTimeout);
    } on TimeoutException {
      try {
        await raf.close();
      } catch (_) {}
      throw YomuAlreadyRunningException(
        lockFile.path,
        cause: TimeoutException(
          'lock acquire exceeded ${acquireTimeout.inMilliseconds}ms',
        ),
      );
    } on PathAccessException {
      try {
        await raf.close();
      } catch (_) {}
      throw YomuAlreadyRunningException(lockFile.path);
    } on FileSystemException catch (e) {
      try {
        await raf.close();
      } catch (_) {}
      throw YomuAlreadyRunningException(lockFile.path, cause: e);
    } catch (e) {
      try {
        await raf.close();
      } catch (_) {}
      if (e is YomuAlreadyRunningException) rethrow;
      throw YomuAlreadyRunningException(lockFile.path, cause: e);
    }
    try {
      await raf.setPosition(0);
      await raf.truncate(0);
      await raf.writeString(
        'pid=$pid acquired=${DateTime.now().toUtc().toIso8601String()}\n',
      );
      await raf.flush();
    } catch (_) {
      // Best-effort metadata; lock is already held.
    }
    _handle = raf;
  }

  /// Release lock only on final process shutdown (closes the handle).
  Future<void> release() async {
    final h = _handle;
    _handle = null;
    if (h == null) return;
    try {
      await h.unlock();
    } catch (_) {}
    try {
      await h.close();
    } catch (_) {}
    // Do NOT delete lockFile — crash recovery relies on OS unlock only.
  }

  static File defaultLockFile(Directory yomuRoot) {
    return File(p.join(yomuRoot.path, 'runtime', 'yomu.lock'));
  }
}

/// Second desktop instance refused storage ownership.
class YomuAlreadyRunningException implements Exception {
  YomuAlreadyRunningException(this.lockPath, {this.cause});

  final String lockPath;
  final Object? cause;

  @override
  String toString() =>
      'Yomu já está em execução (lock exclusivo: $lockPath). '
      'Feche a outra instância antes de abrir de novo.'
      '${cause != null ? ' ($cause)' : ''}';
}
