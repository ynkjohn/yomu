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
    );
    expect(s.host, '127.0.0.1');
    expect(s.isLoopbackOnly, isTrue);
    expect(s.allowOpenCors, isFalse);
  });

  test('health endpoint reports yomu and suwayomi on loopback', () async {
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18787,
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
      allowOpenCors: false,
      suwayomiStatus: () => const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
      ),
    );
    await s.start();
    addTearDown(s.stop);

    final res = await http.get(Uri.parse('http://127.0.0.1:18788/health'));
    expect(res.statusCode, 200);
    final acao = res.headers['access-control-allow-origin'];
    expect(acao, isNull);
  });

  test('open CORS only when explicitly enabled', () async {
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18789,
      allowOpenCors: true,
      suwayomiStatus: () => const SuwayomiStatus(
        state: SuwayomiProcessState.stopped,
      ),
    );
    await s.start();
    addTearDown(s.stop);

    final res = await http.get(Uri.parse('http://127.0.0.1:18789/health'));
    expect(res.headers['access-control-allow-origin'], '*');
  });

  test('loopback detection for localhost variants', () {
    expect(
      YomuServer(
        host: 'localhost',
        suwayomiStatus: () => const SuwayomiStatus(
          state: SuwayomiProcessState.stopped,
        ),
      ).isLoopbackOnly,
      isTrue,
    );
    expect(
      YomuServer(
        host: '0.0.0.0',
        suwayomiStatus: () => const SuwayomiStatus(
          state: SuwayomiProcessState.stopped,
        ),
      ).isLoopbackOnly,
      isFalse,
    );
  });
}
