import 'dart:typed_data';

import 'package:yomu_core/yomu_core.dart';

import '../client/suwayomi_api.dart';
import '../client/suwayomi_models.dart';

/// First vertical adapter from Suwayomi protocol objects to Yomu library
/// contracts. Media identity remains private to this package.
final class SuwayomiLibraryAdapter
    implements LibraryGateway, EngineMediaGateway {
  SuwayomiLibraryAdapter(this._api);

  final SuwayomiApi _api;

  @override
  Future<List<LibraryManga>> listLibrary() async {
    try {
      final upstream = await _api.listLibrary();
      return List<LibraryManga>.unmodifiable(upstream.map(_mapManga));
    } on EngineException {
      rethrow;
    } catch (_) {
      throw const EngineException(
        EngineFailure(
          kind: EngineFailureKind.temporarilyUnavailable,
          code: 'engine_library_unavailable',
          message: 'Não foi possível carregar a biblioteca.',
          retryable: true,
        ),
      );
    }
  }

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {
    try {
      await _api.setInLibrary(mangaId, inLibrary);
    } on EngineException {
      rethrow;
    } catch (_) {
      throw const EngineException(
        EngineFailure(
          kind: EngineFailureKind.temporarilyUnavailable,
          code: 'engine_library_update_failed',
          message: 'Não foi possível atualizar a biblioteca.',
          retryable: true,
        ),
      );
    }
  }

  @override
  Future<MediaPayload> fetch(
    MediaReference reference, {
    required int maxBytes,
  }) async {
    if (maxBytes <= 0 || reference is! _SuwayomiMangaThumbnailReference) {
      throw const EngineException(
        EngineFailure(
          kind: EngineFailureKind.operationRejected,
          code: 'engine_media_reference_invalid',
          message: 'A referência de mídia não é válida.',
          retryable: false,
        ),
      );
    }

    try {
      final response = await _api.client.restGetStream(
        '/api/v1/manga/${reference.mangaId}/thumbnail',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await _cancel(response.stream);
        throw const EngineException(
          EngineFailure(
            kind: EngineFailureKind.operationRejected,
            code: 'engine_media_unavailable',
            message: 'A capa não está disponível.',
            retryable: true,
          ),
        );
      }

      final declaredLength = response.contentLength;
      if (declaredLength != null && declaredLength > maxBytes) {
        await _cancel(response.stream);
        throw const EngineException(
          EngineFailure(
            kind: EngineFailureKind.operationRejected,
            code: 'engine_media_too_large',
            message: 'A capa excede o limite permitido.',
            retryable: false,
          ),
        );
      }

      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const EngineException(
            EngineFailure(
              kind: EngineFailureKind.operationRejected,
              code: 'engine_media_too_large',
              message: 'A capa excede o limite permitido.',
              retryable: false,
            ),
          );
        }
        bytes.add(chunk);
      }

      return MediaPayload(
        bytes: bytes.takeBytes(),
        contentType: _contentType(response.headers['content-type']),
      );
    } on EngineException {
      rethrow;
    } catch (_) {
      throw const EngineException(
        EngineFailure(
          kind: EngineFailureKind.temporarilyUnavailable,
          code: 'engine_media_unavailable',
          message: 'Não foi possível carregar a capa.',
          retryable: true,
        ),
      );
    }
  }

  LibraryManga _mapManga(MangaSummary manga) {
    final thumbnail = manga.thumbnailUrl?.trim();
    final last = manga.lastReadChapter;
    return LibraryManga(
      id: manga.id,
      title: manga.title,
      thumbnail: thumbnail == null || thumbnail.isEmpty
          ? null
          : _SuwayomiMangaThumbnailReference(manga.id),
      inLibrary: manga.inLibrary,
      unreadCount: manga.unreadCount,
      lastReadChapter: last == null
          ? null
          : LibraryResumePoint(
              id: last.id,
              name: last.name,
              lastPageRead: last.lastPageRead,
              pageCount: last.pageCount,
            ),
    );
  }

  static Future<void> _cancel(Stream<List<int>> stream) async {
    final subscription = stream.listen((_) {});
    await subscription.cancel();
  }

  static String? _contentType(String? header) {
    if (header == null) return null;
    final value = header.split(';').first.trim();
    return value.isEmpty ? null : value;
  }
}

final class _SuwayomiMangaThumbnailReference implements MediaReference {
  const _SuwayomiMangaThumbnailReference(this.mangaId);

  final int mangaId;

  @override
  bool operator ==(Object other) =>
      other is _SuwayomiMangaThumbnailReference && mangaId == other.mangaId;

  @override
  int get hashCode => mangaId.hashCode;
}
