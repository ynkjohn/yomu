import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

/// Bridges Maya tools to the managed Suwayomi API (loopback only).
class SuwayomiMayaPort implements MayaLibraryPort {
  SuwayomiMayaPort(this._apiProvider);

  final SuwayomiApi? Function() _apiProvider;

  SuwayomiApi get _api {
    final api = _apiProvider();
    if (api == null) {
      throw StateError('Suwayomi API indisponível');
    }
    return api;
  }

  @override
  Future<List<MayaLibraryItem>> listLibrary() async {
    final list = await _api.listLibrary();
    return list
        .map(
          (m) => MayaLibraryItem(
            id: m.id,
            title: m.title,
            unreadCount: m.unreadCount ?? 0,
            lastChapterId: m.lastReadChapter?.id,
            lastChapterName: m.lastReadChapter?.name,
            lastPageRead: m.lastReadChapter?.lastPageRead,
          ),
        )
        .toList();
  }

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {
    await _api.setInLibrary(mangaId, inLibrary);
  }

  @override
  Future<void> enqueueChapterDownload(int chapterId) async {
    await _api.enqueueChapterDownloads([chapterId]);
  }
}
