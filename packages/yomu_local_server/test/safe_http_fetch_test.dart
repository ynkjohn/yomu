import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yomu_local_server/src/safe_http_fetch.dart'
    show safeHttpFetchForTest;
import 'package:yomu_local_server/yomu_local_server.dart';

void main() {
  test('blocks private and loopback IPv4', () {
    expect(SafeHttpFetch.isBlockedIp(InternetAddress('127.0.0.1')), isTrue);
    expect(SafeHttpFetch.isBlockedIp(InternetAddress('10.0.0.1')), isTrue);
    expect(SafeHttpFetch.isBlockedIp(InternetAddress('192.168.1.1')), isTrue);
    expect(SafeHttpFetch.isBlockedIp(InternetAddress('172.16.0.1')), isTrue);
    expect(SafeHttpFetch.isBlockedIp(InternetAddress('169.254.1.1')), isTrue);
    expect(SafeHttpFetch.isBlockedIp(InternetAddress('8.8.8.8')), isFalse);
  });

  test('blocks IPv4-mapped IPv6 private addresses', () {
    final mapped = InternetAddress('::ffff:192.168.0.1');
    expect(SafeHttpFetch.isBlockedIp(mapped), isTrue);
    final mappedPublic = InternetAddress('::ffff:8.8.8.8');
    expect(SafeHttpFetch.isBlockedIp(mappedPublic), isFalse);
  });

  test(
      'blocks special IPv6 ranges (ULA, docs, multicast, unspecified, 6to4, 100::/64)',
      () {
    expect(SafeHttpFetch.isBlockedIp(InternetAddress('fd12:3456::1')), isTrue);
    expect(
      SafeHttpFetch.isBlockedIp(InternetAddress('2001:db8::1')),
      isTrue,
    );
    expect(SafeHttpFetch.isBlockedIp(InternetAddress('ff02::1')), isTrue);
    expect(SafeHttpFetch.isBlockedIp(InternetAddress('::')), isTrue);
    // 6to4 2002::/16
    expect(
      SafeHttpFetch.isBlockedIp(InternetAddress('2002:cb00:7100::1')),
      isTrue,
    );
    // discard-only 100::/64 (RFC 6666)
    expect(SafeHttpFetch.isBlockedIp(InternetAddress('100::1')), isTrue);
    expect(SafeHttpFetch.isBlockedIp(InternetAddress('100:0:0:0::abcd')), isTrue);
    // public Google DNS-ish
    expect(
      SafeHttpFetch.isBlockedIp(InternetAddress('2001:4860:4860::8888')),
      isFalse,
    );
  });

  test('blocks localhost host literal', () {
    expect(SafeHttpFetch.isBlockedHostLiteral('localhost'), isTrue);
    expect(SafeHttpFetch.isBlockedHostLiteral('127.0.0.1'), isTrue);
    expect(SafeHttpFetch.isBlockedHostLiteral('::ffff:127.0.0.1'), isTrue);
  });

  test('production constructor blocks private DNS; test seam is not barrel API',
      () async {
    final prod = SafeHttpFetch(
      lookup: (h) async => [InternetAddress('127.0.0.1')],
    );
    await expectLater(
      prod.assertHostAllowed('pin-test.yomu.invalid'),
      throwsA(isA<StateError>()),
    );
    // Test seam: import src file (not package barrel).
    final seam = safeHttpFetchForTest(
      lookup: (h) async => [InternetAddress.loopbackIPv4],
      blockIp: (_) => false,
      blockHost: (h) => h.isEmpty,
    );
    final addrs = await seam.resolveSafeAddresses('pin-test.yomu.invalid');
    expect(addrs.single.isLoopback, isTrue);
  });

  test('assertHostAllowed rejects DNS answer with private IP (rebinding)',
      () async {
    final fetch = SafeHttpFetch(
      lookup: (host) async => [
        InternetAddress('8.8.8.8'),
        InternetAddress('10.0.0.1'),
      ],
    );
    await expectLater(
      fetch.assertHostAllowed('evil.example'),
      throwsA(isA<StateError>()),
    );
  });

  test('assertHostAllowed rejects pure loopback DNS', () async {
    final fetch = SafeHttpFetch(
      lookup: (host) async => [InternetAddress('127.0.0.1')],
    );
    await expectLater(
      fetch.assertHostAllowed('evil.example'),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'pinned socket via fictional hostname lookup (not IP literal) + redirects',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final port = server.port;
      var hits = 0;
      server.listen((req) async {
        hits++;
        if (req.uri.path == '/go') {
          req.response.statusCode = 302;
          req.response.headers.set(HttpHeaders.locationHeader, '/final');
          await req.response.close();
          return;
        }
        if (req.uri.path == '/final') {
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.text;
          req.response.write('pinned-ok');
          await req.response.close();
          return;
        }
        req.response.statusCode = 404;
        await req.response.close();
      });

      // Fictional hostname — never use 127.0.0.1 as the request host literal.
      const host = 'pin-test.yomu.invalid';
      final fetch = safeHttpFetchForTest(
        lookup: (h) async {
          expect(h, host);
          return [InternetAddress.loopbackIPv4];
        },
        // Test seam: allow the loopback answer from our stub DNS only.
        blockIp: (ip) => false,
        blockHost: (h) => h.isEmpty,
      );

      final result = await fetch.get(
        Uri.parse('http://$host:$port/go'),
      );
      expect(result.statusCode, 200);
      expect(utf8.decode(result.body), 'pinned-ok');
      expect(hits, greaterThanOrEqualTo(2));
    },
  );

  test('too many redirects fails (hostname + testing seam)', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final port = server.port;
    const host = 'redir-test.yomu.invalid';
    server.listen((req) async {
      req.response.statusCode = 302;
      req.response.headers.set(
        HttpHeaders.locationHeader,
        'http://$host:$port/loop',
      );
      await req.response.close();
    });

    final fetch = safeHttpFetchForTest(
      maxRedirects: 1,
      lookup: (h) async {
        expect(h, host);
        return [InternetAddress.loopbackIPv4];
      },
      blockIp: (_) => false,
      blockHost: (h) => h.isEmpty,
    );
    await expectLater(
      fetch.get(Uri.parse('http://$host:$port/loop')),
      throwsA(
        predicate((e) => e is StateError && '$e'.contains('too_many_redirects')),
      ),
    );
  });
}
