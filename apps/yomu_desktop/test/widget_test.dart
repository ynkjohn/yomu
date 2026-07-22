import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_desktop/screens/extensions_screen.dart';
import 'package:yomu_desktop/screens/server_screen.dart';
import 'package:yomu_desktop/shell/home_shell.dart';
import 'package:yomu_ui/yomu_ui.dart';

void main() {
  test('core status never reports active without a bound server', () {
    final unavailable = deriveYomuCoreStatus(
      boundPort: null,
      readiness: const EngineReadinessSnapshot(
        state: EngineReadinessState.ready,
      ),
    );

    expect(unavailable.label, 'Yomu Core indisponível · Motor ready');
    expect(unavailable.color, YomuTokens.danger);

    final available = deriveYomuCoreStatus(
      boundPort: 8787,
      readiness: const EngineReadinessSnapshot(
        state: EngineReadinessState.ready,
      ),
    );
    expect(available.label, 'Yomu Core ativo · :8787');
    expect(available.color, YomuTokens.success);
  });

  testWidgets('ServerScreen shows stopped motor state', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    bool? requestedLanState;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: ServerScreen(
          status: const SuwayomiStatus(
            state: SuwayomiProcessState.stopped,
            message: 'parado',
            version: 'v2.3.2238-r2238',
            baseUrl: 'http://127.0.0.1:14567',
          ),
          yomuPort: 8787,
          managedRootDir: r'C:\tmp\yomu\data\suwayomi',
          onStart: () {},
          onStop: () {},
          onRestart: () {},
          onHealthCheck: () {},
          lanEnabled: false,
          onToggleLan: (value) => requestedLanState = value,
          pairingCode: null,
          pairingExpiresAt: null,
          onStartPairing: () {},
          onCancelPairing: () {},
          lanAddresses: const [],
          sessionCount: 0,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('stopped'), findsOneWidget);
    expect(find.textContaining('127.0.0.1:14567'), findsWidgets);
    expect(find.text('Iniciar'), findsOneWidget);
    expect(find.textContaining('Yomu HTTP'), findsOneWidget);
    expect(find.textContaining('Permitir acesso na LAN'), findsOneWidget);
    final lanToggle = find.bySemanticsLabel('Permitir acesso na LAN (Wi-Fi)');
    expect(lanToggle, findsOneWidget);
    final lanNode = tester.getSemantics(lanToggle);
    expect(lanNode.hasFlag(SemanticsFlag.hasToggledState), isTrue);
    expect(lanNode.hasFlag(SemanticsFlag.isToggled), isFalse);
    expect(lanNode.hasFlag(SemanticsFlag.isEnabled), isTrue);
    expect(lanNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(lanToggle);
    expect(requestedLanState, isTrue);
    semantics.dispose();
  });

  testWidgets('ServerScreen shows running motor state', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: ServerScreen(
          status: const SuwayomiStatus(
            state: SuwayomiProcessState.running,
            message: 'Suwayomi pronto',
            version: 'v2.3.2238-r2238',
            baseUrl: 'http://127.0.0.1:14567',
            pid: 42,
          ),
          yomuPort: 8787,
          managedRootDir: r'C:\tmp\yomu\data\suwayomi',
          aboutVersion: 'v2.3.2238 / r2238',
          onStart: () {},
          onStop: () {},
          onRestart: () {},
          onHealthCheck: () {},
          lanEnabled: true,
          onToggleLan: (_) {},
          pairingCode: '123456',
          pairingExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
          onStartPairing: () {},
          onCancelPairing: () {},
          lanAddresses: const ['192.168.1.10'],
          sessionCount: 1,
          busy: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('running'), findsOneWidget);
    expect(find.textContaining('Suwayomi pronto'), findsOneWidget);
    expect(find.text('Parar'), findsOneWidget);
    expect(find.textContaining('Código: 123456'), findsOneWidget);
    expect(find.textContaining('http://192.168.1.10:8787/'), findsOneWidget);
    final lanNode = tester.getSemantics(
      find.bySemanticsLabel('Permitir acesso na LAN (Wi-Fi)'),
    );
    expect(lanNode.hasFlag(SemanticsFlag.isToggled), isTrue);
    expect(lanNode.hasFlag(SemanticsFlag.isEnabled), isFalse);
    expect(lanNode.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
    expect(lanNode.value, contains('Alteração em andamento'));
    semantics.dispose();
  });

  testWidgets(
    'ServerScreen revokes by session id without rendering the identifier',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const sessionId = 'session-id-must-remain-private';
      String? revokedSessionId;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildYomuTheme(),
          home: ServerScreen(
            status: const SuwayomiStatus(
              state: SuwayomiProcessState.stopped,
              baseUrl: 'http://127.0.0.1:14567',
            ),
            yomuPort: 8787,
            managedRootDir: r'C:\tmp\yomu\data\suwayomi',
            onStart: () {},
            onStop: () {},
            onRestart: () {},
            onHealthCheck: () {},
            lanEnabled: false,
            onToggleLan: (_) {},
            pairingCode: null,
            pairingExpiresAt: null,
            onStartPairing: () {},
            onCancelPairing: () {},
            lanAddresses: const [],
            sessionCount: 1,
            sessions: [
              PairedSessionRow(
                sessionId: sessionId,
                deviceName: 'iPhone de teste',
                createdAt: DateTime(2026, 7, 15),
              ),
            ],
            onRevokeSession: (value) async => revokedSessionId = value,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('iPhone de teste'), findsOneWidget);
      expect(find.textContaining(sessionId), findsNothing);

      await tester.tap(find.text('Revogar'));

      expect(revokedSessionId, sessionId);
      expect(find.textContaining(sessionId), findsNothing);
    },
  );

  testWidgets('ExtensionsScreen empty when motor not ready', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: const Scaffold(
          body: ExtensionsScreen(gateway: null, engineReady: false),
        ),
      ),
    );

    expect(find.textContaining('recursos de leitura'), findsOneWidget);
  });

  testWidgets('YomuAppShell preserves navigation callback at narrow width', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(640, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? selected;
    var serverTaps = 0;
    var windowDrags = 0;
    var windowMinimizes = 0;
    var windowMaximizes = 0;
    var windowCloses = 0;
    YomuWindowResizeEdge? windowResizeEdge;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: YomuAppShell(
          title: 'Yomu',
          items: const [
            YomuNavItem(
              id: 'server',
              label: 'Servidor',
              icon: YomuIcons.server,
            ),
            YomuNavItem(
              id: 'library',
              label: 'Biblioteca',
              icon: YomuIcons.library,
            ),
          ],
          selectedId: 'server',
          onSelect: (id) => selected = id,
          serverLabel: 'Motor running',
          onServerTap: () => serverTaps++,
          onWindowDrag: () => windowDrags++,
          onWindowMinimize: () => windowMinimizes++,
          onWindowToggleMaximize: () => windowMaximizes++,
          onWindowClose: () => windowCloses++,
          onWindowResize: (edge) => windowResizeEdge = edge,
          body: const Center(child: Text('Conteúdo')),
        ),
      ),
    );

    expect(
      tester
          .getSize(find.byKey(const ValueKey('yomu-window-title-bar')))
          .height,
      YomuTokens.windowTitleBarHeight,
    );
    final closeControl = find.byKey(const ValueKey('yomu-window-close'));
    final minimizeControl = find.byKey(const ValueKey('yomu-window-minimize'));
    final maximizeControl = find.byKey(const ValueKey('yomu-window-maximize'));
    expect(tester.getSize(closeControl), const Size(20, 40));
    expect(
      tester.getCenter(minimizeControl).dx - tester.getCenter(closeControl).dx,
      20,
    );
    expect(
      tester.getCenter(maximizeControl).dx -
          tester.getCenter(minimizeControl).dx,
      20,
    );
    expect(
      find.descendant(of: closeControl, matching: find.byType(IconButton)),
      findsNothing,
    );
    final closeDot = find.descendant(
      of: closeControl,
      matching: find.byWidgetPredicate((widget) {
        if (widget is! Container || widget.decoration is! BoxDecoration) {
          return false;
        }
        return (widget.decoration! as BoxDecoration).shape == BoxShape.circle;
      }),
    );
    expect(closeDot, findsOneWidget);
    expect(tester.getSize(closeDot), const Size.square(12));
    expect(find.bySemanticsLabel('Fechar'), findsOneWidget);
    final titleBar = find.byKey(const ValueKey('yomu-window-title-bar'));
    final windowTitle = find.byKey(const ValueKey('yomu-window-title'));
    expect(tester.getCenter(windowTitle).dx, tester.getCenter(titleBar).dx);
    final windowTitleText = tester.widget<Text>(windowTitle);
    expect(windowTitleText.data, 'Yomu');
    expect(windowTitleText.style?.fontFamily, 'Segoe UI Variable Display');
    expect(windowTitleText.style?.fontSize, 13);
    final rightResize = find.byKey(const ValueKey('yomu-window-resize-right'));
    final rightResizeRegion = tester.widget<MouseRegion>(rightResize);
    expect(rightResizeRegion.cursor, SystemMouseCursors.resizeRight);
    final resizeGesture = await tester.startGesture(
      tester.getCenter(rightResize),
    );
    expect(windowResizeEdge, YomuWindowResizeEdge.right);
    await resizeGesture.up();
    await tester.tap(minimizeControl);
    await tester.tap(maximizeControl);
    await tester.tap(find.byKey(const ValueKey('yomu-window-close')));
    await tester.drag(
      find.byKey(const ValueKey('yomu-window-drag-main')),
      const Offset(30, 0),
    );
    expect(windowMinimizes, 1);
    expect(windowMaximizes, 1);
    expect(windowCloses, 1);
    expect(windowDrags, 1);
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester
          .getSemantics(find.text('Servidor'))
          .hasFlag(SemanticsFlag.isSelected),
      isTrue,
    );
    await tester.tap(find.text('Biblioteca'));
    await tester.pump();

    expect(selected, 'library');
    final navContainer = find.ancestor(
      of: find.text('Biblioteca'),
      matching: find.byType(AnimatedContainer),
    );
    expect(tester.getSize(navContainer.first).height, greaterThanOrEqualTo(44));
    expect(find.text('Perfil local'), findsOneWidget);
    expect(find.textContaining('João'), findsNothing);
    expect(find.text('JP'), findsNothing);
    final serverStatus = find.bySemanticsLabel('Abrir Servidor. Motor running');
    final statusNode = tester.getSemantics(serverStatus);
    expect(statusNode.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(
      statusNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(tester.getSize(serverStatus).height, greaterThanOrEqualTo(44));

    await tester.tap(serverStatus);
    expect(serverTaps, 1);
    final focusDetector = tester.widget<FocusableActionDetector>(
      find.byKey(const ValueKey('yomu-server-status-focus')),
    );
    focusDetector.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(serverTaps, 2);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('AsyncBody keeps loading, empty, and error states distinct', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    Future<void> pump(Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(body: child),
      ),
    );

    await pump(
      const AsyncBody(
        isLoading: true,
        isEmpty: false,
        emptyMessage: '',
        child: SizedBox(),
      ),
    );
    expect(find.text('Preparando conteúdo'), findsOneWidget);
    final loadingSemantics = tester.getSemantics(
      find.text('Preparando conteúdo'),
    );
    expect(loadingSemantics.label, contains('Preparando conteúdo'));
    expect(loadingSemantics.hasFlag(SemanticsFlag.isLiveRegion), isTrue);

    await pump(
      const AsyncBody(
        isLoading: false,
        isEmpty: true,
        emptyMessage: 'Sem itens',
        child: SizedBox(),
      ),
    );
    expect(find.text('Sem itens'), findsOneWidget);

    await pump(
      const AsyncBody(
        isLoading: false,
        isEmpty: false,
        error: 'Falha controlada',
        emptyMessage: '',
        child: SizedBox(),
      ),
    );
    expect(find.text('Falha controlada'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('YomuIconButton exposes an actionable 44px semantics target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(
          body: Center(
            child: YomuIconButton(
              icon: YomuIcons.refresh,
              tooltip: 'Atualizar conteúdo',
              size: 30,
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );

    final target = find.bySemanticsLabel('Atualizar conteúdo');
    final node = tester.getSemantics(target);
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44));

    await tester.tap(target);
    expect(taps, 1);
    semantics.dispose();
  });
}
