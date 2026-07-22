import 'package:test/test.dart';
import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_core/yomu_core.dart';

void main() {
  test('maps library summaries without exposing engine models', () async {
    final library = _FakeLibraryGateway(
      items: const [
        LibraryManga(
          id: 4,
          title: 'Obra',
          unreadCount: 3,
          lastReadChapter: LibraryResumePoint(
            id: 9,
            name: 'Capítulo 9',
            lastPageRead: 2,
          ),
        ),
      ],
    );
    final port = ReadingEngineMayaPort(
      library: library,
      downloads: _FakeDownloadsGateway(),
    );

    final item = (await port.listLibrary()).single;
    expect(item.id, 4);
    expect(item.title, 'Obra');
    expect(item.unreadCount, 3);
    expect(item.lastChapterId, 9);
    expect(item.lastPageRead, 2);
  });

  test('membership delegates to LibraryGateway', () async {
    final library = _FakeLibraryGateway();
    final port = ReadingEngineMayaPort(
      library: library,
      downloads: _FakeDownloadsGateway(),
    );

    await port.setInLibrary(12, true);
    await port.setInLibrary(12, false);

    expect(library.membershipCalls, [(12, true), (12, false)]);
  });

  test('enqueue delegates then resumes downloader', () async {
    final downloads = _FakeDownloadsGateway();
    final port = ReadingEngineMayaPort(
      library: _FakeLibraryGateway(),
      downloads: downloads,
    );

    await port.enqueueChapterDownload(22);

    expect(downloads.operations, ['enqueue:22', 'resume']);
  });

  test('unexpected engine implementation errors are sanitized', () async {
    final port = ReadingEngineMayaPort(
      library: _FakeLibraryGateway(error: StateError('raw vendor body')),
      downloads: _FakeDownloadsGateway(),
    );

    await expectLater(
      port.listLibrary(),
      throwsA(
        isA<EngineException>().having(
          (error) => error.toString(),
          'sanitized error',
          allOf(contains('engine_library_unavailable'), isNot(contains('raw'))),
        ),
      ),
    );
  });
}

final class _FakeLibraryGateway implements LibraryGateway {
  _FakeLibraryGateway({this.items = const [], this.error});

  final List<LibraryManga> items;
  final Object? error;
  final membershipCalls = <(int, bool)>[];

  @override
  Future<List<LibraryManga>> listLibrary() async {
    if (error != null) throw error!;
    return items;
  }

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {
    if (error != null) throw error!;
    membershipCalls.add((mangaId, inLibrary));
  }
}

final class _FakeDownloadsGateway implements DownloadsGateway {
  final operations = <String>[];

  @override
  Future<void> clear() async => operations.add('clear');

  @override
  Future<void> dequeueChapters(List<int> chapterIds) async =>
      operations.add('dequeue:${chapterIds.join(',')}');

  @override
  Future<void> enqueueChapters(List<int> chapterIds) async =>
      operations.add('enqueue:${chapterIds.join(',')}');

  @override
  Future<DownloadsSnapshot> getStatus() async => DownloadsSnapshot(
    managerState: DownloadManagerState.paused,
    queue: const [],
  );

  @override
  Future<bool> hasActivity() async => false;

  @override
  Future<DownloadPauseAck> pause() async => const DownloadPauseAck(
    managerState: DownloadManagerState.paused,
    acknowledged: true,
  );

  @override
  Future<DownloadPauseAck> pauseAndAwaitAck({required Duration timeout}) =>
      pause();

  @override
  Future<void> resume() async => operations.add('resume');
}
