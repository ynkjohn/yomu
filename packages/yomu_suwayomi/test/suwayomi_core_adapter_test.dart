import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  test('maps manga details and library membership to Yomu models', () async {
    final mutations = <Map<String, dynamic>>[];
    final adapter = _adapter((request) async {
      final body = _graphqlBody(request);
      final query = body['query'] as String;
      if (query.contains('updateManga')) {
        mutations.add(body['variables'] as Map<String, dynamic>);
        return _graphqlResponse({
          'updateManga': {
            'manga': {
              'id': 7,
              'title': 'Yomu atualizado',
              'thumbnailUrl': '/private/upstream/cover',
              'sourceId': 'source-7',
              'inLibrary': false,
            },
          },
        });
      }
      return _graphqlResponse({
        'manga': {
          'id': 7,
          'title': 'Yomu detalhes',
          'description': 'Descrição',
          'author': 'Autora',
          'artist': 'Artista',
          'status': 'ONGOING',
          'thumbnailUrl': '/private/upstream/cover',
          'sourceId': 'source-7',
          'inLibrary': true,
        },
      });
    });

    final details = await adapter.getManga(7);
    final updated = await adapter.setInLibrary(7, false);

    expect(
      details,
      ReadingMangaDetails(
        id: 7,
        title: 'Yomu detalhes',
        description: 'Descrição',
        author: 'Autora',
        artist: 'Artista',
        status: 'ONGOING',
        thumbnail: details.thumbnail,
        sourceId: 'source-7',
        inLibrary: true,
      ),
    );
    expect(details.thumbnail, isA<MediaReference>());
    expect(details.thumbnail.toString(), isNot(contains('private/upstream')));
    expect(updated.inLibrary, isFalse);
    expect(mutations, [
      {'id': 7, 'inLibrary': false},
    ]);
  });

  test('falls back from stored chapters to upstream refresh', () async {
    final operations = <String>[];
    final adapter = _adapter((request) async {
      final query = _graphqlBody(request)['query'] as String;
      if (query.contains('chapter(id:')) {
        operations.add('get');
        return _graphqlResponse({
          'chapter': {
            'id': 11,
            'name': 'Capítulo 11',
            'chapterNumber': 11.5,
            'pageCount': 20,
            'scanlator': 'Yomu Scan',
            'lastPageRead': 3,
            'isDownloaded': true,
            'mangaId': 9,
          },
        });
      }
      if (query.contains('fetchMangaAndChapters')) {
        operations.add('refresh');
        return _graphqlResponse({
          'fetchMangaAndChapters': {
            'manga': {'id': 9, 'title': 'Yomu'},
            'chapters': [
              {
                'id': 11,
                'name': 'Capítulo 11',
                'chapterNumber': 11.5,
                'pageCount': 20,
                'scanlator': 'Yomu Scan',
                'lastPageRead': 3,
                'isRead': false,
                'isDownloaded': true,
                'mangaId': 9,
              },
            ],
          },
        });
      }
      operations.add('list');
      return _graphqlResponse({
        'manga': {
          'chapters': {'nodes': <Object?>[], 'totalCount': 0},
        },
      });
    });

    final chapters = await adapter.listChapters(9);
    final chapter = await adapter.getChapter(11);

    expect(operations, ['list', 'refresh', 'get']);
    expect(chapters, const [
      ReadingChapter(
        id: 11,
        name: 'Capítulo 11',
        chapterNumber: 11.5,
        pageCount: 20,
        scanlator: 'Yomu Scan',
        lastPageRead: 3,
        isDownloaded: true,
        mangaId: 9,
      ),
    ]);
    expect(chapter, chapters.single);
  });

  test('maps chapter pages to opaque relative media references', () async {
    var mediaRequested = false;
    final adapter = _adapter((request) async {
      if (request.url.path == '/api/graphql') {
        return _chapterPagesResponse('/api/v1/chapter/11/page/0');
      }
      mediaRequested = true;
      expect(request.url.path, '/api/v1/chapter/11/page/0');
      expect(request.followRedirects, isFalse);
      return http.Response.bytes(
        const [1, 2, 3],
        206,
        headers: {'content-type': 'image/webp; charset=binary'},
      );
    });

    final pages = await adapter.getPages(11);
    final reference = pages.pages.single;
    final payload = await adapter.fetch(reference, maxBytes: 4);

    expect(pages.chapterId, 11);
    expect(pages.chapterName, 'Capítulo 11');
    expect(pages.pageCount, 1);
    expect(reference.toString(), isNot(contains('/api/v1/')));
    expect(payload.bytes, [1, 2, 3]);
    expect(payload.contentType, 'image/webp');
    expect(payload.statusCode, 206);
    expect(mediaRequested, isTrue);
  });

  test('maps reading progress without exposing protocol DTOs', () async {
    Map<String, dynamic>? variables;
    final adapter = _adapter((request) async {
      final body = _graphqlBody(request);
      variables = body['variables'] as Map<String, dynamic>;
      return _graphqlResponse({
        'updateChapter': {
          'chapter': {
            'id': 11,
            'name': 'Capítulo 11',
            'lastPageRead': 8,
            'isRead': true,
            'mangaId': 7,
          },
        },
      });
    });

    final progress = await adapter.updateProgress(
      chapterId: 11,
      lastPageRead: 8,
      isRead: true,
    );

    expect(
      progress,
      const ReadingProgressSnapshot(
        chapterId: 11,
        lastPageRead: 8,
        isRead: true,
      ),
    );
    expect(variables, {'id': 11, 'page': 8, 'isRead': true});
  });

  test('filters source id zero and maps paged catalog search', () async {
    Map<String, dynamic>? searchVariables;
    final adapter = _adapter((request) async {
      final body = _graphqlBody(request);
      final query = body['query'] as String;
      if (query.contains('fetchSourceManga')) {
        searchVariables = body['variables'] as Map<String, dynamic>;
        return _graphqlResponse({
          'fetchSourceManga': {
            'mangas': [
              {
                'id': 41,
                'title': 'Resultado Yomu',
                'thumbnailUrl': 'https://cdn.example/cover.jpg',
                'inLibrary': true,
              },
            ],
            'hasNextPage': false,
          },
        });
      }
      return _graphqlResponse({
        'sources': {
          'nodes': [
            {'id': '0', 'name': 'Local source', 'lang': 'all'},
            {'id': 'source-1', 'name': 'Fonte Yomu', 'lang': 'pt-BR'},
          ],
          'totalCount': 2,
        },
      });
    });

    final sources = await adapter.listSources();
    final results = await adapter.search(
      sourceId: 'source-1',
      query: 'yomu',
      page: 3,
    );

    expect(sources, const [
      CatalogSource(id: 'source-1', name: 'Fonte Yomu', language: 'pt-BR'),
    ]);
    expect(results.single.id, 41);
    expect(results.single.title, 'Resultado Yomu');
    expect(results.single.inLibrary, isTrue);
    expect(results.single.thumbnail, isA<MediaReference>());
    expect(searchVariables, {
      'source': 'source-1',
      'type': 'SEARCH',
      'q': 'yomu',
      'page': 3,
    });
  });

  test('external media uses the SSRF-safe seam with a 25 MiB cap', () async {
    Uri? requestedUri;
    int? requestedLimit;
    final adapter = _adapter(
      (_) async => _chapterPagesResponse('https://cdn.example/page.jpg'),
      safeExternalMediaFetch: (uri, {required maxBytes}) async {
        requestedUri = uri;
        requestedLimit = maxBytes;
        return MediaPayload(
          bytes: const [4, 5, 6],
          contentType: 'image/jpeg',
          statusCode: 200,
        );
      },
    );
    final reference = (await adapter.getPages(11)).pages.single;

    final payload = await adapter.fetch(reference, maxBytes: 40 * 1024 * 1024);

    expect(requestedUri, Uri.parse('https://cdn.example/page.jpg'));
    expect(requestedLimit, 25 * 1024 * 1024);
    expect(payload.bytes, [4, 5, 6]);
  });

  test(
    'rejects redirects and media bodies above the requested limit',
    () async {
      final redirecting = _adapter((request) async {
        if (request.url.path == '/api/graphql') {
          return _chapterPagesResponse('/api/v1/page/redirect');
        }
        return http.Response('', 302, headers: {'location': '/private'});
      });
      final redirectReference = (await redirecting.getPages(11)).pages.single;
      await expectLater(
        redirecting.fetch(redirectReference, maxBytes: 8),
        throwsA(_engineFailureCode('engine_media_redirect_refused')),
      );

      final oversized = _adapter((request) async {
        if (request.url.path == '/api/graphql') {
          return _chapterPagesResponse('/api/v1/page/large');
        }
        return http.Response.bytes(const [1, 2, 3, 4, 5], 200);
      });
      final oversizedReference = (await oversized.getPages(11)).pages.single;
      await expectLater(
        oversized.fetch(oversizedReference, maxBytes: 4),
        throwsA(_engineFailureCode('engine_media_too_large')),
      );

      final externalOversized = _adapter(
        (_) async => _chapterPagesResponse('https://cdn.example/large.jpg'),
        safeExternalMediaFetch: (uri, {required maxBytes}) async {
          expect(maxBytes, 3);
          return MediaPayload(bytes: const [1, 2, 3, 4]);
        },
      );
      final externalReference = (await externalOversized.getPages(
        11,
      )).pages.single;
      await expectLater(
        externalOversized.fetch(externalReference, maxBytes: 3),
        throwsA(_engineFailureCode('engine_media_too_large')),
      );
    },
  );

  test('rejects foreign and traversal media references', () async {
    final adapter = _adapter(
      (_) async => _chapterPagesResponse('/api/v1/pages/%2e%2e/private'),
    );
    await expectLater(
      adapter.fetch(const _ForeignMediaReference(), maxBytes: 1024),
      throwsA(_engineFailureCode('engine_media_reference_invalid')),
    );

    final traversal = (await adapter.getPages(11)).pages.single;
    await expectLater(
      adapter.fetch(traversal, maxBytes: 1024),
      throwsA(_engineFailureCode('engine_media_path_invalid')),
    );
  });

  test('sanitizes upstream and SSRF fetch failures', () async {
    final graphqlFailure = _adapter((_) async {
      return http.Response(
        jsonEncode({
          'errors': [
            {'message': r'GraphQL secret C:\private\engine.db at 14567'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    await expectLater(
      graphqlFailure.getManga(7),
      throwsA(
        isA<EngineException>()
            .having(
              (error) => error.failure.code,
              'code',
              'engine_manga_unavailable',
            )
            .having(
              (error) => error.failure.message,
              'message',
              isNot(contains('private')),
            ),
      ),
    );

    final externalFailure = _adapter(
      (_) async => _chapterPagesResponse('https://blocked.example/page.jpg'),
      safeExternalMediaFetch: (uri, {required maxBytes}) {
        throw StateError(r'blocked_ip_in_dns: 127.0.0.1 C:\private\engine.db');
      },
    );
    final reference = (await externalFailure.getPages(11)).pages.single;
    await expectLater(
      externalFailure.fetch(reference, maxBytes: 1024),
      throwsA(
        isA<EngineException>()
            .having(
              (error) => error.failure.code,
              'code',
              'engine_media_unavailable',
            )
            .having(
              (error) => error.failure.message,
              'message',
              isNot(anyOf(contains('127.0.0.1'), contains('private'))),
            ),
      ),
    );
  });
}

SuwayomiCoreAdapter _adapter(
  Future<http.Response> Function(http.Request request) handler, {
  SafeExternalMediaFetch? safeExternalMediaFetch,
}) {
  return SuwayomiCoreAdapter(
    SuwayomiApi(
      SuwayomiClient(
        baseUrl: 'http://127.0.0.1:14567',
        httpClient: MockClient(handler),
      ),
    ),
    safeExternalMediaFetch:
        safeExternalMediaFetch ??
        (uri, {required maxBytes}) =>
            Future.error(StateError('unexpected_external_media')),
  );
}

Map<String, dynamic> _graphqlBody(http.Request request) {
  expect(request.url.path, '/api/graphql');
  return jsonDecode(request.body) as Map<String, dynamic>;
}

http.Response _graphqlResponse(Map<String, Object?> data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _chapterPagesResponse(String reference) => _graphqlResponse({
  'fetchChapterPages': {
    'pages': [reference],
    'chapter': {
      'id': 11,
      'name': 'Capítulo 11',
      'pageCount': 1,
      'lastPageRead': 0,
      'isRead': false,
    },
  },
});

Matcher _engineFailureCode(String code) =>
    isA<EngineException>().having((error) => error.failure.code, 'code', code);

final class _ForeignMediaReference implements MediaReference {
  const _ForeignMediaReference();
}
