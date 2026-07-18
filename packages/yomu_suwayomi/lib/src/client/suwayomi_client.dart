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
    try {
      final res = await _http
          .get(_u('/api/v1/settings/about'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
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
