import 'package:yomu_core/yomu_core.dart';

import '../client/suwayomi_api.dart';
import '../client/suwayomi_models.dart';

/// Desktop-only anti-corruption adapter for extension catalog capabilities.
final class SuwayomiExtensionsAdapter implements ExtensionsGateway {
  SuwayomiExtensionsAdapter(this._api);

  final SuwayomiApi _api;

  @override
  Future<List<ExtensionRepository>> listRepositories() => _guard(
    code: 'engine_repositories_unavailable',
    message: 'Não foi possível carregar os repositórios.',
    operation: () async => List<ExtensionRepository>.unmodifiable(
      (await _api.listExtensionStores()).map(_mapRepository),
    ),
  );

  @override
  Future<List<ReadingExtension>> listExtensions() => _guard(
    code: 'engine_extensions_unavailable',
    message: 'Não foi possível carregar as extensões.',
    operation: () async => List<ReadingExtension>.unmodifiable(
      (await _api.listExtensions()).map(_mapExtension),
    ),
  );

  @override
  Future<ExtensionCatalogSync> synchronizeCatalog() => _guard(
    code: 'engine_extension_sync_failed',
    message: 'Não foi possível sincronizar o catálogo de extensões.',
    operation: () async =>
        ExtensionCatalogSync(count: await _api.fetchExtensions()),
  );

  @override
  Future<ExtensionRepository> ensureRecommendedRepository() => _guard(
    code: 'engine_repository_setup_failed',
    message: 'Não foi possível preparar o repositório recomendado.',
    operation: () async {
      final stores = await _api.listExtensionStores();
      final existing = stores.where(_isTrustedRecommendedRepository);
      if (existing.isNotEmpty) return _mapRepository(existing.first);

      final added = await _api.addExtensionStore(_recommendedIndexUrl);
      if (added != null && _isTrustedRecommendedRepository(added)) {
        return _mapRepository(added);
      }

      final refreshed = await _api.listExtensionStores();
      final trusted = refreshed.where(_isTrustedRecommendedRepository);
      if (trusted.isEmpty) throw StateError('recommended_repository_missing');
      return _mapRepository(trusted.first);
    },
  );

  @override
  Future<ReadingExtension> install(ExtensionReference reference) {
    if (reference is! _SuwayomiExtensionReference) {
      throw const EngineException(
        EngineFailure(
          kind: EngineFailureKind.operationRejected,
          code: 'engine_extension_reference_invalid',
          message: 'A referência da extensão não é válida.',
          retryable: false,
        ),
      );
    }
    return _guard(
      code: 'engine_extension_install_failed',
      message: 'Não foi possível instalar a extensão.',
      operation: () async =>
          _mapExtension(await _api.installExtension(reference.packageId)),
    );
  }

  @override
  Future<ReadingExtension> installRecommendedExtension() => _guard(
    code: 'engine_extension_install_failed',
    message: 'Não foi possível instalar a extensão recomendada.',
    operation: () async =>
        _mapExtension(await _api.installExtension(_recommendedPackageId)),
  );

  ExtensionRepository _mapRepository(ExtensionStoreInfo repository) =>
      ExtensionRepository(
        name: repository.name,
        state: repository.isLegacy
            ? ExtensionRepositoryState.legacy
            : ExtensionRepositoryState.active,
        recommended: _isTrustedRecommendedRepository(repository),
      );

  ReadingExtension _mapExtension(ExtensionInfo extension) => ReadingExtension(
    reference: _SuwayomiExtensionReference(extension.pkgName),
    name: extension.name,
    installed: extension.isInstalled,
    language: extension.lang,
    version: extension.versionName,
    recommended: extension.pkgName == _recommendedPackageId,
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

  static bool _isTrustedRecommendedRepository(ExtensionStoreInfo store) =>
      _trustedRecommendedIndexUrls.contains(store.indexUrl.trim());
}

final class _SuwayomiExtensionReference implements ExtensionReference {
  const _SuwayomiExtensionReference(this.packageId);

  final String packageId;

  @override
  bool operator ==(Object other) =>
      other is _SuwayomiExtensionReference && packageId == other.packageId;

  @override
  int get hashCode => packageId.hashCode;

  @override
  String toString() => 'ExtensionReference(opaque)';
}

const _recommendedIndexUrl =
    'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json';
const _recommendedPackageId = 'eu.kanade.tachiyomi.extension.all.mangadex';
const _trustedRecommendedIndexUrls = <String>{
  _recommendedIndexUrl,
  'https://cdn.jsdelivr.net/gh/keiyoushi/extensions@repo/index.min.json',
  'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb',
  'https://cdn.jsdelivr.net/gh/keiyoushi/extensions@repo/index.pb',
};
