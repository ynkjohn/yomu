import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_storage/yomu_storage.dart';

const String kMayaCustomProviderId = 'openai-compatible';

final RegExp _dnsHostPattern = RegExp(
  r'^[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$',
);

/// Canonical, validated endpoint for the single OpenAI-compatible profile.
///
/// The first version deliberately accepts only the Chat Completions protocol,
/// with no query, fragment, userinfo, redirects, arbitrary headers or body
/// templates. Remote destinations require HTTPS. Plain HTTP is restricted to
/// literal loopback addresses so mutable hosts-file/DNS aliases cannot widen
/// the local exception.
final class MayaCustomProviderEndpoint {
  factory MayaCustomProviderEndpoint.parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty ||
        trimmed.length > kMayaCustomProviderEndpointUrlMaxChars) {
      throw const MayaLlmException(MayaLlmFailureKind.configuration);
    }

    final parsed = Uri.tryParse(trimmed);
    if (parsed == null ||
        !parsed.isAbsolute ||
        !parsed.hasAuthority ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        parsed.port < 1 ||
        parsed.port > 65535 ||
        trimmed.contains('%')) {
      throw const MayaLlmException(MayaLlmFailureKind.configuration);
    }

    final scheme = parsed.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') {
      throw const MayaLlmException(MayaLlmFailureKind.configuration);
    }

    final segments = parsed.pathSegments;
    if (segments.length < 2 ||
        !parsed.path.endsWith('/chat/completions') ||
        segments[segments.length - 2] != 'chat' ||
        segments.last != 'completions' ||
        segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw const MayaLlmException(MayaLlmFailureKind.configuration);
    }

    final literal = InternetAddress.tryParse(parsed.host);
    late final String canonicalHost;
    if (literal != null) {
      canonicalHost = literal.address.toLowerCase();
      if (scheme == 'http') {
        if (!literal.isLoopback) {
          throw const MayaLlmException(MayaLlmFailureKind.configuration);
        }
      } else if (!isMayaPublicInternetAddress(literal)) {
        throw const MayaLlmException(MayaLlmFailureKind.configuration);
      }
    } else {
      if (scheme != 'https' || !_isValidDnsHost(parsed.host)) {
        throw const MayaLlmException(MayaLlmFailureKind.configuration);
      }
      canonicalHost = parsed.host.toLowerCase();
    }

    final defaultPort = scheme == 'https' ? 443 : 80;
    final canonical = Uri(
      scheme: scheme,
      host: canonicalHost,
      port: parsed.hasPort && parsed.port != defaultPort ? parsed.port : null,
      pathSegments: segments,
    );
    final canonicalUrl = canonical.toString();
    if (canonicalUrl.length > kMayaCustomProviderEndpointUrlMaxChars) {
      throw const MayaLlmException(MayaLlmFailureKind.configuration);
    }
    final binding = sha256.convert(utf8.encode(canonicalUrl)).toString();
    return MayaCustomProviderEndpoint._(
      uri: canonical,
      canonicalUrl: canonicalUrl,
      credentialBinding: binding,
    );
  }

  const MayaCustomProviderEndpoint._({
    required this.uri,
    required this.canonicalUrl,
    required this.credentialBinding,
  });

  final Uri uri;
  final String canonicalUrl;
  final String credentialBinding;

  bool get usesApiKeyCapableTransport => true;
}

bool _isValidDnsHost(String host) {
  if (host.length > 253 ||
      host.endsWith('.') ||
      !_dnsHostPattern.hasMatch(host)) {
    return false;
  }
  final labels = host.split('.');
  if (labels.length < 2) return false;
  return labels.every(
    (label) =>
        label.isNotEmpty &&
        label.length <= 63 &&
        !label.startsWith('-') &&
        !label.endsWith('-'),
  );
}

/// Returns whether [address] is globally routable enough for a custom HTTPS
/// provider. The policy intentionally rejects special-purpose ranges even if
/// an operating system would route them.
bool isMayaPublicInternetAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return false;
  }
  final bytes = address.rawAddress;
  if (bytes.length == 4) return _isPublicIpv4(bytes);
  if (bytes.length != 16) return false;

  if (_isIpv4MappedIpv6(bytes)) {
    return _isPublicIpv4(bytes.sublist(12));
  }

  // Conservatively admit only IPv6 global unicast (2000::/3), then remove
  // special-purpose/documentation/tunneling blocks that can conceal a local
  // IPv4 destination or are not valid provider destinations.
  if ((bytes[0] & 0xe0) != 0x20) return false;
  if (_hasPrefix(bytes, const [0x20, 0x01, 0x00, 0x00], 32) ||
      _hasPrefix(bytes, const [0x20, 0x01, 0x00, 0x02, 0x00, 0x00], 48) ||
      _hasPrefix(bytes, const [0x20, 0x01, 0x00, 0x10], 28) ||
      _hasPrefix(bytes, const [0x20, 0x01, 0x00, 0x20], 28) ||
      _hasPrefix(bytes, const [0x20, 0x01, 0x0d, 0xb8], 32) ||
      _hasPrefix(bytes, const [0x20, 0x02], 16) ||
      _hasPrefix(bytes, const [0x3f, 0xff, 0x00], 20)) {
    return false;
  }
  return true;
}

bool _isPublicIpv4(List<int> bytes) {
  final a = bytes[0];
  final b = bytes[1];
  final c = bytes[2];
  if (a == 0 ||
      a == 10 ||
      a == 127 ||
      a >= 224 ||
      (a == 100 && b >= 64 && b <= 127) ||
      (a == 169 && b == 254) ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 0 && c == 0) ||
      (a == 192 && b == 0 && c == 2) ||
      (a == 192 && b == 88 && c == 99) ||
      (a == 192 && b == 168) ||
      (a == 198 && (b == 18 || b == 19)) ||
      (a == 198 && b == 51 && c == 100) ||
      (a == 203 && b == 0 && c == 113)) {
    return false;
  }
  return true;
}

bool _isIpv4MappedIpv6(List<int> bytes) {
  for (var i = 0; i < 10; i++) {
    if (bytes[i] != 0) return false;
  }
  return bytes[10] == 0xff && bytes[11] == 0xff;
}

bool _hasPrefix(List<int> address, List<int> prefix, int prefixBits) {
  final wholeBytes = prefixBits ~/ 8;
  final remainingBits = prefixBits % 8;
  for (var i = 0; i < wholeBytes; i++) {
    if (address[i] != prefix[i]) return false;
  }
  if (remainingBits == 0) return true;
  final mask = 0xff << (8 - remainingBits) & 0xff;
  return (address[wholeBytes] & mask) == (prefix[wholeBytes] & mask);
}
