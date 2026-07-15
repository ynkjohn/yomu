import 'dart:io';
import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_desktop/screens/downloads_screen.dart';
import 'package:yomu_desktop/screens/home_screen.dart';
import 'package:yomu_desktop/screens/library_screen.dart';
import 'package:yomu_desktop/screens/manga_detail_screen.dart';
import 'package:yomu_desktop/screens/maya_screen.dart';
import 'package:yomu_desktop/screens/server_screen.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

void main() {
  Future<void> setDesktopSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1240, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('Library filters the real collection by title', (tester) async {
    await setDesktopSurface(tester);
    final api = _FakeSuwayomiApi(
      library: const [
        MangaSummary(id: 1, title: 'Frieren', inLibrary: true),
        MangaSummary(id: 2, title: 'Vagabond', inLibrary: true),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(body: LibraryScreen(api: api, engineReady: true)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Frieren'), findsOneWidget);
    expect(find.text('Vagabond'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('library-title-filter')),
      'frie',
    );
    await tester.pump();

    expect(find.text('Frieren'), findsOneWidget);
    expect(find.text('Vagabond'), findsNothing);
  });

  testWidgets('Home search is factual and Control K opens Explore', (
    tester,
  ) async {
    await setDesktopSurface(tester);
    String? destination;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(
          body: HomeScreen(
            api: null,
            engineReady: false,
            onNavigate: (value) => destination = value,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Buscar nas fontes…'), findsOneWidget);
    expect(find.textContaining('biblioteca e nas fontes'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(destination, 'explore');
  });

  testWidgets('Home empty state does not infer that sources are missing', (
    tester,
  ) async {
    await setDesktopSurface(tester);
    String? destination;
    final api = _FakeSuwayomiApi(library: const []);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(
          body: HomeScreen(
            api: api,
            engineReady: true,
            onNavigate: (value) => destination = value,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('primeira fonte'), findsNothing);
    expect(find.text('Explorar fontes'), findsOneWidget);
    await tester.tap(find.text('Explorar fontes'));
    expect(destination, 'explore');
  });

  testWidgets('Manga chapter search keeps a 44px interaction target', (
    tester,
  ) async {
    await setDesktopSurface(tester);
    final api = _FakeSuwayomiApi(
      manga: const MangaDetails(id: 7, title: 'Frieren'),
      chapters: const [
        ChapterInfo(
          id: 70,
          name: 'Capítulo 1',
          chapterNumber: 1,
          sourceOrder: 1,
          mangaId: 7,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: MangaDetailScreen(api: api, mangaId: 7),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final chapterSearch = find.byKey(const ValueKey('chapter-number-filter'));
    expect(chapterSearch, findsOneWidget);
    expect(tester.getSize(chapterSearch).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home renders zero-based reading progress as one-based', (
    tester,
  ) async {
    await setDesktopSurface(tester);
    final api = _FakeSuwayomiApi(
      library: const [
        MangaSummary(
          id: 1,
          title: 'Leitura em andamento',
          inLibrary: true,
          lastReadChapter: ChapterInfo(
            id: 10,
            name: 'Capítulo 1',
            pageCount: 10,
            lastPageRead: 0,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(
          body: HomeScreen(api: api, engineReady: true, onNavigate: (_) {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('pág. 1 de 10 · progresso sincronizado'), findsOneWidget);
    final indicators = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .toList(growable: false);
    expect(indicators, hasLength(2));
    expect(
      indicators.map((indicator) => indicator.value),
      everyElement(closeTo(0.1, 0.0001)),
    );
  });

  testWidgets('Home health rows are semantic 44 pixel button targets', (
    tester,
  ) async {
    await setDesktopSurface(tester);
    final semantics = tester.ensureSemantics();
    String? destination;
    final api = _FakeSuwayomiApi(
      library: const [
        MangaSummary(id: 1, title: 'Na biblioteca', inLibrary: true),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(
          body: HomeScreen(
            api: api,
            engineReady: true,
            onNavigate: (value) => destination = value,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    for (final label in ['Motor operando', 'Ver fila de downloads']) {
      final target = find.bySemanticsLabel(label);
      expect(target, findsOneWidget);
      final size = tester.getSize(target);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      final node = tester.getSemantics(target);
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(node.hasFlag(SemanticsFlag.isEnabled), isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    }

    await tester.tap(find.bySemanticsLabel('Motor operando'));
    await tester.pump();
    expect(destination, 'server');
    semantics.dispose();
  });

  testWidgets('Server lists and copies every current LAN URL', (tester) async {
    await setDesktopSurface(tester);
    MethodCall? clipboardCall;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboardCall = call;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(
          body: ServerScreen(
            status: const SuwayomiStatus(
              state: SuwayomiProcessState.running,
              baseUrl: 'http://127.0.0.1:14567',
            ),
            yomuPort: 8787,
            managedRootDir: r'C:\tmp\yomu',
            onStart: () {},
            onStop: () {},
            onRestart: () {},
            onHealthCheck: () {},
            lanEnabled: true,
            onToggleLan: (_) {},
            pairingCode: null,
            pairingExpiresAt: null,
            onStartPairing: () {},
            onCancelPairing: () {},
            lanAddresses: const ['192.168.0.10', '10.0.0.8'],
            sessionCount: 0,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('http://192.168.0.10:8787/'), findsOneWidget);
    expect(find.text('http://10.0.0.8:8787/'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Copiar http://10.0.0.8:8787/'));
    await tester.pump();

    expect(clipboardCall?.arguments, <String, dynamic>{
      'text': 'http://10.0.0.8:8787/',
    });
  });

  testWidgets('Downloads clears a non-empty queue only after confirmation', (
    tester,
  ) async {
    await setDesktopSurface(tester);
    final api = _FakeSuwayomiApi(
      downloadStatus: const DownloadStatusInfo(
        state: 'STOPPED',
        queue: [DownloadQueueItem(state: 'QUEUED')],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(body: DownloadsScreen(api: api, engineReady: true)),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Limpar fila'));
    await tester.pump();
    expect(api.clearDownloaderCalls, 0);
    expect(find.text('Limpar downloads?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Limpar fila'));
    await tester.pump();
    await tester.pump();

    expect(api.clearDownloaderCalls, 1);
  });

  testWidgets('Maya keeps persisted history visible while the engine is off', (
    tester,
  ) async {
    await setDesktopSurface(tester);
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'yomu-maya-widget-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });
    final store = await tester.runAsync(() async {
      final seed = MayaStore(file);
      seed.messages.add(
        MayaMessage(
          id: 'm1',
          role: MayaRole.assistant,
          text: 'Histórico persistido',
          createdAt: DateTime.utc(2026, 7, 14),
        ),
      );
      await seed.save();
      final loaded = MayaStore(file);
      await loaded.load();
      return loaded;
    });
    expect(store, isNotNull);
    final maya = MayaService(store: store!, libraryPort: _NoopMayaPort());

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(body: MayaScreen(service: maya, engineReady: false)),
      ),
    );
    await tester.pump();

    expect(find.text('Histórico persistido'), findsOneWidget);
    expect(find.text('Maya temporariamente indisponível'), findsNothing);
    expect(
      find.text('Memória detalhada ainda não implementada.'),
      findsOneWidget,
    );
    expect(find.textContaining('apagável, item a item'), findsNothing);
  });

  testWidgets('Maya clears history only after explicit confirmation', (
    tester,
  ) async {
    await setDesktopSurface(tester);
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'yomu-maya-clear-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });
    final store = MayaStore(file);
    store.messages.add(
      MayaMessage(
        id: 'm1',
        role: MayaRole.user,
        text: 'Mensagem para apagar',
        createdAt: DateTime.utc(2026, 7, 14),
      ),
    );
    final maya = MayaService(store: store, libraryPort: _NoopMayaPort());

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(body: MayaScreen(service: maya, engineReady: false)),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Limpar histórico da Maya'));
    await tester.pump();
    expect(store.messages, hasLength(1));
    expect(find.text('Limpar histórico?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Limpar histórico'));
    await tester.pump();
    await tester.pump();

    expect(store.messages, isEmpty);
    expect(find.text('Mensagem para apagar'), findsNothing);
  });
}

class _FakeSuwayomiApi extends SuwayomiApi {
  _FakeSuwayomiApi({
    this.library = const [],
    this.downloadStatus = const DownloadStatusInfo(state: 'STOPPED', queue: []),
    this.manga,
    this.chapters = const [],
  }) : super(SuwayomiClient(baseUrl: 'http://127.0.0.1:14567'));

  final List<MangaSummary> library;
  final MangaDetails? manga;
  final List<ChapterInfo> chapters;
  DownloadStatusInfo downloadStatus;
  int clearDownloaderCalls = 0;

  @override
  Future<List<MangaSummary>> listLibrary() async => library;

  @override
  Future<MangaDetails> getManga(int id) async =>
      manga ?? MangaDetails(id: id, title: 'Mangá $id');

  @override
  Future<List<ChapterInfo>> fetchMangaChapters(int mangaId) async => chapters;

  @override
  Future<List<ChapterInfo>> listMangaChapters(int mangaId) async => chapters;

  @override
  Future<DownloadStatusInfo> getDownloadStatus() async => downloadStatus;

  @override
  Future<void> clearDownloader() async {
    clearDownloaderCalls++;
    downloadStatus = const DownloadStatusInfo(state: 'STOPPED', queue: []);
  }
}

class _NoopMayaPort implements MayaLibraryPort {
  @override
  Future<void> enqueueChapterDownload(int chapterId) async {}

  @override
  Future<List<MayaLibraryItem>> listLibrary() async => const [];

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {}
}
