import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  test('listExtensionStores parses GraphQL nodes', () async {
    final mock = MockClient((request) async {
      expect(request.url.path, '/api/graphql');
      return http.Response(
        jsonEncode({
          'data': {
            'extensionStores': {
              'nodes': [
                {
                  'name': 'Keiyoushi',
                  'indexUrl':
                      'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
                  'isLegacy': false,
                },
              ],
              'totalCount': 1,
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = SuwayomiApi(
      SuwayomiClient(baseUrl: 'http://127.0.0.1:14567', httpClient: mock),
    );
    final stores = await api.listExtensionStores();
    expect(stores, hasLength(1));
    expect(stores.first.name, 'Keiyoushi');
    expect(stores.first.indexUrl, contains('keiyoushi'));
  });

  test('installExtension surfaces GraphQL errors', () async {
    final mock = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'errors': [
            {'message': 'boom'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = SuwayomiApi(
      SuwayomiClient(baseUrl: 'http://127.0.0.1:14567', httpClient: mock),
    );
    await expectLater(
      api.installExtension('eu.kanade.tachiyomi.extension.all.mangadex'),
      throwsA(isA<StateError>()),
    );
  });

  test('searchManga maps titles', () async {
    final mock = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'data': {
            'fetchSourceManga': {
              'mangas': [
                {
                  'id': 1,
                  'title': 'Berserk',
                  'thumbnailUrl': '/t/1',
                  'inLibrary': false,
                },
              ],
              'hasNextPage': false,
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = SuwayomiApi(
      SuwayomiClient(baseUrl: 'http://127.0.0.1:14567', httpClient: mock),
    );
    final results = await api.searchManga(sourceId: '1', query: 'berserk');
    expect(results.single.title, 'Berserk');
    expect(results.single.id, 1);
  });

  test('fetchSourceManga maps catalog type, page, and hasNextPage', () async {
    final mock = MockClient((request) async {
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      final variables = payload['variables'] as Map<String, dynamic>;
      expect(variables['type'], 'POPULAR');
      expect(variables['page'], 2);
      expect(variables['q'], isNull);
      return http.Response(
        jsonEncode({
          'data': {
            'fetchSourceManga': {
              'mangas': [
                {
                  'id': 41,
                  'title': 'Catálogo real',
                  'thumbnailUrl': '/thumb/41',
                  'inLibrary': true,
                },
              ],
              'hasNextPage': true,
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = SuwayomiApi(
      SuwayomiClient(baseUrl: 'http://127.0.0.1:14567', httpClient: mock),
    );

    final result = await api.fetchSourceManga(
      sourceId: '5123733616022476906',
      type: SourceMangaFetchType.popular,
      page: 2,
    );

    expect(result.page, 2);
    expect(result.hasNextPage, isTrue);
    expect(result.items.single.title, 'Catálogo real');
    expect(result.items.single.inLibrary, isTrue);
  });
  test('absoluteUrl prefixes loopback base', () {
    final api = SuwayomiApi(SuwayomiClient(baseUrl: 'http://127.0.0.1:14567'));
    expect(
      api.absoluteUrl('/api/v1/manga/1/page/0'),
      'http://127.0.0.1:14567/api/v1/manga/1/page/0',
    );
    expect(
      api.absoluteUrl('https://cdn.example/x.jpg'),
      'https://cdn.example/x.jpg',
    );
  });

  test('fetchMangaChapters treats No chapters found as empty', () async {
    final mock = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'errors': [
            {'message': 'No chapters found'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = SuwayomiApi(
      SuwayomiClient(baseUrl: 'http://127.0.0.1:14567', httpClient: mock),
    );
    final chapters = await api.fetchMangaChapters(1);
    expect(chapters, isEmpty);
  });

  test('listLibrary parses inLibrary nodes', () async {
    final mock = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'data': {
            'mangas': {
              'nodes': [
                {
                  'id': 9,
                  'title': 'Lib Title',
                  'thumbnailUrl': '/t/9',
                  'inLibrary': true,
                  'unreadCount': 2,
                  'lastReadChapter': {
                    'id': 3,
                    'name': 'Ch.3',
                    'lastPageRead': 4,
                    'isRead': false,
                    'pageCount': 20,
                  },
                },
              ],
              'totalCount': 1,
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = SuwayomiApi(
      SuwayomiClient(baseUrl: 'http://127.0.0.1:14567', httpClient: mock),
    );
    final lib = await api.listLibrary();
    expect(lib.single.title, 'Lib Title');
    expect(lib.single.lastReadChapter?.lastPageRead, 4);
  });

  test('updateChapterProgress maps lastPageRead', () async {
    final mock = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'data': {
            'updateChapter': {
              'chapter': {
                'id': 3,
                'name': 'Ch.3',
                'lastPageRead': 7,
                'isRead': false,
                'pageCount': 20,
                'mangaId': 9,
              },
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = SuwayomiApi(
      SuwayomiClient(baseUrl: 'http://127.0.0.1:14567', httpClient: mock),
    );
    final ch = await api.updateChapterProgress(
      chapterId: 3,
      lastPageRead: 7,
      isRead: false,
    );
    expect(ch.lastPageRead, 7);
    expect(ch.mangaId, 9);
  });

  test('isTrustedKeiyoushiStore aceita URLs oficiais e rejeita substring', () {
    expect(
      SuwayomiApi.isTrustedKeiyoushiStore(
        const ExtensionStoreInfo(
          name: 'Keiyoushi',
          indexUrl: SuwayomiApi.keiyoushiIndexUrl,
          isLegacy: false,
        ),
      ),
      isTrue,
    );
    expect(
      SuwayomiApi.isTrustedKeiyoushiStore(
        const ExtensionStoreInfo(
          name: 'Keiyoushi Impersonator',
          indexUrl: 'https://evil.example/keiyoushi/index.json',
          isLegacy: false,
        ),
      ),
      isFalse,
    );
  });

  test('ensureKeiyoushiStore falha quando add retorna null', () async {
    final mock = MockClient((request) async {
      final body = request.body;
      if (body.contains('extensionStores')) {
        return http.Response(
          jsonEncode({
            'data': {
              'extensionStores': {
                'nodes': <Map<String, Object?>>[],
                'totalCount': 0,
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // addExtensionStore returns null store
      return http.Response(
        jsonEncode({
          'data': {
            'addExtensionStore': {'extensionStore': null},
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = SuwayomiApi(
      SuwayomiClient(baseUrl: 'http://127.0.0.1:14567', httpClient: mock),
    );
    await expectLater(api.ensureKeiyoushiStore(), throwsA(isA<StateError>()));
  });

  test('ensureKeiyoushiStore reutiliza store confiável existente', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      return http.Response(
        jsonEncode({
          'data': {
            'extensionStores': {
              'nodes': [
                {
                  'name': 'Keiyoushi',
                  'indexUrl': SuwayomiApi.keiyoushiIndexUrl,
                  'isLegacy': false,
                },
              ],
              'totalCount': 1,
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = SuwayomiApi(
      SuwayomiClient(baseUrl: 'http://127.0.0.1:14567', httpClient: mock),
    );
    final store = await api.ensureKeiyoushiStore();
    expect(store?.name, 'Keiyoushi');
    expect(calls, 1); // list only, no add
  });

  test('getDownloadStatus parses queue', () async {
    final mock = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'data': {
            'downloadStatus': {
              'state': 'Started',
              'queue': [
                {
                  'state': 'Downloading',
                  'progress': 0.5,
                  'chapter': {'id': 1, 'name': 'Ch.1', 'mangaId': 2},
                  'manga': {
                    'id': 2,
                    'title': 'T',
                    'thumbnailUrl': null,
                    'inLibrary': true,
                  },
                },
              ],
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = SuwayomiApi(
      SuwayomiClient(baseUrl: 'http://127.0.0.1:14567', httpClient: mock),
    );
    final st = await api.getDownloadStatus();
    expect(st.state, 'Started');
    expect(st.queue.single.progress, 0.5);
    expect(st.queue.single.manga?.title, 'T');
  });
}
