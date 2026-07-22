import 'package:yomu_core/yomu_core.dart';

import 'maya_port.dart';
import 'models.dart';

/// Maya bridge expressed only in Yomu reading-engine capabilities.
final class ReadingEngineMayaPort implements MayaLibraryPort {
  ReadingEngineMayaPort({
    required LibraryGateway library,
    required DownloadsGateway downloads,
  }) : _library = library,
       _downloads = downloads;

  final LibraryGateway _library;
  final DownloadsGateway _downloads;

  @override
  Future<List<MayaLibraryItem>> listLibrary() => _guard(
    code: 'engine_library_unavailable',
    message: 'Os recursos de leitura estão temporariamente indisponíveis.',
    operation: () async => (await _library.listLibrary())
        .map(
          (manga) => MayaLibraryItem(
            id: manga.id,
            title: manga.title,
            unreadCount: manga.unreadCount ?? 0,
            lastChapterId: manga.lastReadChapter?.id,
            lastChapterName: manga.lastReadChapter?.name,
            lastPageRead: manga.lastReadChapter?.lastPageRead,
          ),
        )
        .toList(growable: false),
  );

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) => _guard(
    code: 'engine_library_update_failed',
    message: 'Não foi possível atualizar a biblioteca.',
    operation: () => _library.setInLibrary(mangaId, inLibrary),
  );

  @override
  Future<void> enqueueChapterDownload(int chapterId) => _guard(
    code: 'engine_download_enqueue_failed',
    message: 'Não foi possível enfileirar o capítulo.',
    operation: () async {
      await _downloads.enqueueChapters([chapterId]);
      await _downloads.resume();
    },
  );

  Future<T> _guard<T>({
    required String code,
    required String message,
    required Future<T> Function() operation,
  }) async {
    try {
      return await operation();
    } on EngineException {
      rethrow;
    } catch (_) {
      throw EngineException(
        EngineFailure(
          kind: EngineFailureKind.temporarilyUnavailable,
          code: code,
          message: message,
          retryable: true,
        ),
      );
    }
  }
}
