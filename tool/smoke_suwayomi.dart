// ignore_for_file: avoid_print
// Gate Fase 1.5 — isolamento total do Suwayomi gerenciado pelo Yomu.
//
// Usage:
//   dart run tool/smoke_suwayomi.dart
//   dart run tool/smoke_suwayomi.dart --aggressive-rename
//
// --aggressive-rename: temporarily renames %LOCALAPPDATA%\Tachidesk (if present)
// and restores it in a finally block.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

Future<void> main(List<String> args) async {
  final aggressive = args.contains('--aggressive-rename');
  final root = Directory(
    p.join(Directory.systemTemp.path, 'yomu-gate15-isolation'),
  );
  if (root.existsSync()) {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  }
  root.createSync(recursive: true);

  final globalTachidesk = _globalTachideskDir();
  final snapshotBefore = await _snapshotGlobal(globalTachidesk);
  Directory? renamedBackup;

  print('=== Gate 1.5: Suwayomi isolation ===');
  print('Managed root will be: ${p.join(root.path, 'data', 'suwayomi')}');
  print('Global Tachidesk: ${globalTachidesk?.path ?? '(none)'}');
  print('Aggressive rename: $aggressive');

  try {
    if (aggressive &&
        globalTachidesk != null &&
        globalTachidesk.existsSync()) {
      renamedBackup = Directory(
        '${globalTachidesk.path}.bak-yomu-gate15-${DateTime.now().millisecondsSinceEpoch}',
      );
      print('Renaming global Tachidesk → ${renamedBackup.path}');
      globalTachidesk.renameSync(renamedBackup.path);
    }

    final manifest = await VendorManifest.loadForRuntime();
    final paths = SuwayomiPaths(root);
    final manager = SuwayomiProcessManager(
      paths: paths,
      manifest: manifest,
      host: '127.0.0.1',
      port: kYomuSuwayomiPort,
    );

    print('Starting Suwayomi (port $kYomuSuwayomiPort)…');
    final started =
        await manager.start(readyTimeout: const Duration(minutes: 3));
    final startOk = started.when(
      ok: (s) {
        print('START OK: ${s.toJson()}');
        return true;
      },
      err: (m, _) {
        print('START FAIL: $m');
        return false;
      },
    );
    if (!startOk) {
      exitCode = 1;
      await manager.dispose();
      return;
    }

    final isolation = await manager.verifyManagedDataRoot();
    print(
      'Isolation check: ok=${isolation.isOk} observed=${isolation.observedRoot}',
    );
    if (!isolation.isOk) {
      print('ISOLATION FAIL: ${isolation.message}');
      exitCode = 2;
      await manager.dispose();
      return;
    }

    final managedConf =
        File(p.join(paths.dataDir.path, 'server.conf'));
    if (!managedConf.existsSync()) {
      print('FAIL: managed server.conf missing at ${managedConf.path}');
      exitCode = 3;
      await manager.dispose();
      return;
    }
    print('Managed server.conf present: ${managedConf.path}');

    // Ensure we did not recreate global Tachidesk while renamed.
    if (aggressive &&
        globalTachidesk != null &&
        globalTachidesk.existsSync()) {
      print(
        'FAIL: global Tachidesk was recreated during isolated run: '
        '${globalTachidesk.path}',
      );
      exitCode = 4;
      await manager.dispose();
      return;
    }

    final about = await manager.createClient().about();
    print('About: $about');
    if (about == null) {
      print('FAIL: about() null');
      exitCode = 5;
      await manager.dispose();
      return;
    }

    print('Restart…');
    final restarted = await manager.restart();
    final restartOk = restarted.when(
      ok: (_) => true,
      err: (m, _) {
        print('RESTART FAIL: $m');
        return false;
      },
    );
    if (!restartOk) {
      exitCode = 6;
      await manager.dispose();
      return;
    }
    final healthy = await manager.checkHealth();
    print('Health after restart: $healthy');
    if (!healthy) {
      exitCode = 7;
      await manager.dispose();
      return;
    }

    await manager.stop();
    print('Stopped: ${manager.status.state}');
    await manager.dispose();

    // Global must be unchanged (when not renamed).
    if (!aggressive) {
      final snapshotAfter = await _snapshotGlobal(globalTachidesk);
      if (!_snapshotsEqual(snapshotBefore, snapshotAfter)) {
        print('FAIL: global Tachidesk changed during gate:');
        print('  before: $snapshotBefore');
        print('  after:  $snapshotAfter');
        exitCode = 8;
        return;
      }
      print('Global Tachidesk snapshot unchanged.');
    }

    print('=== GATE 1.5 PASSED ===');
    exitCode = 0;
  } finally {
    if (renamedBackup != null && renamedBackup.existsSync()) {
      final target = _globalTachideskDir();
      try {
        if (target != null && target.existsSync()) {
          print(
            'WARNING: target Tachidesk exists while restoring backup; '
            'leaving backup at ${renamedBackup.path}',
          );
        } else if (target != null) {
          print('Restoring global Tachidesk from ${renamedBackup.path}');
          renamedBackup.renameSync(target.path);
        }
      } catch (e) {
        print('ERROR restoring Tachidesk rename: $e');
        print('Manual restore from: ${renamedBackup.path}');
        exitCode = exitCode == 0 ? 9 : exitCode;
      }
    }
  }
}

Directory? _globalTachideskDir() {
  if (!Platform.isWindows) {
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    return Directory(
      p.join(home, '.local', 'share', 'Tachidesk'),
    );
  }
  final local = Platform.environment['LOCALAPPDATA'];
  if (local == null || local.isEmpty) return null;
  return Directory(p.join(local, 'Tachidesk'));
}

Future<Map<String, Object?>> _snapshotGlobal(Directory? dir) async {
  if (dir == null || !dir.existsSync()) {
    return {'exists': false};
  }
  final conf = File(p.join(dir.path, 'server.conf'));
  String? confHash;
  DateTime? confMtime;
  if (conf.existsSync()) {
    confHash = sha256.convert(await conf.readAsBytes()).toString();
    confMtime = conf.statSync().modified;
  }
  final names = dir
      .listSync()
      .map((e) => p.basename(e.path))
      .toList()
    ..sort();
  return {
    'exists': true,
    'confHash': confHash,
    'confMtime': confMtime?.toIso8601String(),
    'entries': names,
  };
}

bool _snapshotsEqual(Map<String, Object?> a, Map<String, Object?> b) {
  return jsonEncode(a) == jsonEncode(b);
}
