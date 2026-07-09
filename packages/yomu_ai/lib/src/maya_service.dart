import 'models.dart';
import 'maya_port.dart';
import 'maya_store.dart';
import 'heuristic_engine.dart';

/// Maya assistant: offline heuristic (+ optional LLM later), ActionProposal safety.
class MayaService {
  MayaService({
    required this.store,
    required this.libraryPort,
    HeuristicMayaEngine? engine,
    this.llm,
  }) : engine = engine ?? HeuristicMayaEngine();

  final MayaStore store;
  final MayaLibraryPort libraryPort;
  final HeuristicMayaEngine engine;
  final MayaLlmProvider? llm;

  List<MayaMessage> get messages => List.unmodifiable(store.messages);

  List<ActionProposal> proposalsFor(MayaMessage message) {
    return message.proposalIds
        .map((id) => store.proposals[id])
        .whereType<ActionProposal>()
        .toList();
  }

  ActionProposal? proposalById(String id) => store.proposals[id];

  Future<void> load() => store.load();

  Future<void> clearHistory() => store.clear();

  /// Process user text → assistant message + optional proposals (not executed).
  Future<MayaTurn> sendUserMessage(String text) async {
    final user = MayaMessage(
      id: 'u-${DateTime.now().microsecondsSinceEpoch}',
      role: MayaRole.user,
      text: text.trim(),
      createdAt: DateTime.now(),
    );
    store.messages.add(user);

    List<MayaLibraryItem> library = const [];
    try {
      library = await libraryPort.listLibrary();
    } catch (e) {
      final err = MayaMessage(
        id: 'm-err-${DateTime.now().microsecondsSinceEpoch}',
        role: MayaRole.assistant,
        text:
            'Não consegui consultar a biblioteca (motor parado?). Detalhe: $e',
        createdAt: DateTime.now(),
      );
      store.messages.add(err);
      await store.save();
      return MayaTurn(assistantMessage: err);
    }

    // Prefer offline heuristic for structured library actions.
    // Optional LLM can enrich free-form answers when no structured match.
    var turn = engine.handle(userText: text, library: library);

    if (llm != null &&
        turn.proposals.isEmpty &&
        _looksLikeChitchat(text) &&
        !_isStructuredCommand(text)) {
      try {
        final ctx = _toolContext(library);
        final llmText = await llm!.complete(
          history: store.messages,
          userText: text,
          toolContext: ctx,
        );
        if (llmText.trim().isNotEmpty) {
          turn = MayaTurn(
            assistantMessage: MayaMessage(
              id: 'm-llm-${DateTime.now().microsecondsSinceEpoch}',
              role: MayaRole.assistant,
              text: llmText.trim(),
              createdAt: DateTime.now(),
            ),
          );
        }
      } catch (_) {
        // keep heuristic turn
      }
    }

    for (final p in turn.proposals) {
      store.proposals[p.id] = p;
    }
    store.messages.add(turn.assistantMessage);
    await store.save();
    return turn;
  }

  /// Confirm a pending proposal and execute via [libraryPort] / return UI hints.
  Future<ActionProposal> confirmProposal(String proposalId) async {
    final p = store.proposals[proposalId];
    if (p == null) {
      throw StateError('Proposta não encontrada: $proposalId');
    }
    if (p.status != ActionProposalStatus.pending) {
      return p;
    }

    try {
      switch (p.kind) {
        case MayaActionKind.downloadChapter:
          final chapterId = p.payload['chapterId'];
          final id = chapterId is int ? chapterId : int.parse('$chapterId');
          await libraryPort.enqueueChapterDownload(id);
        case MayaActionKind.setInLibrary:
          final mangaId = p.payload['mangaId'];
          final id = mangaId is int ? mangaId : int.parse('$mangaId');
          final inLib = p.payload['inLibrary'] != false;
          await libraryPort.setInLibrary(id, inLib);
        case MayaActionKind.openManga:
          // UI navigation only — host navigates after confirm.
          break;
      }
      final done = p.copyWith(status: ActionProposalStatus.executed);
      store.proposals[proposalId] = done;
      store.messages.add(
        MayaMessage(
          id: 'm-ok-${DateTime.now().microsecondsSinceEpoch}',
          role: MayaRole.assistant,
          text: 'Feito: ${p.title}',
          createdAt: DateTime.now(),
        ),
      );
      await store.save();
      return done;
    } catch (e) {
      final failed = p.copyWith(
        status: ActionProposalStatus.failed,
        error: e.toString(),
      );
      store.proposals[proposalId] = failed;
      store.messages.add(
        MayaMessage(
          id: 'm-fail-${DateTime.now().microsecondsSinceEpoch}',
          role: MayaRole.assistant,
          text: 'Falhou: ${p.title} — $e',
          createdAt: DateTime.now(),
        ),
      );
      await store.save();
      return failed;
    }
  }

  Future<ActionProposal> rejectProposal(String proposalId) async {
    final p = store.proposals[proposalId];
    if (p == null) throw StateError('Proposta não encontrada: $proposalId');
    // Executed (and failed) proposals are immutable for audit.
    if (p.status == ActionProposalStatus.executed ||
        p.status == ActionProposalStatus.failed ||
        p.status == ActionProposalStatus.confirmed) {
      return p;
    }
    if (p.status != ActionProposalStatus.pending) {
      return p;
    }
    final rejected = p.copyWith(status: ActionProposalStatus.rejected);
    store.proposals[proposalId] = rejected;
    store.messages.add(
      MayaMessage(
        id: 'm-rej-${DateTime.now().microsecondsSinceEpoch}',
        role: MayaRole.assistant,
        text: 'Cancelado: ${p.title}',
        createdAt: DateTime.now(),
      ),
    );
    await store.save();
    return rejected;
  }

  bool _isStructuredCommand(String text) {
    final l = text.toLowerCase();
    const keys = [
      'biblioteca',
      'continuar',
      'busca',
      'buscar',
      'baixar',
      'download',
      'ajuda',
      'listar',
      'retomar',
    ];
    return keys.any(l.contains);
  }

  bool _looksLikeChitchat(String text) {
    return text.trim().length > 12;
  }

  String _toolContext(List<MayaLibraryItem> library) {
    final buf = StringBuffer('library_count=${library.length}\n');
    for (final m in library.take(30)) {
      buf.writeln(
        '- id=${m.id} title=${m.title} unread=${m.unreadCount}',
      );
    }
    return buf.toString();
  }
}
