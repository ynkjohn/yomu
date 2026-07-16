import 'dart:collection';

import 'package:meta/meta.dart';

/// Role of a Maya chat message.
enum MayaRole { system, user, assistant }

/// Lifecycle of a mutating action that requires explicit confirmation.
enum ActionProposalStatus { pending, confirmed, rejected, executed, failed }

/// Kinds of actions Maya may propose (never auto-executes these).
enum MayaActionKind {
  /// Open manga detail / continue reading in UI.
  openManga,

  /// Enqueue chapter download via Suwayomi.
  downloadChapter,

  /// Toggle library membership.
  setInLibrary,
}

const int kMayaMaxIdChars = 200;
const int kMayaMaxMessageChars = 1024 * 1024;
const int kMayaMaxTitleChars = 500;
const int kMayaMaxDescriptionChars = 4000;
const int kMayaMaxErrorChars = 240;
const int kMayaMaxProposalIdsPerMessage = 128;

const String kMayaOutcomeUncertainError =
    'Resultado não verificado. A ação não será repetida automaticamente.';
const String kMayaLegacyPendingOutcomeUncertainError =
    'Proposta legada bloqueada: não foi possível verificar se a ação já ocorreu.';

final RegExp _mayaIdPattern = RegExp(r'^[A-Za-z0-9._~-]+$');

@immutable
class MayaMessage {
  const MayaMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.proposalIds = const [],
  });

  final String id;
  final MayaRole role;
  final String text;
  final DateTime createdAt;
  final List<String> proposalIds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'proposalIds': proposalIds,
  };

  factory MayaMessage.fromJson(Map<String, dynamic> json) {
    _requireExactKeys(json, const {
      'id',
      'role',
      'text',
      'createdAt',
      'proposalIds',
    }, 'message_fields_invalid');
    final id = requireMayaId(json['id'], code: 'message_id_invalid');
    final role = _requireEnum<MayaRole>(
      json['role'],
      MayaRole.values,
      code: 'message_role_invalid',
    );
    final text = _requireBoundedString(
      json['text'],
      maxChars: kMayaMaxMessageChars,
      allowEmpty: true,
      code: 'message_text_invalid',
    );
    final createdAt = _requireDate(
      json['createdAt'],
      code: 'message_created_at_invalid',
    );
    final rawProposalIds = json['proposalIds'];
    if (rawProposalIds is! List ||
        rawProposalIds.length > kMayaMaxProposalIdsPerMessage) {
      throw const FormatException('message_proposal_ids_invalid');
    }
    final proposalIds = <String>[];
    final seen = <String>{};
    for (final raw in rawProposalIds) {
      final proposalId = requireMayaId(
        raw,
        code: 'message_proposal_id_invalid',
      );
      if (!seen.add(proposalId)) {
        throw const FormatException('message_proposal_id_duplicate');
      }
      proposalIds.add(proposalId);
    }
    return MayaMessage(
      id: id,
      role: role,
      text: text,
      createdAt: createdAt,
      proposalIds: List.unmodifiable(proposalIds),
    );
  }
}

@immutable
class ActionProposal {
  const ActionProposal({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.payload,
    required this.status,
    required this.createdAt,
    this.confirmedAt,
    this.completedAt,
    this.error,
  });

  final String id;
  final MayaActionKind kind;
  final String title;
  final String description;
  final Map<String, dynamic> payload;
  final ActionProposalStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final DateTime? completedAt;
  final String? error;

  ActionProposal copyWith({
    ActionProposalStatus? status,
    DateTime? confirmedAt,
    DateTime? completedAt,
    String? error,
    bool clearConfirmedAt = false,
    bool clearCompletedAt = false,
    bool clearError = false,
  }) {
    return ActionProposal(
      id: id,
      kind: kind,
      title: title,
      description: description,
      payload: payload,
      status: status ?? this.status,
      createdAt: createdAt,
      confirmedAt: clearConfirmedAt ? null : (confirmedAt ?? this.confirmedAt),
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      error: clearError ? null : (error ?? this.error),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'description': description,
    'payload': payload,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'error': error,
  };

  factory ActionProposal.fromJson(Map<String, dynamic> json) {
    _requireExactKeys(json, const {
      'id',
      'kind',
      'title',
      'description',
      'payload',
      'status',
      'createdAt',
      'error',
    }, 'proposal_fields_invalid');
    final id = requireMayaId(json['id'], code: 'proposal_id_invalid');
    final kind = _requireEnum<MayaActionKind>(
      json['kind'],
      MayaActionKind.values,
      code: 'proposal_kind_invalid',
    );
    final status = _requireEnum<ActionProposalStatus>(
      json['status'],
      ActionProposalStatus.values,
      code: 'proposal_status_invalid',
    );
    final rawPayload = json['payload'];
    if (rawPayload is! Map) {
      throw const FormatException('proposal_payload_invalid');
    }
    final payload = normalizeMayaActionPayload(
      kind,
      Map<String, dynamic>.from(rawPayload),
    );
    final rawError = json['error'];
    if (rawError != null && rawError is! String) {
      throw const FormatException('proposal_error_invalid');
    }
    final error = rawError == null
        ? null
        : _requireBoundedString(
            rawError,
            maxChars: kMayaMaxErrorChars,
            allowEmpty: false,
            code: 'proposal_error_invalid',
          );
    return ActionProposal(
      id: id,
      kind: kind,
      title: _requireBoundedString(
        json['title'],
        maxChars: kMayaMaxTitleChars,
        allowEmpty: false,
        code: 'proposal_title_invalid',
      ),
      description: _requireBoundedString(
        json['description'],
        maxChars: kMayaMaxDescriptionChars,
        allowEmpty: false,
        code: 'proposal_description_invalid',
      ),
      payload: payload,
      status: status,
      createdAt: _requireDate(
        json['createdAt'],
        code: 'proposal_created_at_invalid',
      ),
      error: error,
    );
  }
}

/// Strict, canonical payload validation shared by migration and execution.
Map<String, dynamic> normalizeMayaActionPayload(
  MayaActionKind kind,
  Map<String, dynamic> payload,
) {
  final (requiredKeys, optionalKeys) = switch (kind) {
    MayaActionKind.openManga => (
      const <String>{'mangaId'},
      const <String>{'title', 'chapterId'},
    ),
    MayaActionKind.downloadChapter => (
      const <String>{'chapterId'},
      const <String>{'mangaId', 'title'},
    ),
    MayaActionKind.setInLibrary => (
      const <String>{'mangaId', 'inLibrary'},
      const <String>{'title'},
    ),
  };
  final allowed = {...requiredKeys, ...optionalKeys};
  if (!payload.keys.every(allowed.contains) ||
      !requiredKeys.every(payload.containsKey)) {
    throw const FormatException('proposal_payload_fields_invalid');
  }

  final normalized = <String, dynamic>{};
  for (final key in allowed) {
    if (!payload.containsKey(key)) continue;
    final value = payload[key];
    if (key == 'mangaId' || key == 'chapterId') {
      if (value is! int || value <= 0) {
        throw FormatException('proposal_payload_${key}_invalid');
      }
      normalized[key] = value;
    } else if (key == 'inLibrary') {
      if (value is! bool) {
        throw const FormatException('proposal_payload_in_library_invalid');
      }
      normalized[key] = value;
    } else if (key == 'title') {
      normalized[key] = _requireBoundedString(
        value,
        maxChars: kMayaMaxTitleChars,
        allowEmpty: false,
        code: 'proposal_payload_title_invalid',
      );
    }
  }
  return UnmodifiableMapView(normalized);
}

String requireMayaId(Object? value, {required String code}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > kMayaMaxIdChars ||
      !_mayaIdPattern.hasMatch(value)) {
    throw FormatException(code);
  }
  return value;
}

String sanitizeMayaError(String value) {
  var safe = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
  safe = safe.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (safe.isEmpty) return 'Operação não concluída.';
  if (safe.length > kMayaMaxErrorChars) {
    safe = '${safe.substring(0, kMayaMaxErrorChars - 1)}…';
  }
  return safe;
}

void _requireExactKeys(
  Map<String, dynamic> json,
  Set<String> expected,
  String code,
) {
  if (json.length != expected.length || !expected.every(json.containsKey)) {
    throw FormatException(code);
  }
}

T _requireEnum<T extends Enum>(
  Object? value,
  List<T> values, {
  required String code,
}) {
  if (value is! String) throw FormatException(code);
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException(code);
}

DateTime _requireDate(Object? value, {required String code}) {
  if (value is! String) throw FormatException(code);
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.millisecondsSinceEpoch < 0) {
    throw FormatException(code);
  }
  return parsed;
}

String _requireBoundedString(
  Object? value, {
  required int maxChars,
  required bool allowEmpty,
  required String code,
}) {
  if (value is! String ||
      value.length > maxChars ||
      (!allowEmpty && value.trim().isEmpty)) {
    throw FormatException(code);
  }
  return value;
}

/// One assistant turn after processing a user message.
@immutable
class MayaTurn {
  const MayaTurn({required this.assistantMessage, this.proposals = const []});

  final MayaMessage assistantMessage;
  final List<ActionProposal> proposals;
}

/// Library row for Maya tools (decoupled from Suwayomi DTOs).
@immutable
class MayaLibraryItem {
  const MayaLibraryItem({
    required this.id,
    required this.title,
    this.unreadCount = 0,
    this.lastChapterId,
    this.lastChapterName,
    this.lastPageRead,
  });

  final int id;
  final String title;
  final int unreadCount;
  final int? lastChapterId;
  final String? lastChapterName;
  final int? lastPageRead;
}
