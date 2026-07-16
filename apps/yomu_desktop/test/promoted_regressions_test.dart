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

  void addMayaTearDown(WidgetTester tester, MayaService maya) {
    addTearDown(() async {
      Object? closeError;
      StackTrace? closeStackTrace;
      var closed = false;
      maya.close().then(
        (_) => closed = true,
        onError: (Object error, StackTrace stackTrace) {
          closeError = error;
          closeStackTrace = stackTrace;
          closed = true;
        },
      );
      await tester.pump(Duration.zero);
      if (!closed) {
        throw StateError('Maya fixture still had pending asynchronous work.');
      }
      if (closeError != null) {
        Error.throwWithStackTrace(closeError!, closeStackTrace!);
      }
    });
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
    final store = MayaStore.inMemory(
      seedMessages: [
        MayaMessage(
          id: 'm1',
          role: MayaRole.assistant,
          text: 'Histórico persistido',
          createdAt: DateTime.utc(2026, 7, 14),
        ),
      ],
    );
    final maya = MayaService(store: store, libraryPort: _NoopMayaPort());
    addMayaTearDown(tester, maya);

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
    final store = MayaStore.inMemory(
      seedMessages: [
        MayaMessage(
          id: 'm1',
          role: MayaRole.user,
          text: 'Mensagem para apagar',
          createdAt: DateTime.utc(2026, 7, 14),
        ),
      ],
    );
    final maya = MayaService(store: store, libraryPort: _NoopMayaPort());
    addMayaTearDown(tester, maya);

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

  testWidgets('Maya blocks confirm offline but keeps local reject available', (
    tester,
  ) async {
    await setDesktopSurface(tester);
    final message = MayaMessage(
      id: 'm-pending',
      role: MayaRole.assistant,
      text: 'Posso baixar este capítulo.',
      createdAt: DateTime.utc(2026, 7, 14),
      proposalIds: const ['p-pending'],
    );
    final proposal = ActionProposal(
      id: 'p-pending',
      kind: MayaActionKind.downloadChapter,
      title: 'Baixar capítulo',
      description: 'Enfileirar o capítulo 99.',
      payload: const {'chapterId': 99},
      status: ActionProposalStatus.pending,
      createdAt: DateTime.utc(2026, 7, 14),
    );
    final store = MayaStore.inMemory(
      seedMessages: [message],
      seedProposals: [proposal],
    );
    final port = _NoopMayaPort();
    final maya = MayaService(store: store, libraryPort: port);
    addMayaTearDown(tester, maya);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(body: MayaScreen(service: maya, engineReady: false)),
      ),
    );
    await tester.pump();

    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar ação'),
    );
    final reject = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Ignorar'),
    );
    expect(confirm.onPressed, isNull);
    expect(reject.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Ignorar'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Proposta ignorada — nada foi alterado.'), findsOneWidget);
    expect(port.downloads, isEmpty);
  });

  testWidgets('Maya renders confirmed as unverified without retry action', (
    tester,
  ) async {
    await setDesktopSurface(tester);
    final store = MayaStore.inMemory(
      seedMessages: [
        MayaMessage(
          id: 'm-confirmed',
          role: MayaRole.assistant,
          text: 'Confirmação em andamento.',
          createdAt: DateTime.utc(2026, 7, 14),
          proposalIds: const ['p-confirmed'],
        ),
      ],
      seedProposals: [
        ActionProposal(
          id: 'p-confirmed',
          kind: MayaActionKind.downloadChapter,
          title: 'Baixar capítulo',
          description: 'Enfileirar o capítulo 99.',
          payload: const {'chapterId': 99},
          status: ActionProposalStatus.confirmed,
          createdAt: DateTime.utc(2026, 7, 14),
        ),
      ],
    );
    final maya = MayaService(store: store, libraryPort: _NoopMayaPort());
    addMayaTearDown(tester, maya);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(body: MayaScreen(service: maya, engineReady: true)),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'Confirmação registrada, mas o resultado não foi verificado. '
        'A ação não será repetida automaticamente.',
      ),
      findsOneWidget,
    );
    expect(find.text('Confirmar ação'), findsNothing);
  });

  testWidgets('Maya does not expose internal confirmation errors', (
    tester,
  ) async {
    await setDesktopSurface(tester);
    final createdAt = DateTime.utc(2026, 7, 14);
    final store = MayaStore.inMemory(
      seedMessages: [
        MayaMessage(
          id: 'm-sensitive-error',
          role: MayaRole.assistant,
          text: 'Posso baixar este capítulo.',
          createdAt: createdAt,
          proposalIds: const ['p-sensitive-error'],
        ),
      ],
      seedProposals: [
        ActionProposal(
          id: 'p-sensitive-error',
          kind: MayaActionKind.downloadChapter,
          title: 'Baixar capítulo',
          description: 'Enfileirar o capítulo 99.',
          payload: const {'chapterId': 99},
          status: ActionProposalStatus.pending,
          createdAt: createdAt,
        ),
      ],
    );
    final maya = MayaService(
      store: store,
      libraryPort: _NoopMayaPort(),
      hooks: MayaServiceHooks(
        afterConfirmationPersistedBeforeDispatch: (_) async {
          throw StateError(r'secret C:\Users\private\maya_chat.json');
        },
      ),
    );
    addMayaTearDown(tester, maya);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(body: MayaScreen(service: maya, engineReady: true)),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar ação'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'Não foi possível concluir a ação da Maya. '
        'O estado persistido foi preservado.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining(r'C:\Users'), findsNothing);
  });

  testWidgets('Maya shows sanitized legacy migration blocked state', (
    tester,
  ) async {
    await setDesktopSurface(tester);
    const reason =
        'A migração do histórico da Maya foi bloqueada. '
        'O arquivo original foi preservado.';

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: const Scaffold(
          body: MayaScreen(
            service: null,
            engineReady: true,
            unavailableReason: reason,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Histórico da Maya indisponível'), findsOneWidget);
    expect(find.text(reason), findsOneWidget);
    expect(find.text('Biblioteca · conectada'), findsOneWidget);
    expect(find.textContaining('maya_chat.json'), findsNothing);
    expect(find.textContaining(r'C:\'), findsNothing);
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
  final downloads = <int>[];

  @override
  Future<void> enqueueChapterDownload(int chapterId) async {
    downloads.add(chapterId);
  }

  @override
  Future<List<MayaLibraryItem>> listLibrary() async => const [];

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {}
}
