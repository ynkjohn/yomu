import 'dart:async';

import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';

void main() {
  test('readiness exposes only product state and sanitized failure', () {
    const failure = EngineFailure(
      kind: EngineFailureKind.temporarilyUnavailable,
      code: 'engine_temporarily_unavailable',
      message: 'Recursos de leitura temporariamente indisponíveis.',
      retryable: true,
    );
    final retryAt = DateTime.utc(2026, 7, 18, 12);
    final recovering = EngineReadinessSnapshot(
      state: EngineReadinessState.recovering,
      failure: failure,
      attempt: 2,
      nextRetryAt: retryAt,
    );

    expect(recovering.isReady, isFalse);
    expect(recovering.failure, failure);
    expect(recovering.attempt, 2);
    expect(recovering.nextRetryAt, retryAt);
    expect(
      const EngineReadinessSnapshot(state: EngineReadinessState.ready).isReady,
      isTrue,
    );
  });

  test('engine exception contains only the sanitized failure', () {
    const failure = EngineFailure(
      kind: EngineFailureKind.operationRejected,
      code: 'engine_operation_failed',
      message: 'Não foi possível carregar a biblioteca.',
      retryable: true,
    );

    const exception = EngineException(failure);

    expect(exception.failure, failure);
    expect(
      exception.toString(),
      'EngineException(engine_operation_failed): '
      'Não foi possível carregar a biblioteca.',
    );
  });

  test('library models contain opaque media and value semantics', () {
    const cover = _TestMediaReference('cover-7');
    const chapter = LibraryResumePoint(
      id: 9,
      name: 'Capítulo 9',
      lastPageRead: 3,
      pageCount: 12,
    );
    const first = LibraryManga(
      id: 7,
      title: 'Yomu',
      thumbnail: cover,
      inLibrary: true,
      unreadCount: 4,
      lastReadChapter: chapter,
    );
    const second = LibraryManga(
      id: 7,
      title: 'Yomu',
      thumbnail: cover,
      inLibrary: true,
      unreadCount: 4,
      lastReadChapter: chapter,
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(first.thumbnail, isA<MediaReference>());

    const minimal = LibraryManga(id: 8, title: 'Sem progresso');
    expect(minimal.unreadCount, isNull);
    expect(minimal.lastReadChapter, isNull);
    expect(minimal.thumbnail, isNull);
  });

  test('media payload owns a defensive byte copy', () {
    final source = <int>[1, 2, 3];
    final payload = MediaPayload(
      bytes: source,
      contentType: 'image/png',
      statusCode: 206,
    );
    source[0] = 9;

    expect(payload.bytes, <int>[1, 2, 3]);
    expect(() => payload.bytes[0] = 9, throwsUnsupportedError);
    expect(
      payload,
      MediaPayload(
        bytes: const [1, 2, 3],
        contentType: 'image/png',
        statusCode: 206,
      ),
    );
  });

  test('reading and catalog models keep transport identities opaque', () {
    const cover = _TestMediaReference('cover');
    const page = _TestMediaReference('page');
    const manga = ReadingMangaDetails(
      id: 4,
      title: 'Detalhes',
      status: ReadingPublicationStatus.ongoing,
      thumbnail: cover,
      sourceId: 'source',
      inLibrary: true,
    );
    const chapter = ReadingChapter(
      id: 8,
      name: 'Capítulo 8',
      lastPageRead: 2,
      readingOrder: 7,
      mangaId: 4,
    );
    final pages = ReadingChapterPages(
      chapterId: 8,
      pages: const [page],
      pageCount: 1,
      chapterName: chapter.name,
    );
    const source = CatalogSource(
      id: 's',
      name: 'Fonte',
      language: 'pt-BR',
      icon: cover,
    );
    const result = CatalogManga(
      id: 4,
      title: 'Detalhes',
      thumbnail: cover,
      inLibrary: true,
    );

    expect(manga.thumbnail, isA<MediaReference>());
    expect(pages.pages, const [page]);
    expect(() => pages.pages.add(page), throwsUnsupportedError);
    expect(source.language, 'pt-BR');
    expect(result.thumbnail, cover);
    expect(
      CatalogPage(items: const [result], page: 2, hasNextPage: true),
      CatalogPage(items: const [result], page: 2, hasNextPage: true),
    );
  });

  test('external fakes implement each narrow capability', () {
    expect(_TestReadiness(), isA<EngineReadiness>());
    expect(_TestLibraryGateway(), isA<LibraryGateway>());
    expect(_TestMediaGateway(), isA<EngineMediaGateway>());
    expect(_TestDetailsGateway(), isA<MangaDetailsGateway>());
    expect(_TestReaderGateway(), isA<ReaderGateway>());
    expect(_TestProgressGateway(), isA<ReadingProgressGateway>());
    expect(_TestCatalogGateway(), isA<CatalogGateway>());
    expect(_TestExtensionsGateway(), isA<ExtensionsGateway>());
  });
}

final class _TestMediaReference implements MediaReference {
  const _TestMediaReference(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is _TestMediaReference && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

final class _TestReadiness implements EngineReadiness {
  @override
  EngineReadinessSnapshot get current =>
      const EngineReadinessSnapshot(state: EngineReadinessState.initializing);

  @override
  Stream<EngineReadinessSnapshot> get changes => const Stream.empty();
}

final class _TestLibraryGateway implements LibraryGateway {
  @override
  Future<List<LibraryManga>> listLibrary() async => const [];

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {}
}

final class _TestMediaGateway implements EngineMediaGateway {
  @override
  Future<MediaPayload> fetch(
    MediaReference reference, {
    required int maxBytes,
  }) async {
    return MediaPayload(bytes: const []);
  }
}

final class _TestDetailsGateway implements MangaDetailsGateway {
  @override
  Future<ReadingMangaDetails> getManga(int mangaId) async =>
      ReadingMangaDetails(id: mangaId, title: 'Manga');

  @override
  Future<ReadingMangaDetails> setInLibrary(int mangaId, bool inLibrary) async =>
      ReadingMangaDetails(id: mangaId, title: 'Manga', inLibrary: inLibrary);
}

final class _TestReaderGateway implements ReaderGateway {
  @override
  Future<ReadingChapter?> getChapter(int chapterId) async => null;

  @override
  Future<ReadingChapterPages> getPages(int chapterId) async =>
      ReadingChapterPages(chapterId: chapterId, pages: const []);

  @override
  Future<List<ReadingChapter>> listChapters(int mangaId) async => const [];

  @override
  Future<List<ReadingChapter>> refreshChapters(int mangaId) async => const [];
}

final class _TestProgressGateway implements ReadingProgressGateway {
  @override
  Future<ReadingProgressSnapshot> updateProgress({
    required int chapterId,
    required int lastPageRead,
    required bool isRead,
  }) async => ReadingProgressSnapshot(
    chapterId: chapterId,
    lastPageRead: lastPageRead,
    isRead: isRead,
  );
}

final class _TestCatalogGateway implements CatalogGateway {
  @override
  Future<List<CatalogSource>> listSources() async => const [];

  @override
  Future<CatalogPage> search({
    required String sourceId,
    required String query,
    int page = 1,
  }) async => CatalogPage(items: const [], page: page, hasNextPage: false);

  @override
  Future<CatalogPage> popular({required String sourceId, int page = 1}) async =>
      CatalogPage(items: const [], page: page, hasNextPage: false);

  @override
  Future<CatalogPage> latest({required String sourceId, int page = 1}) async =>
      CatalogPage(items: const [], page: page, hasNextPage: false);
}

final class _TestExtensionsGateway implements ExtensionsGateway {
  @override
  Future<ExtensionRepository> ensureRecommendedRepository() async =>
      const ExtensionRepository(
        name: 'Recomendado',
        state: ExtensionRepositoryState.active,
        recommended: true,
      );

  @override
  Future<ReadingExtension> install(ExtensionReference reference) async =>
      ReadingExtension(reference: reference, name: 'Extensão', installed: true);

  @override
  Future<ReadingExtension> installRecommendedExtension() async =>
      const ReadingExtension(
        reference: _TestExtensionReference(),
        name: 'Recomendada',
        installed: true,
        recommended: true,
      );

  @override
  Future<List<ReadingExtension>> listExtensions() async => const [];

  @override
  Future<List<ExtensionRepository>> listRepositories() async => const [];

  @override
  Future<ExtensionCatalogSync> synchronizeCatalog() async =>
      const ExtensionCatalogSync(count: 0);
}

final class _TestExtensionReference implements ExtensionReference {
  const _TestExtensionReference();
}
