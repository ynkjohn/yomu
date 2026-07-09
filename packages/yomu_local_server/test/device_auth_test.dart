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

  test('rate limit after max failed claims invalidates pairing', () async {
    final store = DeviceAuthStore(
      maxFailedAttempts: 5,
      failWindow: const Duration(minutes: 10),
    );
    store.startPairing();
    for (var i = 0; i < 5; i++) {
      final r = await store.claimPairing(
        code: '000000',
        deviceName: 'X',
        clientKey: '10.0.0.5',
      );
      if (i < 4) {
        expect(r.result, PairingClaimResult.invalidOrExpired);
      }
    }
    expect(store.isRateLimited, isTrue);
    expect(store.activePairing, isNull);

    final blocked = await store.claimPairing(
      code: '123456',
      deviceName: 'X',
      clientKey: '10.0.0.5',
    );
    expect(blocked.result, PairingClaimResult.rateLimited);
    expect(blocked.retryAfterSeconds, isNotNull);

    // New code from desktop clears rate limit.
    final p = store.startPairing();
    expect(store.isRateLimited, isFalse);
    final ok = await store.claimPairing(code: p.code, deviceName: 'Phone');
    expect(ok.result, PairingClaimResult.success);
  });
}
