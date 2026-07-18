import 'reading_models.dart';

abstract interface class MangaDetailsGateway {
  Future<ReadingMangaDetails> getManga(int mangaId);

  Future<ReadingMangaDetails> setInLibrary(int mangaId, bool inLibrary);
}
