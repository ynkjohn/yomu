import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Validates absolute URLs for outbound Core fetches (SSRF hardened).
///
/// Resolves DNS, rejects private/special addresses, then **connects only to a
/// pinned validated IP** while keeping Host/SNI as the original hostname.
///
/// **App code:** use [SafeHttpFetch.new] only (exported from the package barrel).
/// **Tests:** use [safeHttpFetchForTest] from this library file — it is
/// intentionally **not** re-exported by `package:yomu_local_server`.
class SafeHttpFetch {
  /// Production constructor — always enforces private/special IP blocking.
  SafeHttpFetch({
    this.maxRedirects = 3,
    this.timeout = const Duration(seconds: 30),
    this.maxBytes = 25 * 1024 * 1024,
    this.lookup = InternetAddress.lookup,
  })  : _blockIp = isBlockedIp,
        _blockHost = isBlockedHostLiteral;

  /// Internal hooks for [safeHttpFetchForTest] only.
  SafeHttpFetch._hooks({
    this.maxRedirects = 3,
    this.timeout = const Duration(seconds: 30),
    this.maxBytes = 25 * 1024 * 1024,
    required this.lookup,
    required bool Function(InternetAddress ip) blockIp,
    required bool Function(String host) blockHost,
  })  : _blockIp = blockIp,
        _blockHost = blockHost;

  final int maxRedirects;
  final Duration timeout;
  final int maxBytes;
  final Future<List<InternetAddress>> Function(String host) lookup;

  final bool Function(InternetAddress ip) _blockIp;
  final bool Function(String host) _blockHost;

  static bool isBlockedIp(InternetAddress ip) {
    if (ip.isLoopback || ip.isLinkLocal) return true;
    final raw = ip.rawAddress;

    if (ip.type == InternetAddressType.IPv4 && raw.length == 4) {
      return _blockedIpv4(raw[0], raw[1], raw[2], raw[3]);
    }

    if (ip.type == InternetAddressType.IPv6 && raw.length == 16) {
      if (_isIpv4Mapped(raw)) {
        return _blockedIpv4(raw[12], raw[13], raw[14], raw[15]);
      }
      if (_isIpv4Compatible(raw)) {
        return _blockedIpv4(raw[12], raw[13], raw[14], raw[15]);
      }
      // fc00::/7 unique local
      if ((raw[0] & 0xfe) == 0xfc) return true;
      // ff00::/8 multicast
      if (raw[0] == 0xff) return true;
      // 2001:db8::/32 documentation
      if (raw[0] == 0x20 &&
          raw[1] == 0x01 &&
          raw[2] == 0x0d &&
          raw[3] == 0xb8) {
        return true;
      }
      // 2002::/16 6to4
      if (raw[0] == 0x20 && raw[1] == 0x02) return true;
      // 100::/64 discard-only (RFC 6666)
      if (raw[0] == 0x01 &&
          raw[1] == 0x00 &&
          raw[2] == 0 &&
          raw[3] == 0 &&
          raw[4] == 0 &&
          raw[5] == 0 &&
          raw[6] == 0 &&
          raw[7] == 0) {
        return true;
      }
      // :: unspecified
      if (raw.every((b) => b == 0)) return true;
    }
    return false;
  }

  static bool _isIpv4Mapped(List<int> raw) {
    for (var i = 0; i < 10; i++) {
      if (raw[i] != 0) return false;
    }
    return raw[10] == 0xff && raw[11] == 0xff;
  }

  static bool _isIpv4Compatible(List<int> raw) {
    for (var i = 0; i < 12; i++) {
      if (raw[i] != 0) return false;
    }
    if (raw[12] == 0 && raw[13] == 0 && raw[14] == 0 && raw[15] <= 1) {
      return false;
    }
    return true;
  }

  static bool _blockedIpv4(int a, int b, int c, int d) {
    if (a == 10) return true;
    if (a == 127) return true;
    if (a == 0) return true;
    if (a == 169 && b == 254) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a == 100 && b >= 64 && b <= 127) return true;
    if (a == 192 && b == 0 && c == 0) return true;
    if (a == 192 && b == 0 && c == 2) return true;
    if (a == 198 && (b == 18 || b == 19)) return true;
    if (a == 198 && b == 51 && c == 100) return true;
    if (a == 203 && b == 0 && c == 113) return true;
    if (a >= 224) return true;
    return false;
  }

  static bool isBlockedHostLiteral(String host) {
    var h = host.toLowerCase();
    if (h.startsWith('[') && h.endsWith(']')) {
      h = h.substring(1, h.length - 1);
    }
    if (h == 'localhost' ||
        h.endsWith('.localhost') ||
        h == '0.0.0.0' ||
        h == '::' ||
        h == '::1') {
      return true;
    }
    if (h.startsWith('::ffff:')) {
      final parsed = InternetAddress.tryParse(h.substring(7));
      if (parsed != null) return isBlockedIp(parsed);
    }
    final parsed = InternetAddress.tryParse(h);
    if (parsed != null) return isBlockedIp(parsed);
    return false;
  }

  Future<List<InternetAddress>> resolveSafeAddresses(String host) async {
    if (_blockHost(host)) {
      throw StateError('blocked_host: $host');
    }
    final literalHost =
        host.startsWith('[') && host.endsWith(']')
            ? host.substring(1, host.length - 1)
            : host;
    final literal = InternetAddress.tryParse(literalHost);
    if (literal != null) {
      if (_blockIp(literal)) {
        throw StateError('blocked_ip: ${literal.address}');
      }
      return [literal];
    }
    final addrs = await lookup(host).timeout(const Duration(seconds: 5));
    if (addrs.isEmpty) throw StateError('dns_empty: $host');
    final safe = <InternetAddress>[];
    for (final a in addrs) {
      if (_blockIp(a)) {
        throw StateError('blocked_ip_in_dns: ${a.address}');
      }
      safe.add(a);
    }
    if (safe.isEmpty) throw StateError('no_public_ip: $host');
    return safe;
  }

  Future<void> assertHostAllowed(String host) async {
    await resolveSafeAddresses(host);
  }

  Future<({int statusCode, String contentType, Uint8List body})> get(
    Uri start,
  ) async {
    var uri = start;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        throw StateError('invalid_scheme: ${uri.scheme}');
      }
      if (uri.host.isEmpty) throw StateError('empty_host');

      final safeAddrs = await resolveSafeAddresses(uri.host);
      final pinned = safeAddrs.first;
      final originalHost = uri.host;
      final port = uri.hasPort
          ? uri.port
          : (uri.scheme == 'https' ? 443 : 80);

      final client = HttpClient()
        ..connectionTimeout = timeout
        ..autoUncompress = true;

      client.connectionFactory = (url, proxyHost, proxyPort) {
        return _pinnedConnect(
          pinned: pinned,
          port: port,
          hostForSni: originalHost,
          https: url.scheme == 'https',
        );
      };

      try {
        // Detect rebinding between pin and connect.
        final recheck = await resolveSafeAddresses(originalHost);
        if (!recheck.any((a) => a.address == pinned.address)) {
          throw StateError('dns_rebinding_detected: $originalHost');
        }

        final req = await client.getUrl(uri).timeout(timeout);
        req.followRedirects = false;
        req.headers.set(HttpHeaders.hostHeader, originalHost);
        req.headers.set(HttpHeaders.userAgentHeader, 'YomuCore/2D');
        final res = await req.close().timeout(timeout);

        if (res.isRedirect ||
            res.statusCode == 301 ||
            res.statusCode == 302 ||
            res.statusCode == 303 ||
            res.statusCode == 307 ||
            res.statusCode == 308) {
          final loc = res.headers.value(HttpHeaders.locationHeader);
          await res.drain<void>();
          if (loc == null || loc.isEmpty) {
            throw StateError('redirect_without_location');
          }
          if (hop == maxRedirects) throw StateError('too_many_redirects');
          uri = uri.resolve(loc);
          continue;
        }

        final chunks = <List<int>>[];
        var total = 0;
        await for (final chunk in res.timeout(timeout)) {
          total += chunk.length;
          if (total > maxBytes) throw StateError('body_too_large');
          chunks.add(chunk);
        }
        final body = Uint8List(total);
        var o = 0;
        for (final c in chunks) {
          body.setRange(o, o + c.length, c);
          o += c.length;
        }
        final ct =
            res.headers.contentType?.mimeType ?? 'application/octet-stream';
        return (statusCode: res.statusCode, contentType: ct, body: body);
      } finally {
        client.close(force: true);
      }
    }
    throw StateError('fetch_failed');
  }

  Future<ConnectionTask<Socket>> _pinnedConnect({
    required InternetAddress pinned,
    required int port,
    required String hostForSni,
    required bool https,
  }) async {
    final task = await Socket.startConnect(pinned, port);
    final raw = await task.socket.timeout(timeout);
    if (!https) {
      return ConnectionTask.fromSocket(Future.value(raw), raw.destroy);
    }
    final secure = await SecureSocket.secure(
      raw,
      host: hostForSni,
    ).timeout(timeout);
    return ConnectionTask.fromSocket(Future.value(secure), secure.destroy);
  }
}

/// Test-only seam: custom DNS/block predicates without a public “disable SSRF”
/// flag on the production API.
///
/// **Not** re-exported from `package:yomu_local_server` — import this file:
/// `import 'package:yomu_local_server/src/safe_http_fetch.dart' show safeHttpFetchForTest;`
@visibleForTesting
SafeHttpFetch safeHttpFetchForTest({
  int maxRedirects = 3,
  Duration timeout = const Duration(seconds: 30),
  int maxBytes = 25 * 1024 * 1024,
  required Future<List<InternetAddress>> Function(String host) lookup,
  bool Function(InternetAddress ip)? blockIp,
  bool Function(String host)? blockHost,
}) {
  return SafeHttpFetch._hooks(
    maxRedirects: maxRedirects,
    timeout: timeout,
    maxBytes: maxBytes,
    lookup: lookup,
    blockIp: blockIp ?? SafeHttpFetch.isBlockedIp,
    blockHost: blockHost ?? SafeHttpFetch.isBlockedHostLiteral,
  );
}
