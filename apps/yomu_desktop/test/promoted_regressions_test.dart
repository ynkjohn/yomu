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
import 'package:yomu_desktop/services/maya_credential_store.dart';
import 'package:yomu_desktop/services/maya_provider_controller.dart';
import 'package:yomu_storage/yomu_storage.dart';
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
    final library = _FakeLibraryGateway(
      library: const [
        LibraryManga(id: 1, title: 'Frieren', inLibrary: true),
        LibraryManga(id: 2, title: 'Vagabond', inLibrary: true),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(
          body: LibraryScreen(
            library: library,
            media: const _EmptyMediaGateway(),
            readiness: const EngineReadinessSnapshot(
              state: EngineReadinessState.ready,
            ),
            onOpenManga: (_) async {},
            onContinueReading: (_) async {},
          ),
        ),
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
            library: null,
            media: const _EmptyMediaGateway(),
            engineReady: false,
            onNavigate: (value) => destination = value,
            onOpenManga: (_) async {},
            onContinueReading: (_) async {},
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
    final library = _FakeLibraryGateway();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(
          body: HomeScreen(
            library: library,
            media: const _EmptyMediaGateway(),
            engineReady: true,
            onNavigate: (value) => destination = value,
            onOpenManga: (_) async {},
            onContinueReading: (_) async {},
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
    final details = _FakeMangaDetailsGateway(
      manga: const ReadingMangaDetails(id: 7, title: 'Frieren'),
    );
    final reader = _FakeReaderGateway(
      chapters: const [
        ReadingChapter(
          id: 70,
          name: 'Capítulo 1',
          chapterNumber: 1,
          readingOrder: 1,
          mangaId: 7,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: MangaDetailScreen(
          details: details,
          reader: reader,
          catalog: const _EmptyCatalogGateway(),
          media: const _EmptyMediaGateway(),
          downloads: _FakeDownloadsGateway(
            snapshot: DownloadsSnapshot(
              managerState: DownloadManagerState.paused,
              queue: const [],
            ),
          ),
          mangaId: 7,
          onOpenChapter:
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
    final library = _FakeLibraryGateway(
      library: const [
        LibraryManga(
          id: 1,
          title: 'Leitura em andamento',
          inLibrary: true,
          lastReadChapter: LibraryResumePoint(
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
          body: HomeScreen(
            library: library,
            media: const _EmptyMediaGateway(),
            engineReady: true,
            onNavigate: (_) {},
            onOpenManga: (_) async {},
            onContinueReading: (_) async {},
          ),
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
    final library = _FakeLibraryGateway(
      library: const [
        LibraryManga(id: 1, title: 'Na biblioteca', inLibrary: true),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(
          body: HomeScreen(
            library: library,
            media: const _EmptyMediaGateway(),
            engineReady: true,
            onNavigate: (value) => destination = value,
            onOpenManga: (_) async {},
            onContinueReading: (_) async {},
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
    final downloads = _FakeDownloadsGateway(
      snapshot: DownloadsSnapshot(
        managerState: DownloadManagerState.paused,
        queue: const [EngineDownloadItem(state: DownloadItemState.queued)],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(
          body: DownloadsScreen(downloads: downloads, engineReady: true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Limpar fila'));
    await tester.pump();
    expect(downloads.clearCalls, 0);
    expect(find.text('Limpar downloads?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Limpar fila'));
    await tester.pump();
    await tester.pump();

    expect(downloads.clearCalls, 1);
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

  testWidgets('Maya keeps local chat usable while the engine is offline', (
    tester,
  ) async {
    await setDesktopSurface(tester);
    final maya = MayaService(
      store: MayaStore.inMemory(),
      libraryPort: _NoopMayaPort(),
    );
    addMayaTearDown(tester, maya);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(body: MayaScreen(service: maya, engineReady: false)),
      ),
    );
    await tester.pump();

    final composer = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Pergunte à Maya…',
    );
    expect(composer, findsOneWidget);
    expect(tester.widget<TextField>(composer).enabled, isTrue);
    expect(find.text('Biblioteca · offline'), findsOneWidget);

    await tester.enterText(composer, 'ajuda');
    await tester.tap(find.bySemanticsLabel('Enviar mensagem'));
    await maya.drain();
    await tester.pump();

    expect(find.text('ajuda'), findsOneWidget);
    expect(
      find.textContaining('Sou a Maya (modo local). Posso:'),
      findsOneWidget,
    );
    expect(maya.messages, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Maya provider dialog protects API key and separates cloud consent',
    (tester) async {
      await setDesktopSurface(tester);
      final fixture = (await tester.runAsync(_MayaProviderUiFixture.create))!;
      addTearDown(() async {
        await tester.runAsync(fixture.close);
      });
      final provider = (await tester.runAsync(fixture.openController))!;
      final maya = MayaService(
        store: MayaStore.inMemory(),
        libraryPort: _NoopMayaPort(),
      );
      addMayaTearDown(tester, maya);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildYomuTheme(),
          home: Scaffold(
            body: MayaScreen(
              service: maya,
              engineReady: false,
              providerController: provider,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('IA · não configurada'), findsOneWidget);
      await tester.tap(find.byTooltip('Configurar IA da Maya'));
      await tester.pumpAndSettle();

      expect(find.text('IA da Maya'), findsOneWidget);
      expect(find.text('Limpar credenciais cloud'), findsOneWidget);
      expect(
        find.textContaining('histórico e biblioteca exigem consentimentos'),
        findsOneWidget,
      );
      final modelField = _mayaTextFieldWithHint(
        'ID exato do modelo do provider',
      );
      final apiKeyField = _mayaTextFieldWithHint('Cole uma nova chave');
      expect(modelField, findsOneWidget);
      expect(apiKeyField, findsOneWidget);
      final initialApiKey = tester.widget<TextField>(apiKeyField);
      expect(initialApiKey.obscureText, isTrue);
      expect(initialApiKey.enableInteractiveSelection, isFalse);
      expect(initialApiKey.controller?.text, isEmpty);

      const secret = 'sk-ui-secret-never-render';
      await tester.enterText(modelField, 'gpt-ui-test');
      await tester.enterText(apiKeyField, secret);
      await tester.tap(find.widgetWithText(FilledButton, 'Salvar e ativar'));
      await tester.pump();

      expect(
        find.text('Confirme o envio da mensagem atual antes de ativar a IA.'),
        findsOneWidget,
      );
      expect(provider.settings, isNull);
      expect(
        _mayaCheckbox(tester, 'Compartilhar histórico recente').value,
        isFalse,
      );
      expect(
        _mayaCheckbox(tester, 'Compartilhar contexto da biblioteca').value,
        isFalse,
      );

      await tester.tap(
        _mayaCheckboxFinder('Autorizo enviar a mensagem atual a este provider'),
      );
      await tester.tap(_mayaCheckboxFinder('Compartilhar histórico recente'));
      await tester.pump();

      expect(
        _mayaCheckbox(
          tester,
          'Autorizo enviar a mensagem atual a este provider',
        ).value,
        isTrue,
      );
      expect(
        _mayaCheckbox(tester, 'Compartilhar histórico recente').value,
        isTrue,
      );
      expect(
        _mayaCheckbox(tester, 'Compartilhar contexto da biblioteca').value,
        isFalse,
      );

      await _invokeAsyncFilledButton(
        tester,
        find.widgetWithText(FilledButton, 'Salvar e ativar'),
      );
      await tester.pumpAndSettle();

      expect(provider.status, MayaProviderControllerStatus.cloudReady);
      expect(provider.settings?.providerId, 'openai');
      expect(provider.settings?.modelId, 'gpt-ui-test');
      expect(provider.settings?.shareRecentHistory, isTrue);
      expect(provider.settings?.shareLibraryContext, isFalse);
      expect(find.text('OpenAI · gpt-ui-test'), findsOneWidget);
      expect(find.textContaining(secret), findsNothing);

      await tester.tap(find.byTooltip('Configurar IA da Maya'));
      await tester.pumpAndSettle();

      final reopenedApiKey = tester.widget<TextField>(
        _mayaTextFieldWithHint('Cole uma nova chave'),
      );
      expect(reopenedApiKey.obscureText, isTrue);
      expect(reopenedApiKey.enableInteractiveSelection, isFalse);
      expect(reopenedApiKey.controller?.text, isEmpty);
      expect(find.textContaining(secret), findsNothing);
      expect(
        _mayaCheckbox(
          tester,
          'Autorizo enviar a mensagem atual a este provider',
        ).value,
        isTrue,
      );
      expect(
        _mayaCheckbox(tester, 'Compartilhar histórico recente').value,
        isTrue,
      );
      expect(
        _mayaCheckbox(tester, 'Compartilhar contexto da biblioteca').value,
        isFalse,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Maya custom provider shows exact destination and optional key', (
    tester,
  ) async {
    await setDesktopSurface(tester);
    final fixture = (await tester.runAsync(_MayaProviderUiFixture.create))!;
    addTearDown(() async {
      await tester.runAsync(fixture.close);
    });
    final provider = (await tester.runAsync(fixture.openController))!;
    final maya = MayaService(
      store: MayaStore.inMemory(),
      libraryPort: _NoopMayaPort(),
    );
    addMayaTearDown(tester, maya);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(
          body: MayaScreen(
            service: maya,
            engineReady: false,
            providerController: provider,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Configurar IA da Maya'));
    await tester.pumpAndSettle();

    final providerField = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    providerField.onChanged!('openai-compatible');
    await tester.pump();

    final endpointField = _mayaTextFieldWithHint(
      'https://api.exemplo.com/v1/chat/completions',
    );
    final modelField = _mayaTextFieldWithHint('ID exato do modelo do provider');
    expect(endpointField, findsOneWidget);
    expect(_mayaCheckbox(tester, 'Usar API key').value, isTrue);

    const endpoint = 'http://127.0.0.1:1234/v1/chat/completions';
    await tester.enterText(endpointField, endpoint);
    await tester.enterText(modelField, 'local-compatible');
    await tester.tap(_mayaCheckboxFinder('Usar API key'));
    await tester.pump();

    expect(_mayaCheckbox(tester, 'Usar API key').value, isFalse);
    expect(_mayaTextFieldWithHint('Cole uma nova chave'), findsNothing);
    expect(find.text('Destino exato: $endpoint'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Salvar e ativar'));
    await tester.pump();
    expect(
      find.text('Confirme o envio da mensagem atual antes de ativar a IA.'),
      findsOneWidget,
    );

    await tester.tap(
      _mayaCheckboxFinder(
        'Autorizo enviar a mensagem atual para este endpoint',
      ),
    );
    await _invokeAsyncFilledButton(
      tester,
      find.widgetWithText(FilledButton, 'Salvar e ativar'),
    );
    await tester.pumpAndSettle();

    expect(provider.status, MayaProviderControllerStatus.cloudReady);
    expect(provider.settings?.providerId, 'openai-compatible');
    expect(provider.customSettings?.endpointUrl, endpoint);
    expect(provider.customSettings?.useApiKey, isFalse);
    expect(find.text('OpenAI-compatible · local-compatible'), findsOneWidget);
  });

  testWidgets('Maya exposes a sanitized degraded provider status', (
    tester,
  ) async {
    await setDesktopSurface(tester);
    final fixture = (await tester.runAsync(_MayaProviderUiFixture.create))!;
    addTearDown(() async {
      await tester.runAsync(fixture.close);
    });
    await tester.runAsync(fixture.persistCloudWithoutCredential);
    final provider = (await tester.runAsync(fixture.openController))!;
    final maya = MayaService(
      store: MayaStore.inMemory(),
      libraryPort: _NoopMayaPort(),
    );
    addMayaTearDown(tester, maya);

    expect(provider.status, MayaProviderControllerStatus.missingCredential);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(
          body: MayaScreen(
            service: maya,
            engineReady: false,
            providerController: provider,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('OpenAI · chave ausente'), findsOneWidget);
    expect(
      find.text('IA por provider · ações só após confirmação'),
      findsOneWidget,
    );
    expect(find.textContaining('credencial'), findsNothing);
    expect(
      tester
          .widget<TextField>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.hintText == 'Pergunte à Maya…',
            ),
          )
          .enabled,
      isTrue,
    );
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
    expect(
      store.proposalById('p-pending')?.status,
      ActionProposalStatus.pending,
    );
    expect(port.downloads, isEmpty);

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

class _FakeDownloadsGateway implements DownloadsGateway {
  _FakeDownloadsGateway({required this.snapshot});

  DownloadsSnapshot snapshot;
  int clearCalls = 0;

  @override
  Future<DownloadsSnapshot> getStatus() async => snapshot;

  @override
  Future<void> clear() async {
    clearCalls++;
    snapshot = DownloadsSnapshot(
      managerState: DownloadManagerState.paused,
      queue: const [],
    );
  }

  @override
  Future<void> dequeueChapters(List<int> chapterIds) async {}

  @override
  Future<void> enqueueChapters(List<int> chapterIds) async {}

  @override
  Future<bool> hasActivity() async => snapshot.hasActivity;

  @override
  Future<DownloadPauseAck> pause() async => const DownloadPauseAck(
    managerState: DownloadManagerState.paused,
    acknowledged: true,
  );

  @override
  Future<DownloadPauseAck> pauseAndAwaitAck({required Duration timeout}) =>
      pause();

  @override
  Future<void> resume() async {}
}

class _FakeLibraryGateway implements LibraryGateway {
  const _FakeLibraryGateway({this.library = const []});

  final List<LibraryManga> library;

  @override
  Future<List<LibraryManga>> listLibrary() async => library;

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {}
}

class _FakeMangaDetailsGateway implements MangaDetailsGateway {
  const _FakeMangaDetailsGateway({required this.manga});

  final ReadingMangaDetails manga;

  @override
  Future<ReadingMangaDetails> getManga(int mangaId) async => manga;

  @override
  Future<ReadingMangaDetails> setInLibrary(int mangaId, bool inLibrary) async =>
      ReadingMangaDetails(
        id: manga.id,
        title: manga.title,
        description: manga.description,
        author: manga.author,
        artist: manga.artist,
        status: manga.status,
        thumbnail: manga.thumbnail,
        sourceId: manga.sourceId,
        inLibrary: inLibrary,
      );
}

class _FakeReaderGateway implements ReaderGateway {
  const _FakeReaderGateway({this.chapters = const []});

  final List<ReadingChapter> chapters;

  @override
  Future<ReadingChapter?> getChapter(int chapterId) async {
    for (final chapter in chapters) {
      if (chapter.id == chapterId) return chapter;
    }
    return null;
  }

  @override
  Future<ReadingChapterPages> getPages(int chapterId) async =>
      ReadingChapterPages(chapterId: chapterId, pages: const []);

  @override
  Future<List<ReadingChapter>> listChapters(int mangaId) async => chapters;

  @override
  Future<List<ReadingChapter>> refreshChapters(int mangaId) async => chapters;
}

class _EmptyCatalogGateway implements CatalogGateway {
  const _EmptyCatalogGateway();

  @override
  Future<CatalogPage> latest({required String sourceId, int page = 1}) async =>
      CatalogPage(items: const [], page: page, hasNextPage: false);

  @override
  Future<List<CatalogSource>> listSources() async => const [];

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

class _EmptyMediaGateway implements EngineMediaGateway {
  const _EmptyMediaGateway();

  @override
  Future<MediaPayload> fetch(
    MediaReference reference, {
    required int maxBytes,
  }) async => MediaPayload(bytes: const []);
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

Finder _mayaTextFieldWithHint(String hint) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == hint,
);

Finder _mayaCheckboxFinder(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byType(CheckboxListTile),
);

CheckboxListTile _mayaCheckbox(WidgetTester tester, String label) =>
    tester.widget<CheckboxListTile>(_mayaCheckboxFinder(label));

Future<void> _invokeAsyncFilledButton(
  WidgetTester tester,
  Finder finder,
) async {
  final callback = tester.widget<FilledButton>(finder).onPressed;
  if (callback == null) {
    throw StateError('Expected an enabled async button.');
  }
  await tester.runAsync(() async {
    final result = Function.apply(callback, const <Object?>[]);
    if (result is! Future<void>) {
      throw StateError('Expected the button callback to return Future<void>.');
    }
    await result;
  });
}

final class _MayaProviderUiFixture {
  _MayaProviderUiFixture._({
    required this.root,
    required this.database,
    required this.credentials,
  });

  static Future<_MayaProviderUiFixture> create() async {
    final root = Directory.systemTemp.createTempSync(
      'yomu-promoted-provider-ui-',
    );
    final database = await YomuDatabase.openForTest(
      root,
      useProcessLock: false,
    );
    return _MayaProviderUiFixture._(
      root: root,
      database: database,
      credentials: FakeMayaCredentialStore(),
    );
  }

  final Directory root;
  final YomuDatabase database;
  final FakeMayaCredentialStore credentials;
  final List<MayaProviderController> _controllers = <MayaProviderController>[];

  Future<MayaProviderController> openController() async {
    final controller = await MayaProviderController.open(
      database: database,
      credentialStore: credentials,
      adapterFactory: _createAdapter,
      clock: () => DateTime.utc(2026, 7, 16, 18),
    );
    _controllers.add(controller);
    return controller;
  }

  Future<void> persistCloudWithoutCredential() {
    return database.setMayaProviderSettings(
      MayaProviderSettings.cloud(
        providerId: 'openai',
        modelPolicy: MayaProviderModelPolicy.explicit,
        modelId: 'gpt-degraded-test',
        shareRecentHistory: false,
        shareLibraryContext: false,
        consentVersion: kCurrentMayaProviderConsentVersion,
        consentedAtMs: 1,
        updatedAtMs: 1,
      ),
    );
  }

  Future<MayaLlmProvider> _createAdapter({
    required MayaProviderAdapterSettings settings,
    required MayaProviderCredentialReader readCredential,
  }) async {
    return _MayaProviderUiAdapter();
  }

  Future<void> close() async {
    for (final controller in _controllers.reversed) {
      await controller.close();
    }
    await database.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

final class _MayaProviderUiAdapter implements MayaLlmProvider {
  @override
  MayaLlmContextPolicy get contextPolicy =>
      const MayaLlmContextPolicy.disabled();

  @override
  Future<MayaLlmResponse> complete(MayaLlmRequest request) async =>
      MayaLlmResponse(text: 'Resposta de teste do provider.');

  @override
  Future<void> close() async {}
}
