import 'suwayomi_client.dart';
import 'suwayomi_models.dart';

/// High-level API using only GraphQL/REST paths confirmed in the matrix + Gate #1.
class SuwayomiApi {
  SuwayomiApi(this.client);

  final SuwayomiClient client;

  static const keiyoushiIndexUrl =
      'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json';

  /// jsDelivr rewrite used by some Suwayomi builds after add/sync.
  static const keiyoushiJsDelivrIndexUrl =
      'https://cdn.jsdelivr.net/gh/keiyoushi/extensions@repo/index.min.json';

  static const mangaDexPkg = 'eu.kanade.tachiyomi.extension.all.mangadex';

  /// Trusted Keiyoushi store URLs only (exact, not substring name match).
  static bool isTrustedKeiyoushiStore(ExtensionStoreInfo store) {
    final url = store.indexUrl.trim();
    return url == keiyoushiIndexUrl ||
        url == keiyoushiJsDelivrIndexUrl ||
        // Server may rewrite to protobuf index while keeping the same host path.
        url ==
            'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb' ||
        url ==
            'https://cdn.jsdelivr.net/gh/keiyoushi/extensions@repo/index.pb';
  }

  String absoluteUrl(String? pathOrUrl) {
    if (pathOrUrl == null || pathOrUrl.isEmpty) return '';
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    final base = client.baseUrl.endsWith('/')
        ? client.baseUrl.substring(0, client.baseUrl.length - 1)
        : client.baseUrl;
    return pathOrUrl.startsWith('/') ? '$base$pathOrUrl' : '$base/$pathOrUrl';
  }

  Future<Map<String, dynamic>?> about() => client.about();

  Future<List<ExtensionStoreInfo>> listExtensionStores() async {
    final body = await client.graphql(r'''
      query {
        extensionStores {
          nodes { name indexUrl isLegacy }
          totalCount
        }
      }
    ''');
    final nodes =
        (((body['data'] as Map?)?['extensionStores'] as Map?)?['nodes']
            as List?) ??
        [];
    return nodes
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => ExtensionStoreInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<ExtensionStoreInfo?> addExtensionStore(String indexUrl) async {
    final body = await client.graphql(
      r'''
      mutation($url: String!) {
        addExtensionStore(input: { indexUrl: $url }) {
          extensionStore { name indexUrl isLegacy }
        }
      }
      ''',
      variables: {'url': indexUrl},
    );
    final store =
        ((body['data'] as Map?)?['addExtensionStore']
                as Map?)?['extensionStore']
            as Map?;
    if (store == null) return null;
    return ExtensionStoreInfo.fromJson(Map<String, dynamic>.from(store));
  }

  Future<ExtensionStoreInfo?> ensureKeiyoushiStore() async {
    final stores = await listExtensionStores();
    final existing = stores.where(isTrustedKeiyoushiStore).toList();
    if (existing.isNotEmpty) return existing.first;
    final added = await addExtensionStore(keiyoushiIndexUrl);
    if (added == null) {
      throw StateError(
        'Falha ao adicionar o repositório Keiyoushi (resposta vazia).',
      );
    }
    if (!isTrustedKeiyoushiStore(added)) {
      // Server may rewrite URL; re-list and accept only trusted hosts.
      final refreshed = await listExtensionStores();
      final trusted = refreshed.where(isTrustedKeiyoushiStore).toList();
      if (trusted.isEmpty) {
        throw StateError(
          'Repositório adicionado, mas URL Keiyoushi confiável não encontrada.',
        );
      }
      return trusted.first;
    }
    return added;
  }

  Future<int> fetchExtensions() async {
    final body = await client.graphql(r'''
      mutation {
        fetchExtensions(input: {}) {
          extensions { pkgName }
        }
      }
      ''', timeout: const Duration(minutes: 2));
    final list =
        (((body['data'] as Map?)?['fetchExtensions'] as Map?)?['extensions']
            as List?) ??
        [];
    return list.length;
  }

  Future<List<ExtensionInfo>> listExtensions({String? query}) async {
    final body = await client.graphql(r'''
      query {
        extensions {
          nodes { pkgName name isInstalled versionName lang apkName }
          totalCount
        }
      }
    ''');
    final nodes =
        (((body['data'] as Map?)?['extensions'] as Map?)?['nodes'] as List?) ??
        [];
    var list = nodes
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => ExtensionInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (query != null && query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      list = list
          .where(
            (e) =>
                e.name.toLowerCase().contains(q) ||
                e.pkgName.toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
  }

  Future<ExtensionInfo> installExtension(String pkgName) async {
    final body = await client.graphql(
      r'''
      mutation($id: String!) {
        updateExtension(input: { id: $id, patch: { install: true } }) {
          extension { pkgName name isInstalled versionName lang }
        }
      }
      ''',
      variables: {'id': pkgName},
      timeout: const Duration(minutes: 2),
    );
    final ext =
        ((body['data'] as Map?)?['updateExtension'] as Map?)?['extension']
            as Map?;
    if (ext == null) {
      throw StateError('Install returned no extension for $pkgName');
    }
    return ExtensionInfo.fromJson(Map<String, dynamic>.from(ext));
  }

  Future<ExtensionInfo> uninstallExtension(String pkgName) async {
    final body = await client.graphql(
      r'''
      mutation($id: String!) {
        updateExtension(input: { id: $id, patch: { uninstall: true } }) {
          extension { pkgName name isInstalled versionName lang }
        }
      }
      ''',
      variables: {'id': pkgName},
    );
    final ext =
        ((body['data'] as Map?)?['updateExtension'] as Map?)?['extension']
            as Map?;
    if (ext == null) {
      throw StateError('Uninstall returned no extension for $pkgName');
    }
    return ExtensionInfo.fromJson(Map<String, dynamic>.from(ext));
  }

  Future<List<SourceInfo>> listSources() async {
    final body = await client.graphql(r'''
      query {
        sources {
          nodes { id name lang iconUrl }
          totalCount
        }
      }
    ''');
    final nodes =
        (((body['data'] as Map?)?['sources'] as Map?)?['nodes'] as List?) ?? [];
    return nodes
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => SourceInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<SourceMangaPage> fetchSourceManga({
    required String sourceId,
    required SourceMangaFetchType type,
    String? query,
    int page = 1,
  }) async {
    if (type == SourceMangaFetchType.search &&
        (query == null || query.trim().isEmpty)) {
      throw ArgumentError.value(query, 'query', 'Search query is required');
    }
    final typeName = switch (type) {
      SourceMangaFetchType.search => 'SEARCH',
      SourceMangaFetchType.popular => 'POPULAR',
      SourceMangaFetchType.latest => 'LATEST',
    };
    final body = await client.graphql(
      r'''
      mutation($source: LongString!, $type: FetchSourceMangaType!, $q: String, $page: Int!) {
        fetchSourceManga(input: {
          source: $source
          type: $type
          query: $q
          page: $page
        }) {
          mangas { id title thumbnailUrl inLibrary }
          hasNextPage
        }
      }
      ''',
      variables: {
        'source': sourceId,
        'type': typeName,
        'q': query?.trim(),
        'page': page,
      },
      timeout: const Duration(seconds: 60),
    );
    final payload =
        ((body['data'] as Map?)?['fetchSourceManga'] as Map?) ?? const {};
    final mangas = (payload['mangas'] as List?) ?? const [];
    return SourceMangaPage(
      items: mangas
          .whereType<Map<dynamic, dynamic>>()
          .map((item) => MangaSummary.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      hasNextPage: payload['hasNextPage'] == true,
      page: page,
    );
  }

  Future<List<MangaSummary>> searchManga({
    required String sourceId,
    required String query,
    int page = 1,
  }) async {
    final result = await fetchSourceManga(
      sourceId: sourceId,
      type: SourceMangaFetchType.search,
      query: query,
      page: page,
    );
    return result.items;
  }

  Future<MangaDetails> getManga(int id) async {
    final body = await client.graphql(
      r'''
      query($id: Int!) {
        manga(id: $id) {
          id
          title
          description
          author
          artist
          status
          thumbnailUrl
          sourceId
          inLibrary
        }
      }
      ''',
      variables: {'id': id},
    );
    final manga = ((body['data'] as Map?)?['manga'] as Map?);
    if (manga == null) throw StateError('Manga $id not found');
    return MangaDetails.fromJson(Map<String, dynamic>.from(manga));
  }

  /// Fetches remote chapters; returns empty list if source has none.
  Future<List<ChapterInfo>> fetchMangaChapters(int mangaId) async {
    try {
      final body = await client.graphql(
        r'''
        mutation($id: Int!) {
          fetchMangaAndChapters(input: {
            id: $id
            fetchManga: true
            fetchChapters: true
          }) {
            manga { id title }
            chapters {
              id
              name
              chapterNumber
              pageCount
              sourceOrder
              scanlator
              lastPageRead
              isRead
              isDownloaded
              mangaId
            }
          }
        }
        ''',
        variables: {'id': mangaId},
        timeout: const Duration(seconds: 90),
      );
      final chapters =
          (((body['data'] as Map?)?['fetchMangaAndChapters']
                  as Map?)?['chapters']
              as List?) ??
          [];
      return chapters
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => ChapterInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      // "No chapters found" is a valid empty state for some titles.
      final msg = e.toString();
      if (msg.contains('No chapters found')) return [];
      rethrow;
    }
  }

  Future<List<ChapterInfo>> listMangaChapters(int mangaId) async {
    final body = await client.graphql(
      r'''
      query($id: Int!) {
        manga(id: $id) {
          chapters {
            nodes {
              id
              name
              chapterNumber
              pageCount
              sourceOrder
              scanlator
              lastPageRead
              isRead
              isDownloaded
              mangaId
            }
            totalCount
          }
        }
      }
      ''',
      variables: {'id': mangaId},
    );
    final nodes =
        ((((body['data'] as Map?)?['manga'] as Map?)?['chapters']
                as Map?)?['nodes']
            as List?) ??
        [];
    return nodes
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => ChapterInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<ChapterPages> fetchChapterPages(int chapterId) async {
    final body = await client.graphql(
      r'''
      mutation($id: Int!) {
        fetchChapterPages(input: { chapterId: $id }) {
          pages
          chapter { id name pageCount lastPageRead isRead }
        }
      }
      ''',
      variables: {'id': chapterId},
      timeout: const Duration(seconds: 90),
    );
    final payload =
        ((body['data'] as Map?)?['fetchChapterPages'] as Map?) ?? {};
    final pagesRaw = payload['pages'];
    final pages = <String>[];
    if (pagesRaw is List) {
      for (final item in pagesRaw) {
        if (item is String && item.isNotEmpty) {
          pages.add(item);
        } else if (item is Map) {
          final url = item['url'] ?? item['imageUrl'] ?? item['path'];
          if (url != null && '$url'.isNotEmpty) pages.add('$url');
        }
      }
    }
    final chapter = payload['chapter'] as Map?;
    return ChapterPages(
      chapterId: chapterId,
      pages: pages,
      pageCount: chapter?['pageCount'] is int
          ? chapter!['pageCount'] as int
          : pages.length,
      chapterName: chapter?['name']?.toString(),
    );
  }

  // --- Library / progress / downloads (Phase 2C) ---

  Future<List<MangaSummary>> listLibrary() async {
    // Prefer condition filter used by modern Suwayomi GraphQL.
    try {
      final body = await client.graphql(r'''
        query {
          mangas(condition: { inLibrary: true }) {
            nodes {
              id
              title
              thumbnailUrl
              inLibrary
              unreadCount
              lastReadChapter {
                id
                name
                lastPageRead
                isRead
                pageCount
                chapterNumber
              }
            }
            totalCount
          }
        }
      ''');
      final nodes =
          (((body['data'] as Map?)?['mangas'] as Map?)?['nodes'] as List?) ??
          [];
      return nodes
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => MangaSummary.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      // Fallback: list all mangas and filter client-side.
      final body = await client.graphql(r'''
        query {
          mangas {
            nodes {
              id
              title
              thumbnailUrl
              inLibrary
              unreadCount
              lastReadChapter {
                id
                name
                lastPageRead
                isRead
                pageCount
                chapterNumber
              }
            }
          }
        }
      ''');
      final nodes =
          (((body['data'] as Map?)?['mangas'] as Map?)?['nodes'] as List?) ??
          [];
      return nodes
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => MangaSummary.fromJson(Map<String, dynamic>.from(e)))
          .where((m) => m.inLibrary)
          .toList();
    }
  }

  Future<MangaDetails> setInLibrary(int mangaId, bool inLibrary) async {
    final body = await client.graphql(
      r'''
      mutation($id: Int!, $inLibrary: Boolean!) {
        updateManga(input: { id: $id, patch: { inLibrary: $inLibrary } }) {
          manga {
            id
            title
            description
            author
            artist
            status
            thumbnailUrl
            sourceId
            inLibrary
          }
        }
      }
      ''',
      variables: {'id': mangaId, 'inLibrary': inLibrary},
    );
    final manga =
        ((body['data'] as Map?)?['updateManga'] as Map?)?['manga'] as Map?;
    if (manga == null) {
      throw StateError('updateManga returned null for $mangaId');
    }
    return MangaDetails.fromJson(Map<String, dynamic>.from(manga));
  }

  Future<ChapterInfo> updateChapterProgress({
    required int chapterId,
    required int lastPageRead,
    bool? isRead,
  }) async {
    final body = await client.graphql(
      r'''
      mutation($id: Int!, $page: Int!, $isRead: Boolean) {
        updateChapter(input: {
          id: $id
          patch: { lastPageRead: $page, isRead: $isRead }
        }) {
          chapter {
            id
            name
            lastPageRead
            isRead
            isDownloaded
            pageCount
            chapterNumber
            mangaId
          }
        }
      }
      ''',
      variables: {'id': chapterId, 'page': lastPageRead, 'isRead': isRead},
    );
    final ch =
        ((body['data'] as Map?)?['updateChapter'] as Map?)?['chapter'] as Map?;
    if (ch == null) {
      throw StateError('updateChapter returned null for $chapterId');
    }
    return ChapterInfo.fromJson(Map<String, dynamic>.from(ch));
  }

  Future<ChapterInfo?> getChapter(int chapterId) async {
    final body = await client.graphql(
      r'''
      query($id: Int!) {
        chapter(id: $id) {
          id
          name
          lastPageRead
          isRead
          isDownloaded
          pageCount
          chapterNumber
          mangaId
          scanlator
          sourceOrder
        }
      }
      ''',
      variables: {'id': chapterId},
    );
    final ch = ((body['data'] as Map?)?['chapter'] as Map?);
    if (ch == null) return null;
    return ChapterInfo.fromJson(Map<String, dynamic>.from(ch));
  }

  Future<DownloadStatusInfo> getDownloadStatus() async {
    final body = await client.graphql(r'''
      query {
        downloadStatus {
          state
          queue {
            state
            progress
            chapter {
              id
              name
              mangaId
              isDownloaded
              pageCount
            }
            manga {
              id
              title
              thumbnailUrl
              inLibrary
            }
          }
        }
      }
    ''');
    final raw = ((body['data'] as Map?)?['downloadStatus'] as Map?);
    if (raw == null) {
      return const DownloadStatusInfo(state: 'UNKNOWN', queue: []);
    }
    return DownloadStatusInfo.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> enqueueChapterDownloads(List<int> chapterIds) async {
    if (chapterIds.isEmpty) return;
    await client.graphql(
      r'''
      mutation($ids: [Int!]!) {
        enqueueChapterDownloads(input: { ids: $ids }) {
          downloadStatus { state }
        }
      }
      ''',
      variables: {'ids': chapterIds},
    );
  }

  Future<void> dequeueChapterDownloads(List<int> chapterIds) async {
    if (chapterIds.isEmpty) return;
    await client.graphql(
      r'''
      mutation($ids: [Int!]!) {
        dequeueChapterDownloads(input: { ids: $ids }) {
          downloadStatus { state }
        }
      }
      ''',
      variables: {'ids': chapterIds},
    );
  }

  Future<void> clearDownloader() async {
    await client.graphql(r'''
      mutation {
        clearDownloader {
          downloadStatus { state }
        }
      }
    ''');
  }

  Future<void> startDownloader() async {
    await client.graphql(r'''
      mutation {
        startDownloader {
          downloadStatus { state }
        }
      }
    ''');
  }

  Future<void> stopDownloader() async {
    await client.graphql(r'''
      mutation {
        stopDownloader {
          downloadStatus { state }
        }
      }
    ''');
  }
}
