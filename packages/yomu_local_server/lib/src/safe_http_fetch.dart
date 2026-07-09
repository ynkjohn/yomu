import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Validates absolute URLs for outbound Core fetches (SSRF hardened).
///
/// Defenses: scheme allowlist, host literal checks, DNS resolution (all A/AAAA),
/// IPv4-mapped IPv6, unique-local / special IPv6, re-check on every redirect.
/// Residual risk: TOCTOU DNS rebinding after connect is documented; we re-resolve
/// on each hop and reject mixed public+private answers.
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
      return _blockedIpv4(raw[0], raw[1], raw[2], raw[3]);
    }

    if (ip.type == InternetAddressType.IPv6 && raw.length == 16) {
      // IPv4-mapped ::ffff:a.b.c.d
      if (_isIpv4Mapped(raw)) {
        return _blockedIpv4(raw[12], raw[13], raw[14], raw[15]);
      }
      // IPv4-compatible obsolete ::a.b.c.d (first 96 bits zero, not ::1)
      if (_isIpv4Compatible(raw)) {
        return _blockedIpv4(raw[12], raw[13], raw[14], raw[15]);
      }
      // Unique local fc00::/7
      if ((raw[0] & 0xfe) == 0xfc) return true;
      // Multicast ff00::/8
      if (raw[0] == 0xff) return true;
      // Documentation 2001:db8::/32
      if (raw[0] == 0x20 &&
          raw[1] == 0x01 &&
          raw[2] == 0x0d &&
          raw[3] == 0xb8) {
        return true;
      }
      // 6to4 2002::/16 often tunnels RFC1918 — treat as blocked for safety
      if (raw[0] == 0x20 && raw[1] == 0x02) return true;
      // Discard-only 100::/64
      if (raw[0] == 0x01 &&
          raw[1] == 0x00 &&
          raw[2] == 0x00 &&
          raw[3] == 0x00) {
        return true;
      }
      // Unspecified ::
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
    // Exclude :: and ::1
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
    if (a == 100 && b >= 64 && b <= 127) return true; // CGNAT
    if (a == 192 && b == 0 && c == 0) return true;
    if (a == 192 && b == 0 && c == 2) return true; // TEST-NET-1
    if (a == 198 && (b == 18 || b == 19)) return true; // benchmark
    if (a == 198 && b == 51 && c == 100) return true; // TEST-NET-2
    if (a == 203 && b == 0 && c == 113) return true; // TEST-NET-3
    if (a >= 224) return true; // multicast / reserved
    return false;
  }

  static bool isBlockedHostLiteral(String host) {
    var h = host.toLowerCase();
    // Strip brackets from IPv6 literals
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
    // IPv4-mapped textual form
    if (h.startsWith('::ffff:')) {
      final v4 = h.substring(7);
      final parsed = InternetAddress.tryParse(v4);
      if (parsed != null) return isBlockedIp(parsed);
    }
    final parsed = InternetAddress.tryParse(h);
    if (parsed != null) return isBlockedIp(parsed);
    return false;
  }

  Future<void> assertHostAllowed(String host) async {
    if (isBlockedHostLiteral(host)) {
      throw StateError('blocked_host: $host');
    }
    // Literal IP already checked; skip DNS.
    if (InternetAddress.tryParse(
          host.startsWith('[') ? host.substring(1, host.length - 1) : host,
        ) !=
        null) {
      return;
    }
    final addrs = await lookup(host).timeout(const Duration(seconds: 5));
    if (addrs.isEmpty) throw StateError('dns_empty: $host');
    var anyPublic = false;
    var anyBlocked = false;
    for (final a in addrs) {
      if (isBlockedIp(a)) {
        anyBlocked = true;
      } else {
        anyPublic = true;
      }
    }
    // DNS rebinding risk: reject if ANY answer is private/special.
    if (anyBlocked) {
      throw StateError('blocked_ip_in_dns: $host');
    }
    if (!anyPublic) {
      throw StateError('no_public_ip: $host');
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
      // Re-resolve every hop (mitigates DNS rebinding between hops).
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
        return (statusCode: res.statusCode, contentType: ct, body: body);
      } finally {
        client.close(force: true);
      }
    }
    throw StateError('fetch_failed');
  }
}
