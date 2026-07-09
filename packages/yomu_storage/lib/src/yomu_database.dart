import 'dart:io';

import 'package:path/path.dart' as p;

/// Placeholder storage façade. Drift schema lands when extras are implemented.
///
/// Schema v0 responsibilities (documented for dual-DB clarity):
/// - device_sessions, app_settings
/// - maya_*, action_proposals, audit_logs
/// - personal_status_overrides
/// - source_specs / source_revisions
/// - reading_analytics
/// - suwayomi_link (id maps)
class YomuDatabase {
  YomuDatabase(this.file);

  final File file;

  static Future<YomuDatabase> open(Directory appSupport) async {
    final dir = Directory(p.join(appSupport.path, 'data'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'yomu.db'));
    if (!file.existsSync()) {
      await file.writeAsString(
        '-- yomu sqlite placeholder v0\n'
        '-- Real Drift migrations in a later phase.\n',
      );
    }
    return YomuDatabase(file);
  }
}
