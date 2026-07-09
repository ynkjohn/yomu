import 'dart:io';

import 'package:test/test.dart';
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
    // ::ffff:192.168.0.1
    final mapped = InternetAddress('::ffff:192.168.0.1');
    expect(SafeHttpFetch.isBlockedIp(mapped), isTrue);
    final mappedPublic = InternetAddress('::ffff:8.8.8.8');
    expect(SafeHttpFetch.isBlockedIp(mappedPublic), isFalse);
  });

  test('blocks unique-local and documentation IPv6', () {
    expect(SafeHttpFetch.isBlockedIp(InternetAddress('fd12:3456::1')), isTrue);
    expect(
      SafeHttpFetch.isBlockedIp(InternetAddress('2001:db8::1')),
      isTrue,
    );
  });

  test('blocks localhost host literal', () {
    expect(SafeHttpFetch.isBlockedHostLiteral('localhost'), isTrue);
    expect(SafeHttpFetch.isBlockedHostLiteral('127.0.0.1'), isTrue);
    expect(SafeHttpFetch.isBlockedHostLiteral('::ffff:127.0.0.1'), isTrue);
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
}
