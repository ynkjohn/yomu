import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  test('trusts only exact official repository URLs', () async {
    final adapter = _adapter((_) async {
      return _graphqlResponse({
        'extensionStores': {
          'nodes': [
            _store('Raw JSON', _rawJsonUrl),
            _store('Raw protobuf', _rawProtobufUrl),
            _store('jsDelivr JSON', _jsDelivrJsonUrl),
            _store('jsDelivr protobuf', _jsDelivrProtobufUrl),
            _store(
              'Keiyoushi impostor',
              'https://evil.example/keiyoushi/extensions/repo/index.pb',
              isLegacy: true,
            ),
          ],
          'totalCount': 5,
        },
      });
    });

    final repositories = await adapter.listRepositories();

    expect(repositories.map((repository) => repository.recommended), [
      isTrue,
      isTrue,
      isTrue,
      isTrue,
      isFalse,
    ]);
    expect(repositories.last.state, ExtensionRepositoryState.legacy);
    expect(repositories.map((repository) => repository.name), [
      'Raw JSON',
      'Raw protobuf',
      'jsDelivr JSON',
      'jsDelivr protobuf',
      'Keiyoushi impostor',
    ]);
  });

  test('ensure reuses an existing trusted repository without adding', () async {
    var calls = 0;
    final adapter = _adapter((_) async {
      calls++;
      return _graphqlResponse({
        'extensionStores': {
          'nodes': [_store('Keiyoushi', '  $_jsDelivrProtobufUrl  ')],
          'totalCount': 1,
        },
      });
    });

    final repository = await adapter.ensureRecommendedRepository();

    expect(repository.name, 'Keiyoushi');
    expect(repository.recommended, isTrue);
    expect(calls, 1);
  });

  test('ensure adds the canonical repository when none exists', () async {
    final operations = <String>[];
    final adapter = _adapter((request) async {
      final body = _graphqlBody(request);
      final query = body['query'] as String;
      if (query.contains('addExtensionStore')) {
        operations.add('add');
        expect(body['variables'], {'url': _rawJsonUrl});
        return _graphqlResponse({
          'addExtensionStore': {
            'extensionStore': _store('Keiyoushi', _rawJsonUrl),
          },
        });
      }
      operations.add('list');
      return _emptyRepositoriesResponse();
    });

    final repository = await adapter.ensureRecommendedRepository();

    expect(repository.recommended, isTrue);
    expect(operations, ['list', 'add']);
  });

  test(
    'ensure accepts the trusted URL rewrite returned by the engine',
    () async {
      var listCalls = 0;
      final adapter = _adapter((request) async {
        final query = _graphqlBody(request)['query'] as String;
        if (query.contains('addExtensionStore')) {
          return _graphqlResponse({
            'addExtensionStore': {
              'extensionStore': _store('Keiyoushi', _jsDelivrProtobufUrl),
            },
          });
        }
        listCalls++;
        return _emptyRepositoriesResponse();
      });

      final repository = await adapter.ensureRecommendedRepository();

      expect(repository.recommended, isTrue);
      expect(listCalls, 1);
    },
  );

  test('ensure relists after a null add response', () async {
    var listCalls = 0;
    final adapter = _adapter((request) async {
      final query = _graphqlBody(request)['query'] as String;
      if (query.contains('addExtensionStore')) {
        return _graphqlResponse({
          'addExtensionStore': {'extensionStore': null},
        });
      }
      listCalls++;
      if (listCalls == 1) return _emptyRepositoriesResponse();
      return _graphqlResponse({
        'extensionStores': {
          'nodes': [_store('Keiyoushi', _rawProtobufUrl)],
          'totalCount': 1,
        },
      });
    });

    final repository = await adapter.ensureRecommendedRepository();

    expect(repository.recommended, isTrue);
    expect(listCalls, 2);
  });

  test(
    'ensure sanitizes a null add followed by a missing repository',
    () async {
      final adapter = _adapter((request) async {
        final query = _graphqlBody(request)['query'] as String;
        if (query.contains('addExtensionStore')) {
          return _graphqlResponse({
            'addExtensionStore': {'extensionStore': null},
          });
        }
        return _emptyRepositoriesResponse();
      });

      await expectLater(
        adapter.ensureRecommendedRepository(),
        throwsA(
          _engineFailure('engine_repository_setup_failed').having(
            (error) => error.failure.message,
            'sanitized message',
            allOf(
              isNot(contains('recommended_repository_missing')),
              isNot(contains(_rawJsonUrl)),
              isNot(contains('14567')),
            ),
          ),
        ),
      );
    },
  );

  test(
    'maps extensions to opaque references and recommendation flags',
    () async {
      final adapter = _adapter((_) async {
        return _graphqlResponse({
          'extensions': {
            'nodes': [
              _extension(
                packageId: _mangaDexPackageId,
                name: 'MangaDex',
                installed: true,
                language: 'all',
                version: '1.4.211',
              ),
              _extension(
                packageId: 'org.example.extension.pt.yomu',
                name: 'Yomu Source',
                installed: false,
                language: 'pt-BR',
                version: '2.0.0',
              ),
            ],
            'totalCount': 2,
          },
        });
      });

      final extensions = await adapter.listExtensions();

      expect(extensions.first.name, 'MangaDex');
      expect(extensions.first.installed, isTrue);
      expect(extensions.first.language, 'all');
      expect(extensions.first.version, '1.4.211');
      expect(extensions.first.recommended, isTrue);
      expect(extensions.last.recommended, isFalse);
      for (final extension in extensions) {
        expect(extension.reference, isA<ExtensionReference>());
        expect(extension.reference.toString(), 'ExtensionReference(opaque)');
        expect(
          extension.reference.toString(),
          isNot(anyOf(contains('tachiyomi'), contains('org.example'))),
        );
      }
    },
  );

  test('synchronizes the extension catalog and reports its count', () async {
    final adapter = _adapter((request) async {
      expect(
        _graphqlBody(request)['query'],
        contains('fetchExtensions(input: {})'),
      );
      return _graphqlResponse({
        'fetchExtensions': {
          'extensions': [
            {'pkgName': 'extension.one'},
            {'pkgName': 'extension.two'},
            {'pkgName': 'extension.three'},
          ],
        },
      });
    });

    expect(
      await adapter.synchronizeCatalog(),
      const ExtensionCatalogSync(count: 3),
    );
  });

  test('installs an extension using its opaque adapter reference', () async {
    final installedPackageIds = <Object?>[];
    final adapter = _adapter((request) async {
      final body = _graphqlBody(request);
      final query = body['query'] as String;
      if (query.contains('updateExtension')) {
        installedPackageIds.add(
          (body['variables'] as Map<String, dynamic>)['id'],
        );
        return _graphqlResponse({
          'updateExtension': {
            'extension': _extension(
              packageId: 'org.example.extension.pt.yomu',
              name: 'Yomu Source',
              installed: true,
            ),
          },
        });
      }
      return _graphqlResponse({
        'extensions': {
          'nodes': [
            _extension(
              packageId: 'org.example.extension.pt.yomu',
              name: 'Yomu Source',
              installed: false,
            ),
          ],
          'totalCount': 1,
        },
      });
    });
    final reference = (await adapter.listExtensions()).single.reference;

    final installed = await adapter.install(reference);

    expect(installed.name, 'Yomu Source');
    expect(installed.installed, isTrue);
    expect(installed.reference.toString(), 'ExtensionReference(opaque)');
    expect(installedPackageIds, ['org.example.extension.pt.yomu']);
  });

  test(
    'rejects a foreign extension reference before calling the engine',
    () async {
      var called = false;
      final adapter = _adapter((_) async {
        called = true;
        return _graphqlResponse(const <String, Object?>{});
      });

      expect(
        () => adapter.install(const _ForeignExtensionReference()),
        throwsA(
          isA<EngineException>()
              .having(
                (error) => error.failure.kind,
                'kind',
                EngineFailureKind.operationRejected,
              )
              .having(
                (error) => error.failure.code,
                'code',
                'engine_extension_reference_invalid',
              )
              .having((error) => error.failure.retryable, 'retryable', isFalse),
        ),
      );
      expect(called, isFalse);
    },
  );

  test(
    'installs the recommended extension without a prior catalog listing',
    () async {
      final adapter = _adapter((request) async {
        final body = _graphqlBody(request);
        expect(
          (body['variables'] as Map<String, dynamic>)['id'],
          _mangaDexPackageId,
        );
        return _graphqlResponse({
          'updateExtension': {
            'extension': _extension(
              packageId: _mangaDexPackageId,
              name: 'MangaDex',
              installed: true,
            ),
          },
        });
      });

      final installed = await adapter.installRecommendedExtension();

      expect(installed.name, 'MangaDex');
      expect(installed.installed, isTrue);
      expect(installed.recommended, isTrue);
      expect(installed.reference.toString(), 'ExtensionReference(opaque)');
    },
  );

  test('sanitizes a missing recommended extension', () async {
    final adapter = _adapter((request) async {
      final body = _graphqlBody(request);
      expect(
        (body['variables'] as Map<String, dynamic>)['id'],
        _mangaDexPackageId,
      );
      return _graphqlResponse({
        'updateExtension': {'extension': null},
      });
    });

    await expectLater(
      adapter.installRecommendedExtension(),
      throwsA(
        _engineFailure('engine_extension_install_failed').having(
          (error) => error.failure.message,
          'sanitized message',
          isNot(contains(_mangaDexPackageId)),
        ),
      ),
    );
  });

  test(
    'sanitizes upstream URLs, package ids, paths, and internal port',
    () async {
      final adapter = _adapter((_) async {
        return http.Response(
          jsonEncode({
            'errors': [
              {
                'message':
                    '$_rawJsonUrl $_mangaDexPackageId '
                    r'C:\private\extensions.db http://127.0.0.1:14567',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await expectLater(
        adapter.listRepositories(),
        throwsA(
          _engineFailure('engine_repositories_unavailable').having(
            (error) => error.failure.message,
            'sanitized message',
            allOf(
              isNot(contains('http://')),
              isNot(contains('https://')),
              isNot(contains(_mangaDexPackageId)),
              isNot(contains('private')),
              isNot(contains('14567')),
            ),
          ),
        ),
      );
    },
  );
}

SuwayomiExtensionsAdapter _adapter(
  Future<http.Response> Function(http.Request request) handler,
) => SuwayomiExtensionsAdapter(
  SuwayomiApi(
    SuwayomiClient(
      baseUrl: 'http://127.0.0.1:14567',
      httpClient: MockClient(handler),
    ),
  ),
);

Map<String, dynamic> _graphqlBody(http.Request request) {
  expect(request.url.path, '/api/graphql');
  return jsonDecode(request.body) as Map<String, dynamic>;
}

http.Response _graphqlResponse(Map<String, Object?> data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _emptyRepositoriesResponse() => _graphqlResponse({
  'extensionStores': {'nodes': <Object?>[], 'totalCount': 0},
});

Map<String, Object?> _store(
  String name,
  String indexUrl, {
  bool isLegacy = false,
}) => {'name': name, 'indexUrl': indexUrl, 'isLegacy': isLegacy};

Map<String, Object?> _extension({
  required String packageId,
  required String name,
  required bool installed,
  String? language,
  String? version,
}) => {
  'pkgName': packageId,
  'name': name,
  'isInstalled': installed,
  'lang': language,
  'versionName': version,
};

TypeMatcher<EngineException> _engineFailure(String code) =>
    isA<EngineException>().having((error) => error.failure.code, 'code', code);

final class _ForeignExtensionReference implements ExtensionReference {
  const _ForeignExtensionReference();
}

const _rawJsonUrl =
    'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json';
const _rawProtobufUrl =
    'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb';
const _jsDelivrJsonUrl =
    'https://cdn.jsdelivr.net/gh/keiyoushi/extensions@repo/index.min.json';
const _jsDelivrProtobufUrl =
    'https://cdn.jsdelivr.net/gh/keiyoushi/extensions@repo/index.pb';
const _mangaDexPackageId = 'eu.kanade.tachiyomi.extension.all.mangadex';
