import 'dart:io';

import 'package:path/path.dart' as p;

/// On-disk layout for Yomu SQLite under `{appSupport}/yomu`.
class YomuStoragePaths {
  YomuStoragePaths(this.yomuRoot);

  /// Typically `{appSupport}/yomu`.
  final Directory yomuRoot;

  Directory get dataDir => Directory(p.join(yomuRoot.path, 'data'));
  Directory get runtimeDir => Directory(p.join(yomuRoot.path, 'runtime'));
  Directory get logsDir => Directory(p.join(yomuRoot.path, 'logs'));

  File get databaseFile => File(p.join(dataDir.path, 'yomu.db'));
  File get lockFile => File(p.join(runtimeDir.path, 'yomu.lock'));
  File get storageLogFile => File(p.join(logsDir.path, 'storage.log'));

  Future<void> ensureLayout() async {
    await Future.wait([
      dataDir.create(recursive: true),
      runtimeDir.create(recursive: true),
      logsDir.create(recursive: true),
    ]);
  }
}
