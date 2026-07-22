import 'library_models.dart';

abstract interface class LibraryGateway {
  Future<List<LibraryManga>> listLibrary();

  Future<void> setInLibrary(int mangaId, bool inLibrary);
}
