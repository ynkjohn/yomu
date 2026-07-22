import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  test('schema probe splits Query and Mutation introspection', () async {
    final queries = <String>[];
    final client = SuwayomiClient(
      baseUrl: 'http://127.0.0.1:14567',
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final query = body['query'] as String;
        queries.add(query);
        expect(RegExp(r'fields\s*\{').allMatches(query), hasLength(1));
        final rootName = query.contains('queryType')
            ? 'queryType'
            : 'mutationType';
        return http.Response(
          jsonEncode({
            'data': {
              '__schema': {
                rootName: {
                  'fields': [
                    {
                      'name': rootName == 'queryType'
                          ? 'mangas'
                          : 'updateManga',
                    },
                  ],
                },
              },
            },
          }),
          200,
        );
      }),
    );

    final result = await client.probeGraphqlSchema();

    expect(result.failure, isNull);
    expect(result.value!.queryFields, ['mangas']);
    expect(result.value!.mutationFields, ['updateManga']);
    expect(queries, hasLength(2));
    expect(queries.first, contains('queryType'));
    expect(queries.last, contains('mutationType'));
  });

  test(
    'pinned artifact, about and GraphQL capabilities are compatible',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.dispose);
      final client = _client(
        queryFields: fixture.manifest.compatibility.requiredQueryFields,
        mutationFields: fixture.manifest.compatibility.requiredMutationFields,
      );

      final result = await SuwayomiCompatibilityProbe(
        client: client,
        manifest: fixture.manifest,
        artifact: fixture.artifact,
      ).run();

      expect(result.compatible, isTrue);
      expect(result.engineVersion, 'v2.3.2238-r2238');
      expect(result.protocolVersion, 'v1');
      expect(result.capabilities, contains('downloads'));
    },
  );

  test('missing pinned capability fails closed', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    final mutations = List<String>.from(
      fixture.manifest.compatibility.requiredMutationFields,
    )..remove('updateChapter');

    final result = await SuwayomiCompatibilityProbe(
      client: _client(
        queryFields: fixture.manifest.compatibility.requiredQueryFields,
        mutationFields: mutations,
      ),
      manifest: fixture.manifest,
      artifact: fixture.artifact,
    ).run();

    expect(result.compatible, isFalse);
    expect(
      result.failure!.kind,
      SuwayomiCompatibilityFailureKind.capabilityMismatch,
    );
  });

  test(
    'version mismatch is incompatible and message details stay internal',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.dispose);

      final result = await SuwayomiCompatibilityProbe(
        client: _client(
          version: 'v9.9.9',
          queryFields: fixture.manifest.compatibility.requiredQueryFields,
          mutationFields: fixture.manifest.compatibility.requiredMutationFields,
        ),
        manifest: fixture.manifest,
        artifact: fixture.artifact,
      ).run();

      expect(
        result.failure!.kind,
        SuwayomiCompatibilityFailureKind.versionMismatch,
      );
      expect(result.failure!.code, 'engine_version_incompatible');
    },
  );

  test('artifact mismatch fails before any protocol request', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    var requests = 0;
    final client = SuwayomiClient(
      baseUrl: 'http://127.0.0.1:14567',
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    await fixture.artifact.writeAsString('tampered');

    final result = await SuwayomiCompatibilityProbe(
      client: client,
      manifest: fixture.manifest,
      artifact: fixture.artifact,
    ).run();

    expect(
      result.failure!.kind,
      SuwayomiCompatibilityFailureKind.artifactInvalid,
    );
    expect(requests, 0);
  });

  test(
    'reachable malformed about is incompatible, not retryable unavailable',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.dispose);
      final client = SuwayomiClient(
        baseUrl: 'http://127.0.0.1:14567',
        httpClient: MockClient(
          (_) async => http.Response('{"version":[],"revision":"r2238"}', 200),
        ),
      );

      final result = await SuwayomiCompatibilityProbe(
        client: client,
        manifest: fixture.manifest,
        artifact: fixture.artifact,
      ).run();

      expect(
        result.failure!.kind,
        SuwayomiCompatibilityFailureKind.protocolMismatch,
      );
    },
  );

  test('GraphQL transport failure remains retryable unavailable', () async {
    final fixture = await _fixture();
    addTearDown(fixture.dispose);
    final client = SuwayomiClient(
      baseUrl: 'http://127.0.0.1:14567',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/v1/settings/about') {
          return http.Response(
            jsonEncode({'version': 'v2.3.2238', 'revision': 'r2238'}),
            200,
          );
        }
        throw const SocketException('offline');
      }),
    );

    final result = await SuwayomiCompatibilityProbe(
      client: client,
      manifest: fixture.manifest,
      artifact: fixture.artifact,
    ).run();

    expect(result.failure!.kind, SuwayomiCompatibilityFailureKind.unavailable);
  });
}

SuwayomiClient _client({
  String version = '2.3.2238',
  String revision = '2238',
  required List<String> queryFields,
  required List<String> mutationFields,
}) {
  return SuwayomiClient(
    baseUrl: 'http://127.0.0.1:14567',
    httpClient: MockClient((request) async {
      if (request.url.path == '/api/v1/settings/about') {
        return http.Response(
          jsonEncode({'version': version, 'revision': revision}),
          200,
        );
      }
      if (request.url.path == '/api/graphql') {
        return http.Response(
          jsonEncode({
            'data': {
              '__schema': {
                'queryType': {
                  'fields': queryFields.map((name) => {'name': name}).toList(),
                },
                'mutationType': {
                  'fields': mutationFields
                      .map((name) => {'name': name})
                      .toList(),
                },
              },
            },
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    }),
  );
}

Future<
  ({File artifact, VendorManifest manifest, Future<void> Function() dispose})
>
_fixture() async {
  final root = await Directory.systemTemp.createTemp('yomu-compat-');
  final artifact = File('${root.path}${Platform.pathSeparator}engine.jar');
  final bytes = utf8.encode('pinned-engine');
  await artifact.writeAsBytes(bytes);
  final hash = sha256.convert(bytes).toString();
  final manifest = VendorManifest(
    suwayomi: SuwayomiArtifact(
      version: 'v2.3.2238',
      revision: 'r2238',
      jarFile: 'engine.jar',
      downloadUrl: 'https://example.invalid/engine.jar',
      sourceUrl: 'https://example.invalid/source',
      sourceCommit: List.filled(40, 'a').join(),
      sourceArchiveFile: 'source.tar.gz',
      sourceArchiveUrl: 'https://example.invalid/source.tar.gz',
      sourceSha256: List.filled(64, 'b').join(),
      sourceRequiredEntries: const ['source/LICENSE'],
      checksumUrl: 'https://example.invalid/checksums',
      sha256: hash,
      minJre: 21,
      license: 'MPL-2.0',
      licenseUrl: 'https://example.invalid/license',
    ),
    compatibility: const EngineCompatibilitySpec(
      restApiVersion: 'v1',
      graphqlPath: '/api/graphql',
      capabilities: ['library', 'reader', 'downloads'],
      requiredQueryFields: ['mangas', 'manga', 'chapter', 'downloadStatus'],
      requiredMutationFields: [
        'updateManga',
        'updateChapter',
        'stopDownloader',
      ],
    ),
  );
  return (
    artifact: artifact,
    manifest: manifest,
    dispose: () => root.delete(recursive: true),
  );
}
