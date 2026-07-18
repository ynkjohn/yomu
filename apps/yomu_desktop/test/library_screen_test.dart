import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_desktop/screens/library_screen.dart';
import 'package:yomu_ui/yomu_ui.dart';

void main() {
  Future<void> pumpLibrary(
    WidgetTester tester, {
    required LibraryGateway? library,
    EngineMediaGateway? media,
    EngineReadinessSnapshot readiness = const EngineReadinessSnapshot(
      state: EngineReadinessState.ready,
    ),
    Future<void> Function(LibraryManga)? onOpen,
    Future<void> Function(LibraryManga)? onContinue,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1240, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomuTheme(),
        home: Scaffold(
          body: LibraryScreen(
            library: library,
            media: media,
            readiness: readiness,
            onOpenManga: onOpen ?? (_) async {},
            onContinueReading: onContinue ?? (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('uses Yomu models, bounded media and composition callbacks', (
    tester,
  ) async {
    const reference = _FakeMediaReference('cover-7');
    final media = _RecordingMediaGateway();
    var opened = 0;
    var continued = 0;
    const manga = LibraryManga(
      id: 7,
      title: 'Yomu Boundary',
      thumbnail: reference,
      inLibrary: true,
      lastReadChapter: LibraryResumePoint(
        id: 3,
        name: 'Capítulo 3',
        lastPageRead: 2,
      ),
    );

    await pumpLibrary(
      tester,
      library: const _FakeLibraryGateway([manga]),
      media: media,
      onOpen: (_) async {
        opened++;
      },
      onContinue: (_) async {
        continued++;
      },
    );

    expect(find.text('Yomu Boundary'), findsOneWidget);
    expect(media.references, [reference]);
    expect(media.maxBytes, [8 * 1024 * 1024]);

    final card = find.byKey(const ValueKey('library-manga-7'));
    final inkWell = tester.widget<InkWell>(card);
    inkWell.onTap?.call();
    await tester.pump();
    expect(opened, 1);

    inkWell.onDoubleTap?.call();
    await tester.pump();
    expect(continued, 1);
  });

  testWidgets('sanitizes unexpected gateway errors', (tester) async {
    await pumpLibrary(
      tester,
      library: const _ThrowingLibraryGateway(
        r'GraphQL failed at C:\private\engine.db',
      ),
    );

    expect(
      find.text('Não foi possível carregar a biblioteca.'),
      findsOneWidget,
    );
    expect(find.textContaining('GraphQL'), findsNothing);
    expect(find.textContaining('private'), findsNothing);
  });

  testWidgets('shows product readiness without vendor terminology', (
    tester,
  ) async {
    await pumpLibrary(
      tester,
      library: null,
      readiness: const EngineReadinessSnapshot(
        state: EngineReadinessState.actionRequired,
        failure: EngineFailure(
          kind: EngineFailureKind.actionRequired,
          code: 'engine_action_required',
          message: 'Recursos de leitura não estão disponíveis no momento.',
          retryable: true,
        ),
      ),
    );

    expect(
      find.text('Recursos de leitura não estão disponíveis no momento.'),
      findsOneWidget,
    );
    expect(find.textContaining('Suwayomi'), findsNothing);
    expect(find.textContaining('Java'), findsNothing);
    expect(find.textContaining('14567'), findsNothing);
  });
}

final class _FakeMediaReference implements MediaReference {
  const _FakeMediaReference(this.id);

  final String id;

  @override
  bool operator ==(Object other) =>
      other is _FakeMediaReference && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

final class _FakeLibraryGateway implements LibraryGateway {
  const _FakeLibraryGateway(this.items);

  final List<LibraryManga> items;

  @override
  Future<List<LibraryManga>> listLibrary() async => items;
}

final class _ThrowingLibraryGateway implements LibraryGateway {
  const _ThrowingLibraryGateway(this.message);

  final String message;

  @override
  Future<List<LibraryManga>> listLibrary() => Future.error(StateError(message));
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
