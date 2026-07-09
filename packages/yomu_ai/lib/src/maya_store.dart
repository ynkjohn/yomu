import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// JSON persistence for Maya conversations (until Drift lands).
class MayaStore {
  MayaStore(this.file);

  final File file;
  final List<MayaMessage> messages = [];
  final Map<String, ActionProposal> proposals = {};

  Future<void> load() async {
    if (!file.existsSync()) return;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return;
      messages
        ..clear()
        ..addAll(
          (raw['messages'] as List? ?? [])
              .whereType<Map<dynamic, dynamic>>()
              .map((e) => MayaMessage.fromJson(Map<String, dynamic>.from(e))),
        );
      proposals.clear();
      for (final item
          in (raw['proposals'] as List? ?? []).whereType<Map<dynamic, dynamic>>()) {
        final p = ActionProposal.fromJson(Map<String, dynamic>.from(item));
        proposals[p.id] = p;
      }
    } catch (_) {
      // ignore corrupt store
    }
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'messages': messages.map((m) => m.toJson()).toList(),
        'proposals': proposals.values.map((p) => p.toJson()).toList(),
      }),
    );
  }

  Future<void> clear() async {
    messages.clear();
    proposals.clear();
    await save();
  }
}
