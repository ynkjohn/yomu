import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_desktop/services/maya_custom_provider_security.dart';

Matcher _configurationFailure() => isA<MayaLlmException>().having(
  (error) => error.kind,
  'kind',
  MayaLlmFailureKind.configuration,
);

void main() {
  test('canonicalizes public HTTPS and binds the exact destination', () {
    final endpoint = MayaCustomProviderEndpoint.parse(
      '  HTTPS://API.Example.com:443/v1/chat/completions  ',
    );
    final same = MayaCustomProviderEndpoint.parse(
      'https://api.example.com/v1/chat/completions',
    );
    final other = MayaCustomProviderEndpoint.parse(
      'https://api.example.com/openai/chat/completions',
    );

    expect(
      endpoint.canonicalUrl,
      'https://api.example.com/v1/chat/completions',
    );
    expect(endpoint.uri, Uri.parse(endpoint.canonicalUrl));
    expect(endpoint.credentialBinding, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(endpoint.credentialBinding, same.credentialBinding);
    expect(endpoint.credentialBinding, isNot(other.credentialBinding));
  });

  test('allows plain HTTP only for literal IPv4 or IPv6 loopback', () {
    expect(
      MayaCustomProviderEndpoint.parse(
        'http://127.0.0.1:1234/v1/chat/completions',
      ).canonicalUrl,
      'http://127.0.0.1:1234/v1/chat/completions',
    );
    expect(
      MayaCustomProviderEndpoint.parse(
        'http://[::1]:8080/v1/chat/completions',
      ).canonicalUrl,
      'http://[::1]:8080/v1/chat/completions',
    );

    for (final value in <String>[
      'http://localhost:1234/v1/chat/completions',
      'http://192.168.1.20/v1/chat/completions',
      'http://10.0.0.5/v1/chat/completions',
      'https://127.0.0.1/v1/chat/completions',
      'https://[::1]/v1/chat/completions',
    ]) {
      expect(
        () => MayaCustomProviderEndpoint.parse(value),
        throwsA(_configurationFailure()),
      );
    }
  });

  test('rejects ambiguous URL features and non-Chat protocols', () {
    for (final value in <String>[
      'ftp://api.example.com/v1/chat/completions',
      'https://user@api.example.com/v1/chat/completions',
      'https://api.example.com/v1/chat/completions?mode=test',
      'https://api.example.com/v1/chat/completions#fragment',
      'https://api.example.com/v1/responses',
      'https://api.example.com/v1/chat/completions/',
      'https://api.example.com/v1/%63hat/completions',
      'https://single-label/v1/chat/completions',
      'https://api.example.com:0/v1/chat/completions',
      'https://api.example.com:65536/v1/chat/completions',
      'https://api.example.com:abc/v1/chat/completions',
      'https://api.example.com:999999999999999999/v1/chat/completions',
    ]) {
      expect(
        () => MayaCustomProviderEndpoint.parse(value),
        throwsA(_configurationFailure()),
      );
    }
  });

  test('public-address policy blocks private and special-purpose ranges', () {
    for (final value in <String>[
      '8.8.8.8',
      '93.184.216.34',
      '2606:4700:4700::1111',
    ]) {
      expect(isMayaPublicInternetAddress(InternetAddress(value)), isTrue);
    }
    for (final value in <String>[
      '0.0.0.0',
      '10.0.0.1',
      '100.64.0.1',
      '127.0.0.1',
      '169.254.1.1',
      '172.16.0.1',
      '192.0.2.1',
      '192.168.0.1',
      '198.18.0.1',
      '198.51.100.1',
      '203.0.113.1',
      '224.0.0.1',
      '::1',
      'fd00::1',
      'fe80::1',
      '2001:db8::1',
      '2002:c0a8:101::1',
      '::ffff:192.168.1.1',
    ]) {
      expect(
        isMayaPublicInternetAddress(InternetAddress(value)),
        isFalse,
        reason: value,
      );
    }
  });
}
