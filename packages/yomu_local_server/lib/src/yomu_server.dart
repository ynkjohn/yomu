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
import 'media_ticket_store.dart';
import 'safe_http_fetch.dart';

typedef SuwayomiStatusProvider = SuwayomiStatus Function();
typedef SuwayomiApiProvider = SuwayomiApi? Function();

/// Yomu local HTTP server: PWA static + authenticated API proxy to Suwayomi.
///
/// Phase 2D: media tickets (no open URL proxy), sanitized LAN health, CORS allowlist.
class YomuServer {
  YomuServer({
    required this.suwayomiStatus,
    required this.auth,
    this.apiProvider,
    this.pwaDir,
    this.host = '127.0.0.1',
    this.port = 8787,
    this.allowLanCors = false,
    this.allowedOrigins = const [],
    MediaTicketStore? mediaTickets,
    SafeHttpFetch? safeFetch,
    http.Client? httpClient,
  })  : mediaTickets = mediaTickets ?? MediaTicketStore(),
        safeFetch = safeFetch ?? SafeHttpFetch(),
        _http = httpClient ?? http.Client();

  final SuwayomiStatusProvider suwayomiStatus;
  final DeviceAuthStore auth;
  final SuwayomiApiProvider? apiProvider;
  final Directory? pwaDir;
  final String host;
  final int port;

  /// When true, CORS may reflect an Origin that is in [allowedOrigins].
  final bool allowLanCors;

  /// Explicit Origins allowed for LAN CORS (e.g. `http://192.168.0.10:8787`).
  final List<String> allowedOrigins;

  final MediaTicketStore mediaTickets;
  final SafeHttpFetch safeFetch;
  final http.Client _http;

  HttpServer? _server;

  int? get boundPort => _server?.port;
  String? get boundAddress => _server?.address.address;

  bool get isLoopbackOnly {
    final h = host.toLowerCase();
    return h == '127.0.0.1' || h == 'localhost' || h == '::1';
  }

  SuwayomiApi? get _api => apiProvider?.call();

  Handler buildHandler() {
    final router = Router();

    // --- Public (sanitized on LAN) ---
    router.get('/health', (Request request) {
      return _json(_healthPayload());
    });

    router.get('/api/v1/health', (Request request) async {
      return _json(_healthPayload());
    });

    router.post('/api/v1/pairing/claim', (Request request) async {
      final body = await _readJson(request);
      final code = '${body['code'] ?? ''}';
      final name = '${body['deviceName'] ?? 'iPhone'}';
      final clientKey = _clientKey(request);
      final outcome = await auth.claimPairing(
        code: code,
        deviceName: name,
        clientKey: clientKey,
      );
      switch (outcome.result) {
        case PairingClaimResult.rateLimited:
          return Response(
            429,
            body: jsonEncode({
              'error': 'rate_limited',
              'retryAfter': outcome.retryAfterSeconds,
            }),
            headers: {
              'content-type': 'application/json; charset=utf-8',
              if (outcome.retryAfterSeconds != null)
                'retry-after': '${outcome.retryAfterSeconds}',
            },
          );
        case PairingClaimResult.invalidOrExpired:
          return _json({'error': 'invalid_or_expired_code'}, status: 401);
        case PairingClaimResult.success:
          final session = outcome.session!;
          return _json({
            'token': session.token,
            'deviceName': session.deviceName,
            'createdAt': session.createdAt.toIso8601String(),
          });
      }
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
                'thumbnailUrl': _ticketMediaUrl(session.token, m.thumbnailUrl),
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
        'thumbnailUrl': _ticketMediaUrl(session.token, m.thumbnailUrl),
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
                  'url': _issueTicketUrl(session.token, e.value),
                },
              )
              .toList(),
        });
      }),
    );

    // Ticket-only media proxy — never accept raw `u=` absolute URLs from client.
    router.get('/api/v1/media', _auth((req, session) async {
      // Reject legacy open-proxy param first (SSRF surface).
      if (req.url.queryParameters.containsKey('u')) {
        return _json({'error': 'raw_url_forbidden'}, status: 400);
      }
      final ticketId = req.url.queryParameters['t'];
      if (ticketId == null || ticketId.isEmpty) {
        return _json({'error': 'missing_ticket'}, status: 400);
      }
      final ticket = mediaTickets.resolve(
        ticketId: ticketId,
        sessionToken: session.token,
      );
      if (ticket == null) {
        return _json({'error': 'invalid_or_expired_ticket'}, status: 404);
      }
      return _proxyMediaTarget(ticket.target);
    }));

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
        return _proxyMediaTarget(pages.pages[index]);
      }),
    );

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
                'thumbnailUrl': _ticketMediaUrl(session.token, m.thumbnailUrl),
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

    // Never log request bodies (may contain pairing codes) — use method/path only.
    var pipeline = const Pipeline().addMiddleware(_safeLogRequests());
    pipeline = pipeline.addMiddleware(_corsMiddleware());
    return pipeline.addHandler(handler);
  }

  Map<String, Object?> _healthPayload() {
    if (!isLoopbackOnly) {
      // LAN: minimal disclosure.
      final s = suwayomiStatus();
      return {
        'yomu': 'ok',
        'suwayomiReady': s.isReady,
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
    // Loopback: fuller diagnostics for desktop tooling.
    return {
      'yomu': 'ok',
      'bind': {
        'host': host,
        'port': boundPort ?? port,
        'loopbackOnly': true,
      },
      'suwayomi': {
        'state': suwayomiStatus().state.name,
        'isReady': suwayomiStatus().isReady,
      },
      'auth': {
        'sessions': auth.sessions.length,
        'pairingActive': auth.activePairing != null,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  String _clientKey(Request request) {
    final xff = request.headers['x-forwarded-for'];
    if (xff != null && xff.isNotEmpty) {
      return xff.split(',').first.trim();
    }
    final conn = request.context['shelf.io.connection_info'];
    if (conn is HttpConnectionInfo) {
      return conn.remoteAddress.address;
    }
    return 'unknown';
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

  String? _ticketMediaUrl(String sessionToken, String? path) {
    if (path == null || path.isEmpty) return null;
    final m = RegExp(r'/api/v1/manga/(\d+)/thumbnail').firstMatch(path);
    if (m != null) {
      return '/api/v1/manga/${m.group(1)}/thumbnail';
    }
    return _issueTicketUrl(sessionToken, path);
  }

  String _issueTicketUrl(String sessionToken, String target) {
    final id = mediaTickets.issue(
      sessionToken: sessionToken,
      target: target,
    );
    return '/api/v1/media?t=$id';
  }

  Future<Response> _proxyMediaTarget(String pathOrUrl) async {
    final api = _api;
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      try {
        final r = await safeFetch.get(Uri.parse(pathOrUrl));
        return Response(
          r.statusCode,
          body: r.body,
          headers: {
            'content-type': r.contentType,
            'cache-control': 'private, max-age=3600',
          },
        );
      } catch (e) {
        return _json(
          {'error': 'external_fetch_blocked', 'message': e.toString()},
          status: 502,
        );
      }
    }
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
    // Loopback Suwayomi only — not an open proxy.
    final uri = Uri.parse('$base$p');
    if (!_isLoopbackUri(uri)) {
      return _json({'error': 'upstream_not_loopback'}, status: 500);
    }
    final res =
        await _http.get(uri).timeout(const Duration(seconds: 60));
    return Response(
      res.statusCode,
      body: res.bodyBytes,
      headers: {
        'content-type': res.headers['content-type'] ?? 'application/octet-stream',
        'cache-control': 'private, max-age=3600',
      },
    );
  }

  bool _isLoopbackUri(Uri uri) {
    final h = uri.host.toLowerCase();
    return h == '127.0.0.1' || h == 'localhost' || h == '::1';
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

  Middleware _safeLogRequests() {
    return (inner) {
      return (request) async {
        final watch = Stopwatch()..start();
        final response = await inner(request);
        watch.stop();
        // Path only — never query (tickets) or body (codes).
        // ignore: avoid_print
        print(
          '${request.method} ${request.requestedUri.path} '
          '[${response.statusCode}] ${watch.elapsed}',
        );
        return response;
      };
    };
  }

  Middleware _corsMiddleware() {
    return (inner) {
      return (request) async {
        if (!allowLanCors) {
          // Same-origin default: no CORS headers.
          if (request.method == 'OPTIONS') {
            return Response(403);
          }
          return inner(request);
        }
        final origin = request.headers['origin'];
        final allowed = origin != null &&
            origin.isNotEmpty &&
            allowedOrigins.contains(origin);
        final headers = <String, String>{
          if (allowed) 'Access-Control-Allow-Origin': origin!,
          if (allowed)
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          if (allowed)
            'Access-Control-Allow-Headers': 'Authorization, Content-Type',
          if (allowed) 'Vary': 'Origin',
        };
        if (request.method == 'OPTIONS') {
          if (!allowed) return Response(403);
          return Response.ok('', headers: headers);
        }
        final response = await inner(request);
        if (!allowed) return response;
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
