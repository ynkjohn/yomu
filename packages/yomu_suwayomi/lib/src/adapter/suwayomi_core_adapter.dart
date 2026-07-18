import 'dart:typed_data';

import 'package:yomu_core/yomu_core.dart';

import '../client/suwayomi_api.dart';
import '../client/suwayomi_models.dart';

typedef SafeExternalMediaFetch =
    Future<MediaPayload> Function(Uri uri, {required int maxBytes});

/// Anti-corruption adapter for the capabilities consumed by Yomu Core/PWA.
///
/// The concrete adapter is aggregated for composition only. YomuServer receives
/// each narrow Yomu gateway separately.
final class SuwayomiCoreAdapter
    implements
        MangaDetailsGateway,
        ReaderGateway,
        ReadingProgressGateway,
        CatalogGateway,
        EngineMediaGateway {
  SuwayomiCoreAdapter(
    this._api, {
    required SafeExternalMediaFetch safeExternalMediaFetch,
  }) : _safeExternalMediaFetch = safeExternalMediaFetch;

  final SuwayomiApi _api;
  final SafeExternalMediaFetch _safeExternalMediaFetch;

  @override
  Future<ReadingMangaDetails> getManga(int mangaId) => _guard(
    code: 'engine_manga_unavailable',
    message: 'Não foi possível carregar este título.',
    operation: () async => _mapManga(await _api.getManga(mangaId)),
  );

  @override
  Future<ReadingMangaDetails> setInLibrary(int mangaId, bool inLibrary) =>
      _guard(
        code: 'engine_library_update_failed',
        message: 'Não foi possível atualizar a biblioteca.',
        operation: () async =>
            _mapManga(await _api.setInLibrary(mangaId, inLibrary)),
      );

  @override
  Future<List<ReadingChapter>> listChapters(int mangaId) => _guard(
    code: 'engine_chapters_unavailable',
    message: 'Não foi possível carregar os capítulos.',
    operation: () async {
      var chapters = await _api.listMangaChapters(mangaId);
      if (chapters.isEmpty) {
        chapters = await _api.fetchMangaChapters(mangaId);
      }
      return List<ReadingChapter>.unmodifiable(chapters.map(_mapChapter));
    },
  );

  @override
  Future<List<ReadingChapter>> refreshChapters(int mangaId) => _guard(
    code: 'engine_chapters_refresh_failed',
    message: 'Não foi possível atualizar os capítulos.',
    operation: () async {
      var chapters = await _api.fetchMangaChapters(mangaId);
      if (chapters.isEmpty) {
        chapters = await _api.listMangaChapters(mangaId);
      }
      return List<ReadingChapter>.unmodifiable(chapters.map(_mapChapter));
    },
  );

  @override
  Future<ReadingChapter?> getChapter(int chapterId) => _guard(
    code: 'engine_chapter_unavailable',
    message: 'Não foi possível carregar o capítulo.',
    operation: () async {
      final chapter = await _api.getChapter(chapterId);
      return chapter == null ? null : _mapChapter(chapter);
    },
  );

  @override
  Future<ReadingChapterPages> getPages(int chapterId) => _guard(
    code: 'engine_pages_unavailable',
    message: 'Não foi possível carregar as páginas.',
    operation: () async {
      final pages = await _api.fetchChapterPages(chapterId);
      return ReadingChapterPages(
        chapterId: pages.chapterId,
        chapterName: pages.chapterName,
        pageCount: pages.pageCount,
        pages: pages.pages.map(_SuwayomiCoreMediaReference.new).toList(),
      );
    },
  );

  @override
  Future<ReadingProgressSnapshot> updateProgress({
    required int chapterId,
    required int lastPageRead,
    required bool isRead,
  }) => _guard(
    code: 'engine_progress_update_failed',
    message: 'Não foi possível salvar o progresso.',
    operation: () async {
      final chapter = await _api.updateChapterProgress(
        chapterId: chapterId,
        lastPageRead: lastPageRead,
        isRead: isRead,
      );
      return ReadingProgressSnapshot(
        chapterId: chapter.id,
        lastPageRead: chapter.lastPageRead ?? lastPageRead,
        isRead: chapter.isRead,
      );
    },
  );

  @override
  Future<List<CatalogSource>> listSources() => _guard(
    code: 'engine_sources_unavailable',
    message: 'Não foi possível carregar as fontes.',
    operation: () async => List<CatalogSource>.unmodifiable(
      (await _api.listSources())
          .where((source) => source.id != '0')
          .map(
            (source) => CatalogSource(
              id: source.id,
              name: source.name,
              language: source.lang,
              icon: _reference(source.iconUrl),
            ),
          ),
    ),
  );

  @override
  Future<CatalogPage> search({
    required String sourceId,
    required String query,
    int page = 1,
  }) => _fetchCatalogPage(
    code: 'engine_catalog_search_failed',
    message: 'Não foi possível pesquisar nesta fonte.',
    sourceId: sourceId,
    type: SourceMangaFetchType.search,
    query: query,
    page: page,
  );

  @override
  Future<CatalogPage> popular({required String sourceId, int page = 1}) =>
      _fetchCatalogPage(
        code: 'engine_catalog_popular_failed',
        message: 'Não foi possível carregar os títulos populares.',
        sourceId: sourceId,
        type: SourceMangaFetchType.popular,
        page: page,
      );

  @override
  Future<CatalogPage> latest({required String sourceId, int page = 1}) =>
      _fetchCatalogPage(
        code: 'engine_catalog_latest_failed',
        message: 'Não foi possível carregar os lançamentos recentes.',
        sourceId: sourceId,
        type: SourceMangaFetchType.latest,
        page: page,
      );

  @override
  Future<MediaPayload> fetch(
    MediaReference reference, {
    required int maxBytes,
  }) async {
    if (maxBytes <= 0 || reference is! _SuwayomiCoreMediaReference) {
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
      final target = reference.target.trim();
      final absolute = Uri.tryParse(target);
      if (absolute != null &&
          absolute.hasScheme &&
          (absolute.scheme == 'http' || absolute.scheme == 'https') &&
          absolute.host.isNotEmpty) {
        final externalMaxBytes = maxBytes < _externalMediaMaxBytes
            ? maxBytes
            : _externalMediaMaxBytes;
        final payload = await _safeExternalMediaFetch(
          absolute,
          maxBytes: externalMaxBytes,
        );
        if (payload.bytes.length > externalMaxBytes) throw _mediaTooLarge;
        return payload;
      }

      final path = target.startsWith('/') ? target : '/$target';
      final lower = path.toLowerCase();
      if (!path.startsWith('/api/v1/') ||
          path.contains('..') ||
          path.contains('\\') ||
          lower.contains('%2e') ||
          lower.contains('%5c')) {
        throw const EngineException(
          EngineFailure(
            kind: EngineFailureKind.operationRejected,
            code: 'engine_media_path_invalid',
            message: 'A referência de mídia não é válida.',
            retryable: false,
          ),
        );
      }
      return _readRelative(path, maxBytes: maxBytes);
    } on EngineException {
      rethrow;
    } catch (_) {
      throw const EngineException(
        EngineFailure(
          kind: EngineFailureKind.temporarilyUnavailable,
          code: 'engine_media_unavailable',
          message: 'Não foi possível carregar a mídia.',
          retryable: true,
        ),
      );
    }
  }

  Future<MediaPayload> _readRelative(
    String path, {
    required int maxBytes,
  }) async {
    final response = await _api.client.restGetStream(path);
    if (_isRedirect(response.statusCode)) {
      await _cancel(response.stream);
      throw const EngineException(
        EngineFailure(
          kind: EngineFailureKind.operationRejected,
          code: 'engine_media_redirect_refused',
          message: 'O redirecionamento de mídia foi recusado.',
          retryable: true,
        ),
      );
    }
    final declaredLength = response.contentLength;
    if (declaredLength != null && declaredLength > maxBytes) {
      await _cancel(response.stream);
      throw _mediaTooLarge;
    }

    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maxBytes) throw _mediaTooLarge;
      bytes.add(chunk);
    }
    return MediaPayload(
      bytes: bytes.takeBytes(),
      contentType: _contentType(response.headers['content-type']),
      statusCode: response.statusCode,
    );
  }

  ReadingMangaDetails _mapManga(MangaDetails manga) {
    return ReadingMangaDetails(
      id: manga.id,
      title: manga.title,
      description: manga.description,
      author: manga.author,
      artist: manga.artist,
      status: _publicationStatus(manga.status),
      thumbnail: _thumbnail(manga.id, manga.thumbnailUrl),
      sourceId: manga.sourceId,
      inLibrary: manga.inLibrary,
    );
  }

  ReadingChapter _mapChapter(ChapterInfo chapter) {
    return ReadingChapter(
      id: chapter.id,
      name: chapter.name,
      chapterNumber: chapter.chapterNumber,
      pageCount: chapter.pageCount,
      readingOrder: chapter.sourceOrder,
      scanlator: chapter.scanlator,
      lastPageRead: chapter.lastPageRead,
      isRead: chapter.isRead,
      isDownloaded: chapter.isDownloaded,
      mangaId: chapter.mangaId,
    );
  }

  MediaReference? _thumbnail(int mangaId, String? upstream) {
    if (upstream == null || upstream.trim().isEmpty) return null;
    return _SuwayomiCoreMediaReference('/api/v1/manga/$mangaId/thumbnail');
  }

  MediaReference? _reference(String? upstream) {
    final value = upstream?.trim();
    return value == null || value.isEmpty
        ? null
        : _SuwayomiCoreMediaReference(value);
  }

  Future<CatalogPage> _fetchCatalogPage({
    required String code,
    required String message,
    required String sourceId,
    required SourceMangaFetchType type,
    String? query,
    required int page,
  }) => _guard(
    code: code,
    message: message,
    operation: () async {
      final upstream = await _api.fetchSourceManga(
        sourceId: sourceId,
        type: type,
        query: query,
        page: page,
      );
      return CatalogPage(
        items: upstream.items
            .map(
              (manga) => CatalogManga(
                id: manga.id,
                title: manga.title,
                thumbnail: _thumbnail(manga.id, manga.thumbnailUrl),
                inLibrary: manga.inLibrary,
              ),
            )
            .toList(),
        page: upstream.page,
        hasNextPage: upstream.hasNextPage,
      );
    },
  );

  static ReadingPublicationStatus? _publicationStatus(String? upstream) {
    final value = upstream?.trim().toUpperCase();
    if (value == null || value.isEmpty) return null;
    return switch (value) {
      'ONGOING' => ReadingPublicationStatus.ongoing,
      'COMPLETED' => ReadingPublicationStatus.completed,
      'LICENSED' => ReadingPublicationStatus.licensed,
      'PUBLISHING_FINISHED' => ReadingPublicationStatus.publishingFinished,
      'CANCELLED' => ReadingPublicationStatus.cancelled,
      'ON_HIATUS' => ReadingPublicationStatus.onHiatus,
      _ => ReadingPublicationStatus.unknown,
    };
  }

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

  static bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

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

final class _SuwayomiCoreMediaReference implements MediaReference {
  const _SuwayomiCoreMediaReference(this.target);

  final String target;

  @override
  bool operator ==(Object other) =>
      other is _SuwayomiCoreMediaReference && target == other.target;

  @override
  int get hashCode => target.hashCode;
}

const _mediaTooLarge = EngineException(
  EngineFailure(
    kind: EngineFailureKind.operationRejected,
    code: 'engine_media_too_large',
    message: 'A mídia excede o limite permitido.',
    retryable: false,
  ),
);

const _externalMediaMaxBytes = 25 * 1024 * 1024;
