abstract interface class ExtensionReference {}

enum ExtensionRepositoryState { active, legacy }

final class ExtensionRepository {
  const ExtensionRepository({
    required this.name,
    required this.state,
    this.recommended = false,
  });

  final String name;
  final ExtensionRepositoryState state;
  final bool recommended;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtensionRepository &&
          name == other.name &&
          state == other.state &&
          recommended == other.recommended;

  @override
  int get hashCode => Object.hash(name, state, recommended);
}

final class ReadingExtension {
  const ReadingExtension({
    required this.reference,
    required this.name,
    required this.installed,
    this.language,
    this.version,
    this.recommended = false,
  });

  final ExtensionReference reference;
  final String name;
  final bool installed;
  final String? language;
  final String? version;
  final bool recommended;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadingExtension &&
          reference == other.reference &&
          name == other.name &&
          installed == other.installed &&
          language == other.language &&
          version == other.version &&
          recommended == other.recommended;

  @override
  int get hashCode =>
      Object.hash(reference, name, installed, language, version, recommended);
}

final class ExtensionCatalogSync {
  const ExtensionCatalogSync({required this.count});

  final int count;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtensionCatalogSync && count == other.count;

  @override
  int get hashCode => count.hashCode;
}

abstract interface class ExtensionsGateway {
  Future<List<ExtensionRepository>> listRepositories();

  Future<List<ReadingExtension>> listExtensions();

  Future<ExtensionCatalogSync> synchronizeCatalog();

  Future<ExtensionRepository> ensureRecommendedRepository();

  Future<ReadingExtension> install(ExtensionReference reference);

  Future<ReadingExtension> installRecommendedExtension();
}
