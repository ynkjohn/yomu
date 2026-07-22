import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_local_server/yomu_local_server.dart';

void main() {
  test('reading routes preserve the authenticated /api/v1 wire', () async {
    final auth = DeviceAuthStore.inMemory();
    addTearDown(auth.close);
    final token = await _pair(auth);
    final engine = _FakeReadingEngine();
    final server = YomuServer(
      auth: auth,
      engineReadiness: engine,
      library: engine,
      mangaDetails: engine,
      reader: engine,
      progress: engine,
      catalog: engine,
      media: engine,
    );
    final handler = server.buildHandler();

    final library = await _json(
      await _request(handler, token, 'GET', '/api/v1/library'),
    );
    expect(library, {
      'items': [
        {
          'id': 7,
          'title': 'Yomu Library',
          'thumbnailUrl': '/api/v1/manga/7/thumbnail',
          'inLibrary': true,
          'unreadCount': 2,
          'lastReadChapter': {
            'id': 11,
            'name': 'Capítulo 11',
            'lastPageRead': 3,
          },
        },
      ],
    });

    final details = await _json(
      await _request(handler, token, 'GET', '/api/v1/manga/7'),
    );
    expect(details, {
      'id': 7,
      'title': 'Yomu Details',
      'description': 'Descrição',
      'author': 'Autora',
      'artist': 'Artista',
      'status': 'ONGOING',
      'thumbnailUrl': '/api/v1/manga/7/thumbnail',
      'sourceId': 'source-1',
      'inLibrary': true,
    });

    final membership = await _json(
      await _request(
        handler,
        token,
        'POST',
        '/api/v1/manga/7/library',
        body: {'inLibrary': false},
      ),
    );
    expect(membership, {'id': 7, 'inLibrary': false});

    final chapters = await _json(
      await _request(handler, token, 'GET', '/api/v1/manga/7/chapters'),
    );
    expect(chapters, {
      'items': [
        {
          'id': 11,
          'name': 'Capítulo 11',
          'chapterNumber': 11.5,
          'pageCount': 2,
          'lastPageRead': 3,
          'isRead': false,
          'isDownloaded': true,
          'scanlator': 'Yomu Scan',
        },
      ],
    });
    expect(engine.listChapterCalls, 1);

    final pages = await _json(
      await _request(handler, token, 'GET', '/api/v1/chapters/11/pages'),
    );
    expect(pages['chapterId'], 11);
    expect(pages['chapterName'], 'Capítulo 11');
    expect(pages['pageCount'], 2);
    expect(pages['mangaId'], 7);
    expect(pages['lastPageRead'], 3);
    final pageItems = pages['pages'] as List<dynamic>;
    expect(pageItems, hasLength(2));
    expect((pageItems.first as Map)['index'], 0);
    final ticketUrl = (pageItems.first as Map)['url'] as String;
    expect(ticketUrl, startsWith('/api/v1/media?t='));

    final ticketMedia = await _request(handler, token, 'GET', ticketUrl);
    expect(ticketMedia.statusCode, 200);
    expect(ticketMedia.headers['content-type'], 'image/png');
    expect(await _bytes(ticketMedia), [1, 2, 3]);

    final pageImage = await _request(
      handler,
      token,
      'GET',
      '/api/v1/chapters/11/pages/1/image',
    );
    expect(pageImage.statusCode, 200);
    expect(await _bytes(pageImage), [1, 2, 3]);

    final thumbnail = await _request(
      handler,
      token,
      'GET',
      '/api/v1/manga/7/thumbnail',
    );
    expect(thumbnail.statusCode, 200);
    expect(await _bytes(thumbnail), [1, 2, 3]);
    expect(engine.mediaLimits, everyElement(40 * 1024 * 1024));

    final progress = await _json(
      await _request(
        handler,
        token,
        'PUT',
        '/api/v1/chapters/11/progress',
        body: {'lastPageRead': 5, 'isRead': true},
      ),
    );
    expect(progress, {'id': 11, 'lastPageRead': 5, 'isRead': true});

    final sources = await _json(
      await _request(handler, token, 'GET', '/api/v1/sources'),
    );
    expect(sources, {
      'items': [
        {'id': 'source-1', 'name': 'Fonte Yomu', 'lang': 'pt-BR'},
      ],
    });

    final search = await _json(
      await _request(
        handler,
        token,
        'GET',
        '/api/v1/sources/source-1/search?q=yomu',
      ),
    );
    expect(search, {
      'items': [
        {
          'id': 8,
          'title': 'Resultado Yomu',
          'thumbnailUrl': '/api/v1/manga/8/thumbnail',
          'inLibrary': false,
        },
      ],
    });
  });

  test(
    'every reading route keeps authentication on its existing method',
    () async {
      final auth = DeviceAuthStore.inMemory();
      addTearDown(auth.close);
      final engine = _FakeReadingEngine();
      final handler = YomuServer(
        auth: auth,
        engineReadiness: engine,
        library: engine,
        mangaDetails: engine,
        reader: engine,
        progress: engine,
        catalog: engine,
        media: engine,
      ).buildHandler();
      final routes = <({String method, String path, Object? body})>[
        (method: 'GET', path: '/api/v1/library', body: null),
        (method: 'GET', path: '/api/v1/manga/7', body: null),
        (
          method: 'POST',
          path: '/api/v1/manga/7/library',
          body: {'inLibrary': true},
        ),
        (method: 'GET', path: '/api/v1/manga/7/chapters', body: null),
        (method: 'GET', path: '/api/v1/chapters/11/pages', body: null),
        (method: 'GET', path: '/api/v1/media?t=opaque', body: null),
        (method: 'GET', path: '/api/v1/chapters/11/pages/0/image', body: null),
        (method: 'GET', path: '/api/v1/manga/7/thumbnail', body: null),
        (
          method: 'PUT',
          path: '/api/v1/chapters/11/progress',
          body: {'lastPageRead': 3, 'isRead': false},
        ),
        (method: 'GET', path: '/api/v1/sources', body: null),
        (
          method: 'GET',
          path: '/api/v1/sources/source-1/search?q=yomu',
          body: null,
        ),
      ];

      for (final route in routes) {
        final response = await handler(
          Request(
            route.method,
            Uri.parse('http://127.0.0.1${route.path}'),
            headers: {
              if (route.body != null) 'content-type': 'application/json',
            },
            body: route.body == null ? null : jsonEncode(route.body),
          ),
        );
        expect(
          response.statusCode,
          401,
          reason: '${route.method} ${route.path}',
        );
        expect(await _json(response), {'error': 'unauthorized'});
      }
    },
  );

  test('EngineException keeps the v1 error and sanitized message', () async {
    final auth = DeviceAuthStore.inMemory();
    addTearDown(auth.close);
    final token = await _pair(auth);
    const engine = _EngineFailingLibraryGateway();
    final server = YomuServer(
      auth: auth,
      engineReadiness: const _FixedReadiness(),
      library: engine,
    );

    final response = await _request(
      server.buildHandler(),
      token,
      'GET',
      '/api/v1/library',
    );
    expect(response.statusCode, 502);
    expect(await _json(response), {
      'error': 'upstream_error',
      'message': 'Não foi possível carregar a biblioteca.',
    });
  });

  test('unexpected reading failures never expose upstream details', () async {
    final auth = DeviceAuthStore.inMemory();
    addTearDown(auth.close);
    final token = await _pair(auth);
    const engine = _ThrowingLibraryGateway(
      r'GraphQL secret C:\private\engine.db at 127.0.0.1:14567',
    );
    final server = YomuServer(
      auth: auth,
      engineReadiness: const _FixedReadiness(),
      library: engine,
    );

    final response = await _request(
      server.buildHandler(),
      token,
      'GET',
      '/api/v1/library',
    );
    expect(response.statusCode, 502);
    final body = await _json(response);
    expect(body['error'], 'upstream_error');
    expect(
      body['message'],
      'Recursos de leitura temporariamente indisponíveis.',
    );
    expect(jsonEncode(body), isNot(contains('GraphQL')));
    expect(jsonEncode(body), isNot(contains('private')));
    expect(jsonEncode(body), isNot(contains('14567')));
  });
}

Future<String> _pair(DeviceAuthStore auth) async {
  final pairing = auth.startPairing();
  final result = await auth.claimPairing(
    code: pairing.code,
    deviceName: 'Route test',
  );
  return result.bearerToken!;
}

Future<Response> _request(
  Handler handler,
  String token,
  String method,
  String path, {
  Map<String, Object?>? body,
}) async {
  return await handler(
    Request(
      method,
      Uri.parse('http://127.0.0.1$path'),
      headers: {
        'authorization': 'Bearer $token',
        if (body != null) 'content-type': 'application/json',
      },
      body: body == null ? null : jsonEncode(body),
    ),
  );
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, dynamic>;

Future<List<int>> _bytes(Response response) async {
  final bytes = <int>[];
  await for (final chunk in response.read()) {
    bytes.addAll(chunk);
  }
  return bytes;
}

final class _FakeReadingEngine
    implements
        EngineReadiness,
        LibraryGateway,
        MangaDetailsGateway,
        ReaderGateway,
        ReadingProgressGateway,
        CatalogGateway,
        EngineMediaGateway {
  static const cover7 = _TestMediaReference('cover-7');
  static const cover8 = _TestMediaReference('cover-8');
  static const page0 = _TestMediaReference('page-0');
  static const page1 = _TestMediaReference('page-1');

  int listChapterCalls = 0;
  final mediaLimits = <int>[];

  @override
  EngineReadinessSnapshot get current =>
      const EngineReadinessSnapshot(state: EngineReadinessState.ready);

  @override
  Stream<EngineReadinessSnapshot> get changes => const Stream.empty();

  @override
  Future<List<LibraryManga>> listLibrary() async => const [
    LibraryManga(
      id: 7,
      title: 'Yomu Library',
      thumbnail: cover7,
      inLibrary: true,
      unreadCount: 2,
      lastReadChapter: LibraryResumePoint(
        id: 11,
        name: 'Capítulo 11',
        lastPageRead: 3,
      ),
    ),
  ];

  @override
  Future<ReadingMangaDetails> getManga(int mangaId) async =>
      ReadingMangaDetails(
        id: mangaId,
        title: 'Yomu Details',
        description: 'Descrição',
        author: 'Autora',
        artist: 'Artista',
        status: ReadingPublicationStatus.ongoing,
        thumbnail: mangaId == 7 ? cover7 : cover8,
        sourceId: 'source-1',
        inLibrary: true,
      );

  @override
  Future<ReadingMangaDetails> setInLibrary(int mangaId, bool inLibrary) async =>
      ReadingMangaDetails(
        id: mangaId,
        title: 'Yomu Details',
        inLibrary: inLibrary,
      );

  @override
  Future<List<ReadingChapter>> listChapters(int mangaId) async {
    listChapterCalls++;
    return const [
      ReadingChapter(
        id: 11,
        name: 'Capítulo 11',
        chapterNumber: 11.5,
        pageCount: 2,
        scanlator: 'Yomu Scan',
        lastPageRead: 3,
        isDownloaded: true,
        mangaId: 7,
      ),
    ];
  }

  @override
  Future<List<ReadingChapter>> refreshChapters(int mangaId) =>
      listChapters(mangaId);

  @override
  Future<ReadingChapter?> getChapter(int chapterId) async => ReadingChapter(
    id: chapterId,
    name: 'Capítulo 11',
    pageCount: 2,
    lastPageRead: 3,
    mangaId: 7,
  );

  @override
  Future<ReadingChapterPages> getPages(int chapterId) async =>
      ReadingChapterPages(
        chapterId: chapterId,
        chapterName: 'Capítulo 11',
        pageCount: 2,
        pages: const [page0, page1],
      );

  @override
  Future<ReadingProgressSnapshot> updateProgress({
    required int chapterId,
    required int lastPageRead,
    required bool isRead,
  }) async => ReadingProgressSnapshot(
    chapterId: chapterId,
    lastPageRead: lastPageRead,
    isRead: isRead,
  );

  @override
  Future<List<CatalogSource>> listSources() async => const [
    CatalogSource(id: 'source-1', name: 'Fonte Yomu', language: 'pt-BR'),
  ];

  @override
  Future<CatalogPage> search({
    required String sourceId,
    required String query,
    int page = 1,
  }) async => CatalogPage(
    items: const [
      CatalogManga(id: 8, title: 'Resultado Yomu', thumbnail: cover8),
    ],
    page: page,
    hasNextPage: false,
  );

  @override
  Future<CatalogPage> popular({required String sourceId, int page = 1}) async =>
      CatalogPage(items: const [], page: page, hasNextPage: false);

  @override
  Future<CatalogPage> latest({required String sourceId, int page = 1}) async =>
      CatalogPage(items: const [], page: page, hasNextPage: false);

  @override
  Future<MediaPayload> fetch(
    MediaReference reference, {
    required int maxBytes,
  }) async {
    mediaLimits.add(maxBytes);
    return MediaPayload(bytes: const [1, 2, 3], contentType: 'image/png');
  }
}

final class _ThrowingLibraryGateway implements LibraryGateway {
  const _ThrowingLibraryGateway(this.message);

  final String message;

  @override
  Future<List<LibraryManga>> listLibrary() => Future.error(StateError(message));

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) =>
      Future.error(StateError(message));
}

final class _EngineFailingLibraryGateway implements LibraryGateway {
  const _EngineFailingLibraryGateway();

  @override
  Future<List<LibraryManga>> listLibrary() {
    throw const EngineException(
      EngineFailure(
        kind: EngineFailureKind.temporarilyUnavailable,
        code: 'engine_library_unavailable',
        message: 'Não foi possível carregar a biblioteca.',
        retryable: true,
      ),
    );
  }

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {
    await listLibrary();
  }
}

final class _FixedReadiness implements EngineReadiness {
  const _FixedReadiness();

  @override
  EngineReadinessSnapshot get current =>
      const EngineReadinessSnapshot(state: EngineReadinessState.ready);

  @override
  Stream<EngineReadinessSnapshot> get changes => const Stream.empty();
}

final class _TestMediaReference implements MediaReference {
  const _TestMediaReference(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is _TestMediaReference && value == other.value;

  @override
  int get hashCode => value.hashCode;
}
