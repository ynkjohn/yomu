import 'downloads_gateway.dart';
import 'engine_readiness.dart';
import 'extensions_gateway.dart';
import 'library_gateway.dart';
import 'library_models.dart';
import 'manga_details_gateway.dart';
import 'reading_models.dart';

/// Shared synchronous admission boundary for mutable desktop capabilities.
///
/// Operations admitted before [stopAccepting] may finish. Later operations are
/// rejected before reaching an engine adapter. Lifecycle-only drains such as
/// [DownloadsGateway.pauseAndAwaitAck] deliberately bypass this user-mutation
/// gate.
final class EngineMutationGate {
  bool _accepting = true;

  bool get isAccepting => _accepting;

  void stopAccepting() {
    _accepting = false;
  }

  void ensureAccepting() {
    if (!_accepting) throw engineMutationsBlockedException;
  }

  Future<T> run<T>(Future<T> Function() operation) {
    try {
      ensureAccepting();
      return operation();
    } catch (error, stackTrace) {
      return Future<T>.error(error, stackTrace);
    }
  }
}

final class GuardedLibraryGateway implements LibraryGateway {
  GuardedLibraryGateway({required this.delegate, required this.gate});

  final LibraryGateway delegate;
  final EngineMutationGate gate;

  @override
  Future<List<LibraryManga>> listLibrary() => delegate.listLibrary();

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) =>
      gate.run(() => delegate.setInLibrary(mangaId, inLibrary));
}

final class GuardedMangaDetailsGateway implements MangaDetailsGateway {
  GuardedMangaDetailsGateway({required this.delegate, required this.gate});

  final MangaDetailsGateway delegate;
  final EngineMutationGate gate;

  @override
  Future<ReadingMangaDetails> getManga(int mangaId) =>
      delegate.getManga(mangaId);

  @override
  Future<ReadingMangaDetails> setInLibrary(int mangaId, bool inLibrary) =>
      gate.run(() => delegate.setInLibrary(mangaId, inLibrary));
}

final class GuardedDownloadsGateway implements DownloadsGateway {
  GuardedDownloadsGateway({required this.delegate, required this.gate});

  final DownloadsGateway delegate;
  final EngineMutationGate gate;

  @override
  Future<DownloadsSnapshot> getStatus() => delegate.getStatus();

  @override
  Future<void> enqueueChapters(List<int> chapterIds) =>
      gate.run(() => delegate.enqueueChapters(chapterIds));

  @override
  Future<void> dequeueChapters(List<int> chapterIds) =>
      gate.run(() => delegate.dequeueChapters(chapterIds));

  @override
  Future<DownloadPauseAck> pause() => gate.run(delegate.pause);

  @override
  Future<void> resume() => gate.run(delegate.resume);

  @override
  Future<void> clear() => gate.run(delegate.clear);

  @override
  Future<bool> hasActivity() => delegate.hasActivity();

  @override
  Future<DownloadPauseAck> pauseAndAwaitAck({required Duration timeout}) =>
      delegate.pauseAndAwaitAck(timeout: timeout);
}

final class GuardedExtensionsGateway implements ExtensionsGateway {
  GuardedExtensionsGateway({required this.delegate, required this.gate});

  final ExtensionsGateway delegate;
  final EngineMutationGate gate;

  @override
  Future<List<ExtensionRepository>> listRepositories() =>
      delegate.listRepositories();

  @override
  Future<List<ReadingExtension>> listExtensions() => delegate.listExtensions();

  @override
  Future<ExtensionCatalogSync> synchronizeCatalog() =>
      gate.run(delegate.synchronizeCatalog);

  @override
  Future<ExtensionRepository> ensureRecommendedRepository() =>
      gate.run(delegate.ensureRecommendedRepository);

  @override
  Future<ReadingExtension> install(ExtensionReference reference) =>
      gate.run(() => delegate.install(reference));

  @override
  Future<ReadingExtension> installRecommendedExtension() =>
      gate.run(delegate.installRecommendedExtension);
}

const engineMutationsBlockedException = EngineException(
  EngineFailure(
    kind: EngineFailureKind.operationRejected,
    code: 'engine_mutations_blocked',
    message: 'Novas alterações estão temporariamente bloqueadas.',
    retryable: true,
  ),
);
