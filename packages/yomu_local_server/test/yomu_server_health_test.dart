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

  test('LAN CORS reflects Origin when enabled', () async {
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18789,
      allowLanCors: true,
      auth: DeviceAuthStore(),
      suwayomiStatus: () => const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
      ),
    );
    await s.start();
    addTearDown(s.stop);

    final res = await http.get(
      Uri.parse('http://127.0.0.1:18789/health'),
      headers: {'origin': 'http://192.168.1.10:8787'},
    );
    expect(res.headers['access-control-allow-origin'], 'http://192.168.1.10:8787');
    expect(res.headers['access-control-allow-origin'], isNot('*'));
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

  test('media proxy rejects path traversal and requires auth', () async {
    final auth = DeviceAuthStore();
    final pairing = auth.startPairing();
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18792,
      auth: auth,
      suwayomiStatus: () => const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
      ),
    );
    await s.start();
    addTearDown(s.stop);

    final denied = await http.get(
      Uri.parse(
        'http://127.0.0.1:18792/api/v1/media?u=${Uri.encodeQueryComponent('/api/v1/manga/1/thumbnail')}',
      ),
    );
    expect(denied.statusCode, 401);

    final claim = await http.post(
      Uri.parse('http://127.0.0.1:18792/api/v1/pairing/claim'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'code': pairing.code, 'deviceName': 'Phone'}),
    );
    final token = (jsonDecode(claim.body) as Map)['token'] as String;

    final bad = await http.get(
      Uri.parse(
        'http://127.0.0.1:18792/api/v1/media?u=${Uri.encodeQueryComponent('../etc/passwd')}',
      ),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(bad.statusCode, 400);
  });
}
