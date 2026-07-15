import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_desktop/screens/reader_screen.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

ChapterInfo _chapter(int id, {int? lastPageRead, bool isRead = false}) =>
    ChapterInfo(
      id: id,
      name: 'Capítulo $id',
      lastPageRead: lastPageRead,
      isRead: isRead,
      sourceOrder: id,
    );

class _ProgressCall {
  const _ProgressCall(this.chapterId, this.page, this.isRead);

  final int chapterId;
  final int page;
  final bool? isRead;
}

class _FakeReaderApi extends SuwayomiApi {
  _FakeReaderApi({
    required Iterable<ChapterInfo> chapters,
    required Map<int, List<String>> pages,
  }) : chapters = {for (final chapter in chapters) chapter.id: chapter},
       pages = Map<int, List<String>>.from(pages),
       super(SuwayomiClient(baseUrl: 'http://127.0.0.1:14567'));

  final Map<int, ChapterInfo> chapters;
  final Map<int, List<String>> pages;
  final Map<int, Completer<ChapterPages>> blockedPages = {};
  final List<int> fetchCalls = [];
  final List<_ProgressCall> progressCalls = [];
  Completer<ChapterInfo>? nextProgressSave;

  @override
  Future<ChapterInfo?> getChapter(int chapterId) async => chapters[chapterId];

  @override
  Future<ChapterPages> fetchChapterPages(int chapterId) {
    fetchCalls.add(chapterId);
    final blocked = blockedPages[chapterId];
    if (blocked != null) return blocked.future;
    return Future.value(
      ChapterPages(chapterId: chapterId, pages: pages[chapterId] ?? const []),
    );
  }

  @override
  Future<ChapterInfo> updateChapterProgress({
    required int chapterId,
    required int lastPageRead,
    bool? isRead,
  }) async {
    progressCalls.add(_ProgressCall(chapterId, lastPageRead, isRead));
    final updated = chapters[chapterId]!.copyWith(
      lastPageRead: lastPageRead,
      isRead: isRead,
    );
    chapters[chapterId] = updated;
    final blocked = nextProgressSave;
    nextProgressSave = null;
    if (blocked != null) return blocked.future;
    return updated;
  }
}

Future<void> _pumpReader(
  WidgetTester tester, {
  required _FakeReaderApi api,
  required ChapterInfo chapter,
  required List<ChapterInfo> chapters,
  bool openSettings = false,
  ReaderPageContentBuilder? pageContentBuilder,
}) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderScreen(
        api: api,
        mangaId: 1,
        mangaTitle: 'Obra',
        chapter: chapter,
        chapters: chapters,
        openSettingsOnStart: openSettings,
        pageContentBuilder: pageContentBuilder,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _pageImage(String suffix) => find.byWidgetPredicate((widget) {
  if (widget is! Image || widget.image is! NetworkImage) return false;
  return (widget.image as NetworkImage).url.endsWith(suffix);
});

void main() {
  testWidgets('transição bloqueia avanço duplicado até a carga terminar', (
    tester,
  ) async {
    final chapters = [_chapter(1), _chapter(2), _chapter(3)];
    final api = _FakeReaderApi(
      chapters: chapters,
      pages: {
        1: ['/chapter-1/page-0'],
        2: ['/chapter-2/page-0'],
        3: ['/chapter-3/page-0'],
      },
    );
    api.blockedPages[2] = Completer<ChapterPages>();
    await _pumpReader(
      tester,
      api: api,
      chapter: chapters.first,
      chapters: chapters,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    expect(api.fetchCalls, [1, 2]);

    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();

    expect(api.fetchCalls, [1, 2]);
  });

  testWidgets('página dupla mantém a página seguinte à esquerda', (
    tester,
  ) async {
    final chapter = _chapter(1);
    final api = _FakeReaderApi(
      chapters: [chapter],
      pages: {
        1: ['/page-0', '/page-1', '/page-2', '/page-3'],
      },
    );
    await _pumpReader(
      tester,
      api: api,
      chapter: chapter,
      chapters: [chapter],
      openSettings: true,
    );

    await tester.tap(find.text('Página dupla'));
    await tester.pumpAndSettle();

    expect(_pageImage('/page-0'), findsOneWidget);
    expect(_pageImage('/page-1'), findsOneWidget);
    expect(
      tester.getCenter(_pageImage('/page-1')).dx,
      lessThan(tester.getCenter(_pageImage('/page-0')).dx),
    );
  });

  testWidgets(
    'página dupla avança uma página e conclui capítulo par como lido',
    (tester) async {
      final chapter = _chapter(1);
      final api = _FakeReaderApi(
        chapters: [chapter],
        pages: {
          1: ['/page-0', '/page-1', '/page-2', '/page-3'],
        },
      );
      await _pumpReader(
        tester,
        api: api,
        chapter: chapter,
        chapters: [chapter],
        openSettings: true,
      );
      await tester.tap(find.text('Página dupla'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Próxima página'));
      await tester.pump();
      expect(_pageImage('/page-1'), findsOneWidget);
      expect(_pageImage('/page-2'), findsOneWidget);
      expect(_pageImage('/page-3'), findsNothing);

      for (
        var i = 0;
        i < 4 && find.text('Capítulo concluído').evaluate().isEmpty;
        i++
      ) {
        await tester.tap(find.byTooltip('Próxima página'));
        await tester.pump();
      }
      await tester.pump();

      expect(find.text('Capítulo concluído'), findsOneWidget);
      expect(api.progressCalls, isNotEmpty);
      expect(api.progressCalls.last.chapterId, 1);
      expect(api.progressCalls.last.page, 3);
      expect(api.progressCalls.last.isRead, isTrue);
    },
  );

  testWidgets('resume e slider procuram a página real em rolagem vertical', (
    tester,
  ) async {
    final chapter = _chapter(1, lastPageRead: 12);
    final pages = List.generate(14, (index) => '/page-$index');
    final heights = List.generate(14, (index) => index < 7 ? 120.0 : 700.0);
    final api = _FakeReaderApi(chapters: [chapter], pages: {1: pages});
    await _pumpReader(
      tester,
      api: api,
      chapter: chapter,
      chapters: [chapter],
      openSettings: true,
      pageContentBuilder: (context, index, url) => SizedBox(
        key: ValueKey('test-page-$index'),
        height: heights[index],
        child: Text('Página de teste $index'),
      ),
    );

    await tester.tap(find.text('Rolagem vertical'));
    await tester.pumpAndSettle();

    final viewport = tester.getRect(find.byType(ListView));
    expect(
      tester
          .getRect(find.byKey(const ValueKey('test-page-12')))
          .overlaps(viewport),
      isTrue,
    );

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(11);
    slider.onChanged!(1);
    await tester.pumpAndSettle();

    expect(
      tester
          .getRect(find.byKey(const ValueKey('test-page-1')))
          .overlaps(viewport),
      isTrue,
    );
  });

  testWidgets('rolagem expõe largura fixa em vez de opções de fit inertes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final chapter = _chapter(1);
    final api = _FakeReaderApi(
      chapters: [chapter],
      pages: {
        1: ['/page-0', '/page-1'],
      },
    );
    await _pumpReader(
      tester,
      api: api,
      chapter: chapter,
      chapters: [chapter],
      openSettings: true,
    );

    await tester.tap(find.text('Rolagem vertical'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rolagem vertical'));
    await tester.pumpAndSettle();

    expect(find.text('Largura fixa na rolagem'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Encaixe da página: largura fixa nos modos de rolagem',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('scroll natural usa viewport real e abre painel no fim', (
    tester,
  ) async {
    final chapter = _chapter(1);
    final pages = List.generate(5, (index) => '/page-$index');
    const heights = [180.0, 520.0, 240.0, 620.0, 260.0];
    final api = _FakeReaderApi(chapters: [chapter], pages: {1: pages});
    await _pumpReader(
      tester,
      api: api,
      chapter: chapter,
      chapters: [chapter],
      openSettings: true,
      pageContentBuilder: (context, index, url) => SizedBox(
        key: ValueKey('test-page-$index'),
        height: heights[index],
        child: Text('Página de teste $index'),
      ),
    );
    await tester.tap(find.text('Webtoon'));
    await tester.pumpAndSettle();

    final firstRect = tester.getRect(find.byKey(const ValueKey('test-page-0')));
    final secondRect = tester.getRect(
      find.byKey(const ValueKey('test-page-1')),
    );
    // The page containers have a one-pixel border on each edge; webtoon mode
    // removes the layout gap while those borders remain visible.
    expect(secondRect.top - firstRect.bottom, lessThanOrEqualTo(2.01));

    // At this shallow offset a linear percentage still maps to page 0, while
    // the measured RenderBoxes show the much taller page 1 as most visible.
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.progressCalls, isNotEmpty);
    expect(api.progressCalls.last.page, 1);
    expect(api.progressCalls.last.isRead, isFalse);

    await tester.fling(find.byType(ListView), const Offset(0, -2200), 4000);
    await tester.pumpAndSettle();

    expect(find.text('Capítulo concluído'), findsOneWidget);
    expect(api.progressCalls, isNotEmpty);
    expect(api.progressCalls.last.page, 4);
    expect(api.progressCalls.last.isRead, isTrue);
  });

  testWidgets('dispose mantém save final e não chama estado descartado', (
    tester,
  ) async {
    final chapter = _chapter(1);
    final api = _FakeReaderApi(
      chapters: [chapter],
      pages: {
        1: ['/page-0', '/page-1'],
      },
    );
    await _pumpReader(tester, api: api, chapter: chapter, chapters: [chapter]);
    final blocked = Completer<ChapterInfo>();
    api.nextProgressSave = blocked;

    await tester.tap(find.byTooltip('Próxima página'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.progressCalls, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    blocked.complete(_chapter(1, lastPageRead: 1, isRead: true));
    await tester.pump();
    await tester.pump();

    expect(api.progressCalls, hasLength(2));
    expect(api.progressCalls.last.page, 1);
    expect(api.progressCalls.last.isRead, isTrue);
    expect(tester.takeException(), isNull);
  });
}
