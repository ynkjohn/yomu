import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// In-memory (+ optional file) device pairing for the local Yomu API.
class DeviceSession {
  DeviceSession({
    required this.token,
    required this.deviceName,
    required this.createdAt,
    this.lastSeenAt,
  });

  final String token;
  final String deviceName;
  final DateTime createdAt;
  DateTime? lastSeenAt;

  Map<String, dynamic> toJson() => {
        'token': token,
        'deviceName': deviceName,
        'createdAt': createdAt.toIso8601String(),
        'lastSeenAt': lastSeenAt?.toIso8601String(),
      };

  factory DeviceSession.fromJson(Map<String, dynamic> json) {
    return DeviceSession(
      token: '${json['token']}',
      deviceName: '${json['deviceName'] ?? 'device'}',
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      lastSeenAt: DateTime.tryParse('${json['lastSeenAt'] ?? ''}'),
    );
  }
}

class PairingCode {
  PairingCode({
    required this.code,
    required this.expiresAt,
  });

  final String code;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Outcome of [DeviceAuthStore.claimPairing].
enum PairingClaimResult {
  success,
  invalidOrExpired,
  rateLimited,
}

class PairingClaimOutcome {
  const PairingClaimOutcome({
    required this.result,
    this.session,
    this.retryAfterSeconds,
  });

  final PairingClaimResult result;
  final DeviceSession? session;
  final int? retryAfterSeconds;
}

class DeviceAuthStore {
  DeviceAuthStore({
    this.persistFile,
    this.maxFailedAttempts = 5,
    this.failWindow = const Duration(minutes: 10),
  });

  final File? persistFile;
  final int maxFailedAttempts;
  final Duration failWindow;
  final _sessions = <String, DeviceSession>{};
  PairingCode? _activePairing;
  final _rng = Random.secure();

  /// Failed claim timestamps keyed by client IP only (no global lockout).
  final _failTimestamps = <String, List<DateTime>>{};
  final _rateLimitedUntilByKey = <String, DateTime>{};

  List<DeviceSession> get sessions =>
      _sessions.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  PairingCode? get activePairing =>
      (_activePairing != null && !_activePairing!.isExpired)
          ? _activePairing
          : null;

  bool isRateLimitedFor(String clientKey) {
    final until = _rateLimitedUntilByKey[clientKey];
    return until != null && DateTime.now().isBefore(until);
  }

  int? rateLimitRetryAfterSecondsFor(String clientKey) {
    final until = _rateLimitedUntilByKey[clientKey];
    if (until == null) return null;
    final s = until.difference(DateTime.now()).inSeconds;
    return s > 0 ? s : null;
  }

  Future<void> load() async {
    final file = persistFile;
    if (file == null || !file.existsSync()) return;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return;
      final list = raw['sessions'];
      if (list is List) {
        for (final item in list.whereType<Map<dynamic, dynamic>>()) {
          final s = DeviceSession.fromJson(Map<String, dynamic>.from(item));
          _sessions[s.token] = s;
        }
      }
    } catch (_) {
      // ignore corrupt store
    }
  }

  Future<void> _persist() async {
    final file = persistFile;
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'sessions': sessions.map((s) => s.toJson()).toList(),
      }),
    );
  }

  /// Creates a short numeric pairing code (6 digits), valid 5 minutes.
  /// Clears prior rate-limit window for a fresh code.
  PairingCode startPairing({Duration ttl = const Duration(minutes: 5)}) {
    final code = (_rng.nextInt(900000) + 100000).toString();
    _activePairing = PairingCode(
      code: code,
      expiresAt: DateTime.now().add(ttl),
    );
    // New code clears all rate-limit state (desktop operator action).
    _failTimestamps.clear();
    _rateLimitedUntilByKey.clear();
    return _activePairing!;
  }

  void cancelPairing() {
    _activePairing = null;
  }

  /// Claims pairing code and returns a bearer token.
  ///
  /// Never log [code] or resulting token. Rate-limited **per clientKey (IP)** only —
  /// one misbehaving LAN host cannot lock out other devices.
  Future<PairingClaimOutcome> claimPairing({
    required String code,
    required String deviceName,
    String clientKey = 'unknown',
  }) async {
    if (isRateLimitedFor(clientKey)) {
      return PairingClaimOutcome(
        result: PairingClaimResult.rateLimited,
        retryAfterSeconds: rateLimitRetryAfterSecondsFor(clientKey),
      );
    }

    final p = _activePairing;
    if (p == null || p.isExpired) {
      await _registerFailure(clientKey);
      if (isRateLimitedFor(clientKey)) {
        return PairingClaimOutcome(
          result: PairingClaimResult.rateLimited,
          retryAfterSeconds: rateLimitRetryAfterSecondsFor(clientKey),
        );
      }
      return const PairingClaimOutcome(result: PairingClaimResult.invalidOrExpired);
    }
    if (p.code != code.trim()) {
      await _registerFailure(clientKey);
      if (isRateLimitedFor(clientKey)) {
        return PairingClaimOutcome(
          result: PairingClaimResult.rateLimited,
          retryAfterSeconds: rateLimitRetryAfterSecondsFor(clientKey),
        );
      }
      return const PairingClaimOutcome(result: PairingClaimResult.invalidOrExpired);
    }

    _activePairing = null;
    _failTimestamps.remove(clientKey);
    _rateLimitedUntilByKey.remove(clientKey);
    final token = _randomToken();
    final session = DeviceSession(
      token: token,
      deviceName: deviceName.trim().isEmpty ? 'iPhone' : deviceName.trim(),
      createdAt: DateTime.now(),
      lastSeenAt: DateTime.now(),
    );
    _sessions[token] = session;
    await _persist();
    return PairingClaimOutcome(
      result: PairingClaimResult.success,
      session: session,
    );
  }

  Future<void> _registerFailure(String clientKey) async {
    final now = DateTime.now();
    final cutoff = now.subtract(failWindow);
    final list = _failTimestamps.putIfAbsent(clientKey, () => <DateTime>[]);
    list.removeWhere((t) => t.isBefore(cutoff));
    list.add(now);

    if (list.length >= maxFailedAttempts) {
      _rateLimitedUntilByKey[clientKey] = now.add(failWindow);
      // Do not cancel pairing globally — other IPs may still claim.
    }
  }

  DeviceSession? authenticate(String? bearer) {
    if (bearer == null || bearer.isEmpty) return null;
    var token = bearer;
    if (token.toLowerCase().startsWith('bearer ')) {
      token = token.substring(7).trim();
    }
    final s = _sessions[token];
    if (s == null) return null;
    s.lastSeenAt = DateTime.now();
    return s;
  }

  Future<bool> revoke(String token) async {
    final removed = _sessions.remove(token) != null;
    if (removed) await _persist();
    return removed;
  }

  Future<void> revokeAll() async {
    _sessions.clear();
    await _persist();
  }

  String _randomToken() {
    final bytes = List<int>.generate(32, (_) => _rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
