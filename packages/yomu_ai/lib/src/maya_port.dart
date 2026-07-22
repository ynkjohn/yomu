import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

import 'models.dart';

/// Port implemented by the host to reach Yomu reading capabilities / UI.
///
/// Maya never talks to engine ports on LAN; the host injects local access.
abstract class MayaLibraryPort {
  Future<List<MayaLibraryItem>> listLibrary();

  Future<void> setInLibrary(int mangaId, bool inLibrary);

  Future<void> enqueueChapterDownload(int chapterId);
}

const int kMayaLlmMaxCurrentInputBytes = 32 * 1024;
const int kMayaLlmMaxHistoryBytes = 32 * 1024;
const int kMayaLlmMaxHistoryMessages = 12;
const int kMayaLlmMaxLibraryBytes = 48 * 1024;
const int kMayaLlmMaxLibraryItems = 30;
const int kMayaLlmMaxIntents = 4;

/// Data-sharing policy read immediately before each cloud request.
///
/// The provider manager may change this policy at runtime. Disabled means the
/// deterministic local engine remains the only responder.
@immutable
class MayaLlmContextPolicy {
  const MayaLlmContextPolicy({
    required this.enabled,
    this.shareRecentHistory = false,
    this.shareLibraryContext = false,
    this.contextLease,
  });

  const MayaLlmContextPolicy.disabled()
    : enabled = false,
      shareRecentHistory = false,
      shareLibraryContext = false,
      contextLease = null;

  final bool enabled;
  final bool shareRecentHistory;
  final bool shareLibraryContext;

  /// Opaque, request-scoped capability owned by the provider implementation.
  ///
  /// Callers must copy this value by identity into [MayaLlmRequest] without
  /// inspecting, serializing or persisting it.
  final Object? contextLease;
}

/// Only persisted user/assistant turns can become provider conversation data.
/// Persisted `system` messages are deliberately excluded by [MayaService].
@immutable
class MayaLlmMessage {
  const MayaLlmMessage({required this.role, required this.text})
    : assert(role == MayaRole.user || role == MayaRole.assistant);

  final MayaRole role;
  final String text;
}

/// Untrusted Suwayomi snapshot supplied as structured data, never as authority.
@immutable
class MayaLlmLibraryItem {
  const MayaLlmLibraryItem({
    required this.mangaId,
    required this.title,
    required this.unreadCount,
    this.lastChapterId,
    this.lastChapterName,
  });

  final int mangaId;
  final String title;
  final int unreadCount;
  final int? lastChapterId;
  final String? lastChapterName;

  Map<String, Object?> toJson() => <String, Object?>{
    'manga_id': mangaId,
    'title': title,
    'unread_count': unreadCount,
    'last_chapter_id': lastChapterId,
    'last_chapter_name': lastChapterName,
  };
}

/// Provider-visible intentions. They never execute an effect directly.
enum MayaLlmTool { openManga, downloadChapter }

/// A provider request assembled after consent and context budgets are applied.
@immutable
class MayaLlmRequest {
  MayaLlmRequest({
    required this.currentUserText,
    required List<MayaLlmMessage> history,
    required List<MayaLlmLibraryItem> library,
    required Set<MayaLlmTool> availableTools,
    required this.libraryAvailable,
    required this.cancellation,
    this.contextLease,
  }) : history = List<MayaLlmMessage>.unmodifiable(history),
       library = List<MayaLlmLibraryItem>.unmodifiable(library),
       availableTools = UnmodifiableSetView<MayaLlmTool>(
         Set<MayaLlmTool>.from(availableTools),
       );

  final String currentUserText;
  final List<MayaLlmMessage> history;
  final List<MayaLlmLibraryItem> library;
  final Set<MayaLlmTool> availableTools;
  final bool libraryAvailable;
  final MayaLlmCancellationToken cancellation;

  /// Opaque, non-serializable lease copied exactly from the captured policy.
  final Object? contextLease;
}

/// Untrusted tool intention returned by a provider adapter.
///
/// IDs are only hints. [MayaService] resolves them against the exact snapshot
/// used for the request and constructs canonical local [ActionProposal]s.
@immutable
class MayaLlmIntent {
  const MayaLlmIntent.openManga({required this.mangaId})
    : tool = MayaLlmTool.openManga,
      chapterId = null;

  const MayaLlmIntent.downloadChapter({
    required this.mangaId,
    required this.chapterId,
  }) : tool = MayaLlmTool.downloadChapter;

  final MayaLlmTool tool;
  final int mangaId;
  final int? chapterId;
}

@immutable
class MayaLlmResponse {
  MayaLlmResponse({this.text, List<MayaLlmIntent> intents = const []})
    : intents = List<MayaLlmIntent>.unmodifiable(intents);

  final String? text;
  final List<MayaLlmIntent> intents;
}

enum MayaLlmFailureKind {
  unavailable,
  unauthorized,
  rateLimited,
  providerFailure,
  timeout,
  cancelled,
  invalidResponse,
  responseTooLarge,
  transport,
  configuration,
}

/// Sanitized provider failure. Remote bodies, prompts and credentials are not
/// retained in the exception and therefore cannot leak through `toString()`.
class MayaLlmException implements Exception {
  const MayaLlmException(this.kind);

  final MayaLlmFailureKind kind;

  @override
  String toString() => 'MayaLlmException(${kind.name})';
}

/// Cooperative cancellation shared by service, provider manager and transport.
class MayaLlmCancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) {
      throw const MayaLlmException(MayaLlmFailureKind.cancelled);
    }
  }
}

/// Provider-neutral LLM backend. Disabled = offline heuristic only.
///
/// Implementations must make [close] idempotent and use it to abort any request
/// in flight so desktop teardown cannot wait forever on a socket.
abstract class MayaLlmProvider {
  MayaLlmContextPolicy get contextPolicy;

  Future<MayaLlmResponse> complete(MayaLlmRequest request);

  Future<void> close();
}
