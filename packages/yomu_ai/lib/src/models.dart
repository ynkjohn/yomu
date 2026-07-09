import 'package:meta/meta.dart';

/// Role of a Maya chat message.
enum MayaRole { system, user, assistant }

/// Lifecycle of a mutating action that requires explicit confirmation.
enum ActionProposalStatus {
  pending,
  confirmed,
  rejected,
  executed,
  failed,
}

/// Kinds of actions Maya may propose (never auto-executes these).
enum MayaActionKind {
  /// Open manga detail / continue reading in UI.
  openManga,

  /// Enqueue chapter download via Suwayomi.
  downloadChapter,

  /// Toggle library membership.
  setInLibrary,
}

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
    return MayaMessage(
      id: '${json['id']}',
      role: MayaRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => MayaRole.assistant,
      ),
      text: '${json['text'] ?? ''}',
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      proposalIds: (json['proposalIds'] as List?)
              ?.map((e) => '$e')
              .toList() ??
          const [],
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
    this.error,
  });

  final String id;
  final MayaActionKind kind;
  final String title;
  final String description;
  final Map<String, dynamic> payload;
  final ActionProposalStatus status;
  final DateTime createdAt;
  final String? error;

  ActionProposal copyWith({
    ActionProposalStatus? status,
    String? error,
  }) {
    return ActionProposal(
      id: id,
      kind: kind,
      title: title,
      description: description,
      payload: payload,
      status: status ?? this.status,
      createdAt: createdAt,
      error: error ?? this.error,
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
    return ActionProposal(
      id: '${json['id']}',
      kind: MayaActionKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => MayaActionKind.openManga,
      ),
      title: '${json['title'] ?? ''}',
      description: '${json['description'] ?? ''}',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      status: ActionProposalStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => ActionProposalStatus.pending,
      ),
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      error: json['error']?.toString(),
    );
  }
}

/// One assistant turn after processing a user message.
@immutable
class MayaTurn {
  const MayaTurn({
    required this.assistantMessage,
    this.proposals = const [],
  });

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
