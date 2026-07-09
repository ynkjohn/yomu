import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_desktop/screens/extensions_screen.dart';
import 'package:yomu_desktop/screens/server_screen.dart';
import 'package:yomu_ui/yomu_ui.dart';

void main() {
  testWidgets('ServerScreen shows stopped motor state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          onToggleLan: (_) {},
          pairingCode: null,
          pairingExpiresAt: null,
          onStartPairing: () {},
          onCancelPairing: () {},
          lanAddresses: const [],
          sessionCount: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('stopped'), findsOneWidget);
    expect(find.textContaining('127.0.0.1:14567'), findsWidgets);
    expect(find.text('Iniciar'), findsOneWidget);
    expect(find.textContaining('Yomu HTTP'), findsOneWidget);
    expect(find.textContaining('Permitir acesso na LAN'), findsOneWidget);
  });

  testWidgets('ServerScreen shows running motor state', (tester) async {
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
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('running'), findsOneWidget);
    expect(find.textContaining('Suwayomi pronto'), findsOneWidget);
    expect(find.text('Parar'), findsOneWidget);
    expect(find.textContaining('Código: 123456'), findsOneWidget);
    expect(find.textContaining('http://192.168.1.10:8787/'), findsOneWidget);
  });

  testWidgets('ExtensionsScreen empty when motor not ready', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: const Scaffold(
          body: ExtensionsScreen(api: null, engineReady: false),
        ),
      ),
    );

    expect(find.textContaining('Inicie o Suwayomi'), findsOneWidget);
  });
}
