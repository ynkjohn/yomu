import 'dart:io';

import 'package:test/test.dart';
import 'package:yomu_local_server/yomu_local_server.dart';

void main() {
  test('blocks private and loopback IPv4', () {
    expect(
      SafeHttpFetch.isBlockedIp(InternetAddress('127.0.0.1')),
      isTrue,
    );
    expect(
      SafeHttpFetch.isBlockedIp(InternetAddress('10.0.0.1')),
      isTrue,
    );
    expect(
      SafeHttpFetch.isBlockedIp(InternetAddress('192.168.1.1')),
      isTrue,
    );
    expect(
      SafeHttpFetch.isBlockedIp(InternetAddress('172.16.0.1')),
      isTrue,
    );
    expect(
      SafeHttpFetch.isBlockedIp(InternetAddress('169.254.1.1')),
      isTrue,
    );
    expect(
      SafeHttpFetch.isBlockedIp(InternetAddress('8.8.8.8')),
      isFalse,
    );
  });

  test('blocks localhost host literal', () {
    expect(SafeHttpFetch.isBlockedHostLiteral('localhost'), isTrue);
    expect(SafeHttpFetch.isBlockedHostLiteral('127.0.0.1'), isTrue);
  });

  test('assertHostAllowed rejects loopback via DNS mock', () async {
    final fetch = SafeHttpFetch(
      lookup: (host) async => [InternetAddress('127.0.0.1')],
    );
    await expectLater(
      fetch.assertHostAllowed('evil.example'),
      throwsA(isA<StateError>()),
    );
  });
}
