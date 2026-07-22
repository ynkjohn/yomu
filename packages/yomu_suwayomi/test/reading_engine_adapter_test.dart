import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  test(
    'library adapter maps protocol DTOs to Yomu models and opaque media',
    () async {
      var mediaRequested = false;
      final client = MockClient((request) async {
        if (request.url.path == '/api/graphql') {
          return http.Response(
            jsonEncode({
              'data': {
                'mangas': {
                  'nodes': [
                    {
                      'id': 9,
                      'title': 'Biblioteca Yomu',
                      'thumbnailUrl': '/private/upstream/path',
                      'inLibrary': true,
                      'unreadCount': 2,
                      'lastReadChapter': {
                        'id': 3,
                        'name': 'Capítulo 3',
                        'lastPageRead': 4,
                      },
                    },
                  ],
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        mediaRequested = true;
        expect(request.url.path, '/api/v1/manga/9/thumbnail');
        expect(request.followRedirects, isFalse);
        return http.Response.bytes(
          const [1, 2, 3, 4],
          200,
          headers: {'content-type': 'image/jpeg; charset=binary'},
        );
      });
      final adapter = SuwayomiLibraryAdapter(
        SuwayomiApi(
          SuwayomiClient(baseUrl: 'http://127.0.0.1:14567', httpClient: client),
        ),
      );

      final library = await adapter.listLibrary();
      final manga = library.single;

      expect(manga.id, 9);
      expect(manga.title, 'Biblioteca Yomu');
      expect(manga.inLibrary, isTrue);
      expect(manga.unreadCount, 2);
      expect(
        manga.lastReadChapter,
        const LibraryResumePoint(id: 3, name: 'Capítulo 3', lastPageRead: 4),
      );
      expect(manga.thumbnail, isA<MediaReference>());
      expect(manga.thumbnail.toString(), isNot(contains('/private/upstream')));

      final payload = await adapter.fetch(manga.thumbnail!, maxBytes: 16);
      expect(payload.bytes, [1, 2, 3, 4]);
      expect(payload.contentType, 'image/jpeg');
      expect(mediaRequested, isTrue);
    },
  );

  test('library adapter sanitizes upstream errors', () async {
    final client = MockClient((_) async {
      return http.Response(
        jsonEncode({
          'errors': [
            {'message': r'GraphQL secret C:\private\engine.db'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final adapter = SuwayomiLibraryAdapter(
      SuwayomiApi(
        SuwayomiClient(baseUrl: 'http://127.0.0.1:14567', httpClient: client),
      ),
    );

    await expectLater(
      adapter.listLibrary(),
      throwsA(
        isA<EngineException>()
            .having(
              (error) => error.failure.code,
              'code',
              'engine_library_unavailable',
            )
            .having(
              (error) => error.failure.message,
              'sanitized message',
              isNot(contains('private')),
            ),
      ),
    );
  });

  test('media adapter fails closed when the byte limit is exceeded', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/graphql') {
        return http.Response(
          jsonEncode({
            'data': {
              'mangas': {
                'nodes': [
                  {
                    'id': 4,
                    'title': 'Capa grande',
                    'thumbnailUrl': '/thumbnail',
                    'inLibrary': true,
                  },
                ],
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response.bytes(const [1, 2, 3, 4, 5], 200);
    });
    final adapter = SuwayomiLibraryAdapter(
      SuwayomiApi(
        SuwayomiClient(baseUrl: 'http://127.0.0.1:14567', httpClient: client),
      ),
    );
    final reference = (await adapter.listLibrary()).single.thumbnail!;

    await expectLater(
      adapter.fetch(reference, maxBytes: 4),
      throwsA(
        isA<EngineException>().having(
          (error) => error.failure.code,
          'code',
          'engine_media_too_large',
        ),
      ),
    );
  });

  test('media adapter rejects foreign references', () async {
    final adapter = SuwayomiLibraryAdapter(
      SuwayomiApi(SuwayomiClient(baseUrl: 'http://127.0.0.1:14567')),
    );

    await expectLater(
      adapter.fetch(const _ForeignMediaReference(), maxBytes: 1),
      throwsA(
        isA<EngineException>().having(
          (error) => error.failure.code,
          'code',
          'engine_media_reference_invalid',
        ),
      ),
    );
  });
}

final class _ForeignMediaReference implements MediaReference {
  const _ForeignMediaReference();
}
