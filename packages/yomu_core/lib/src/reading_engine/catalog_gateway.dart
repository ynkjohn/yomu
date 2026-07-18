import 'media_gateway.dart';

final class CatalogSource {
  const CatalogSource({
    required this.id,
    required this.name,
    required this.language,
  });

  final String id;
  final String name;
  final String language;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogSource &&
          id == other.id &&
          name == other.name &&
          language == other.language;

  @override
  int get hashCode => Object.hash(id, name, language);
}

final class CatalogManga {
  const CatalogManga({
    required this.id,
    required this.title,
    this.thumbnail,
    this.inLibrary = false,
  });

  final int id;
  final String title;
  final MediaReference? thumbnail;
  final bool inLibrary;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogManga &&
          id == other.id &&
          title == other.title &&
          thumbnail == other.thumbnail &&
          inLibrary == other.inLibrary;

  @override
  int get hashCode => Object.hash(id, title, thumbnail, inLibrary);
}

abstract interface class CatalogGateway {
  Future<List<CatalogSource>> listSources();

  Future<List<CatalogManga>> search({
    required String sourceId,
    required String query,
    int page = 1,
  });
}
