import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

import 'device_auth.dart';

typedef SuwayomiStatusProvider = SuwayomiStatus Function();
typedef SuwayomiApiProvider = SuwayomiApi? Function();

/// Yomu local HTTP server: PWA static + authenticated API proxy to Suwayomi.
///
/// - Default bind: `127.0.0.1` (loopback).
/// - LAN bind (`0.0.0.0`) only when [host] is set explicitly by the desktop app.
/// - Suwayomi is never bound to LAN; API calls go to loopback Suwayomi via [apiProvider].
class YomuServer {
  YomuServer({
    required this.suwayomiStatus,
    required this.auth,
    this.apiProvider,
    this.pwaDir,
    this.host = '127.0.0.1',
    this.port = 8787,
    this.allowLanCors = false,
  });

  final SuwayomiStatusProvider suwayomiStatus;
  final DeviceAuthStore auth;
  final SuwayomiApiProvider? apiProvider;
  final Directory? pwaDir;
  final String host;
  final int port;

  /// When LAN is enabled, allow browser Origin from phone (same network).
  /// Still requires Bearer token. Not a wildcard for unauthenticated routes only.
  final bool allowLanCors;

  HttpServer? _server;
  final _http = http.Client();

  int? get boundPort => _server?.port;
  String? get boundAddress => _server?.address.address;

  bool get isLoopbackOnly {
    final h = host.toLowerCase();
    return h == '127.0.0.1' || h == 'localhost' || h == '::1';
  }

  SuwayomiApi? get _api => apiProvider?.call();

  Handler buildHandler() {
    final router = Router();

    // --- Public ---
    router.get('/health', (Request request) {
      return _json({
        'yomu': 'ok',
        'bind': {
          'host': host,
          'port': boundPort ?? port,
          'loopbackOnly': isLoopbackOnly,
        },
        'suwayomi': suwayomiStatus().toJson(),
        'auth': {
          'sessions': auth.sessions.length,
          'pairingActive': auth.activePairing != null,
        },
        'timestamp': DateTime.now().toIso8601String(),
      });
    });

    router.get('/api/v1/health', (Request request) async {
      return router.call(Request('GET', Uri.parse('http://local/health')));
    });

    // Pairing claim is public (phone enters code). Start is desktop-only via Flutter.
    router.post('/api/v1/pairing/claim', (Request request) async {
      final body = await _readJson(request);
      final code = '${body['code'] ?? ''}';
      final name = '${body['deviceName'] ?? 'iPhone'}';
      final session = await auth.claimPairing(code: code, deviceName: name);
      if (session == null) {
        return _json({'error': 'invalid_or_expired_code'}, status: 401);
      }
      return _json({
        'token': session.token,
        'deviceName': session.deviceName,
        'createdAt': session.createdAt.toIso8601String(),
      });
    });

    // --- Authenticated API ---
    router.get('/api/v1/me', _auth((req, session) async {
      return _json({
        'deviceName': session.deviceName,
        'createdAt': session.createdAt.toIso8601String(),
      });
    }));

    router.get('/api/v1/library', _auth((req, session) async {
      final api = _requireApi();
      final list = await api.listLibrary();
      return _json({
        'items': list
            .map(
              (m) => {
                'id': m.id,
                'title': m.title,
                'thumbnailUrl': _publicMediaUrl(m.thumbnailUrl),
                'inLibrary': m.inLibrary,
                'unreadCount': m.unreadCount,
                'lastReadChapter': m.lastReadChapter == null
                    ? null
                    : {
                        'id': m.lastReadChapter!.id,
                        'name': m.lastReadChapter!.name,
                        'lastPageRead': m.lastReadChapter!.lastPageRead,
                      },
              },
            )
            .toList(),
      });
    }));

    router.get('/api/v1/manga/<id|[0-9]+>', _auth((req, session) async {
      final id = int.parse(req.params['id']!);
      final api = _requireApi();
      final m = await api.getManga(id);
      return _json({
        'id': m.id,
        'title': m.title,
        'description': m.description,
        'author': m.author,
        'artist': m.artist,
        'status': m.status,
        'thumbnailUrl': _publicMediaUrl(m.thumbnailUrl),
        'sourceId': m.sourceId,
        'inLibrary': m.inLibrary,
      });
    }));

    router.post('/api/v1/manga/<id|[0-9]+>/library', _auth((req, session) async {
      final id = int.parse(req.params['id']!);
      final body = await _readJson(req);
      final inLibrary = body['inLibrary'] == true;
      final api = _requireApi();
      final m = await api.setInLibrary(id, inLibrary);
      return _json({'id': m.id, 'inLibrary': m.inLibrary});
    }));

    router.get('/api/v1/manga/<id|[0-9]+>/chapters', _auth((req, session) async {
      final id = int.parse(req.params['id']!);
      final api = _requireApi();
      var chapters = await api.listMangaChapters(id);
      if (chapters.isEmpty) {
        chapters = await api.fetchMangaChapters(id);
      }
      return _json({
        'items': chapters
            .map(
              (c) => {
                'id': c.id,
                'name': c.name,
                'chapterNumber': c.chapterNumber,
                'pageCount': c.pageCount,
                'lastPageRead': c.lastPageRead,
                'isRead': c.isRead,
                'isDownloaded': c.isDownloaded,
                'scanlator': c.scanlator,
              },
            )
            .toList(),
      });
    }));

    router.get(
      '/api/v1/chapters/<id|[0-9]+>/pages',
      _auth((req, session) async {
        final id = int.parse(req.params['id']!);
        final api = _requireApi();
        final ch = await api.getChapter(id);
        final pages = await api.fetchChapterPages(id);
        final mangaId = ch?.mangaId;
        // Suwayomi page URLs use mangaId + chapter *index* (not DB chapter id),
        // e.g. /api/v1/manga/33/chapter/1/page/0. Always proxy that exact path.
        return _json({
          'chapterId': pages.chapterId,
          'chapterName': pages.chapterName,
          'pageCount': pages.pageCount,
          'mangaId': mangaId,
          'lastPageRead': ch?.lastPageRead,
          'pages': pages.pages
              .asMap()
              .entries
              .map(
                (e) => {
                  'index': e.key,
                  'url': _mediaProxyUrl(e.value),
                },
              )
              .toList(),
        });
      }),
    );

    // Authenticated media proxy — never expose Suwayomi port to the phone.
    // Query `u` = Suwayomi-relative path (/api/v1/...) or absolute http(s) URL.
    router.get('/api/v1/media', _auth((req, session) async {
      final raw = req.url.queryParameters['u'];
      if (raw == null || raw.isEmpty) {
        return _json({'error': 'missing_u'}, status: 400);
      }
      return _proxyMedia(raw);
    }));

    // Back-compat image route: resolve real Suwayomi path via page list
    // (must NOT rebuild path with chapter DB id — REST uses chapter index).
    router.get(
      '/api/v1/chapters/<id|[0-9]+>/pages/<index|[0-9]+>/image',
      _auth((req, session) async {
        final id = int.parse(req.params['id']!);
        final index = int.parse(req.params['index']!);
        final api = _requireApi();
        final pages = await api.fetchChapterPages(id);
        if (index < 0 || index >= pages.pages.length) {
          return _json({'error': 'page_out_of_range'}, status: 404);
        }
        return _proxyMedia(pages.pages[index]);
      }),
    );

    // Thumbnail proxy
    router.get('/api/v1/manga/<id|[0-9]+>/thumbnail', _auth((req, session) async {
      final id = int.parse(req.params['id']!);
      final api = _requireApi();
      return _proxyBytes(api.client.baseUrl, '/api/v1/manga/$id/thumbnail');
    }));

    router.put('/api/v1/chapters/<id|[0-9]+>/progress', _auth((req, session) async {
      final id = int.parse(req.params['id']!);
      final body = await _readJson(req);
      final page = body['lastPageRead'];
      final lastPageRead = page is int ? page : int.tryParse('$page') ?? 0;
      final isRead = body['isRead'] == true;
      final api = _requireApi();
      final ch = await api.updateChapterProgress(
        chapterId: id,
        lastPageRead: lastPageRead,
        isRead: isRead,
      );
      return _json({
        'id': ch.id,
        'lastPageRead': ch.lastPageRead,
        'isRead': ch.isRead,
      });
    }));

    router.get('/api/v1/sources', _auth((req, session) async {
      final api = _requireApi();
      final sources = await api.listSources();
      return _json({
        'items': sources
            .where((s) => s.id != '0')
            .map(
              (s) => {
                'id': s.id,
                'name': s.name,
                'lang': s.lang,
              },
            )
            .toList(),
      });
    }));

    router.get('/api/v1/sources/<id>/search', _auth((req, session) async {
      final sourceId = req.params['id']!;
      final q = req.url.queryParameters['q'] ?? '';
      if (q.isEmpty) {
        return _json({'error': 'missing_q'}, status: 400);
      }
      final api = _requireApi();
      final items = await api.searchManga(sourceId: sourceId, query: q);
      return _json({
        'items': items
            .map(
              (m) => {
                'id': m.id,
                'title': m.title,
                'thumbnailUrl': _publicMediaUrl(m.thumbnailUrl),
                'inLibrary': m.inLibrary,
              },
            )
            .toList(),
      });
    }));

    Handler handler = router.call;

    final dir = pwaDir;
    if (dir != null && dir.existsSync()) {
      final staticHandler = createStaticHandler(
        dir.path,
        defaultDocument: 'index.html',
      );
      handler = Cascade().add(router.call).add(staticHandler).handler;
    }

    var pipeline = const Pipeline().addMiddleware(logRequests());
    if (allowLanCors) {
      pipeline = pipeline.addMiddleware(_lanCors());
    }
    return pipeline.addHandler(handler);
  }

  Handler _auth(
    Future<Response> Function(Request req, DeviceSession session) inner,
  ) {
    return (Request request) async {
      final session = auth.authenticate(
        request.headers['authorization'],
      );
      if (session == null) {
        return _json({'error': 'unauthorized'}, status: 401);
      }
      try {
        return await inner(request, session);
      } catch (e) {
        return _json(
          {'error': 'upstream_error', 'message': e.toString()},
          status: 502,
        );
      }
    };
  }

  SuwayomiApi _requireApi() {
    final api = _api;
    if (api == null) {
      throw StateError('Suwayomi API unavailable (motor stopped?)');
    }
    return api;
  }

  String? _publicMediaUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    // Rewrite Suwayomi relative thumbs to authenticated Yomu routes when possible.
    final m = RegExp(r'/api/v1/manga/(\d+)/thumbnail').firstMatch(path);
    if (m != null) {
      return '/api/v1/manga/${m.group(1)}/thumbnail';
    }
    if (path.startsWith('/api/v1/')) {
      return _mediaProxyUrl(path);
    }
    if (path.startsWith('/')) return path;
    return path;
  }

  /// Public (authenticated) URL that streams a Suwayomi path/URL through Core.
  String _mediaProxyUrl(String suwayomiPathOrUrl) {
    return '/api/v1/media?u=${Uri.encodeQueryComponent(suwayomiPathOrUrl)}';
  }

  Future<Response> _proxyMedia(String pathOrUrl) async {
    final api = _api;
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      final res = await _http
          .get(Uri.parse(pathOrUrl))
          .timeout(const Duration(seconds: 60));
      return Response(
        res.statusCode,
        body: res.bodyBytes,
        headers: {
          'content-type': res.headers['content-type'] ?? 'image/jpeg',
          'cache-control': 'private, max-age=3600',
        },
      );
    }
    // Only allow Suwayomi API-relative paths (no open proxy).
    final cleaned = pathOrUrl.startsWith('/') ? pathOrUrl : '/$pathOrUrl';
    if (!cleaned.startsWith('/api/v1/') || cleaned.contains('..')) {
      return _json({'error': 'invalid_media_path'}, status: 400);
    }
    if (api == null) {
      return _json({'error': 'upstream_unavailable'}, status: 502);
    }
    return _proxyBytes(api.client.baseUrl, cleaned);
  }

  Future<Response> _proxyBytes(String baseUrl, String path) async {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    final res =
        await _http.get(Uri.parse('$base$p')).timeout(const Duration(seconds: 60));
    return Response(
      res.statusCode,
      body: res.bodyBytes,
      headers: {
        'content-type': res.headers['content-type'] ?? 'application/octet-stream',
        'cache-control': 'private, max-age=3600',
      },
    );
  }

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final raw = await request.readAsString();
    if (raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {};
  }

  Response _json(Object body, {int status = 200}) {
    return Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  /// CORS for LAN PWA served from same host is mostly unnecessary, but Safari
  /// edge cases may need it. Reflect request origin when present; never `*`.
  Middleware _lanCors() {
    return (inner) {
      return (request) async {
        final origin = request.headers['origin'];
        final headers = <String, String>{
          if (origin != null && origin.isNotEmpty)
            'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Authorization, Content-Type',
          'Vary': 'Origin',
        };
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: headers);
        }
        final response = await inner(request);
        return response.change(headers: {...response.headers, ...headers});
      };
    };
  }

  Future<void> start() async {
    _server = await shelf_io.serve(buildHandler(), host, port);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  void close() {
    _http.close();
  }
}
