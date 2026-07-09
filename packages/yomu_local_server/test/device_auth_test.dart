import 'package:test/test.dart';
import 'package:yomu_local_server/yomu_local_server.dart';

void main() {
  test('pairing code expires and claim works once', () async {
    final store = DeviceAuthStore();
    final p = store.startPairing(ttl: const Duration(minutes: 1));
    expect(store.activePairing?.code, p.code);

    final s1 = await store.claimPairing(code: p.code, deviceName: 'A');
    expect(s1, isNotNull);
    expect(store.authenticate('Bearer ${s1!.token}'), isNotNull);

    final s2 = await store.claimPairing(code: p.code, deviceName: 'B');
    expect(s2, isNull);
  });

  test('revoke removes session', () async {
    final store = DeviceAuthStore();
    final p = store.startPairing();
    final s = await store.claimPairing(code: p.code, deviceName: 'A');
    expect(await store.revoke(s!.token), isTrue);
    expect(store.authenticate(s.token), isNull);
  });
}
