import 'dart:async';
import 'dart:io';

import 'package:yomu_storage/yomu_storage.dart';

/// Helper process for multi-process lock tests (uses real [YomuProcessLock]).
///
/// Usage: `dart run yomu_storage:lock_probe <lockPath> [try|hold]`
/// - try (default): time only [YomuProcessLock.acquire]; print ACQUIRE_MS + LOCK_*
/// - hold: acquire, print HELD, wait until killed (OS frees lock on exit)
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: lock_probe <lockPath> [try|hold]');
    exit(64);
  }
  final lockFile = File(args[0]);
  final mode = args.length > 1 ? args[1] : 'try';
  final lock = YomuProcessLock(
    lockFile,
    acquireTimeout: const Duration(milliseconds: 800),
  );
  if (mode == 'hold') {
    // Time only acquire (not process startup).
    final sw = Stopwatch()..start();
    await lock.acquire();
    sw.stop();
    stdout.writeln('ACQUIRE_MS=${sw.elapsedMilliseconds}');
    stdout.writeln('HELD');
    await stdout.flush();
    // Stay alive until parent kills this helper (not Yomu/Java).
    await Completer<void>().future;
    return;
  }
  // try mode: measure only YomuProcessLock.acquire wall time.
  final sw = Stopwatch()..start();
  try {
    await lock.acquire();
    sw.stop();
    stdout.writeln('ACQUIRE_MS=${sw.elapsedMilliseconds}');
    stdout.writeln('LOCK_OK');
    await lock.release();
    exit(0);
  } on YomuAlreadyRunningException {
    sw.stop();
    stdout.writeln('ACQUIRE_MS=${sw.elapsedMilliseconds}');
    stdout.writeln('LOCK_FAIL');
    exit(2);
  } on TimeoutException {
    sw.stop();
    stdout.writeln('ACQUIRE_MS=${sw.elapsedMilliseconds}');
    stdout.writeln('LOCK_TIMEOUT');
    exit(3);
  } catch (e) {
    sw.stop();
    stdout.writeln('ACQUIRE_MS=${sw.elapsedMilliseconds}');
    stdout.writeln('LOCK_FAIL');
    exit(2);
  }
}
