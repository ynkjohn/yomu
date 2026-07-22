import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_desktop/screens/downloads_screen.dart';

void main() {
  testWidgets('pause, resume and dequeue use normalized gateway operations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final downloads = _FakeDownloadsGateway(
      DownloadsSnapshot(
        managerState: DownloadManagerState.running,
        queue: const [
          EngineDownloadItem(
            state: DownloadItemState.downloading,
            chapterId: 7,
            chapterName: 'Capítulo 7',
            mangaTitle: 'Obra',
            progress: 0.5,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadsScreen(downloads: downloads, engineReady: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 baixando'), findsOneWidget);
    await tester.tap(find.text('Pausar tudo'));
    await tester.pumpAndSettle();
    expect(downloads.operations, contains('pause'));
    expect(find.text('Retomar tudo'), findsOneWidget);

    await tester.tap(find.text('Retomar tudo'));
    await tester.pumpAndSettle();
    expect(downloads.operations, contains('resume'));

    await tester.tap(find.byTooltip('Remover da fila'));
    await tester.pumpAndSettle();
    expect(downloads.operations, contains('dequeue:7'));
  });

  testWidgets('unexpected failures never expose raw engine text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final downloads = _FakeDownloadsGateway(
      DownloadsSnapshot(
        managerState: DownloadManagerState.paused,
        queue: const [],
      ),
      error: StateError('private upstream body'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadsScreen(downloads: downloads, engineReady: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível carregar os downloads.'),
      findsOneWidget,
    );
    expect(find.textContaining('private upstream'), findsNothing);
  });
}

final class _FakeDownloadsGateway implements DownloadsGateway {
  _FakeDownloadsGateway(this.snapshot, {this.error});

  DownloadsSnapshot snapshot;
  final Object? error;
  final operations = <String>[];

  @override
  Future<DownloadsSnapshot> getStatus() async {
    if (error != null) throw error!;
    return snapshot;
  }

  @override
  Future<void> clear() async {
    operations.add('clear');
    snapshot = DownloadsSnapshot(
      managerState: snapshot.managerState,
      queue: const [],
    );
  }

  @override
  Future<void> dequeueChapters(List<int> chapterIds) async {
    operations.add('dequeue:${chapterIds.join(',')}');
    snapshot = DownloadsSnapshot(
      managerState: snapshot.managerState,
      queue: snapshot.queue
          .where((item) => !chapterIds.contains(item.chapterId))
          .toList(),
    );
  }

  @override
  Future<void> enqueueChapters(List<int> chapterIds) async {
    operations.add('enqueue:${chapterIds.join(',')}');
  }

  @override
  Future<bool> hasActivity() async => snapshot.hasActivity;

  @override
  Future<DownloadPauseAck> pause() async {
    operations.add('pause');
    snapshot = DownloadsSnapshot(
      managerState: DownloadManagerState.paused,
      queue: snapshot.queue,
    );
    return const DownloadPauseAck(
      managerState: DownloadManagerState.paused,
      acknowledged: true,
    );
  }

  @override
  Future<DownloadPauseAck> pauseAndAwaitAck({required Duration timeout}) =>
      pause();

  @override
  Future<void> resume() async {
    operations.add('resume');
    snapshot = DownloadsSnapshot(
      managerState: DownloadManagerState.running,
      queue: snapshot.queue,
    );
  }
}
