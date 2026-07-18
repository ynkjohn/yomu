import 'package:collection/collection.dart';

import 'media_gateway.dart';

final class CatalogSource {
  const CatalogSource({
    required this.id,
    required this.name,
    required this.language,
    this.icon,
  });

  final String id;
  final String name;
  final String language;
  final MediaReference? icon;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogSource &&
          id == other.id &&
          name == other.name &&
          language == other.language &&
          icon == other.icon;

  @override
  int get hashCode => Object.hash(id, name, language, icon);
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

final class CatalogPage {
  CatalogPage({
    required List<CatalogManga> items,
    required this.page,
    required this.hasNextPage,
  }) : items = List<CatalogManga>.unmodifiable(items);

  final List<CatalogManga> items;
  final int page;
  final bool hasNextPage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogPage &&
          const ListEquality<CatalogManga>().equals(items, other.items) &&
          page == other.page &&
          hasNextPage == other.hasNextPage;

  @override
  int get hashCode => Object.hash(
    const ListEquality<CatalogManga>().hash(items),
    page,
    hasNextPage,
  );
}

abstract interface class CatalogGateway {
  Future<List<CatalogSource>> listSources();

  Future<CatalogPage> search({
    required String sourceId,
    required String query,
    int page = 1,
  });

  Future<CatalogPage> popular({required String sourceId, int page = 1});

  Future<CatalogPage> latest({required String sourceId, int page = 1});
}
