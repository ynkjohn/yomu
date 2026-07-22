import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin HTTP client for Suwayomi loopback API (REST + GraphQL).
///
/// Full operation matrix is documented in docs/suwayomi-api-matrix.md and must
/// be validated against the pinned JAR before building UI for each capability.
class SuwayomiClient {
  SuwayomiClient({required this.baseUrl, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  /// Best-effort health: try REST about, then GraphQL trivial query, then root.
  Future<bool> isHealthy() async {
    try {
      final about = await _http
          .get(_u('/api/v1/settings/about'))
          .timeout(const Duration(seconds: 3));
      if (about.statusCode >= 200 && about.statusCode < 500) {
        // 401 still means server is up.
        return true;
      }
    } catch (_) {}

    try {
      final gql = await _http
          .post(
            _u('/api/graphql'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'query': '{ __typename }'}),
          )
          .timeout(const Duration(seconds: 3));
      if (gql.statusCode >= 200 && gql.statusCode < 500) return true;
    } catch (_) {}

    try {
      final root = await _http.get(_u('/')).timeout(const Duration(seconds: 3));
      return root.statusCode >= 200 && root.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> about() async {
    final result = await probeAbout();
    return result.value;
  }

  Future<SuwayomiAboutProbeResult> probeAbout() async {
    try {
      final res = await _http
          .get(_u('/api/v1/settings/about'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) {
        return const SuwayomiAboutProbeResult.incompatible();
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] is! String ||
          decoded['revision'] is! String) {
        return const SuwayomiAboutProbeResult.incompatible();
      }
      return SuwayomiAboutProbeResult.ok(decoded);
    } catch (_) {
      return const SuwayomiAboutProbeResult.unavailable();
    }
  }

  Future<SuwayomiGraphqlSchema?> graphqlSchema({
    String path = '/api/graphql',
  }) async {
    final result = await probeGraphqlSchema(path: path);
    return result.value;
  }

  Future<SuwayomiGraphqlSchemaProbeResult> probeGraphqlSchema({
    String path = '/api/graphql',
  }) async {
    try {
      // GraphQL Java rejects asking for `__Type.fields` more than once in a
      // single operation. Probe each root independently so the pinned engine's
      // introspection-good-faith protection remains enabled.
      final queryFields = await _probeGraphqlRootFields(
        path: path,
        operationName: 'YomuQueryCompatibilityProbe',
        rootName: 'queryType',
      );
      final mutationFields = await _probeGraphqlRootFields(
        path: path,
        operationName: 'YomuMutationCompatibilityProbe',
        rootName: 'mutationType',
      );
      return SuwayomiGraphqlSchemaProbeResult.ok(
        SuwayomiGraphqlSchema(
          queryFields: queryFields,
          mutationFields: mutationFields,
        ),
      );
    } on _IncompatibleGraphqlSchema {
      return const SuwayomiGraphqlSchemaProbeResult.incompatible();
    } catch (_) {
      return const SuwayomiGraphqlSchemaProbeResult.unavailable();
    }
  }

  Future<List<String>> _probeGraphqlRootFields({
    required String path,
    required String operationName,
    required String rootName,
  }) async {
    final res = await _http
        .post(
          _u(path),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'query':
                '''
              query $operationName {
                __schema {
                  $rootName { fields { name } }
                }
              }
            ''',
          }),
        )
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw const _IncompatibleGraphqlSchema();
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map || decoded['errors'] != null) {
      throw const _IncompatibleGraphqlSchema();
    }
    final data = decoded['data'];
    final schema = data is Map ? data['__schema'] : null;
    final fields = schema is Map ? _schemaFieldNames(schema[rootName]) : null;
    if (fields == null) throw const _IncompatibleGraphqlSchema();
    return fields;
  }

  static List<String>? _schemaFieldNames(Object? type) {
    if (type is! Map || type['fields'] is! List) return null;
    final out = <String>[];
    for (final field in type['fields'] as List) {
      if (field is! Map || field['name'] is! String) return null;
      out.add(field['name'] as String);
    }
    return out;
  }

  Future<Map<String, dynamic>> graphql(
    String query, {
    Map<String, dynamic>? variables,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final res = await _http
        .post(
          _u('/api/graphql'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'query': query,
            if (variables != null) 'variables': variables,
          }),
        )
        .timeout(timeout);
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) {
      throw StateError('GraphQL response is not a map (${res.statusCode})');
    }
    if (res.statusCode >= 400) {
      throw StateError('GraphQL HTTP ${res.statusCode}: ${res.body}');
    }
    if (body['errors'] != null) {
      throw StateError('GraphQL errors: ${body['errors']}');
    }
    return body;
  }

  Future<http.Response> restGet(String path) {
    return _http.get(_u(path)).timeout(const Duration(seconds: 30));
  }

  /// Starts a REST GET without buffering the response body or following
  /// redirects. Reading-engine adapters use this to enforce their own byte
  /// limits before media crosses the Yomu boundary.
  Future<http.StreamedResponse> restGetStream(
    String path, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    final request = http.Request('GET', _u(path))..followRedirects = false;
    return _http.send(request).timeout(timeout);
  }

  Future<http.Response> restPost(String path, {Object? body}) {
    return _http
        .post(
          _u(path),
          headers: {'Content-Type': 'application/json'},
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
  }
}

final class SuwayomiGraphqlSchema {
  SuwayomiGraphqlSchema({
    required Iterable<String> queryFields,
    required Iterable<String> mutationFields,
  }) : queryFields = List<String>.unmodifiable(queryFields),
       mutationFields = List<String>.unmodifiable(mutationFields);

  final List<String> queryFields;
  final List<String> mutationFields;
}

enum SuwayomiProbeFailure { unavailable, incompatible }

final class SuwayomiAboutProbeResult {
  const SuwayomiAboutProbeResult.ok(this.value) : failure = null;

  const SuwayomiAboutProbeResult.unavailable()
    : value = null,
      failure = SuwayomiProbeFailure.unavailable;

  const SuwayomiAboutProbeResult.incompatible()
    : value = null,
      failure = SuwayomiProbeFailure.incompatible;

  final Map<String, dynamic>? value;
  final SuwayomiProbeFailure? failure;
}

final class SuwayomiGraphqlSchemaProbeResult {
  const SuwayomiGraphqlSchemaProbeResult.ok(this.value) : failure = null;

  const SuwayomiGraphqlSchemaProbeResult.unavailable()
    : value = null,
      failure = SuwayomiProbeFailure.unavailable;

  const SuwayomiGraphqlSchemaProbeResult.incompatible()
    : value = null,
      failure = SuwayomiProbeFailure.incompatible;

  final SuwayomiGraphqlSchema? value;
  final SuwayomiProbeFailure? failure;
}

final class _IncompatibleGraphqlSchema implements Exception {
  const _IncompatibleGraphqlSchema();
}
