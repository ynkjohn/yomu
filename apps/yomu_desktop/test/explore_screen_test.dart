import 'dart:async';
import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_desktop/screens/explore_screen.dart';
import 'package:yomu_desktop/screens/extensions_screen.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

class _FetchCall {
  const _FetchCall({
    required this.sourceId,
    required this.type,
    required this.query,
    required this.page,
  });

  final String sourceId;
  final SourceMangaFetchType type;
  final String? query;
  final int page;
}

class _FakeSuwayomiApi extends SuwayomiApi {
  _FakeSuwayomiApi() : super(SuwayomiClient(baseUrl: 'http://127.0.0.1:14567'));

  Future<List<SourceInfo>> Function()? listSourcesHandler;
  Future<SourceMangaPage> Function(_FetchCall call)? fetchMangaHandler;
  Future<List<ExtensionStoreInfo>> Function()? listStoresHandler;
  Future<List<ExtensionInfo>> Function()? listExtensionsHandler;
  Future<ExtensionInfo> Function(String pkg)? installHandler;

  int listSourcesCalls = 0;
  int listExtensionsCalls = 0;
  final List<_FetchCall> fetchCalls = [];

  @override
  Future<List<SourceInfo>> listSources() {
    listSourcesCalls++;
    return listSourcesHandler?.call() ?? Future.value(const []);
  }

  @override
  Future<SourceMangaPage> fetchSourceManga({
    required String sourceId,
    required SourceMangaFetchType type,
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
          SourceMangaPage(items: const [], hasNextPage: false, page: page),
        );
  }

  @override
  Future<List<ExtensionStoreInfo>> listExtensionStores() {
    return listStoresHandler?.call() ?? Future.value(const []);
  }

  @override
  Future<List<ExtensionInfo>> listExtensions({String? query}) {
    listExtensionsCalls++;
    return listExtensionsHandler?.call() ?? Future.value(const []);
  }

  @override
  Future<ExtensionInfo> installExtension(String pkgName) {
    return installHandler?.call(pkgName) ??
        Future.error(StateError('unexpected install: $pkgName'));
  }
}

const _source = SourceInfo(id: 'source-1', name: 'MangaDex', lang: 'en');

Future<void> _pumpExplore(
  WidgetTester tester,
  SuwayomiApi api, {
  bool engineReady = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildYomuTheme(),
      home: Scaffold(
        body: ExploreScreen(api: api, engineReady: engineReady),
      ),
    ),
  );
}

Future<void> _pumpExtensions(
  WidgetTester tester,
  SuwayomiApi api, {
  bool repositoriesOnly = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildYomuTheme(),
      home: Scaffold(
        body: ExtensionsScreen(
          api: api,
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
    final sources = Completer<List<SourceInfo>>();
    final popular = Completer<SourceMangaPage>();
    final search = Completer<SourceMangaPage>();
    final api = _FakeSuwayomiApi();
    api.listSourcesHandler = () => sources.future;
    api.fetchMangaHandler = (call) => switch (call.type) {
      SourceMangaFetchType.search => search.future,
      _ => popular.future,
    };

    await _pumpExplore(tester, api);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    sources.complete(const [_source]);
    await tester.pumpAndSettle();
    expect(find.text('MangaDex'), findsOneWidget);

    await tester.tap(find.text('MangaDex'));
    await tester.pump();
    expect(api.fetchCalls.single.type, SourceMangaFetchType.popular);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Carregando catálogo'), findsOneWidget);
    expect(find.bySemanticsLabel('Carregando obras'), findsNothing);

    popular.complete(
      const SourceMangaPage(
        items: [MangaSummary(id: 1, title: 'One Piece')],
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
    expect(api.fetchCalls.last.type, SourceMangaFetchType.search);
    expect(api.fetchCalls.last.query, 'Berserk');

    search.complete(
      const SourceMangaPage(
        items: [MangaSummary(id: 2, title: 'Berserk')],
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
    final source = SourceInfo(id: 'source-long', name: longName, lang: 'pt');
    final api = _FakeSuwayomiApi();
    api.listSourcesHandler = () async => [source];
    api.fetchMangaHandler = (call) async =>
        SourceMangaPage(items: const [], hasNextPage: false, page: call.page);

    await _pumpExplore(tester, api);
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
    final pageTwo = Completer<SourceMangaPage>();
    final api = _FakeSuwayomiApi();
    api.listSourcesHandler = () async => const [_source];
    api.fetchMangaHandler = (call) {
      if (call.page == 1) {
        return Future.value(
          const SourceMangaPage(
            items: [MangaSummary(id: 1, title: 'One Piece')],
            hasNextPage: true,
            page: 1,
          ),
        );
      }
      return pageTwo.future;
    };

    await _pumpExplore(tester, api);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MangaDex'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Carregar mais'));
    await tester.pump();
    expect(find.text('Carregando…'), findsOneWidget);

    pageTwo.completeError(StateError('falha controlada na página 2'));
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
    final api = _FakeSuwayomiApi();
    api.listSourcesHandler = () async => const [_source];
    api.fetchMangaHandler = (call) async => SourceMangaPage(
      items: [
        MangaSummary(
          id: call.page,
          title: call.page == 1 ? 'Primeira' : 'Segunda',
        ),
      ],
      hasNextPage: call.page == 1,
      page: call.page,
    );

    await _pumpExplore(tester, api);
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

    expect(api.fetchCalls, hasLength(2));
    expect(api.fetchCalls.last.page, 2);
    expect(api.fetchCalls.last.type, SourceMangaFetchType.popular);
    expect(api.fetchCalls.last.query, isNull);
    expect(find.text('Segunda'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('engine loss rejects stale catalog response and resets source', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final catalog = Completer<SourceMangaPage>();
    final api = _FakeSuwayomiApi();
    api.listSourcesHandler = () async => const [_source];
    api.fetchMangaHandler = (_) => catalog.future;

    await _pumpExplore(tester, api);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MangaDex'));
    await tester.pump();

    await _pumpExplore(tester, api, engineReady: false);
    await tester.pump();
    expect(find.text('Fontes indisponíveis'), findsOneWidget);

    catalog.complete(
      const SourceMangaPage(
        items: [MangaSummary(id: 99, title: 'Resposta obsoleta')],
        hasNextPage: false,
        page: 1,
      ),
    );
    await tester.pump();

    await _pumpExplore(tester, api);
    await tester.pumpAndSettle();
    expect(find.text('MangaDex'), findsOneWidget);
    expect(find.text('Resposta obsoleta'), findsNothing);
    expect(api.listSourcesCalls, 2);
  });

  testWidgets('successful extension install refreshes Explore sources', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeSuwayomiApi();
    api.listStoresHandler = () async => const [];
    api.listExtensionsHandler = () async => const [
      ExtensionInfo(
        pkgName: 'extension.test',
        name: 'Extensão Teste',
        isInstalled: false,
        lang: 'pt-BR',
      ),
    ];
    api.installHandler = (pkg) async => ExtensionInfo(
      pkgName: pkg,
      name: 'Extensão Teste',
      isInstalled: true,
      lang: 'pt-BR',
    );

    api.listSourcesHandler = () async => api.listSourcesCalls <= 1
        ? const [_source]
        : const [
            _source,
            SourceInfo(
              id: 'source-2',
              name: 'Fonte recém-instalada',
              lang: 'pt',
            ),
          ];

    await _pumpExplore(tester, api);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extensões'));
    await tester.pumpAndSettle();
    expect(find.text('Extensão Teste'), findsOneWidget);

    await tester.tap(find.text('Instalar'));
    await tester.pumpAndSettle();
    expect(api.listSourcesCalls, 2);

    await tester.tap(find.text('Fontes'));
    await tester.pumpAndSettle();
    expect(find.text('Fonte recém-instalada'), findsOneWidget);
  });

  testWidgets('install completion refreshes sources after leaving the tab', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final install = Completer<ExtensionInfo>();
    final api = _FakeSuwayomiApi();
    api.listStoresHandler = () async => const [];
    api.listExtensionsHandler = () async => const [
      ExtensionInfo(
        pkgName: 'extension.late',
        name: 'Extensão tardia',
        isInstalled: false,
      ),
    ];
    api.installHandler = (_) => install.future;
    api.listSourcesHandler = () async => api.listSourcesCalls <= 1
        ? const [_source]
        : const [
            _source,
            SourceInfo(
              id: 'source-late',
              name: 'Fonte após troca de aba',
              lang: 'pt',
            ),
          ];

    await _pumpExplore(tester, api);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extensões'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instalar'));
    await tester.pump();
    await tester.tap(find.text('Fontes'));
    await tester.pump();

    install.complete(
      const ExtensionInfo(
        pkgName: 'extension.late',
        name: 'Extensão tardia',
        isInstalled: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(api.listSourcesCalls, 2);
    expect(find.text('Fonte após troca de aba'), findsOneWidget);
  });

  testWidgets('install reports a source refresh failure', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeSuwayomiApi();
    api.listSourcesHandler = () {
      if (api.listSourcesCalls == 1) return Future.value(const [_source]);
      return Future.error(StateError('falha no refresh de fontes'));
    };
    api.listStoresHandler = () async => const [];
    api.listExtensionsHandler = () async => const [
      ExtensionInfo(
        pkgName: 'extension.refresh-failure',
        name: 'Extensão com refresh falho',
        isInstalled: false,
      ),
    ];
    api.installHandler = (pkg) async => ExtensionInfo(
      pkgName: pkg,
      name: 'Extensão com refresh falho',
      isInstalled: true,
    );

    await _pumpExplore(tester, api);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extensões'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instalar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('fontes não foram atualizadas'), findsOneWidget);
    expect(find.textContaining('falha no refresh de fontes'), findsOneWidget);
  });

  testWidgets('repository actions stay disabled while install is in flight', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final install = Completer<ExtensionInfo>();
    final api = _FakeSuwayomiApi();
    api.listSourcesHandler = () async => const [_source];
    api.listStoresHandler = () async => const [
      ExtensionStoreInfo(
        name: 'Store ativa',
        indexUrl: 'https://store.invalid/index.json',
      ),
    ];
    api.listExtensionsHandler = () async => const [
      ExtensionInfo(
        pkgName: 'extension.cross-tab',
        name: 'Extensão entre abas',
        isInstalled: false,
      ),
    ];
    api.installHandler = (_) => install.future;

    await _pumpExplore(tester, api);
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
      const ExtensionInfo(
        pkgName: 'extension.cross-tab',
        name: 'Extensão entre abas',
        isInstalled: true,
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
    final api = _FakeSuwayomiApi();
    api.listSourcesHandler = () async => const [_source];
    api.listStoresHandler = () async => const [
      ExtensionStoreInfo(
        name: 'Store filtro',
        indexUrl: 'https://filter.invalid/index.json',
      ),
    ];
    api.listExtensionsHandler = () async => const [
      ExtensionInfo(
        pkgName: 'extension.primary',
        name: 'Extensão primária',
        isInstalled: false,
      ),
      ExtensionInfo(
        pkgName: 'extension.secondary',
        name: 'Extensão secundária',
        isInstalled: false,
      ),
    ];

    await _pumpExplore(tester, api);
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

    final replacementApi = _FakeSuwayomiApi();
    replacementApi.listSourcesHandler = () async => const [_source];
    replacementApi.listStoresHandler = () async => const [];
    replacementApi.listExtensionsHandler = () async => const [
      ExtensionInfo(
        pkgName: 'extension.replacement',
        name: 'Extensão substituta',
        isInstalled: false,
      ),
    ];
    await _pumpExplore(tester, replacementApi);
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
    final install = Completer<ExtensionInfo>();
    final reload = Completer<List<ExtensionInfo>>();
    final api = _FakeSuwayomiApi();
    api.listStoresHandler = () async => const [];
    api.listExtensionsHandler = () {
      if (api.listExtensionsCalls == 1) {
        return Future.value(const [
          ExtensionInfo(
            pkgName: 'extension.mutex',
            name: 'Extensão mutex',
            isInstalled: false,
          ),
          ExtensionInfo(
            pkgName: 'extension.other',
            name: 'Extensão secundária',
            isInstalled: false,
          ),
        ]);
      }
      return reload.future;
    };
    api.installHandler = (_) => install.future;

    await _pumpExtensions(tester, api);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Instalar').first);
    await tester.pump();

    final reloadWhileInstalling = tester.getSemantics(
      find.bySemanticsLabel('Recarregar'),
    );
    expect(reloadWhileInstalling.hasFlag(SemanticsFlag.isEnabled), isFalse);
    expect(api.listExtensionsCalls, 1);

    install.complete(
      const ExtensionInfo(
        pkgName: 'extension.mutex',
        name: 'Extensão mutex',
        isInstalled: true,
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
      ExtensionInfo(
        pkgName: 'extension.mutex',
        name: 'Extensão mutex',
        isInstalled: true,
      ),
      ExtensionInfo(
        pkgName: 'extension.other',
        name: 'Extensão secundária',
        isInstalled: false,
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
    final stores = Completer<List<ExtensionStoreInfo>>();
    final api = _FakeSuwayomiApi();
    api.listStoresHandler = () => stores.future;
    api.listExtensionsHandler = () async => const [
      ExtensionInfo(
        pkgName: 'catalog.ready',
        name: 'Catálogo pronto',
        isInstalled: false,
      ),
    ];

    await _pumpExtensions(tester, api);
    await tester.pump();
    await tester.pump();
    expect(find.text('Catálogo pronto'), findsOneWidget);

    stores.completeError(StateError('falha isolada de stores'));
    await tester.pumpAndSettle();
    expect(find.textContaining('falha isolada de stores'), findsNothing);

    await _pumpExtensions(tester, api, repositoriesOnly: true);
    await tester.pump();
    expect(find.textContaining('falha isolada de stores'), findsOneWidget);
  });

  testWidgets(
    'repository skeleton is labeled and settles with reduced motion',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final stores = Completer<List<ExtensionStoreInfo>>();
      final api = _FakeSuwayomiApi();
      api.listStoresHandler = () => stores.future;
      api.listExtensionsHandler = () async => const [];

      await tester.pumpWidget(
        MaterialApp(
          theme: buildYomuTheme(),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: ExtensionsScreen(
                api: api,
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
    final api = _FakeSuwayomiApi();
    api.listStoresHandler = () async => const [
      ExtensionStoreInfo(
        name: 'Store A',
        indexUrl: 'https://a.invalid/index.json',
      ),
      ExtensionStoreInfo(
        name: 'Store B',
        indexUrl: 'https://b.invalid/index.json',
      ),
    ];
    api.listExtensionsHandler = () async => const [
      ExtensionInfo(
        pkgName: 'extension.a',
        name: 'Extensão A',
        isInstalled: false,
      ),
      ExtensionInfo(
        pkgName: 'extension.b',
        name: 'Extensão B',
        isInstalled: false,
      ),
    ];

    await _pumpExtensions(tester, api, repositoriesOnly: true);
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
    final extensions = Completer<List<ExtensionInfo>>();
    final api = _FakeSuwayomiApi();
    api.listStoresHandler = () async => const [
      ExtensionStoreInfo(
        name: 'Store pronta',
        indexUrl: 'https://ready.invalid/index.json',
      ),
    ];
    api.listExtensionsHandler = () => extensions.future;

    await _pumpExtensions(tester, api, repositoriesOnly: true);
    await tester.pump();
    await tester.pump();

    expect(find.text('Store pronta'), findsOneWidget);
    expect(find.text('Carregando catálogo agregado…'), findsOneWidget);
    expect(find.text('Catálogo agregado · 0 extensões'), findsNothing);

    extensions.completeError(StateError('falha no catálogo agregado'));
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

  testWidgets('API replacement rejects stale stores and catalog generations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final oldStores = Completer<List<ExtensionStoreInfo>>();
    final oldExtensions = Completer<List<ExtensionInfo>>();
    final oldApi = _FakeSuwayomiApi();
    oldApi.listStoresHandler = () => oldStores.future;
    oldApi.listExtensionsHandler = () => oldExtensions.future;
    final newApi = _FakeSuwayomiApi();
    newApi.listStoresHandler = () async => const [
      ExtensionStoreInfo(name: 'Store nova', indexUrl: 'https://new.invalid'),
    ];
    newApi.listExtensionsHandler = () async => const [
      ExtensionInfo(
        pkgName: 'new.extension',
        name: 'Extensão nova',
        isInstalled: false,
      ),
    ];

    await _pumpExtensions(tester, oldApi);
    await tester.pump();
    await _pumpExtensions(tester, newApi);
    await tester.pumpAndSettle();
    expect(find.text('Extensão nova'), findsOneWidget);

    oldStores.complete(const [
      ExtensionStoreInfo(name: 'Store velha', indexUrl: 'https://old.invalid'),
    ]);
    oldExtensions.complete(const [
      ExtensionInfo(
        pkgName: 'old.extension',
        name: 'Extensão velha',
        isInstalled: false,
      ),
    ]);
    await tester.pump();
    expect(find.text('Extensão nova'), findsOneWidget);
    expect(find.text('Extensão velha'), findsNothing);

    await _pumpExtensions(tester, newApi, repositoriesOnly: true);
    await tester.pump();
    expect(find.text('Store nova'), findsOneWidget);
    expect(find.text('Store velha'), findsNothing);
  });

  testWidgets('promoted Explore controls expose semantics and 44px targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeSuwayomiApi();
    api.listSourcesHandler = () async => const [_source];
    api.fetchMangaHandler = (call) async =>
        SourceMangaPage(items: const [], hasNextPage: false, page: call.page);
    api.listStoresHandler = () async => const [];
    api.listExtensionsHandler = () async => const [];

    await _pumpExplore(tester, api);
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
    final install = Completer<ExtensionInfo>();
    final api = _FakeSuwayomiApi();
    api.listSourcesHandler = () async => const [_source];
    api.listStoresHandler = () async => const [];
    api.listExtensionsHandler = () async => const [
      ExtensionInfo(
        pkgName: 'extension.busy',
        name: 'Extensão ocupada',
        isInstalled: false,
      ),
    ];
    api.installHandler = (_) => install.future;

    await _pumpExplore(tester, api);
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
      const ExtensionInfo(
        pkgName: 'extension.busy',
        name: 'Extensão ocupada',
        isInstalled: true,
      ),
    );
    await tester.pumpAndSettle();
    semantics.dispose();
  });
}
