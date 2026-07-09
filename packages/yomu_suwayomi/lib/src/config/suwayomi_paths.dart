import 'dart:io';

import 'package:path/path.dart' as p;

/// On-disk layout under the Yomu application support directory.
///
/// [dataDir] is passed to Suwayomi as `server.rootDir` and must never be the
/// global `%LOCALAPPDATA%\Tachidesk` folder.
class SuwayomiPaths {
  SuwayomiPaths(this.root);

  /// Typically `{appSupport}/yomu`.
  final Directory root;

  Directory get runtimeDir => Directory(p.join(root.path, 'runtime', 'suwayomi'));
  Directory get jreDir => Directory(p.join(root.path, 'runtime', 'jre'));

  /// Managed Suwayomi rootDir (conf, DB, extensions, downloads).
  Directory get dataDir => Directory(p.join(root.path, 'data', 'suwayomi'));
  Directory get configDir => Directory(p.join(root.path, 'config'));
  Directory get logsDir => Directory(p.join(root.path, 'logs'));

  File jarFile(String jarName) => File(p.join(runtimeDir.path, jarName));
  File get serverConf => File(p.join(configDir.path, 'server.conf'));
  File get processLog => File(p.join(logsDir.path, 'suwayomi.log'));
  File get vendorManifestCopy => File(p.join(runtimeDir.path, 'manifest.json'));

  Future<void> ensureLayout() async {
    await Future.wait([
      runtimeDir.create(recursive: true),
      jreDir.create(recursive: true),
      dataDir.create(recursive: true),
      configDir.create(recursive: true),
      logsDir.create(recursive: true),
    ]);
  }
}
