import 'dart:async';
import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_desktop/screens/explore_screen.dart';
import 'package:yomu_desktop/screens/extensions_screen.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_ui/yomu_ui.dart';

class _FetchCall {
  const _FetchCall({
    required this.sourceId,
    required this.type,
    required this.query,
    required this.page,
  });

  final String sourceId;
  final ExploreCatalogMode type;
  final String? query;
  final int page;
}

class _TestExtensionReference implements ExtensionReference {
  const _TestExtensionReference(this.id);

  final int id;

  @override
  bool operator ==(Object other) =>
      other is _TestExtensionReference && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class _FakeReadingEngine
    implements CatalogGateway, ExtensionsGateway, EngineMediaGateway {
  Future<List<CatalogSource>> Function()? listSourcesHandler;
  Future<CatalogPage> Function(_FetchCall call)? fetchMangaHandler;
  Future<List<ExtensionRepository>> Function()? listStoresHandler;
  Future<List<ReadingExtension>> Function()? listExtensionsHandler;
  Future<ReadingExtension> Function(ExtensionReference reference)?
  installHandler;
  Future<ExtensionCatalogSync> Function()? synchronizeHandler;
  Future<ExtensionRepository> Function()? ensureRepositoryHandler;
  Future<ReadingExtension> Function()? installRecommendedHandler;
  Future<MediaPayload> Function(MediaReference reference, int maxBytes)?
  mediaHandler;

  int listSourcesCalls = 0;
  int listExtensionsCalls = 0;
  final List<_FetchCall> fetchCalls = [];

  @override
  Future<List<CatalogSource>> listSources() {
    listSourcesCalls++;
    return listSourcesHandler?.call() ?? Future.value(const []);
  }

  Future<CatalogPage> _fetch({
    required String sourceId,
    required ExploreCatalogMode type,
    String? query,
    int page = 1,
  }) {
    final call = _FetchCall(
      sourceId: sourceId,
      type: type,
      query: query,
      page: page,
    );
    fetchCalls.add(call);
    return fetchMangaHandler?.call(call) ??
        Future.value(
          CatalogPage(items: const [], hasNextPage: false, page: page),
        );
  }

  @override
  Future<CatalogPage> search({
    required String sourceId,
    required String query,
    int page = 1,
  }) => _fetch(
    sourceId: sourceId,
    type: ExploreCatalogMode.search,
    query: query,
    page: page,
  );

  @override
  Future<CatalogPage> popular({required String sourceId, int page = 1}) =>
      _fetch(sourceId: sourceId, type: ExploreCatalogMode.popular, page: page);

  @override
  Future<CatalogPage> latest({required String sourceId, int page = 1}) =>
      _fetch(sourceId: sourceId, type: ExploreCatalogMode.latest, page: page);

  @override
  Future<List<ExtensionRepository>> listRepositories() {
    return listStoresHandler?.call() ?? Future.value(const []);
  }

  @override
  Future<List<ReadingExtension>> listExtensions() {
    listExtensionsCalls++;
    return listExtensionsHandler?.call() ?? Future.value(const []);
  }

  @override
  Future<ReadingExtension> install(ExtensionReference reference) {
    return installHandler?.call(reference) ??
        Future.error(StateError('unexpected extension install'));
  }

  @override
  Future<ExtensionCatalogSync> synchronizeCatalog() =>
      synchronizeHandler?.call() ??
      Future.value(const ExtensionCatalogSync(count: 0));

  @override
  Future<ExtensionRepository> ensureRecommendedRepository() =>
      ensureRepositoryHandler?.call() ??
      Future.value(
        const ExtensionRepository(
          name: 'Repositório recomendado',
          state: ExtensionRepositoryState.active,
          recommended: true,
        ),
      );

  @override
  Future<ReadingExtension> installRecommendedExtension() =>
      installRecommendedHandler?.call() ??
      Future.error(StateError('unexpected recommended extension install'));

  @override
  Future<MediaPayload> fetch(
    MediaReference reference, {
    required int maxBytes,
  }) =>
      mediaHandler?.call(reference, maxBytes) ??
      Future.value(MediaPayload(bytes: const []));
}

const _source = CatalogSource(id: 'source-1', name: 'MangaDex', language: 'en');

EngineException _sanitizedFailure(String message) => EngineException(
  EngineFailure(
    kind: EngineFailureKind.temporarilyUnavailable,
    code: 'test_failure',
    message: message,
    retryable: true,
  ),
);

Future<void> _pumpExplore(
  WidgetTester tester,
  _FakeReadingEngine engine, {
  bool engineReady = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildYomuTheme(),
      home: Scaffold(
        body: ExploreScreen(
          catalog: engine,
          extensions: engine,
          media: engine,
          engineReady: engineReady,
          onOpenManga: (_) async {},
        ),
      ),
    ),
  );
}

Future<void> _pumpExtensions(
  WidgetTester tester,
  _FakeReadingEngine engine, {
  bool repositoriesOnly = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildYomuTheme(),
      home: Scaffold(
        body: ExtensionsScreen(
          gateway: engine,
          engineReady: true,
          repositoriesOnly: repositoriesOnly,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('Explore owns source, catalog, and search loading states', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final sources = Completer<List<CatalogSource>>();
    final popular = Completer<CatalogPage>();
    final search = Completer<CatalogPage>();
    final engine = _FakeReadingEngine();
    engine.listSourcesHandler = () => sources.future;
    engine.fetchMangaHandler = (call) => switch (call.type) {
      ExploreCatalogMode.search => search.future,
      _ => popular.future,
    };

    await _pumpExplore(tester, engine);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    sources.complete(const [_source]);
    await tester.pumpAndSettle();
    expect(find.text('MangaDex'), findsOneWidget);

    await tester.tap(find.text('MangaDex'));
    await tester.pump();
    expect(engine.fetchCalls.single.type, ExploreCatalogMode.popular);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Carregando catálogo'), findsOneWidget);
    expect(find.bySemanticsLabel('Carregando obras'), findsNothing);

    popular.complete(
      CatalogPage(
        items: [CatalogManga(id: 1, title: 'One Piece')],
        hasNextPage: true,
        page: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('One Piece'), findsOneWidget);
    expect(find.text('Carregar mais'), findsOneWidget);

    final searchField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Buscar nesta fonte…',
    );
    await tester.enterText(searchField, '  Berserk  ');
    await tester.pump();
    expect(find.byTooltip('Limpar busca'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(engine.fetchCalls.last.type, ExploreCatalogMode.search);
    expect(engine.fetchCalls.last.query, 'Berserk');

    search.complete(
      CatalogPage(
        items: [CatalogManga(id: 2, title: 'Berserk')],
        hasNextPage: false,
        page: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Berserk'), findsOneWidget);
    expect(find.text('One Piece'), findsNothing);
    semantics.dispose();
  });

  testWidgets('long source names do not overflow the catalog toolbar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final longName = List.filled(30, 'FonteMuitoLonga').join(' ');
    final source = CatalogSource(
      id: 'source-long',
      name: longName,
      language: 'pt',
    );
    final engine = _FakeReadingEngine();
    engine.listSourcesHandler = () async => [source];
    engine.fetchMangaHandler = (call) async =>
        CatalogPage(items: const [], hasNextPage: false, page: call.page);

    await _pumpExplore(tester, engine);
    await tester.pumpAndSettle();
    await tester.tap(find.text(longName));
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text(longName));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('load-more failure stays visible without discarding results', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pageTwo = Completer<CatalogPage>();
    final engine = _FakeReadingEngine();
    engine.listSourcesHandler = () async => const [_source];
    engine.fetchMangaHandler = (call) {
      if (call.page == 1) {
        return Future.value(
          CatalogPage(
            items: [CatalogManga(id: 1, title: 'One Piece')],
            hasNextPage: true,
            page: 1,
          ),
        );
      }
      return pageTwo.future;
    };

    await _pumpExplore(tester, engine);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MangaDex'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Carregar mais'));
    await tester.pump();
    expect(find.text('Carregando…'), findsOneWidget);

    pageTwo.completeError(_sanitizedFailure('falha controlada na página 2'));
    await tester.pumpAndSettle();
    expect(find.text('One Piece'), findsOneWidget);
    expect(find.textContaining('falha controlada na página 2'), findsOneWidget);
    expect(find.text('Carregar mais'), findsOneWidget);
    final error = tester.getSemantics(
      find.bySemanticsLabel(RegExp('falha controlada na página 2')),
    );
    expect(error.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
    semantics.dispose();
  });

  testWidgets('load-more keeps the last submitted query snapshot', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = _FakeReadingEngine();
    engine.listSourcesHandler = () async => const [_source];
    engine.fetchMangaHandler = (call) async => CatalogPage(
      items: [
        CatalogManga(
          id: call.page,
          title: call.page == 1 ? 'Primeira' : 'Segunda',
        ),
      ],
      hasNextPage: call.page == 1,
      page: call.page,
    );

    await _pumpExplore(tester, engine);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MangaDex'));
    await tester.pumpAndSettle();

    final searchField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Buscar nesta fonte…',
    );
    await tester.enterText(searchField, 'ainda não submetida');
    await tester.pump();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Popular'))
          .hasFlag(SemanticsFlag.isSelected),
      isTrue,
    );
    await tester.tap(find.text('Carregar mais'));
    await tester.pumpAndSettle();

    expect(engine.fetchCalls, hasLength(2));
    expect(engine.fetchCalls.last.page, 2);
    expect(engine.fetchCalls.last.type, ExploreCatalogMode.popular);
    expect(engine.fetchCalls.last.query, isNull);
    expect(find.text('Segunda'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('engine loss rejects stale catalog response and resets source', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final catalog = Completer<CatalogPage>();
    final engine = _FakeReadingEngine();
    engine.listSourcesHandler = () async => const [_source];
    engine.fetchMangaHandler = (_) => catalog.future;

    await _pumpExplore(tester, engine);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MangaDex'));
    await tester.pump();

    await _pumpExplore(tester, engine, engineReady: false);
    await tester.pump();
    expect(find.text('Fontes indisponíveis'), findsOneWidget);

    catalog.complete(
      CatalogPage(
        items: [CatalogManga(id: 99, title: 'Resposta obsoleta')],
        hasNextPage: false,
        page: 1,
      ),
    );
    await tester.pump();

    await _pumpExplore(tester, engine);
    await tester.pumpAndSettle();
    expect(find.text('MangaDex'), findsOneWidget);
    expect(find.text('Resposta obsoleta'), findsNothing);
    expect(engine.listSourcesCalls, 2);
  });

  testWidgets('successful extension install refreshes Explore sources', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = _FakeReadingEngine();
    engine.listStoresHandler = () async => const [];
    engine.listExtensionsHandler = () async => const [
      ReadingExtension(
        reference: _TestExtensionReference(1),
        name: 'Extensão Teste',
        installed: false,
        language: 'pt-BR',
      ),
    ];
    engine.installHandler = (reference) async => ReadingExtension(
      reference: reference,
      name: 'Extensão Teste',
      installed: true,
      language: 'pt-BR',
    );

    engine.listSourcesHandler = () async => engine.listSourcesCalls <= 1
        ? const [_source]
        : const [
            _source,
            CatalogSource(
              id: 'source-2',
              name: 'Fonte recém-instalada',
              language: 'pt',
            ),
          ];

    await _pumpExplore(tester, engine);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extensões'));
    await tester.pumpAndSettle();
    expect(find.text('Extensão Teste'), findsOneWidget);

    await tester.tap(find.text('Instalar'));
    await tester.pumpAndSettle();
    expect(engine.listSourcesCalls, 2);

    await tester.tap(find.text('Fontes'));
    await tester.pumpAndSettle();
    expect(find.text('Fonte recém-instalada'), findsOneWidget);
  });

  testWidgets('install completion refreshes sources after leaving the tab', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final install = Completer<ReadingExtension>();
    final engine = _FakeReadingEngine();
    engine.listStoresHandler = () async => const [];
    engine.listExtensionsHandler = () async => const [
      ReadingExtension(
        reference: _TestExtensionReference(2),
        name: 'Extensão tardia',
        installed: false,
      ),
    ];
    engine.installHandler = (_) => install.future;
    engine.listSourcesHandler = () async => engine.listSourcesCalls <= 1
        ? const [_source]
        : const [
            _source,
            CatalogSource(
              id: 'source-late',
              name: 'Fonte após troca de aba',
              language: 'pt',
            ),
          ];

    await _pumpExplore(tester, engine);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extensões'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instalar'));
    await tester.pump();
    await tester.tap(find.text('Fontes'));
    await tester.pump();

    install.complete(
      const ReadingExtension(
        reference: _TestExtensionReference(2),
        name: 'Extensão tardia',
        installed: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(engine.listSourcesCalls, 2);
    expect(find.text('Fonte após troca de aba'), findsOneWidget);
  });

  testWidgets('install reports a source refresh failure', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = _FakeReadingEngine();
    engine.listSourcesHandler = () {
      if (engine.listSourcesCalls == 1) return Future.value(const [_source]);
      return Future.error(_sanitizedFailure('falha no refresh de fontes'));
    };
    engine.listStoresHandler = () async => const [];
    engine.listExtensionsHandler = () async => const [
      ReadingExtension(
        reference: _TestExtensionReference(3),
        name: 'Extensão com refresh falho',
        installed: false,
      ),
    ];
    engine.installHandler = (reference) async => ReadingExtension(
      reference: reference,
      name: 'Extensão com refresh falho',
      installed: true,
    );

    await _pumpExplore(tester, engine);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extensões'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instalar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('fontes não foram atualizadas'), findsOneWidget);
    await tester.tap(find.text('Fontes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('falha no refresh de fontes'), findsOneWidget);
  });

  testWidgets('repository actions stay disabled while install is in flight', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final install = Completer<ReadingExtension>();
    final engine = _FakeReadingEngine();
    engine.listSourcesHandler = () async => const [_source];
    engine.listStoresHandler = () async => const [
      ExtensionRepository(
        name: 'Store ativa',
        state: ExtensionRepositoryState.active,
      ),
    ];
    engine.listExtensionsHandler = () async => const [
      ReadingExtension(
        reference: _TestExtensionReference(4),
        name: 'Extensão entre abas',
        installed: false,
      ),
    ];
    engine.installHandler = (_) => install.future;

    await _pumpExplore(tester, engine);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extensões'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instalar'));
    await tester.pump();
    await tester.tap(find.text('Repositórios'));
    await tester.pump();

    final sync = tester.getSemantics(
      find.bySemanticsLabel('Sincronizar catálogo'),
    );
    expect(sync.hasFlag(SemanticsFlag.isEnabled), isFalse);

    install.complete(
      const ReadingExtension(
        reference: _TestExtensionReference(4),
        name: 'Extensão entre abas',
        installed: true,
      ),
    );
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('extension filter stays visible and consistent across tabs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = _FakeReadingEngine();
    engine.listSourcesHandler = () async => const [_source];
    engine.listStoresHandler = () async => const [
      ExtensionRepository(
        name: 'Store filtro',
        state: ExtensionRepositoryState.active,
      ),
    ];
    engine.listExtensionsHandler = () async => const [
      ReadingExtension(
        reference: _TestExtensionReference(5),
        name: 'Extensão primária',
        installed: false,
      ),
      ReadingExtension(
        reference: _TestExtensionReference(6),
        name: 'Extensão secundária',
        installed: false,
      ),
    ];

    await _pumpExplore(tester, engine);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extensões'));
    await tester.pumpAndSettle();
    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          (widget.decoration?.hintText?.startsWith('Filtrar extensões') ??
              false),
    );
    await tester.enterText(search, 'secundária');
    await tester.pump();
    expect(find.text('Extensão primária'), findsNothing);
    expect(find.text('Extensão secundária'), findsOneWidget);

    await tester.tap(find.text('Repositórios'));
    await tester.pump();
    await tester.tap(find.text('Extensões'));
    await tester.pump();

    final restoredField = tester.widget<TextField>(search);
    expect(restoredField.controller?.text, 'secundária');
    expect(find.text('Extensão primária'), findsNothing);
    expect(find.text('Extensão secundária'), findsOneWidget);

    final replacementEngine = _FakeReadingEngine();
    replacementEngine.listSourcesHandler = () async => const [_source];
    replacementEngine.listStoresHandler = () async => const [];
    replacementEngine.listExtensionsHandler = () async => const [
      ReadingExtension(
        reference: _TestExtensionReference(7),
        name: 'Extensão substituta',
        installed: false,
      ),
    ];
    await _pumpExplore(tester, replacementEngine);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(search).controller?.text, isEmpty);
    expect(find.text('Extensão substituta'), findsOneWidget);
  });

  testWidgets('extension reload and install are mutually exclusive', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final install = Completer<ReadingExtension>();
    final reload = Completer<List<ReadingExtension>>();
    final engine = _FakeReadingEngine();
    engine.listStoresHandler = () async => const [];
    engine.listExtensionsHandler = () {
      if (engine.listExtensionsCalls == 1) {
        return Future.value(const [
          ReadingExtension(
            reference: _TestExtensionReference(8),
            name: 'Extensão mutex',
            installed: false,
          ),
          ReadingExtension(
            reference: _TestExtensionReference(9),
            name: 'Extensão secundária',
            installed: false,
          ),
        ]);
      }
      return reload.future;
    };
    engine.installHandler = (_) => install.future;

    await _pumpExtensions(tester, engine);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instalar').first);
    await tester.pump();

    final reloadWhileInstalling = tester.getSemantics(
      find.bySemanticsLabel('Recarregar'),
    );
    expect(reloadWhileInstalling.hasFlag(SemanticsFlag.isEnabled), isFalse);
    expect(engine.listExtensionsCalls, 1);

    install.complete(
      const ReadingExtension(
        reference: _TestExtensionReference(8),
        name: 'Extensão mutex',
        installed: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Recarregar'));
    await tester.pump();

    final installWhileReloading = tester.getSemantics(
      find.bySemanticsLabel('Instalar'),
    );
    expect(installWhileReloading.hasFlag(SemanticsFlag.isEnabled), isFalse);

    reload.complete(const [
      ReadingExtension(
        reference: _TestExtensionReference(8),
        name: 'Extensão mutex',
        installed: true,
      ),
      ReadingExtension(
        reference: _TestExtensionReference(9),
        name: 'Extensão secundária',
        installed: false,
      ),
    ]);
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('store failure does not block or leak into extension catalog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final stores = Completer<List<ExtensionRepository>>();
    final engine = _FakeReadingEngine();
    engine.listStoresHandler = () => stores.future;
    engine.listExtensionsHandler = () async => const [
      ReadingExtension(
        reference: _TestExtensionReference(10),
        name: 'Catálogo pronto',
        installed: false,
      ),
    ];

    await _pumpExtensions(tester, engine);
    await tester.pump();
    await tester.pump();
    expect(find.text('Catálogo pronto'), findsOneWidget);

    stores.completeError(_sanitizedFailure('falha isolada de stores'));
    await tester.pumpAndSettle();
    expect(find.textContaining('falha isolada de stores'), findsNothing);

    await _pumpExtensions(tester, engine, repositoriesOnly: true);
    await tester.pump();
    expect(find.textContaining('falha isolada de stores'), findsOneWidget);
  });

  testWidgets(
    'repository skeleton is labeled and settles with reduced motion',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final stores = Completer<List<ExtensionRepository>>();
      final engine = _FakeReadingEngine();
      engine.listStoresHandler = () => stores.future;
      engine.listExtensionsHandler = () async => const [];

      await tester.pumpWidget(
        MaterialApp(
          theme: buildYomuTheme(),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: ExtensionsScreen(
                gateway: engine,
                engineReady: true,
                repositoriesOnly: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final loading = tester.getSemantics(
        find.bySemanticsLabel('Carregando repositórios'),
      );
      expect(loading.hasFlag(SemanticsFlag.isLiveRegion), isTrue);

      stores.complete(const []);
      await tester.pumpAndSettle();
      semantics.dispose();
    },
  );

  testWidgets('multiple stores expose one factual aggregate sync action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = _FakeReadingEngine();
    engine.listStoresHandler = () async => const [
      ExtensionRepository(
        name: 'Store A',
        state: ExtensionRepositoryState.active,
      ),
      ExtensionRepository(
        name: 'Store B',
        state: ExtensionRepositoryState.active,
      ),
    ];
    engine.listExtensionsHandler = () async => const [
      ReadingExtension(
        reference: _TestExtensionReference(11),
        name: 'Extensão A',
        installed: false,
      ),
      ReadingExtension(
        reference: _TestExtensionReference(12),
        name: 'Extensão B',
        installed: false,
      ),
    ];

    await _pumpExtensions(tester, engine, repositoriesOnly: true);
    await tester.pumpAndSettle();

    expect(find.text('Store A'), findsOneWidget);
    expect(find.text('Store B'), findsOneWidget);
    expect(find.text('Catálogo agregado · 2 extensões'), findsOneWidget);
    expect(find.bySemanticsLabel('Sincronizar catálogo'), findsOneWidget);
    expect(
      find.text('repositório ativo no catálogo agregado'),
      findsNWidgets(2),
    );
    semantics.dispose();
  });

  testWidgets('repository catalog owns loading and error independently', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final extensions = Completer<List<ReadingExtension>>();
    final engine = _FakeReadingEngine();
    engine.listStoresHandler = () async => const [
      ExtensionRepository(
        name: 'Store pronta',
        state: ExtensionRepositoryState.active,
      ),
    ];
    engine.listExtensionsHandler = () => extensions.future;

    await _pumpExtensions(tester, engine, repositoriesOnly: true);
    await tester.pump();
    await tester.pump();

    expect(find.text('Store pronta'), findsOneWidget);
    expect(find.text('Carregando catálogo agregado…'), findsOneWidget);
    expect(find.text('Catálogo agregado · 0 extensões'), findsNothing);

    extensions.completeError(_sanitizedFailure('falha no catálogo agregado'));
    await tester.pumpAndSettle();

    expect(find.text('Store pronta'), findsOneWidget);
    expect(find.text('Catálogo agregado indisponível'), findsOneWidget);
    expect(find.textContaining('falha no catálogo agregado'), findsOneWidget);
    final error = tester.getSemantics(
      find.bySemanticsLabel(RegExp('falha no catálogo agregado')),
    );
    expect(error.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
    semantics.dispose();
  });

  testWidgets(
    'gateway replacement rejects stale stores and catalog generations',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final oldStores = Completer<List<ExtensionRepository>>();
      final oldExtensions = Completer<List<ReadingExtension>>();
      final oldEngine = _FakeReadingEngine();
      oldEngine.listStoresHandler = () => oldStores.future;
      oldEngine.listExtensionsHandler = () => oldExtensions.future;
      final newEngine = _FakeReadingEngine();
      newEngine.listStoresHandler = () async => const [
        ExtensionRepository(
          name: 'Store nova',
          state: ExtensionRepositoryState.active,
        ),
      ];
      newEngine.listExtensionsHandler = () async => const [
        ReadingExtension(
          reference: _TestExtensionReference(13),
          name: 'Extensão nova',
          installed: false,
        ),
      ];

      await _pumpExtensions(tester, oldEngine);
      await tester.pump();
      await _pumpExtensions(tester, newEngine);
      await tester.pumpAndSettle();
      expect(find.text('Extensão nova'), findsOneWidget);

      oldStores.complete(const [
        ExtensionRepository(
          name: 'Store velha',
          state: ExtensionRepositoryState.active,
        ),
      ]);
      oldExtensions.complete(const [
        ReadingExtension(
          reference: _TestExtensionReference(14),
          name: 'Extensão velha',
          installed: false,
        ),
      ]);
      await tester.pump();
      expect(find.text('Extensão nova'), findsOneWidget);
      expect(find.text('Extensão velha'), findsNothing);

      await _pumpExtensions(tester, newEngine, repositoriesOnly: true);
      await tester.pump();
      expect(find.text('Store nova'), findsOneWidget);
      expect(find.text('Store velha'), findsNothing);
    },
  );

  testWidgets('promoted Explore controls expose semantics and 44px targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = _FakeReadingEngine();
    engine.listSourcesHandler = () async => const [_source];
    engine.fetchMangaHandler = (call) async =>
        CatalogPage(items: const [], hasNextPage: false, page: call.page);
    engine.listStoresHandler = () async => const [];
    engine.listExtensionsHandler = () async => const [];

    await _pumpExplore(tester, engine);
    await tester.pumpAndSettle();

    final sourcesTab = find.widgetWithText(TextButton, 'Fontes');
    expect(tester.getSize(sourcesTab).height, greaterThanOrEqualTo(44));
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Fontes'))
          .hasFlag(SemanticsFlag.isSelected),
      isTrue,
    );

    await tester.tap(find.text('MangaDex'));
    await tester.pumpAndSettle();
    final popularChip = find.widgetWithText(TextButton, 'Popular');
    expect(tester.getSize(popularChip).height, greaterThanOrEqualTo(44));
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Popular'))
          .hasFlag(SemanticsFlag.isSelected),
      isTrue,
    );
    final catalogSearch = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Buscar nesta fonte…',
    );
    expect(tester.getSize(catalogSearch).height, greaterThanOrEqualTo(44));

    await tester.tap(find.text('Extensões'));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Extensões'))
          .hasFlag(SemanticsFlag.isSelected),
      isTrue,
    );
    final extensionSearch = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          (widget.decoration?.hintText?.startsWith('Filtrar extensões') ??
              false),
    );
    expect(tester.getSize(extensionSearch).height, greaterThanOrEqualTo(44));
    final reload = find.bySemanticsLabel('Recarregar');
    expect(tester.getSize(reload).height, greaterThanOrEqualTo(44));
    semantics.dispose();
  });

  testWidgets('extension install exposes a live busy state', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final install = Completer<ReadingExtension>();
    final engine = _FakeReadingEngine();
    engine.listSourcesHandler = () async => const [_source];
    engine.listStoresHandler = () async => const [];
    engine.listExtensionsHandler = () async => const [
      ReadingExtension(
        reference: _TestExtensionReference(15),
        name: 'Extensão ocupada',
        installed: false,
      ),
    ];
    engine.installHandler = (_) => install.future;

    await _pumpExplore(tester, engine);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extensões'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instalar'));
    await tester.pump();

    final busy = tester.getSemantics(
      find.bySemanticsLabel('Instalando Extensão ocupada'),
    );
    expect(busy.hasFlag(SemanticsFlag.isLiveRegion), isTrue);

    install.complete(
      const ReadingExtension(
        reference: _TestExtensionReference(15),
        name: 'Extensão ocupada',
        installed: true,
      ),
    );
    await tester.pumpAndSettle();
    semantics.dispose();
  });
}
