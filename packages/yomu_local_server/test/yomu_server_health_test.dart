import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_local_server/yomu_local_server.dart';

void main() {
  test('default host is loopback-only', () {
    final s = YomuServer(
      engineReadiness: const _FixedReadiness.actionRequired(),
      auth: DeviceAuthStore.inMemory(),
    );
    expect(s.host, '127.0.0.1');
    expect(s.isLoopbackOnly, isTrue);
    expect(s.allowLanCors, isFalse);
  });

  test('health endpoint reports yomu and suwayomi on loopback', () async {
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18787,
      auth: DeviceAuthStore.inMemory(),
      engineReadiness: const _FixedReadiness.actionRequired(),
    );
    await s.start();
    addTearDown(s.stop);

    final res = await http.get(Uri.parse('http://127.0.0.1:18787/health'));
    expect(res.statusCode, 200);
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    expect(map['yomu'], 'ok');
    expect((map['readingEngine'] as Map)['state'], 'actionRequired');
    expect((map['readingEngine'] as Map)['isReady'], isFalse);
    expect((map['suwayomi'] as Map)['state'], 'stopped');
    expect((map['suwayomi'] as Map)['isReady'], isFalse);
    expect((map['bind'] as Map)['loopbackOnly'], isTrue);
  });

  test('LAN health is sanitized (no pid/sessions/pairing)', () async {
    // host 0.0.0.0 → isLoopbackOnly false → sanitized payload
    final lanServer = YomuServer(
      host: '0.0.0.0',
      port: 18794,
      auth: DeviceAuthStore.inMemory(),
      engineReadiness: const _FixedReadiness(
        EngineReadinessSnapshot(
          state: EngineReadinessState.ready,
          failure: EngineFailure(
            kind: EngineFailureKind.unknown,
            code: 'secret_code',
            message: 'secret 14567',
            retryable: false,
          ),
        ),
      ),
    );
    await lanServer.start();
    addTearDown(lanServer.stop);
    final res = await http.get(Uri.parse('http://127.0.0.1:18794/health'));
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    expect(map['yomu'], 'ok');
    expect(map['engineReady'], isTrue);
    expect(map.containsKey('suwayomiReady'), isTrue);
    expect(map.containsKey('suwayomi'), isFalse);
    expect(map.containsKey('auth'), isFalse);
    expect(map.containsKey('bind'), isFalse);
    expect(map.containsKey('pid'), isFalse);
    expect(jsonEncode(map), isNot(contains('secret')));
    expect(jsonEncode(map), isNot(contains('14567')));
  });

  test('default CORS is not wildcard', () async {
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18788,
      allowLanCors: false,
      auth: DeviceAuthStore.inMemory(),
      engineReadiness: const _FixedReadiness.actionRequired(),
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
      auth: DeviceAuthStore.inMemory(),
      engineReadiness: const _FixedReadiness.actionRequired(),
    );
    await s.start();
    addTearDown(s.stop);

    final ok = await http.get(
      Uri.parse('http://127.0.0.1:18789/health'),
      headers: {'origin': 'http://192.168.1.10:8787'},
    );
    expect(
      ok.headers['access-control-allow-origin'],
      'http://192.168.1.10:8787',
    );
    expect(ok.headers['access-control-allow-origin'], isNot('*'));

    final denied = await http.get(
      Uri.parse('http://127.0.0.1:18789/health'),
      headers: {'origin': 'http://evil.example'},
    );
    expect(denied.headers['access-control-allow-origin'], isNull);
  });

  test('pairing claim issues token; API requires auth', () async {
    final auth = DeviceAuthStore.inMemory();
    final pairing = auth.startPairing();
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18790,
      auth: auth,
      engineReadiness: const _FixedReadiness.actionRequired(),
    );
    await s.start();
    addTearDown(s.stop);

    final denied = await http.get(
      Uri.parse('http://127.0.0.1:18790/api/v1/library'),
    );
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

  test('closed auth returns sanitized 503 without echoing bearer', () async {
    final auth = DeviceAuthStore.inMemory();
    final pairing = auth.startPairing();
    final outcome = await auth.claimPairing(
      code: pairing.code,
      deviceName: 'Phone',
    );
    final token = outcome.bearerToken!;
    await auth.close();
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18798,
      auth: auth,
      engineReadiness: const _FixedReadiness.actionRequired(),
    );
    await s.start();
    addTearDown(s.stop);

    final response = await http.get(
      Uri.parse('http://127.0.0.1:18798/api/v1/me'),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(response.statusCode, 503);
    expect((jsonDecode(response.body) as Map)['error'], 'auth_unavailable');
    expect(response.body.contains(token), isFalse);
  });

  test('invalid pairing code rejected', () async {
    final auth = DeviceAuthStore.inMemory();
    auth.startPairing();
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18791,
      auth: auth,
      engineReadiness: const _FixedReadiness.actionRequired(),
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

  test(
    'JSON body: 400 invalid JSON, 413 too large, 400 invalid UTF-8',
    () async {
      final auth = DeviceAuthStore.inMemory();
      auth.startPairing();
      final s = YomuServer(
        host: '127.0.0.1',
        port: 18796,
        auth: auth,
        engineReadiness: const _FixedReadiness.actionRequired(),
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
    },
  );
  test('session revoke endpoint', () async {
    final auth = DeviceAuthStore.inMemory();
    final pairing = auth.startPairing();
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18797,
      auth: auth,
      engineReadiness: const _FixedReadiness.actionRequired(),
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
    final auth = DeviceAuthStore.inMemory();
    final pairing = auth.startPairing();
    final tickets = MediaTicketStore();
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18792,
      auth: auth,
      mediaTickets: tickets,
      engineReadiness: const _FixedReadiness.actionRequired(),
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
      sessionId: (await auth.authenticate(token))!.sessionId,
      reference: const _TestMediaReference('thumbnail-1'),
    );
    final missingApi = await http.get(
      Uri.parse('http://127.0.0.1:18792/api/v1/media?t=$tid'),
      headers: {'authorization': 'Bearer $token'},
    );
    // No media gateway → sanitized 502 upstream.
    expect(missingApi.statusCode, anyOf(502, 400, 500));
  });

  test('pairing rate limit returns 429 + Retry-After', () async {
    final auth = DeviceAuthStore.inMemory(maxFailedAttemptsPerPairingIp: 3);
    auth.startPairing();
    final s = YomuServer(
      host: '127.0.0.1',
      port: 18795,
      auth: auth,
      engineReadiness: const _FixedReadiness.actionRequired(),
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

  test(
    'shutdown drains admitted API request and rejects late request',
    () async {
      final auth = DeviceAuthStore.inMemory();
      addTearDown(auth.close);
      final token = await _pairToken(auth);
      final library = _BlockingLibrary();
      final server = YomuServer(
        auth: auth,
        library: library,
        engineReadiness: const _FixedReadiness.actionRequired(),
      );
      final handler = server.buildHandler();

      final admitted = handler(
        Request(
          'GET',
          Uri.parse('http://localhost/api/v1/library'),
          headers: {'authorization': 'Bearer $token'},
        ),
      );
      await library.entered.future;

      server.beginShutdown();
      var drainCompleted = false;
      final drain = server
          .drain(timeout: const Duration(seconds: 1))
          .whenComplete(() => drainCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(drainCompleted, isFalse);

      final late = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/api/v1/library'),
          headers: {'authorization': 'Bearer $token'},
        ),
      );
      expect(late.statusCode, 503);
      expect(jsonDecode(await late.readAsString()), {
        'error': 'shutting_down',
        'message': 'O Yomu está encerrando com segurança.',
      });
      expect(library.calls, 1);

      final health = await handler(
        Request('GET', Uri.parse('http://localhost/api/v1/health')),
      );
      expect(health.statusCode, 200);

      library.release.complete();
      expect((await admitted).statusCode, 200);
      expect(await drain, YomuServerDrainResult.drained);
    },
  );

  test('shutdown request drain has a bounded timeout', () async {
    final auth = DeviceAuthStore.inMemory();
    addTearDown(auth.close);
    final token = await _pairToken(auth);
    final library = _BlockingLibrary();
    final server = YomuServer(
      auth: auth,
      library: library,
      engineReadiness: const _FixedReadiness.actionRequired(),
    );
    final handler = server.buildHandler();

    final admitted = handler(
      Request(
        'GET',
        Uri.parse('http://localhost/api/v1/library'),
        headers: {'authorization': 'Bearer $token'},
      ),
    );
    await library.entered.future;
    server.beginShutdown();

    expect(
      await server.drain(timeout: Duration.zero),
      YomuServerDrainResult.timedOut,
    );

    library.release.complete();
    await admitted;
    expect(
      await server.drain(timeout: const Duration(seconds: 1)),
      YomuServerDrainResult.drained,
    );
  });

  test(
    'forced stop advances after an admitted request exceeds its drain',
    () async {
      final auth = DeviceAuthStore.inMemory();
      addTearDown(auth.close);
      final token = await _pairToken(auth);
      final library = _BlockingLibrary();
      final server = YomuServer(
        host: '127.0.0.1',
        port: 0,
        auth: auth,
        library: library,
        engineReadiness: const _FixedReadiness.actionRequired(),
      );
      await server.start();
      final client = http.Client();
      addTearDown(client.close);

      final admitted = client
          .get(
            Uri.parse('http://127.0.0.1:${server.boundPort}/api/v1/library'),
            headers: {'authorization': 'Bearer $token'},
          )
          .then<Object>(
            (response) => response,
            onError: (Object error) => error,
          );
      await library.entered.future;
      server.beginShutdown();
      expect(
        await server.drain(timeout: Duration.zero),
        YomuServerDrainResult.timedOut,
      );

      await server.stop(force: true).timeout(const Duration(seconds: 1));
      library.release.complete();
      await admitted;
    },
  );

  test(
    'progress request admitted before shutdown keeps its mutation lease',
    () async {
      final auth = DeviceAuthStore.inMemory();
      addTearDown(auth.close);
      final token = await _pairToken(auth);
      final upstream = _RecordingProgress();
      final progress = ReadingProgressCoordinator(upstream);
      final server = YomuServer(
        auth: auth,
        progress: progress,
        engineReadiness: const _FixedReadiness.actionRequired(),
      );
      final handler = server.buildHandler();
      final body = StreamController<List<int>>();

      final admitted = handler(
        Request(
          'PUT',
          Uri.parse('http://localhost/api/v1/chapters/11/progress'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/json',
          },
          body: body.stream,
        ),
      );
      server.beginShutdown();
      progress.stopAccepting();
      body.add(utf8.encode('{"lastPageRead":4,"isRead":false}'));
      await body.close();

      final response = await admitted;
      expect(response.statusCode, 200);
      expect(upstream.calls, 1);
      expect(progress.isAccepting, isFalse);

      final late = await handler(
        Request(
          'PUT',
          Uri.parse('http://localhost/api/v1/chapters/11/progress'),
          headers: {'authorization': 'Bearer $token'},
          body: '{"lastPageRead":5,"isRead":false}',
        ),
      );
      expect(late.statusCode, 503);
    },
  );
}

Future<String> _pairToken(DeviceAuthStore auth) async {
  final pairing = auth.startPairing();
  final outcome = await auth.claimPairing(
    code: pairing.code,
    deviceName: 'Test device',
    clientKey: '127.0.0.1',
  );
  return outcome.bearerToken!;
}

final class _FixedReadiness implements EngineReadiness {
  const _FixedReadiness(this.current);

  const _FixedReadiness.actionRequired()
    : current = const EngineReadinessSnapshot(
        state: EngineReadinessState.actionRequired,
      );

  @override
  final EngineReadinessSnapshot current;

  @override
  Stream<EngineReadinessSnapshot> get changes => const Stream.empty();
}

final class _TestMediaReference implements MediaReference {
  const _TestMediaReference(this.value);

  final String value;
}

final class _BlockingLibrary implements LibraryGateway {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();
  int calls = 0;

  @override
  Future<List<LibraryManga>> listLibrary() async {
    calls += 1;
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return const [];
  }

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {}
}

final class _RecordingProgress implements ReadingProgressGateway {
  int calls = 0;

  @override
  Future<ReadingProgressSnapshot> updateProgress({
    required int chapterId,
    required int lastPageRead,
    required bool isRead,
  }) async {
    calls += 1;
    return ReadingProgressSnapshot(
      chapterId: chapterId,
      lastPageRead: lastPageRead,
      isRead: isRead,
    );
  }
}
