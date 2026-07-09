import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:yomu_core/yomu_core.dart';

typedef SuwayomiStatusProvider = SuwayomiStatus Function();

/// Yomu local HTTP server (health + optional static PWA stub).
///
/// Defaults to **loopback only** (`127.0.0.1`). Binding to LAN must be an
/// explicit future opt-in with device pairing — not enabled in Phase 2B.
///
/// Never proxies or exposes Suwayomi on the LAN.
class YomuServer {
  YomuServer({
    required this.suwayomiStatus,
    this.pwaDir,
    this.host = '127.0.0.1',
    this.port = 8787,
    this.allowOpenCors = false,
  });

  final SuwayomiStatusProvider suwayomiStatus;
  final Directory? pwaDir;

  /// Bind address. Default loopback — not `0.0.0.0`.
  final String host;
  final int port;

  /// When false (default), no `Access-Control-Allow-Origin: *` headers.
  final bool allowOpenCors;

  HttpServer? _server;

  int? get boundPort => _server?.port;
  String? get boundAddress => _server?.address.address;

  bool get isLoopbackOnly {
    final h = host.toLowerCase();
    return h == '127.0.0.1' || h == 'localhost' || h == '::1';
  }

  Handler buildHandler() {
    final router = Router();

    router.get('/health', (Request request) {
      final s = suwayomiStatus();
      final body = {
        'yomu': 'ok',
        'bind': {
          'host': host,
          'port': boundPort ?? port,
          'loopbackOnly': isLoopbackOnly,
        },
        'suwayomi': s.toJson(),
        'timestamp': DateTime.now().toIso8601String(),
        'note': isLoopbackOnly
            ? 'Yomu HTTP is loopback-only; PWA/LAN is not enabled.'
            : 'LAN bind active (requires future auth).',
      };
      return Response.ok(
        jsonEncode(body),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    router.get('/api/v1/health', (Request request) {
      return router.call(
        Request('GET', Uri.parse('http://local/health')),
      );
    });

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
    if (allowOpenCors) {
      pipeline = pipeline.addMiddleware(_openCors());
    }
    return pipeline.addHandler(handler);
  }

  /// Permissive CORS — **not** used by default. Reserved for explicit dev opt-in.
  Middleware _openCors() {
    const headers = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    };
    return (inner) {
      return (request) async {
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
}
