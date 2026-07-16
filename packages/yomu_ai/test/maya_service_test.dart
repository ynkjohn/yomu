import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_storage/yomu_storage.dart';

class _FakePort implements MayaLibraryPort {
  final items = <MayaLibraryItem>[
    const MayaLibraryItem(
      id: 7,
      title: 'One Piece',
      unreadCount: 2,
      lastChapterId: 99,
      lastChapterName: 'Cap 1000',
    ),
  ];
  final downloads = <int>[];
  int startDownloaderCalls = 0;
  final libraryToggles = <int, bool>{};
  bool failLibrary = false;
  bool failDownloadAfterDispatch = false;

  @override
  Future<List<MayaLibraryItem>> listLibrary() async {
    if (failLibrary) throw StateError('secret-library-error');
    return items;
  }

  @override
  Future<void> enqueueChapterDownload(int chapterId) async {
    downloads.add(chapterId);
    startDownloaderCalls++;
    if (failDownloadAfterDispatch) {
      throw StateError('secret-download-error');
    }
  }

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {
    libraryToggles[mangaId] = inLibrary;
  }
}

class _BlockingPort extends _FakePort {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<List<MayaLibraryItem>> listLibrary() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return super.listLibrary();
  }
}

void main() {
  test('send + confirm download executes only after durable confirm', () async {
    final store = MayaStore.inMemory();
    final port = _FakePort();
    final maya = MayaService(store: store, libraryPort: port);
    addTearDown(maya.close);

    final turn = await maya.sendUserMessage('baixar');
    expect(turn.proposals, isNotEmpty);
    expect(port.downloads, isEmpty);

    final proposal = turn.proposals.first;
    final done = await maya.confirmProposal(proposal.id);
    expect(done.status, ActionProposalStatus.executed);
    expect(done.confirmedAt, isNotNull);
    expect(done.completedAt, isNotNull);
    expect(port.downloads, <int>[99]);
    expect(port.startDownloaderCalls, 1);
  });

  test('50 concurrent confirms dispatch one effect', () async {
    final store = MayaStore.inMemory();
    final port = _FakePort();
    final maya = MayaService(store: store, libraryPort: port);
    addTearDown(maya.close);
    final proposal = (await maya.sendUserMessage('baixar')).proposals.single;

    final results = await Future.wait<ActionProposal>(
      List<Future<ActionProposal>>.generate(
        50,
        (_) => maya.confirmProposal(proposal.id),
      ),
    );

    expect(
      results.every((result) => result.status == ActionProposalStatus.executed),
      isTrue,
    );
    expect(port.downloads, <int>[99]);
    expect(port.startDownloaderCalls, 1);
  });

  test('reject wins a queued race and confirm never dispatches', () async {
    final store = MayaStore.inMemory();
    final port = _FakePort();
    final maya = MayaService(store: store, libraryPort: port);
    addTearDown(maya.close);
    final proposal = (await maya.sendUserMessage('baixar')).proposals.single;

    final rejectedFuture = maya.rejectProposal(proposal.id);
    final confirmedFuture = maya.confirmProposal(proposal.id);
    final rejected = await rejectedFuture;
    final confirmed = await confirmedFuture;

    expect(rejected.status, ActionProposalStatus.rejected);
    expect(confirmed.status, ActionProposalStatus.rejected);
    expect(port.downloads, isEmpty);
  });

  test('reject after execute does not rewrite audit status', () async {
    final store = MayaStore.inMemory();
    final port = _FakePort();
    final maya = MayaService(store: store, libraryPort: port);
    addTearDown(maya.close);
    final proposal = (await maya.sendUserMessage('baixar')).proposals.single;

    final done = await maya.confirmProposal(proposal.id);
    final after = await maya.rejectProposal(proposal.id);

    expect(done.status, ActionProposalStatus.executed);
    expect(after.status, ActionProposalStatus.executed);
    expect(port.downloads, <int>[99]);
  });

  test('crash after confirm and before dispatch is never retried', () async {
    final store = MayaStore.inMemory();
    final port = _FakePort();
    final maya = MayaService(
      store: store,
      libraryPort: port,
      hooks: MayaServiceHooks(
        afterConfirmationPersistedBeforeDispatch: (_) async {
          throw StateError('simulated-crash');
        },
      ),
    );
    addTearDown(maya.close);
    final proposal = (await maya.sendUserMessage('baixar')).proposals.single;

    await expectLater(maya.confirmProposal(proposal.id), throwsStateError);
    expect(
      maya.proposalById(proposal.id)!.status,
      ActionProposalStatus.confirmed,
    );
    expect(port.downloads, isEmpty);

    final retry = await maya.confirmProposal(proposal.id);
    expect(retry.status, ActionProposalStatus.confirmed);
    expect(port.downloads, isEmpty);
    await expectLater(maya.clearHistory(), throwsStateError);
    expect(maya.proposalById(proposal.id), isNotNull);
  });

  test(
    'crash after effect leaves confirmed and never dispatches twice',
    () async {
      final store = MayaStore.inMemory();
      final port = _FakePort();
      final maya = MayaService(
        store: store,
        libraryPort: port,
        hooks: MayaServiceHooks(
          afterEffectBeforeCompletionPersisted: (_) async {
            throw StateError('simulated-crash');
          },
        ),
      );
      addTearDown(maya.close);
      final proposal = (await maya.sendUserMessage('baixar')).proposals.single;

      await expectLater(maya.confirmProposal(proposal.id), throwsStateError);
      expect(port.downloads, <int>[99]);
      expect(
        maya.proposalById(proposal.id)!.status,
        ActionProposalStatus.confirmed,
      );

      final retry = await maya.confirmProposal(proposal.id);
      expect(retry.status, ActionProposalStatus.confirmed);
      expect(port.downloads, <int>[99]);
    },
  );

  test(
    'post-dispatch exception persists only a sanitized uncertain result',
    () async {
      final store = MayaStore.inMemory();
      final port = _FakePort()..failDownloadAfterDispatch = true;
      final maya = MayaService(store: store, libraryPort: port);
      addTearDown(maya.close);
      final proposal = (await maya.sendUserMessage('baixar')).proposals.single;

      final result = await maya.confirmProposal(proposal.id);

      expect(result.status, ActionProposalStatus.confirmed);
      expect(result.error, kMayaOutcomeUncertainError);
      expect(port.downloads, <int>[99]);
      expect(
        store.messages.any(
          (message) => message.text.contains('secret-download'),
        ),
        isFalse,
      );
      expect(result.error, isNot(contains('secret-download')));
    },
  );

  test(
    'library failure persists a generic atomic turn without raw error',
    () async {
      final store = MayaStore.inMemory();
      final port = _FakePort()..failLibrary = true;
      final maya = MayaService(store: store, libraryPort: port);
      addTearDown(maya.close);

      final turn = await maya.sendUserMessage('biblioteca');

      expect(store.messages, hasLength(2));
      expect(turn.assistantMessage.text, contains('motor local'));
      expect(turn.assistantMessage.text, isNot(contains('secret-library')));
    },
  );

  test('empty input is rejected without persistence', () async {
    final store = MayaStore.inMemory();
    final maya = MayaService(store: store, libraryPort: _FakePort());
    addTearDown(maya.close);

    await expectLater(maya.sendUserMessage('   '), throwsArgumentError);
    expect(store.messages, isEmpty);
    expect(store.proposals, isEmpty);
  });

  test(
    'close blocks admission synchronously and drains admitted write',
    () async {
      final store = MayaStore.inMemory();
      final port = _BlockingPort();
      final maya = MayaService(store: store, libraryPort: port);

      final admitted = maya.sendUserMessage('biblioteca');
      await port.entered.future;
      final closeFuture = maya.close();

      expect(maya.isClosed, isTrue);
      await expectLater(
        maya.sendUserMessage('outra mensagem'),
        throwsStateError,
      );
      port.release.complete();
      await admitted;
      await closeFuture;
      expect(store.messages, hasLength(2));
    },
  );

  test('public cache views cannot be mutated', () {
    final message = MayaMessage(
      id: 'message-immutable',
      role: MayaRole.assistant,
      text: 'Persistido',
      createdAt: DateTime.utc(2026, 7, 14),
    );
    final store = MayaStore.inMemory(seedMessages: <MayaMessage>[message]);

    expect(() => store.messages.add(message), throwsUnsupportedError);
    expect(() => store.proposals.clear(), throwsUnsupportedError);
  });

  test('new proposals must belong to an assistant message', () async {
    final createdAt = DateTime.utc(2026, 7, 14);
    final message = MayaMessage(
      id: 'message-user-owned',
      role: MayaRole.user,
      text: 'Baixe.',
      createdAt: createdAt,
      proposalIds: const <String>['proposal-user-owned'],
    );
    final proposal = ActionProposal(
      id: 'proposal-user-owned',
      kind: MayaActionKind.downloadChapter,
      title: 'Baixar capítulo',
      description: 'Enfileirar capítulo.',
      payload: const <String, Object>{'chapterId': 99},
      status: ActionProposalStatus.pending,
      createdAt: createdAt,
    );
    expect(
      () => MayaStore.inMemory(
        seedMessages: <MayaMessage>[message],
        seedProposals: <ActionProposal>[proposal],
      ),
      throwsStateError,
    );

    final store = MayaStore.inMemory();

    await expectLater(
      store.appendTurn(
        messages: <MayaMessage>[message],
        proposals: <ActionProposal>[proposal],
      ),
      throwsArgumentError,
    );
    expect(store.messages, isEmpty);
    expect(store.proposals, isEmpty);
  });

  test('reload rejects a persisted proposal owned by a user message', () async {
    final root = await Directory.systemTemp.createTemp('yomu-ai-owner-');
    final database = await YomuDatabase.openForTest(
      root,
      useProcessLock: false,
    );
    try {
      final store = await MayaStore.open(
        database: database,
        legacyFile: File('${root.path}${Platform.pathSeparator}maya_chat.json'),
      );
      await database.appendMayaTurn(
        messages: const <NewMayaMessage>[
          NewMayaMessage(
            messageId: 'message-user-owned',
            role: 'user',
            text: 'Baixe.',
            createdAtMs: 1,
          ),
        ],
        proposals: const <NewMayaProposal>[
          NewMayaProposal(
            proposalId: 'proposal-user-owned',
            messageId: 'message-user-owned',
            proposalOrder: 0,
            kind: 'downloadChapter',
            title: 'Baixar capítulo',
            description: 'Enfileirar capítulo.',
            payloadJson: '{"chapterId":99}',
            status: 'pending',
            createdAtMs: 1,
          ),
        ],
      );

      await expectLater(store.load(), throwsStateError);
      expect(store.messages, isEmpty);
      expect(store.proposals, isEmpty);
    } finally {
      await database.close();
      await root.delete(recursive: true);
    }
  });

  test('persistent pre-dispatch crash remains blocked after reopen', () async {
    final root = await Directory.systemTemp.createTemp('yomu-ai-barrier-');
    var database = await YomuDatabase.openForTest(root, useProcessLock: false);
    final legacyFile = File(
      '${root.path}${Platform.pathSeparator}maya_chat.json',
    );
    try {
      final firstStore = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
      );
      final firstPort = _FakePort();
      final firstService = MayaService(
        store: firstStore,
        libraryPort: firstPort,
        hooks: MayaServiceHooks(
          afterConfirmationPersistedBeforeDispatch: (_) async {
            throw StateError('simulated-crash');
          },
        ),
      );
      final proposal = (await firstService.sendUserMessage(
        'baixar',
      )).proposals.single;

      await expectLater(
        firstService.confirmProposal(proposal.id),
        throwsStateError,
      );
      expect(firstPort.downloads, isEmpty);
      await firstService.close();
      await database.close();

      database = await YomuDatabase.openForTest(root, useProcessLock: false);
      final reopenedStore = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
      );
      final secondPort = _FakePort();
      final secondService = MayaService(
        store: reopenedStore,
        libraryPort: secondPort,
      );
      final reopened = secondService.proposalById(proposal.id)!;
      expect(reopened.status, ActionProposalStatus.confirmed);
      expect(reopened.error, kMayaOutcomeUncertainError);

      final retry = await secondService.confirmProposal(proposal.id);
      expect(retry.status, ActionProposalStatus.confirmed);
      expect(secondPort.downloads, isEmpty);
      await secondService.close();
    } finally {
      try {
        await database.close();
      } catch (_) {}
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    }
  });

  test('terminal persistence failure never fabricates executed and restart '
      'does not retry', () async {
    final root = await Directory.systemTemp.createTemp('yomu-ai-confirm-');
    var database = await YomuDatabase.openForTest(root, useProcessLock: false);
    final legacyFile = File(
      '${root.path}${Platform.pathSeparator}maya_chat.json',
    );
    try {
      final store = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
      );
      final firstPort = _FakePort();
      final firstService = MayaService(
        store: store,
        libraryPort: firstPort,
        hooks: MayaServiceHooks(
          afterEffectBeforeCompletionPersisted: (_) async {
            await database.close();
          },
        ),
      );
      final proposal = (await firstService.sendUserMessage(
        'baixar',
      )).proposals.single;

      Object? persistenceError;
      try {
        await firstService.confirmProposal(proposal.id);
      } catch (error) {
        persistenceError = error;
      }
      await firstService.close();
      expect(persistenceError, isNotNull);
      expect(firstPort.downloads, <int>[99]);
      expect(
        firstService.proposalById(proposal.id)!.status,
        ActionProposalStatus.confirmed,
      );

      database = await YomuDatabase.openForTest(root, useProcessLock: false);
      final reopenedStore = await MayaStore.open(
        database: database,
        legacyFile: legacyFile,
      );
      final secondPort = _FakePort();
      final secondService = MayaService(
        store: reopenedStore,
        libraryPort: secondPort,
      );
      final reopened = secondService.proposalById(proposal.id)!;
      expect(reopened.status, ActionProposalStatus.confirmed);
      expect(reopened.error, kMayaOutcomeUncertainError);

      final retry = await secondService.confirmProposal(proposal.id);
      expect(retry.status, ActionProposalStatus.confirmed);
      expect(secondPort.downloads, isEmpty);
      await secondService.close();
    } finally {
      try {
        await database.close();
      } catch (_) {}
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    }
  });
}
