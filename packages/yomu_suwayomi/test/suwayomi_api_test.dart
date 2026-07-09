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
                {'id': 1, 'title': 'Berserk', 'thumbnailUrl': '/t/1', 'inLibrary': false},
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

  test('absoluteUrl prefixes loopback base', () {
    final api = SuwayomiApi(
      SuwayomiClient(baseUrl: 'http://127.0.0.1:14567'),
    );
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
}
