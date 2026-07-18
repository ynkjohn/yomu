import 'reading_models.dart';

abstract interface class ReaderGateway {
  Future<List<ReadingChapter>> listChapters(int mangaId);

  Future<List<ReadingChapter>> refreshChapters(int mangaId);

  Future<ReadingChapter?> getChapter(int chapterId);

  Future<ReadingChapterPages> getPages(int chapterId);
}
