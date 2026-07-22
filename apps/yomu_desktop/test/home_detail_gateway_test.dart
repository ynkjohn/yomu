import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_desktop/screens/home_screen.dart';
import 'package:yomu_desktop/screens/manga_detail_screen.dart';
import 'package:yomu_ui/yomu_ui.dart';

void main() {
  const mediaLimit = 8 * 1024 * 1024;

  Future<void> useDesktopSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    required LibraryGateway? library,
    required bool engineReady,
    EngineMediaGateway? media,
    Future<void> Function(LibraryManga)? onOpen,
    Future<void> Function(LibraryManga)? onContinue,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(
          body: HomeScreen(
            library: library,
            media: media,
            engineReady: engineReady,
            onRetryEngine: () {},
            onNavigate: (_) {},
            onOpenManga: onOpen ?? (_) async {},
            onContinueReading: onContinue ?? (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpDetails(
    WidgetTester tester, {
    required MangaDetailsGateway details,
    required ReaderGateway reader,
    CatalogGateway catalog = const _CatalogGateway(),
    EngineMediaGateway media = const _EmptyMediaGateway(),
    DownloadsGateway? downloads,
    OpenReadingChapter? onOpen,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: MangaDetailScreen(
          details: details,
          reader: reader,
          catalog: catalog,
          media: media,
          downloads: downloads ?? _RecordingDownloadsGateway(),
          mangaId: 7,
          onOpenChapter:
              onOpen ??
              ({
                required mangaId,
                required mangaTitle,
                required chapter,
                required chapters,
                required openSettings,
              }) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Home discards old gateway responses and engine-loss results', (
    tester,
  ) async {
    await useDesktopSurface(tester);
    final oldGateway = _DeferredLibraryGateway();
    final newGateway = _DeferredLibraryGateway();

    await pumpHome(tester, library: oldGateway, engineReady: true);
    await pumpHome(tester, library: newGateway, engineReady: true);

    newGateway.complete(const [
      LibraryManga(
        id: 2,
        title: 'Resposta nova',
        lastReadChapter: LibraryResumePoint(id: 20, name: 'Capítulo novo'),
      ),
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Resposta nova'), findsOneWidget);

    oldGateway.complete(const [
      LibraryManga(
        id: 1,
        title: 'Resposta antiga',
        lastReadChapter: LibraryResumePoint(id: 10, name: 'Capítulo antigo'),
      ),
    ]);
    await tester.pump();
    expect(find.text('Resposta antiga'), findsNothing);
    expect(find.text('Resposta nova'), findsOneWidget);

    final lostGateway = _DeferredLibraryGateway();
    await pumpHome(tester, library: lostGateway, engineReady: true);
    await pumpHome(tester, library: lostGateway, engineReady: false);
    lostGateway.complete(const [LibraryManga(id: 3, title: 'Motor antigo')]);
    await tester.pump();

    expect(find.text('Motor antigo'), findsNothing);
    expect(
      find.text('Os recursos de leitura estão indisponíveis no momento.'),
      findsOneWidget,
    );
    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets('Home sanitizes unexpected failures', (tester) async {
    await useDesktopSurface(tester);

    await pumpHome(
      tester,
      library: const _ThrowingLibraryGateway(
        r'GraphQL C:\private\engine.db token=secret',
      ),
      engineReady: true,
    );
    await tester.pump();

    expect(
      find.textContaining('Não foi possível carregar a biblioteca.'),
      findsOneWidget,
    );
    expect(find.textContaining('GraphQL'), findsNothing);
    expect(find.textContaining('private'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
  });

  testWidgets('Home uses opaque 8 MiB media and reloads after callbacks', (
    tester,
  ) async {
    await useDesktopSurface(tester);
    const reference = _MediaReference('home-cover');
    const manga = LibraryManga(
      id: 9,
      title: 'Opaque Home',
      thumbnail: reference,
      unreadCount: 0,
      lastReadChapter: LibraryResumePoint(
        id: 91,
        name: 'Capítulo 9',
        lastPageRead: 2,
        pageCount: 10,
      ),
    );
    final library = _RecordingLibraryGateway(const [manga]);
    final media = _RecordingMediaGateway();
    var opens = 0;
    var resumes = 0;

    await pumpHome(
      tester,
      library: library,
      media: media,
      engineReady: true,
      onOpen: (value) async {
        expect(value, manga);
        opens++;
      },
      onContinue: (value) async {
        expect(value, manga);
        resumes++;
      },
    );
    await tester.pump();

    expect(media.references, isNotEmpty);
    expect(media.references, everyElement(reference));
    expect(media.maxBytes, everyElement(mediaLimit));

    await tester.tap(find.text('Retomar'));
    await tester.pump();
    await tester.pump();
    expect(resumes, 1);
    expect(library.calls, 2);

    await tester.tap(find.text('Opaque Home'));
    await tester.pump();
    await tester.pump();
    expect(opens, 1);
    expect(library.calls, 3);
  });

  testWidgets(
    'MangaDetail refreshes explicitly and forwards membership, order and ids',
    (tester) async {
      await useDesktopSurface(tester);
      const cover = _MediaReference('detail-cover');
      final details = _MutableDetailsGateway(
        const ReadingMangaDetails(
          id: 7,
          title: 'Gateway Detail',
          thumbnail: cover,
          sourceId: 'source-7',
        ),
      );
      final reader = _RecordingReaderGateway(const [
        ReadingChapter(id: 30, name: 'Capítulo 3', readingOrder: 3),
        ReadingChapter(id: 10, name: 'Capítulo 1', readingOrder: 1),
        ReadingChapter(id: 20, name: 'Capítulo 2', readingOrder: 2),
      ]);
      final media = _RecordingMediaGateway();
      final downloads = _RecordingDownloadsGateway();
      int? openedChapter;
      List<int>? openedOrder;

      await pumpDetails(
        tester,
        details: details,
        reader: reader,
        media: media,
        downloads: downloads,
        onOpen:
            ({
              required mangaId,
              required mangaTitle,
              required chapter,
              required chapters,
              required openSettings,
            }) async {
              expect(mangaId, 7);
              expect(mangaTitle, 'Gateway Detail');
              expect(openSettings, isFalse);
              openedChapter = chapter.id;
              openedOrder = chapters.map((item) => item.id).toList();
            },
      );
      await tester.pump();

      expect(reader.refreshCalls, 1);
      expect(reader.listCalls, 0);
      expect(media.references, [cover]);
      expect(media.maxBytes, [mediaLimit]);

      await tester.tap(find.byTooltip('Adicionar à biblioteca'));
      await tester.pump();
      await tester.pump();
      expect(details.membershipCalls, const [(7, true)]);
      expect(find.text('Na biblioteca'), findsOneWidget);

      await tester.ensureVisible(find.text('Baixar'));
      await tester.tap(find.text('Baixar'));
      await tester.pump();
      expect(downloads.enqueued, const [
        [30, 10, 20],
      ]);
      expect(downloads.resumeCalls, 1);

      await tester.tap(find.byTooltip('Baixar capítulo').first);
      await tester.pump();
      expect(downloads.enqueued.last, const [30]);
      expect(downloads.resumeCalls, 2);

      await tester.ensureVisible(find.text('Começar leitura'));
      await tester.tap(find.text('Começar leitura'));
      await tester.pump();
      expect(openedChapter, 10);
      expect(openedOrder, const [10, 20, 30]);
    },
  );

  testWidgets('MangaDetail ignores an old chapter response', (tester) async {
    await useDesktopSurface(tester);
    final reader = _DeferredReaderGateway();

    await pumpDetails(
      tester,
      details: _MutableDetailsGateway(_details()),
      reader: reader,
    );
    expect(reader.refreshCalls, 1);

    await tester.tap(find.byTooltip('Atualizar'));
    await tester.pump();
    await tester.pump();
    expect(reader.refreshCalls, 2);

    reader.complete(1, const [
      ReadingChapter(id: 2, name: 'Capítulo novo', readingOrder: 2),
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Capítulo novo'), findsWidgets);

    reader.complete(0, const [
      ReadingChapter(id: 1, name: 'Capítulo antigo', readingOrder: 1),
    ]);
    await tester.pump();
    expect(find.text('Capítulo antigo'), findsNothing);
    expect(find.text('Capítulo novo'), findsWidgets);
  });

  testWidgets('MangaDetail ignores an old chapter error', (tester) async {
    await useDesktopSurface(tester);
    final reader = _DeferredReaderGateway();

    await pumpDetails(
      tester,
      details: _MutableDetailsGateway(_details()),
      reader: reader,
    );
    await tester.tap(find.byTooltip('Atualizar'));
    await tester.pump();
    await tester.pump();

    reader.complete(1, const [ReadingChapter(id: 2, name: 'Capítulo vigente')]);
    await tester.pump();
    await tester.pump();
    reader.completeError(0, StateError(r'GraphQL C:\private\chapters.db'));
    await tester.pump();

    expect(find.text('Capítulo vigente'), findsWidgets);
    expect(find.text('Tentar de novo'), findsNothing);
    expect(find.textContaining('GraphQL'), findsNothing);
    expect(find.textContaining('private'), findsNothing);
  });

  testWidgets('MangaDetail sanitizes unexpected detail failures', (
    tester,
  ) async {
    await useDesktopSurface(tester);

    await pumpDetails(
      tester,
      details: const _ThrowingDetailsGateway(
        r'GraphQL C:\private\engine.db token=secret',
      ),
      reader: const _RecordingReaderGateway([]),
    );
    await tester.pump();

    expect(find.text('Não foi possível carregar este título.'), findsOneWidget);
    expect(find.textContaining('GraphQL'), findsNothing);
    expect(find.textContaining('private'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
  });
}

ReadingMangaDetails _details() => const ReadingMangaDetails(
  id: 7,
  title: 'Detalhe concorrente',
  sourceId: 'source-7',
);

final class _MediaReference implements MediaReference {
  const _MediaReference(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is _MediaReference && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

final class _DeferredLibraryGateway implements LibraryGateway {
  final _completer = Completer<List<LibraryManga>>();

  @override
  Future<List<LibraryManga>> listLibrary() => _completer.future;

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {}

  void complete(List<LibraryManga> items) => _completer.complete(items);
}

final class _RecordingLibraryGateway implements LibraryGateway {
  _RecordingLibraryGateway(this.items);

  final List<LibraryManga> items;
  int calls = 0;

  @override
  Future<List<LibraryManga>> listLibrary() async {
    calls++;
    return items;
  }

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {}
}

final class _ThrowingLibraryGateway implements LibraryGateway {
  const _ThrowingLibraryGateway(this.message);

  final String message;

  @override
  Future<List<LibraryManga>> listLibrary() => Future.error(StateError(message));

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) =>
      Future.error(StateError(message));
}

final class _MutableDetailsGateway implements MangaDetailsGateway {
  _MutableDetailsGateway(this.current);

  ReadingMangaDetails current;
  final membershipCalls = <(int, bool)>[];

  @override
  Future<ReadingMangaDetails> getManga(int mangaId) async => current;

  @override
  Future<ReadingMangaDetails> setInLibrary(int mangaId, bool inLibrary) async {
    membershipCalls.add((mangaId, inLibrary));
    current = ReadingMangaDetails(
      id: current.id,
      title: current.title,
      description: current.description,
      author: current.author,
      artist: current.artist,
      status: current.status,
      thumbnail: current.thumbnail,
      sourceId: current.sourceId,
      inLibrary: inLibrary,
    );
    return current;
  }
}

final class _ThrowingDetailsGateway implements MangaDetailsGateway {
  const _ThrowingDetailsGateway(this.message);

  final String message;

  @override
  Future<ReadingMangaDetails> getManga(int mangaId) =>
      Future.error(StateError(message));

  @override
  Future<ReadingMangaDetails> setInLibrary(int mangaId, bool inLibrary) =>
      Future.error(StateError(message));
}

final class _RecordingReaderGateway implements ReaderGateway {
  const _RecordingReaderGateway(this.chapters);

  final List<ReadingChapter> chapters;
  static final _counts = Expando<_ReaderCounts>();

  _ReaderCounts get _counter => _counts[this] ??= _ReaderCounts();
  int get listCalls => _counter.listCalls;
  int get refreshCalls => _counter.refreshCalls;

  @override
  Future<ReadingChapter?> getChapter(int chapterId) async => null;

  @override
  Future<ReadingChapterPages> getPages(int chapterId) async =>
      ReadingChapterPages(chapterId: chapterId, pages: const []);

  @override
  Future<List<ReadingChapter>> listChapters(int mangaId) async {
    _counter.listCalls++;
    return chapters;
  }

  @override
  Future<List<ReadingChapter>> refreshChapters(int mangaId) async {
    _counter.refreshCalls++;
    return chapters;
  }
}

final class _ReaderCounts {
  int listCalls = 0;
  int refreshCalls = 0;
}

final class _DeferredReaderGateway implements ReaderGateway {
  final _refreshes = <Completer<List<ReadingChapter>>>[];

  int get refreshCalls => _refreshes.length;

  @override
  Future<ReadingChapter?> getChapter(int chapterId) async => null;

  @override
  Future<ReadingChapterPages> getPages(int chapterId) async =>
      ReadingChapterPages(chapterId: chapterId, pages: const []);

  @override
  Future<List<ReadingChapter>> listChapters(int mangaId) async => const [];

  @override
  Future<List<ReadingChapter>> refreshChapters(int mangaId) {
    final completer = Completer<List<ReadingChapter>>();
    _refreshes.add(completer);
    return completer.future;
  }

  void complete(int index, List<ReadingChapter> chapters) =>
      _refreshes[index].complete(chapters);

  void completeError(int index, Object error) =>
      _refreshes[index].completeError(error);
}

final class _CatalogGateway implements CatalogGateway {
  const _CatalogGateway();

  @override
  Future<CatalogPage> latest({required String sourceId, int page = 1}) async =>
      CatalogPage(items: const [], page: page, hasNextPage: false);

  @override
  Future<List<CatalogSource>> listSources() async => const [
    CatalogSource(id: 'source-7', name: 'Fonte Yomu', language: 'pt-BR'),
  ];

  @override
  Future<CatalogPage> popular({required String sourceId, int page = 1}) async =>
      CatalogPage(items: const [], page: page, hasNextPage: false);

  @override
  Future<CatalogPage> search({
    required String sourceId,
    required String query,
    int page = 1,
  }) async => CatalogPage(items: const [], page: page, hasNextPage: false);
}

final class _RecordingMediaGateway implements EngineMediaGateway {
  final references = <MediaReference>[];
  final maxBytes = <int>[];

  @override
  Future<MediaPayload> fetch(
    MediaReference reference, {
    required int maxBytes,
  }) async {
    references.add(reference);
    this.maxBytes.add(maxBytes);
    return MediaPayload(bytes: const []);
  }
}

final class _EmptyMediaGateway implements EngineMediaGateway {
  const _EmptyMediaGateway();

  @override
  Future<MediaPayload> fetch(
    MediaReference reference, {
    required int maxBytes,
  }) async => MediaPayload(bytes: const []);
}

final class _RecordingDownloadsGateway implements DownloadsGateway {
  final enqueued = <List<int>>[];
  int resumeCalls = 0;

  @override
  Future<void> clear() async {}

  @override
  Future<void> dequeueChapters(List<int> chapterIds) async {}

  @override
  Future<void> enqueueChapters(List<int> chapterIds) async {
    enqueued.add(List<int>.from(chapterIds));
  }

  @override
  Future<DownloadsSnapshot> getStatus() async => DownloadsSnapshot(
    managerState: DownloadManagerState.paused,
    queue: const [],
  );

  @override
  Future<bool> hasActivity() async => false;

  @override
  Future<DownloadPauseAck> pause() async => const DownloadPauseAck(
    managerState: DownloadManagerState.paused,
    acknowledged: true,
  );

  @override
  Future<DownloadPauseAck> pauseAndAwaitAck({required Duration timeout}) =>
      pause();

  @override
  Future<void> resume() async {
    resumeCalls++;
  }
}
