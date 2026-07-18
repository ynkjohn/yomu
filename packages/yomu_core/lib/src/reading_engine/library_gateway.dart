import 'library_models.dart';

/// Read-only library capability used by the first migration vertical.
abstract interface class LibraryGateway {
  Future<List<LibraryManga>> listLibrary();
}
