import 'dart:async';
import 'dart:convert';

import 'package:yomu_core/yomu_core.dart';

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
    EngineMutationGate? mutationGate,
  }) : engine = engine ?? HeuristicMayaEngine(),
       _mutationGate = mutationGate;

  final MayaStore store;
  final MayaLibraryPort libraryPort;
  final HeuristicMayaEngine engine;
  final MayaLlmProvider? llm;
  final MayaServiceHooks hooks;
  final EngineMutationGate? _mutationGate;

  Future<void> _tail = Future<void>.value();
  Future<void>? _closeFuture;
  bool _accepting = true;
  int _messageSequence = 0;
  MayaLlmCancellationToken? _activeLlmCancellation;

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

  /// Synchronously rejects every later chat or proposal mutation.
  ///
  /// Operations admitted before this boundary remain serialized in [_tail]
  /// and are drained by [close].
  void stopAccepting() {
    _accepting = false;
  }

  /// Stop admission synchronously and drain operations already queued.
  ///
  /// The shared [YomuDatabase] remains owned by desktop lifecycle teardown.
  Future<void> close() {
    stopAccepting();
    _activeLlmCancellation?.cancel();
    return _closeFuture ??= Future.wait<void>(<Future<void>>[
      _tail,
      if (llm != null) llm!.close(),
    ]);
  }

  /// Process user text into one atomic user + assistant turn.
  Future<MayaTurn> sendUserMessage(String text) {
    return _enqueue(() async {
      final userText = text.trim();
      if (userText.isEmpty) {
        throw ArgumentError.value(text, 'text', 'não pode ser vazio');
      }
      if (userText.length > kMayaMaxMessageChars) {
        throw ArgumentError.value(text, 'text', 'excede o limite da Maya');
      }
      final user = MayaMessage(
        id: _freshMessageId('u'),
        role: MayaRole.user,
        text: userText,
        createdAt: DateTime.now().toUtc(),
      );

      final policy =
          llm?.contextPolicy ?? const MayaLlmContextPolicy.disabled();
      var library = const <MayaLibraryItem>[];
      var libraryAvailable = false;
      var cloudAttempted = false;

      if (policy.enabled) {
        cloudAttempted = true;
        if (policy.shareLibraryContext) {
          try {
            library = List<MayaLibraryItem>.unmodifiable(
              await libraryPort.listLibrary(),
            );
            libraryAvailable = true;
          } catch (_) {
            // Cloud chat remains available without Suwayomi. No library data or
            // tools are exposed when the snapshot cannot be obtained.
          }
        }

        if (utf8.encode(userText).length <= kMayaLlmMaxCurrentInputBytes) {
          final cancellation = MayaLlmCancellationToken();
          _activeLlmCancellation = cancellation;
          try {
            final request = _llmRequest(
              policy: policy,
              currentUserText: userText,
              library: library,
              libraryAvailable: libraryAvailable,
              cancellation: cancellation,
            );
            final response = await llm!.complete(request);
            cancellation.throwIfCancelled();
            final cloudTurn = _cloudTurn(
              response,
              library: request.library,
              availableTools: request.availableTools,
            );
            if (cloudTurn != null) {
              await store.appendTurn(
                messages: <MayaMessage>[user, cloudTurn.assistantMessage],
                proposals: cloudTurn.proposals,
              );
              return _storedTurn(cloudTurn);
            }
          } on MayaLlmException {
            // Sanitized provider failures fall through to the local engine.
          } catch (_) {
            // Adapters are an untrusted boundary. Never surface raw errors.
          } finally {
            if (identical(_activeLlmCancellation, cancellation)) {
              _activeLlmCancellation = null;
            }
          }
        }
      }

      if (!libraryAvailable) {
        try {
          library = List<MayaLibraryItem>.unmodifiable(
            await libraryPort.listLibrary(),
          );
          libraryAvailable = true;
        } catch (_) {
          final turn = _libraryUnavailableTurn(cloudFallback: cloudAttempted);
          await store.appendTurn(
            messages: <MayaMessage>[user, turn.assistantMessage],
            proposals: const <ActionProposal>[],
          );
          return _storedTurn(turn);
        }
      }

      MayaTurn turn;
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

      if (cloudAttempted) turn = _asLocalFallback(turn);

      await store.appendTurn(
        messages: <MayaMessage>[user, turn.assistantMessage],
        proposals: turn.proposals,
      );
      return _storedTurn(turn);
    });
  }

  /// Persist confirmation before dispatching any external effect.
  Future<ActionProposal> confirmProposal(String proposalId) {
    if (!_accepting) {
      return Future<ActionProposal>.error(
        StateError('MayaService já foi encerrado.'),
      );
    }
    try {
      _mutationGate?.ensureAccepting();
    } catch (error, stackTrace) {
      return Future<ActionProposal>.error(error, stackTrace);
    }
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
      origin: turn.origin,
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

  String _boundedMessageText(String value) {
    if (value.length <= kMayaMaxMessageChars) return value;
    return value.substring(0, kMayaMaxMessageChars);
  }

  MayaLlmRequest _llmRequest({
    required MayaLlmContextPolicy policy,
    required String currentUserText,
    required List<MayaLibraryItem> library,
    required bool libraryAvailable,
    required MayaLlmCancellationToken cancellation,
  }) {
    final sharedLibrary = policy.shareLibraryContext && libraryAvailable
        ? _boundedLibraryContext(library)
        : const <MayaLlmLibraryItem>[];
    final tools = <MayaLlmTool>{};
    if (sharedLibrary.isNotEmpty) {
      tools.add(MayaLlmTool.openManga);
      if (sharedLibrary.any((item) => item.lastChapterId != null)) {
        tools.add(MayaLlmTool.downloadChapter);
      }
    }
    return MayaLlmRequest(
      currentUserText: currentUserText,
      history: policy.shareRecentHistory
          ? _boundedRecentHistory()
          : const <MayaLlmMessage>[],
      library: sharedLibrary,
      availableTools: tools,
      libraryAvailable: policy.shareLibraryContext && libraryAvailable,
      cancellation: cancellation,
      contextLease: policy.contextLease,
    );
  }

  List<MayaLlmMessage> _boundedRecentHistory() {
    final selected = <MayaLlmMessage>[];
    var bytes = 0;
    for (final message in store.messages.reversed) {
      if (selected.length >= kMayaLlmMaxHistoryMessages) break;
      if (message.role == MayaRole.system) continue;
      final messageBytes = utf8.encode(message.text).length;
      if (messageBytes > kMayaLlmMaxHistoryBytes - bytes) continue;
      selected.add(MayaLlmMessage(role: message.role, text: message.text));
      bytes += messageBytes;
    }
    return List<MayaLlmMessage>.unmodifiable(selected.reversed);
  }

  List<MayaLlmLibraryItem> _boundedLibraryContext(
    List<MayaLibraryItem> library,
  ) {
    final selected = <MayaLlmLibraryItem>[];
    var bytes = 0;
    for (final item in library.take(kMayaLlmMaxLibraryItems)) {
      final candidate = MayaLlmLibraryItem(
        mangaId: item.id,
        title: item.title,
        unreadCount: item.unreadCount,
        lastChapterId: item.lastChapterId,
        lastChapterName: item.lastChapterName,
      );
      final candidateBytes = utf8.encode(jsonEncode(candidate.toJson())).length;
      if (candidateBytes > kMayaLlmMaxLibraryBytes - bytes) break;
      selected.add(candidate);
      bytes += candidateBytes;
    }
    return List<MayaLlmLibraryItem>.unmodifiable(selected);
  }

  MayaTurn? _cloudTurn(
    MayaLlmResponse response, {
    required List<MayaLlmLibraryItem> library,
    required Set<MayaLlmTool> availableTools,
  }) {
    final proposals = _validatedLlmProposals(
      response.intents,
      library: library,
      availableTools: availableTools,
    );
    var text = _boundedMessageText((response.text ?? '').trim());
    if (text.isEmpty && proposals.isNotEmpty) {
      text = proposals.length == 1
          ? 'Preparei uma ação segura para você confirmar.'
          : 'Preparei ${proposals.length} ações seguras para você confirmar.';
    }
    if (text.isEmpty) return null;
    return MayaTurn(
      assistantMessage: MayaMessage(
        id: _freshMessageId('m-cloud'),
        role: MayaRole.assistant,
        text: text,
        createdAt: DateTime.now().toUtc(),
        proposalIds: proposals.map((proposal) => proposal.id).toList(),
      ),
      proposals: proposals,
      origin: MayaResponseOrigin.cloud,
    );
  }

  List<ActionProposal> _validatedLlmProposals(
    List<MayaLlmIntent> intents, {
    required List<MayaLlmLibraryItem> library,
    required Set<MayaLlmTool> availableTools,
  }) {
    final itemsById = <int, MayaLlmLibraryItem>{
      for (final item in library) item.mangaId: item,
    };
    final proposals = <ActionProposal>[];
    final seen = <String>{};
    for (final intent in intents.take(kMayaLlmMaxIntents)) {
      if (!availableTools.contains(intent.tool)) continue;
      final item = itemsById[intent.mangaId];
      if (item == null) continue;
      final key = '${intent.tool.name}:${intent.mangaId}:${intent.chapterId}';
      if (!seen.add(key)) continue;
      final now = DateTime.now().toUtc();
      switch (intent.tool) {
        case MayaLlmTool.openManga:
          proposals.add(
            ActionProposal(
              id: _freshProposalId('p-cloud-open'),
              kind: MayaActionKind.openManga,
              title: 'Abrir ${item.title}',
              description: 'Abrir a obra selecionada na biblioteca.',
              payload: <String, dynamic>{
                'mangaId': item.mangaId,
                'title': item.title,
                if (item.lastChapterId != null) 'chapterId': item.lastChapterId,
              },
              status: ActionProposalStatus.pending,
              createdAt: now,
            ),
          );
        case MayaLlmTool.downloadChapter:
          final chapterId = intent.chapterId;
          if (chapterId == null || chapterId != item.lastChapterId) continue;
          proposals.add(
            ActionProposal(
              id: _freshProposalId('p-cloud-download'),
              kind: MayaActionKind.downloadChapter,
              title: 'Baixar capítulo de ${item.title}',
              description:
                  'Enfileirar download de '
                  '${item.lastChapterName ?? 'capítulo $chapterId'}.',
              payload: <String, dynamic>{
                'mangaId': item.mangaId,
                'chapterId': chapterId,
                'title': item.title,
              },
              status: ActionProposalStatus.pending,
              createdAt: now,
            ),
          );
      }
    }
    return List<ActionProposal>.unmodifiable(proposals);
  }

  String _freshProposalId(String prefix) {
    while (true) {
      final id =
          '$prefix-${DateTime.now().microsecondsSinceEpoch}-'
          '${_messageSequence++}';
      if (store.proposalById(id) == null) return id;
    }
  }

  MayaTurn _asLocalFallback(MayaTurn turn) {
    final text = _boundedMessageText(
      'Modo local (fallback): ${turn.assistantMessage.text}',
    );
    return MayaTurn(
      assistantMessage: MayaMessage(
        id: turn.assistantMessage.id,
        role: turn.assistantMessage.role,
        text: text,
        createdAt: turn.assistantMessage.createdAt,
        proposalIds: turn.assistantMessage.proposalIds,
      ),
      proposals: turn.proposals,
      origin: MayaResponseOrigin.localFallback,
    );
  }

  MayaTurn _libraryUnavailableTurn({required bool cloudFallback}) {
    final prefix = cloudFallback ? 'Modo local (fallback): ' : '';
    return MayaTurn(
      assistantMessage: MayaMessage(
        id: _freshMessageId('m-library-unavailable'),
        role: MayaRole.assistant,
        text:
            '${prefix}Não consegui consultar a biblioteca agora. '
            'Verifique se o motor local está disponível e tente novamente.',
        createdAt: DateTime.now().toUtc(),
      ),
      origin: cloudFallback
          ? MayaResponseOrigin.localFallback
          : MayaResponseOrigin.local,
    );
  }
}
