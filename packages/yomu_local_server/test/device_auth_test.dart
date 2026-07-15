import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yomu_local_server/yomu_local_server.dart';

void main() {
  test('pairing code expires and claim works once', () async {
    final store = DeviceAuthStore();
    final p = store.startPairing(ttl: const Duration(minutes: 1));
    expect(store.activePairing?.code, p.code);

    final s1 = await store.claimPairing(code: p.code, deviceName: 'A');
    expect(s1.result, PairingClaimResult.success);
    expect(store.authenticate('Bearer ${s1.session!.token}'), isNotNull);
    expect(s1.session!.expiresAt.isAfter(DateTime.now()), isTrue);

    final s2 = await store.claimPairing(code: p.code, deviceName: 'B');
    expect(s2.result, PairingClaimResult.invalidOrExpired);
  });

  test('revoke removes session', () async {
    final store = DeviceAuthStore();
    final p = store.startPairing();
    final s = await store.claimPairing(code: p.code, deviceName: 'A');
    expect(await store.revoke(s.session!.token), isTrue);
    expect(store.authenticate(s.session!.token), isNull);
  });

  test('revokeDevice removes by name', () async {
    final store = DeviceAuthStore();
    final p = store.startPairing();
    final s = await store.claimPairing(code: p.code, deviceName: 'iPhone-X');
    expect(await store.revokeDevice('iPhone-X'), 1);
    expect(store.authenticate(s.session!.token), isNull);
  });

  test(
    'rate limit is per nonce|IP only (does not cancel pairing for other IPs)',
    () async {
      final store = DeviceAuthStore(
        maxFailedAttemptsPerPairingIp: 5,
        failWindow: const Duration(minutes: 10),
      );
      final pairing = store.startPairing();

      for (var i = 0; i < 5; i++) {
        await store.claimPairing(
          code: '000000',
          deviceName: 'X',
          clientKey: '10.0.0.5',
        );
      }
      expect(store.isRateLimitedFor('10.0.0.5'), isTrue);
      expect(
        store.activePairing?.code,
        pairing.code,
        reason: 'pairing must stay open for other IPs',
      );

      final ok = await store.claimPairing(
        code: pairing.code,
        deviceName: 'Phone',
        clientKey: '10.0.0.9',
      );
      expect(ok.result, PairingClaimResult.success);
    },
  );
  test(
    'rate-limited IP does not poison a different IP on same nonce',
    () async {
      final store = DeviceAuthStore(maxFailedAttemptsPerPairingIp: 3);
      final pairing = store.startPairing();
      for (var i = 0; i < 3; i++) {
        await store.claimPairing(
          code: '000000',
          deviceName: 'X',
          clientKey: '10.0.0.1',
        );
      }
      expect(store.activePairing, isNotNull);
      expect(store.isRateLimitedFor('10.0.0.1'), isTrue);
      expect(store.isRateLimitedFor('10.0.0.2'), isFalse);

      final ok = await store.claimPairing(
        code: pairing.code,
        deviceName: 'Y',
        clientKey: '10.0.0.2',
      );
      expect(ok.result, PairingClaimResult.success);
    },
  );

  test(
    'claim + revokeAll persistence is serialized and stays revoked on reload',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'yomu-auth-persist-race',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final file = File(
        '${root.path}${Platform.pathSeparator}device-sessions.json',
      );
      final firstWriteEntered = Completer<void>();
      final releaseFirstWrite = Completer<void>();
      var writeCount = 0;

      final store = DeviceAuthStore(
        persistFile: file,
        persistWriterForTest: (target, contents) async {
          writeCount++;
          if (writeCount == 1) {
            firstWriteEntered.complete();
            await releaseFirstWrite.future;
          }
          await target.writeAsString(contents, flush: true);
        },
      );
      final pairing = store.startPairing();
      final claim = store.claimPairing(code: pairing.code, deviceName: 'Phone');
      await firstWriteEntered.future;

      final revokeAll = store.revokeAll();
      releaseFirstWrite.complete();
      final outcome = await claim;
      await revokeAll;

      expect(outcome.result, PairingClaimResult.success);
      expect(store.sessions, isEmpty);
      expect(writeCount, 2);

      final persisted = jsonDecode(await file.readAsString()) as Map;
      expect(persisted['sessions'], isEmpty);

      final reloaded = DeviceAuthStore(persistFile: file);
      await reloaded.load();
      expect(reloaded.sessions, isEmpty);
    },
  );
}
