import 'dart:async';

import 'heuristic_engine.dart';
import 'maya_port.dart';
import 'maya_store.dart';
import 'models.dart';

class MayaServiceHooks {
  const MayaServiceHooks({
    this.afterConfirmationPersistedBeforeDispatch,
    this.afterEffectBeforeCompletionPersisted,
  });

  /// Test-only crash point after the durable confirmation barrier.
  final Future<void> Function(ActionProposal proposal)?
  afterConfirmationPersistedBeforeDispatch;

  /// Test-only crash point after an effect may have happened, before terminal
  /// state is persisted.
  final Future<void> Function(ActionProposal proposal)?
  afterEffectBeforeCompletionPersisted;
}

/// Maya assistant with serialized, storage-first mutations.
///
/// `confirmed` is the at-most-once barrier: once persisted, a proposal is
/// never dispatched automatically again. Exactly-once delivery is impossible
/// until the Suwayomi action ports accept durable idempotency keys.
class MayaService {
  MayaService({
    required this.store,
    required this.libraryPort,
    HeuristicMayaEngine? engine,
    this.llm,
    this.hooks = const MayaServiceHooks(),
  }) : engine = engine ?? HeuristicMayaEngine();

  final MayaStore store;
  final MayaLibraryPort libraryPort;
  final HeuristicMayaEngine engine;
  final MayaLlmProvider? llm;
  final MayaServiceHooks hooks;

  Future<void> _tail = Future<void>.value();
  Future<void>? _closeFuture;
  bool _accepting = true;
  int _messageSequence = 0;

  List<MayaMessage> get messages => store.messages;

  bool get isClosed => !_accepting;

  List<ActionProposal> proposalsFor(MayaMessage message) {
    return List<ActionProposal>.unmodifiable(
      message.proposalIds.map(store.proposalById).whereType<ActionProposal>(),
    );
  }

  ActionProposal? proposalById(String id) => store.proposalById(id);

  Future<void> load() => _enqueue(store.load);

  Future<void> clearHistory() => _enqueue(store.clear);

  /// Wait for all operations admitted before this call.
  Future<void> drain() => _tail;

  /// Stop admission synchronously and drain operations already queued.
  ///
  /// The shared [YomuDatabase] remains owned by desktop lifecycle teardown.
  Future<void> close() {
    _accepting = false;
    return _closeFuture ??= _tail;
  }

  /// Process user text into one atomic user + assistant turn.
  Future<MayaTurn> sendUserMessage(String text) {
    return _enqueue(() async {
      final userText = text.trim();
      if (userText.isEmpty) {
        throw ArgumentError.value(text, 'text', 'não pode ser vazio');
      }
      final user = MayaMessage(
        id: _freshMessageId('u'),
        role: MayaRole.user,
        text: userText,
        createdAt: DateTime.now().toUtc(),
      );

      MayaTurn turn;
      List<MayaLibraryItem> library;
      try {
        library = await libraryPort.listLibrary();
      } catch (_) {
        turn = MayaTurn(
          assistantMessage: MayaMessage(
            id: _freshMessageId('m-library-unavailable'),
            role: MayaRole.assistant,
            text:
                'Não consegui consultar a biblioteca agora. '
                'Verifique se o motor local está disponível e tente novamente.',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        await store.appendTurn(
          messages: <MayaMessage>[user, turn.assistantMessage],
          proposals: const <ActionProposal>[],
        );
        return _storedTurn(turn);
      }

      try {
        turn = engine.handle(userText: userText, library: library);
      } catch (_) {
        turn = MayaTurn(
          assistantMessage: MayaMessage(
            id: _freshMessageId('m-unavailable'),
            role: MayaRole.assistant,
            text:
                'Não consegui preparar uma resposta local agora. '
                'Nenhuma ação foi executada.',
            createdAt: DateTime.now().toUtc(),
          ),
        );
      }

      if (llm != null &&
          turn.proposals.isEmpty &&
          _looksLikeChitchat(userText) &&
          !_isStructuredCommand(userText)) {
        try {
          final llmText = await llm!.complete(
            history: List<MayaMessage>.unmodifiable(<MayaMessage>[
              ...store.messages,
              user,
            ]),
            userText: userText,
            toolContext: _toolContext(library),
          );
          final normalized = _boundedMessageText(llmText.trim());
          if (normalized.isNotEmpty) {
            turn = MayaTurn(
              assistantMessage: MayaMessage(
                id: _freshMessageId('m-llm'),
                role: MayaRole.assistant,
                text: normalized,
                createdAt: DateTime.now().toUtc(),
              ),
            );
          }
        } catch (_) {
          // The deterministic local turn remains authoritative.
        }
      }

      await store.appendTurn(
        messages: <MayaMessage>[user, turn.assistantMessage],
        proposals: turn.proposals,
      );
      return _storedTurn(turn);
    });
  }

  /// Persist confirmation before dispatching any external effect.
  Future<ActionProposal> confirmProposal(String proposalId) {
    return _enqueue(() async {
      var proposal = store.proposalById(proposalId);
      if (proposal == null) throw StateError('Proposta não encontrada.');
      if (proposal.status != ActionProposalStatus.pending) return proposal;

      try {
        normalizeMayaActionPayload(
          proposal.kind,
          Map<String, dynamic>.from(proposal.payload),
        );
      } on FormatException {
        final failedAt = DateTime.now().toUtc();
        final message = MayaMessage(
          id: _freshMessageId('m-invalid-proposal'),
          role: MayaRole.assistant,
          text: 'A proposta salva é inválida. Nenhuma ação foi executada.',
          createdAt: failedAt,
        );
        await store.resolvePending(
          proposal.id,
          status: ActionProposalStatus.failed,
          completedAt: failedAt,
          error: 'Proposta inválida. Nenhuma ação foi executada.',
          outcomeMessage: message,
        );
        return store.proposalById(proposal.id)!;
      }

      final confirmedAt = DateTime.now().toUtc();
      if (!await store.confirmPending(proposal.id, confirmedAt)) {
        return store.proposalById(proposal.id) ?? proposal;
      }
      proposal = store.proposalById(proposal.id)!;

      await hooks.afterConfirmationPersistedBeforeDispatch?.call(proposal);

      try {
        await _dispatch(proposal);
      } catch (_) {
        final message = MayaMessage(
          id: _freshMessageId('m-unverified'),
          role: MayaRole.assistant,
          text:
              'A confirmação foi registrada, mas o resultado não pôde ser '
              'verificado. A ação não será repetida automaticamente.',
          createdAt: DateTime.now().toUtc(),
        );
        if (!await store.markConfirmedOutcomeUncertain(
          proposal.id,
          outcomeMessage: message,
        )) {
          throw StateError('Não foi possível registrar o resultado da ação.');
        }
        return store.proposalById(proposal.id)!;
      }

      await hooks.afterEffectBeforeCompletionPersisted?.call(proposal);

      final completedAt = DateTime.now().toUtc();
      final message = MayaMessage(
        id: _freshMessageId('m-ok'),
        role: MayaRole.assistant,
        text: 'Feito: ${proposal.title}',
        createdAt: completedAt,
      );
      if (!await store.completeConfirmed(
        proposal.id,
        status: ActionProposalStatus.executed,
        completedAt: completedAt,
        outcomeMessage: message,
      )) {
        return store.proposalById(proposal.id) ?? proposal;
      }
      return store.proposalById(proposal.id)!;
    });
  }

  Future<ActionProposal> rejectProposal(String proposalId) {
    return _enqueue(() async {
      final proposal = store.proposalById(proposalId);
      if (proposal == null) throw StateError('Proposta não encontrada.');
      if (proposal.status != ActionProposalStatus.pending) return proposal;

      final completedAt = DateTime.now().toUtc();
      final message = MayaMessage(
        id: _freshMessageId('m-rejected'),
        role: MayaRole.assistant,
        text: 'Cancelado: ${proposal.title}',
        createdAt: completedAt,
      );
      if (!await store.resolvePending(
        proposal.id,
        status: ActionProposalStatus.rejected,
        completedAt: completedAt,
        outcomeMessage: message,
      )) {
        return store.proposalById(proposal.id) ?? proposal;
      }
      return store.proposalById(proposal.id)!;
    });
  }

  Future<void> _dispatch(ActionProposal proposal) async {
    final payload = normalizeMayaActionPayload(
      proposal.kind,
      Map<String, dynamic>.from(proposal.payload),
    );
    switch (proposal.kind) {
      case MayaActionKind.downloadChapter:
        await libraryPort.enqueueChapterDownload(payload['chapterId']! as int);
      case MayaActionKind.setInLibrary:
        await libraryPort.setInLibrary(
          payload['mangaId']! as int,
          payload['inLibrary']! as bool,
        );
      case MayaActionKind.openManga:
        // Host navigation happens only after this method returns `executed`.
        break;
    }
  }

  MayaTurn _storedTurn(MayaTurn turn) {
    final assistant = store.messageById(turn.assistantMessage.id);
    if (assistant == null) {
      throw StateError('Maya turn persistence readback failed.');
    }
    return MayaTurn(
      assistantMessage: assistant,
      proposals: List<ActionProposal>.unmodifiable(
        turn.proposals.map((proposal) {
          final stored = store.proposalById(proposal.id);
          if (stored == null) {
            throw StateError('Maya proposal persistence readback failed.');
          }
          return stored;
        }),
      ),
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    if (!_accepting) {
      return Future<T>.error(StateError('MayaService já foi encerrado.'));
    }
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  String _freshMessageId(String prefix) {
    while (true) {
      final id =
          '$prefix-${DateTime.now().microsecondsSinceEpoch}-'
          '${_messageSequence++}';
      if (store.messageById(id) == null) return id;
    }
  }

  bool _isStructuredCommand(String text) {
    final lower = text.toLowerCase();
    const keys = <String>[
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
    return keys.any(lower.contains);
  }

  bool _looksLikeChitchat(String text) => text.trim().length > 12;

  String _boundedMessageText(String value) {
    if (value.length <= kMayaMaxMessageChars) return value;
    return value.substring(0, kMayaMaxMessageChars);
  }

  String _toolContext(List<MayaLibraryItem> library) {
    final buffer = StringBuffer('library_count=${library.length}\n');
    for (final manga in library.take(30)) {
      buffer.writeln(
        '- id=${manga.id} title=${manga.title} unread=${manga.unreadCount}',
      );
    }
    return buffer.toString();
  }
}
