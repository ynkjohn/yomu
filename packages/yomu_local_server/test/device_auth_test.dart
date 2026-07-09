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

  test('rate limit is per-IP only (does not lock other clients)', () async {
    final store = DeviceAuthStore(
      maxFailedAttempts: 5,
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
    expect(store.activePairing?.code, pairing.code,
        reason: 'pairing stays active for other IPs');

    final blocked = await store.claimPairing(
      code: pairing.code,
      deviceName: 'Attacker',
      clientKey: '10.0.0.5',
    );
    expect(blocked.result, PairingClaimResult.rateLimited);

    // Different IP can still claim the same active code.
    final ok = await store.claimPairing(
      code: pairing.code,
      deviceName: 'Phone',
      clientKey: '10.0.0.9',
    );
    expect(ok.result, PairingClaimResult.success);
  });
}
