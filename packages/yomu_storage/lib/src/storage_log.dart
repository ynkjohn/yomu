import 'dart:io';

/// Append-only log **outside** the SQLite DB (recovery / quarantine events).
class YomuStorageLog {
  YomuStorageLog(this.file);

  final File file;

  static const int maxErrorChars = 240;

  /// Sanitize free-form error text for logs (no file bodies, no unbounded dumps).
  static String sanitizeError(Object? error) {
    var s = error?.toString() ?? 'unknown';
    s = s.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Avoid pasting large payloads if an error embeds them.
    if (s.length > maxErrorChars) {
      s = '${s.substring(0, maxErrorChars)}…';
    }
    return s;
  }

  Future<void> append(String message) async {
    await file.parent.create(recursive: true);
    final safe = message.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    final line =
        '${DateTime.now().toUtc().toIso8601String()} $safe${Platform.lineTerminator}';
    await file.writeAsString(line, mode: FileMode.append, flush: true);
  }
}
