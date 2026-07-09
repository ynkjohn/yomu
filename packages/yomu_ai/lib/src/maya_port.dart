import 'models.dart';

/// Port implemented by the desktop shell to reach Suwayomi / UI.
///
/// Maya never talks to Suwayomi ports on LAN; the host injects loopback access.
abstract class MayaLibraryPort {
  Future<List<MayaLibraryItem>> listLibrary();

  Future<void> setInLibrary(int mangaId, bool inLibrary);

  Future<void> enqueueChapterDownload(int chapterId);
}

/// Optional LLM backend. Null = offline heuristic only.
abstract class MayaLlmProvider {
  Future<String> complete({
    required List<MayaMessage> history,
    required String userText,
    required String toolContext,
  });
}
