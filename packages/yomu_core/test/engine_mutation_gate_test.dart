import 'dart:async';

import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';

void main() {
  test(
    'library reads continue while later membership writes are rejected',
    () async {
      final delegate = _FakeLibraryGateway();
      final gate = EngineMutationGate();
      final guarded = GuardedLibraryGateway(delegate: delegate, gate: gate);

      gate.stopAccepting();

      expect(await guarded.listLibrary(), hasLength(1));
      await _expectBlocked(guarded.setInLibrary(7, true));
      expect(delegate.membershipCalls, isEmpty);
    },
  );

  test('operation admitted before the seal may finish', () async {
    final delegate = _FakeLibraryGateway(blockMembership: true);
    final gate = EngineMutationGate();
    final guarded = GuardedLibraryGateway(delegate: delegate, gate: gate);

    final admitted = guarded.setInLibrary(7, true);
    await delegate.membershipEntered.future;
    gate.stopAccepting();
    delegate.releaseMembership.complete();

    await admitted;
    expect(delegate.membershipCalls, [(7, true)]);
    await _expectBlocked(guarded.setInLibrary(8, true));
  });

  test(
    'manga details keep reads and reject membership after the seal',
    () async {
      final delegate = _FakeMangaDetailsGateway();
      final gate = EngineMutationGate()..stopAccepting();
      final guarded = GuardedMangaDetailsGateway(
        delegate: delegate,
        gate: gate,
      );

      expect((await guarded.getManga(4)).id, 4);
      await _expectBlocked(guarded.setInLibrary(4, true));
      expect(delegate.membershipCalls, isEmpty);
    },
  );

  test(
    'downloads reject user mutations but preserve status and lifecycle pause',
    () async {
      final delegate = _FakeDownloadsGateway();
      final gate = EngineMutationGate()..stopAccepting();
      final guarded = GuardedDownloadsGateway(delegate: delegate, gate: gate);

      expect(
        (await guarded.getStatus()).managerState,
        DownloadManagerState.running,
      );
      expect(await guarded.hasActivity(), isTrue);
      expect(
        (await guarded.pauseAndAwaitAck(
          timeout: const Duration(seconds: 1),
        )).acknowledged,
        isTrue,
      );

      await _expectBlocked(guarded.enqueueChapters([1]));
      await _expectBlocked(guarded.dequeueChapters([1]));
      await _expectBlocked(guarded.pause());
      await _expectBlocked(guarded.resume());
      await _expectBlocked(guarded.clear());

      expect(delegate.operations, ['status', 'activity', 'lifecycle-pause']);
    },
  );

  test('extensions keep reads and reject every mutable operation', () async {
    final delegate = _FakeExtensionsGateway();
    final gate = EngineMutationGate()..stopAccepting();
    final guarded = GuardedExtensionsGateway(delegate: delegate, gate: gate);

    expect(await guarded.listRepositories(), hasLength(1));
    expect(await guarded.listExtensions(), hasLength(1));

    await _expectBlocked(guarded.synchronizeCatalog());
    await _expectBlocked(guarded.ensureRecommendedRepository());
    await _expectBlocked(guarded.install(const _FakeExtensionReference()));
    await _expectBlocked(guarded.installRecommendedExtension());

    expect(delegate.mutationCalls, isEmpty);
  });
}

Future<void> _expectBlocked(Future<Object?> operation) => expectLater(
  operation,
  throwsA(
    isA<EngineException>().having(
      (error) => error.failure.code,
      'failure code',
      'engine_mutations_blocked',
    ),
  ),
);

final class _FakeLibraryGateway implements LibraryGateway {
  _FakeLibraryGateway({this.blockMembership = false});

  final bool blockMembership;
  final membershipEntered = Completer<void>();
  final releaseMembership = Completer<void>();
  final membershipCalls = <(int, bool)>[];

  @override
  Future<List<LibraryManga>> listLibrary() async => const [
    LibraryManga(id: 7, title: 'Yomu'),
  ];

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {
    if (!membershipEntered.isCompleted) membershipEntered.complete();
    if (blockMembership) await releaseMembership.future;
    membershipCalls.add((mangaId, inLibrary));
  }
}

final class _FakeMangaDetailsGateway implements MangaDetailsGateway {
  final membershipCalls = <(int, bool)>[];

  @override
  Future<ReadingMangaDetails> getManga(int mangaId) async =>
      ReadingMangaDetails(id: mangaId, title: 'Yomu');

  @override
  Future<ReadingMangaDetails> setInLibrary(int mangaId, bool inLibrary) async {
    membershipCalls.add((mangaId, inLibrary));
    return ReadingMangaDetails(
      id: mangaId,
      title: 'Yomu',
      inLibrary: inLibrary,
    );
  }
}

final class _FakeDownloadsGateway implements DownloadsGateway {
  final operations = <String>[];

  @override
  Future<void> clear() async => operations.add('clear');

  @override
  Future<void> dequeueChapters(List<int> chapterIds) async =>
      operations.add('dequeue');

  @override
  Future<void> enqueueChapters(List<int> chapterIds) async =>
      operations.add('enqueue');

  @override
  Future<DownloadsSnapshot> getStatus() async {
    operations.add('status');
    return DownloadsSnapshot(
      managerState: DownloadManagerState.running,
      queue: const [EngineDownloadItem(state: DownloadItemState.downloading)],
    );
  }

  @override
  Future<bool> hasActivity() async {
    operations.add('activity');
    return true;
  }

  @override
  Future<DownloadPauseAck> pause() async {
    operations.add('pause');
    return const DownloadPauseAck(
      managerState: DownloadManagerState.paused,
      acknowledged: true,
    );
  }

  @override
  Future<DownloadPauseAck> pauseAndAwaitAck({required Duration timeout}) async {
    operations.add('lifecycle-pause');
    return const DownloadPauseAck(
      managerState: DownloadManagerState.paused,
      acknowledged: true,
    );
  }

  @override
  Future<void> resume() async => operations.add('resume');
}

final class _FakeExtensionsGateway implements ExtensionsGateway {
  final mutationCalls = <String>[];

  @override
  Future<ExtensionRepository> ensureRecommendedRepository() async {
    mutationCalls.add('repository');
    return const ExtensionRepository(
      name: 'Recomendado',
      state: ExtensionRepositoryState.active,
      recommended: true,
    );
  }

  @override
  Future<ReadingExtension> install(ExtensionReference reference) async {
    mutationCalls.add('install');
    return ReadingExtension(
      reference: reference,
      name: 'Extensão',
      installed: true,
    );
  }

  @override
  Future<ReadingExtension> installRecommendedExtension() async {
    mutationCalls.add('recommended');
    return const ReadingExtension(
      reference: _FakeExtensionReference(),
      name: 'Recomendada',
      installed: true,
    );
  }

  @override
  Future<List<ReadingExtension>> listExtensions() async => const [
    ReadingExtension(
      reference: _FakeExtensionReference(),
      name: 'Extensão',
      installed: false,
    ),
  ];

  @override
  Future<List<ExtensionRepository>> listRepositories() async => const [
    ExtensionRepository(
      name: 'Recomendado',
      state: ExtensionRepositoryState.active,
      recommended: true,
    ),
  ];

  @override
  Future<ExtensionCatalogSync> synchronizeCatalog() async {
    mutationCalls.add('sync');
    return const ExtensionCatalogSync(count: 1);
  }
}

final class _FakeExtensionReference implements ExtensionReference {
  const _FakeExtensionReference();
}
