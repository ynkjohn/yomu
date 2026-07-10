import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_local_server/yomu_local_server.dart';

void main() {
  test('default host is loopback-only', () {
    final s = YomuServer(
      suwayomiStatus: () => const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
      ),
      auth: DeviceAuthStore(),
    );
    expect(s.host, '127.0.0.1');
    expect(s.isLoopbackOnly, isTrue);
    expect(s.allowLanCors, isFalse);
  });

  test('health endpoint reports yomu and suwayomi on loopback', () async {
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18787,
      auth: DeviceAuthStore(),
      suwayomiStatus: () => const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
        message: 'test',
      ),
    );
    await s.start();
    addTearDown(s.stop);

    final res = await http.get(Uri.parse('http://127.0.0.1:18787/health'));
    expect(res.statusCode, 200);
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    expect(map['yomu'], 'ok');
    expect((map['suwayomi'] as Map)['state'], 'stopped');
    expect((map['bind'] as Map)['loopbackOnly'], isTrue);
  });

  test('LAN health is sanitized (no pid/sessions/pairing)', () async {
    // host 0.0.0.0 → isLoopbackOnly false → sanitized payload
    // Distinctive pid so substring checks are not poisoned by timestamps.
    const leakPid = 8675309;
    final lanServer = YomuServer(
      host: '0.0.0.0',
      port: 18794,
      auth: DeviceAuthStore(),
      suwayomiStatus: () => const SuwayomiStatus(
        state: SuwayomiProcessState.running,
        pid: leakPid,
        message: 'secret',
        baseUrl: 'http://127.0.0.1:14567',
      ),
    );
    await lanServer.start();
    addTearDown(lanServer.stop);
    final res = await http.get(Uri.parse('http://127.0.0.1:18794/health'));
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    expect(map['yomu'], 'ok');
    expect(map.containsKey('suwayomiReady'), isTrue);
    expect(map.containsKey('suwayomi'), isFalse);
    expect(map.containsKey('auth'), isFalse);
    expect(map.containsKey('bind'), isFalse);
    expect(map.containsKey('pid'), isFalse);
    expect(jsonEncode(map), isNot(contains('secret')));
    expect(jsonEncode(map), isNot(contains('14567')));
    expect(jsonEncode(map), isNot(contains('$leakPid')));
  });

  test('default CORS is not wildcard', () async {
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18788,
      allowLanCors: false,
      auth: DeviceAuthStore(),
      suwayomiStatus: () => const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
      ),
    );
    await s.start();
    addTearDown(s.stop);

    final res = await http.get(Uri.parse('http://127.0.0.1:18788/health'));
    expect(res.statusCode, 200);
    expect(res.headers['access-control-allow-origin'], isNull);
  });

  test('LAN CORS only for allowlisted Origin', () async {
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18789,
      allowLanCors: true,
      allowedOrigins: const ['http://192.168.1.10:8787'],
      auth: DeviceAuthStore(),
      suwayomiStatus: () => const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
      ),
    );
    await s.start();
    addTearDown(s.stop);

    final ok = await http.get(
      Uri.parse('http://127.0.0.1:18789/health'),
      headers: {'origin': 'http://192.168.1.10:8787'},
    );
    expect(ok.headers['access-control-allow-origin'], 'http://192.168.1.10:8787');
    expect(ok.headers['access-control-allow-origin'], isNot('*'));

    final denied = await http.get(
      Uri.parse('http://127.0.0.1:18789/health'),
      headers: {'origin': 'http://evil.example'},
    );
    expect(denied.headers['access-control-allow-origin'], isNull);
  });

  test('pairing claim issues token; API requires auth', () async {
    final auth = DeviceAuthStore();
    final pairing = auth.startPairing();
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18790,
      auth: auth,
      suwayomiStatus: () => const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
      ),
    );
    await s.start();
    addTearDown(s.stop);

    final denied = await http.get(Uri.parse('http://127.0.0.1:18790/api/v1/library'));
    expect(denied.statusCode, 401);

    final claim = await http.post(
      Uri.parse('http://127.0.0.1:18790/api/v1/pairing/claim'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'code': pairing.code, 'deviceName': 'TestPhone'}),
    );
    expect(claim.statusCode, 200);
    final token = (jsonDecode(claim.body) as Map)['token'] as String;
    expect(token, isNotEmpty);

    final me = await http.get(
      Uri.parse('http://127.0.0.1:18790/api/v1/me'),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(me.statusCode, 200);
    expect((jsonDecode(me.body) as Map)['deviceName'], 'TestPhone');
  });

  test('invalid pairing code rejected', () async {
    final auth = DeviceAuthStore();
    auth.startPairing();
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18791,
      auth: auth,
      suwayomiStatus: () => const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
      ),
    );
    await s.start();
    addTearDown(s.stop);

    final claim = await http.post(
      Uri.parse('http://127.0.0.1:18791/api/v1/pairing/claim'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'code': '000000', 'deviceName': 'X'}),
    );
    expect(claim.statusCode, 401);
  });

  test('JSON body: 400 invalid JSON, 413 too large, 400 invalid UTF-8', () async {
    final auth = DeviceAuthStore();
    auth.startPairing();
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18796,
      auth: auth,
      suwayomiStatus: () => const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
      ),
    );
    await s.start();
    addTearDown(s.stop);

    final bad = await http.post(
      Uri.parse('http://127.0.0.1:18796/api/v1/pairing/claim'),
      headers: {'content-type': 'application/json'},
      body: '{not-json',
    );
    expect(bad.statusCode, 400);
    expect(jsonDecode(bad.body)['error'], isNotNull);

    final huge = 'x' * (YomuServer.maxJsonBodyBytes + 100);
    final large = await http.post(
      Uri.parse('http://127.0.0.1:18796/api/v1/pairing/claim'),
      headers: {'content-type': 'application/json'},
      body: '{"code":"$huge"}',
    );
    expect(large.statusCode, 413);
    expect(jsonDecode(large.body)['error'], 'body_too_large');

    // Invalid UTF-8 sequence (0xFF is never valid in UTF-8).
    final utf8Bad = await http.post(
      Uri.parse('http://127.0.0.1:18796/api/v1/pairing/claim'),
      headers: {'content-type': 'application/json'},
      body: [0x7b, 0xff, 0x7d], // `{` + invalid + `}`
    );
    expect(utf8Bad.statusCode, 400);
    expect(jsonDecode(utf8Bad.body)['error'], 'utf8_invalid');
  });
  test('session revoke endpoint', () async {
    final auth = DeviceAuthStore();
    final pairing = auth.startPairing();
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18797,
      auth: auth,
      suwayomiStatus: () => const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
      ),
    );
    await s.start();
    addTearDown(s.stop);

    final claim = await http.post(
      Uri.parse('http://127.0.0.1:18797/api/v1/pairing/claim'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'code': pairing.code, 'deviceName': 'Phone'}),
    );
    final token = (jsonDecode(claim.body) as Map)['token'] as String;

    final rev = await http.post(
      Uri.parse('http://127.0.0.1:18797/api/v1/session/revoke'),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(rev.statusCode, 200);
    expect(jsonDecode(rev.body)['revoked'], isTrue);

    final me = await http.get(
      Uri.parse('http://127.0.0.1:18797/api/v1/me'),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(me.statusCode, 401);
  });

  test('raw media u= forbidden; ticket required', () async {
    final auth = DeviceAuthStore();
    final pairing = auth.startPairing();
    final tickets = MediaTicketStore();
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18792,
      auth: auth,
      mediaTickets: tickets,
      suwayomiStatus: () => const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
      ),
    );
    await s.start();
    addTearDown(s.stop);

    final claim = await http.post(
      Uri.parse('http://127.0.0.1:18792/api/v1/pairing/claim'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'code': pairing.code, 'deviceName': 'Phone'}),
    );
    final token = (jsonDecode(claim.body) as Map)['token'] as String;

    final raw = await http.get(
      Uri.parse(
        'http://127.0.0.1:18792/api/v1/media?u=${Uri.encodeQueryComponent('http://127.0.0.1:1/')}',
      ),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(raw.statusCode, 400);
    expect((jsonDecode(raw.body) as Map)['error'], 'raw_url_forbidden');

    final tid = tickets.issue(
      sessionToken: token,
      target: '/api/v1/manga/1/thumbnail',
    );
    final missingApi = await http.get(
      Uri.parse('http://127.0.0.1:18792/api/v1/media?t=$tid'),
      headers: {'authorization': 'Bearer $token'},
    );
    // No Suwayomi apiProvider → 502 upstream
    expect(missingApi.statusCode, anyOf(502, 400, 500));
  });

  test('pairing rate limit returns 429 + Retry-After', () async {
    final auth = DeviceAuthStore(maxFailedAttemptsPerPairingIp: 3);
    auth.startPairing();
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18795,
      auth: auth,
      suwayomiStatus: () => const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
      ),
    );
    await s.start();
    addTearDown(s.stop);

    Future<http.Response> bad() => http.post(
          Uri.parse('http://127.0.0.1:18795/api/v1/pairing/claim'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'code': '000000', 'deviceName': 'X'}),
        );

    await bad();
    await bad();
    final last = await bad();
    expect(last.statusCode, anyOf(401, 429));
    final blocked = await bad();
    expect(blocked.statusCode, 429);
    expect(blocked.headers['retry-after'], isNotNull);
  });
}
