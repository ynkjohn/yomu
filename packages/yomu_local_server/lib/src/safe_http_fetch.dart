import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Validates absolute URLs for outbound Core fetches (SSRF hardened).
class SafeHttpFetch {
  SafeHttpFetch({
    this.maxRedirects = 3,
    this.timeout = const Duration(seconds: 30),
    this.maxBytes = 25 * 1024 * 1024,
    this.lookup = InternetAddress.lookup,
  });

  final int maxRedirects;
  final Duration timeout;
  final int maxBytes;
  final Future<List<InternetAddress>> Function(String host) lookup;

  /// Returns true if [ip] is loopback / link-local / private / special.
  static bool isBlockedIp(InternetAddress ip) {
    if (ip.isLoopback || ip.isLinkLocal) return true;
    final raw = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4 && raw.length == 4) {
      final a = raw[0], b = raw[1];
      if (a == 10) return true; // 10/8
      if (a == 127) return true;
      if (a == 0) return true;
      if (a == 169 && b == 254) return true; // link-local
      if (a == 172 && b >= 16 && b <= 31) return true; // 172.16/12
      if (a == 192 && b == 168) return true; // 192.168/16
      if (a == 100 && b >= 64 && b <= 127) return true; // CGNAT 100.64/10
      if (a == 192 && b == 0 && raw[2] == 0) return true; // 192.0.0.0/24
      if (a >= 224) return true; // multicast / reserved
    }
    if (ip.type == InternetAddressType.IPv6) {
      // Unique local fc00::/7, link-local fe80::/10 already isLinkLocal
      if (raw.isNotEmpty && (raw[0] & 0xfe) == 0xfc) return true;
    }
    return false;
  }

  static bool isBlockedHostLiteral(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.localhost') || h == '0.0.0.0') {
      return true;
    }
    // Literal IP in host
    final parsed = InternetAddress.tryParse(host);
    if (parsed != null) return isBlockedIp(parsed);
    return false;
  }

  Future<void> assertHostAllowed(String host) async {
    if (isBlockedHostLiteral(host)) {
      throw StateError('blocked_host: $host');
    }
    final addrs = await lookup(host).timeout(const Duration(seconds: 5));
    if (addrs.isEmpty) throw StateError('dns_empty: $host');
    for (final a in addrs) {
      if (isBlockedIp(a)) {
        throw StateError('blocked_ip: ${a.address}');
      }
    }
  }

  /// GET with manual redirects; re-validates host/IP on each hop.
  Future<({int statusCode, String contentType, Uint8List body})> get(
    Uri start,
  ) async {
    var uri = start;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        throw StateError('invalid_scheme: ${uri.scheme}');
      }
      if (uri.host.isEmpty) throw StateError('empty_host');
      await assertHostAllowed(uri.host);

      final client = HttpClient()
        ..connectionTimeout = timeout
        ..maxConnectionsPerHost = 2
        ..autoUncompress = true;
      try {
        final req = await client.getUrl(uri).timeout(timeout);
        req.followRedirects = false;
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
          client.close(force: true);
          if (loc == null || loc.isEmpty) {
            throw StateError('redirect_without_location');
          }
          if (hop == maxRedirects) {
            throw StateError('too_many_redirects');
          }
          uri = uri.resolve(loc);
          continue;
        }

        final chunks = <List<int>>[];
        var total = 0;
        await for (final chunk in res.timeout(timeout)) {
          total += chunk.length;
          if (total > maxBytes) {
            throw StateError('body_too_large');
          }
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
        client.close(force: true);
        return (statusCode: res.statusCode, contentType: ct, body: body);
      } finally {
        client.close(force: true);
      }
    }
    throw StateError('fetch_failed');
  }
}
