import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class DeviceSession {
  DeviceSession({
    required this.token,
    required this.deviceName,
    required this.createdAt,
    required this.expiresAt,
    this.lastSeenAt,
  });

  final String token;
  final String deviceName;
  final DateTime createdAt;
  final DateTime expiresAt;
  DateTime? lastSeenAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'token': token,
        'deviceName': deviceName,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'lastSeenAt': lastSeenAt?.toIso8601String(),
      };

  factory DeviceSession.fromJson(Map<String, dynamic> json) {
    final created =
        DateTime.tryParse('${json['createdAt']}') ?? DateTime.now();
    final expires = DateTime.tryParse('${json['expiresAt']}') ??
        created.add(const Duration(days: 30));
    return DeviceSession(
      token: '${json['token']}',
      deviceName: '${json['deviceName'] ?? 'device'}',
      createdAt: created,
      expiresAt: expires,
      lastSeenAt: DateTime.tryParse('${json['lastSeenAt'] ?? ''}'),
    );
  }
}

class PairingCode {
  PairingCode({
    required this.code,
    required this.expiresAt,
    required this.nonce,
  });

  final String code;
  final DateTime expiresAt;
  final String nonce;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

enum PairingClaimResult { success, invalidOrExpired, rateLimited }

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
    this.maxFailedAttemptsPerPairingIp = 5,
    this.failWindow = const Duration(minutes: 10),
    this.sessionTtl = const Duration(days: 30),
  });

  final File? persistFile;
  final int maxFailedAttemptsPerPairingIp;
  final Duration failWindow;
  final Duration sessionTtl;
  final _sessions = <String, DeviceSession>{};
  PairingCode? _activePairing;
  final _rng = Random.secure();

  /// Failures keyed by `nonce|ip` only — never cancels pairing for other IPs.
  final _failTimestamps = <String, List<DateTime>>{};
  final _rateLimitedUntil = <String, DateTime>{};

  List<DeviceSession> get sessions {
    _purgeExpiredSessions();
    return _sessions.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  PairingCode? get activePairing =>
      (_activePairing != null && !_activePairing!.isExpired)
          ? _activePairing
          : null;

  String _pairIpKey(String nonce, String clientKey) => '$nonce|$clientKey';

  bool isRateLimitedFor(String clientKey, {String? nonce}) {
    final n = nonce ?? _activePairing?.nonce;
    if (n == null) return false;
    final until = _rateLimitedUntil[_pairIpKey(n, clientKey)];
    return until != null && DateTime.now().isBefore(until);
  }

  int? rateLimitRetryAfterSecondsFor(String clientKey, {String? nonce}) {
    final n = nonce ?? _activePairing?.nonce;
    if (n == null) return null;
    final until = _rateLimitedUntil[_pairIpKey(n, clientKey)];
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
          if (!s.isExpired) _sessions[s.token] = s;
        }
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    final file = persistFile;
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'sessions': sessions.map((s) => s.toJson()).toList()}),
    );
  }

  void _purgeExpiredSessions() {
    _sessions.removeWhere((_, s) => s.isExpired);
  }

  PairingCode startPairing({Duration ttl = const Duration(minutes: 5)}) {
    final code = (_rng.nextInt(900000) + 100000).toString();
    final nonce = _randomToken().substring(0, 12);
    _activePairing = PairingCode(
      code: code,
      expiresAt: DateTime.now().add(ttl),
      nonce: nonce,
    );
    // Clear only limits for previous nonces of this operator action
    _failTimestamps.clear();
    _rateLimitedUntil.clear();
    return _activePairing!;
  }

  void cancelPairing() {
    _activePairing = null;
  }

  Future<PairingClaimOutcome> claimPairing({
    required String code,
    required String deviceName,
    String clientKey = 'unknown',
  }) async {
    final p = _activePairing;
    if (p == null || p.isExpired) {
      return const PairingClaimOutcome(
        result: PairingClaimResult.invalidOrExpired,
      );
    }

    final key = _pairIpKey(p.nonce, clientKey);
    if (isRateLimitedFor(clientKey, nonce: p.nonce)) {
      return PairingClaimOutcome(
        result: PairingClaimResult.rateLimited,
        retryAfterSeconds: rateLimitRetryAfterSecondsFor(clientKey, nonce: p.nonce),
      );
    }

    if (p.code != code.trim()) {
      await _registerPairIpFailure(key);
      if (isRateLimitedFor(clientKey, nonce: p.nonce)) {
        return PairingClaimOutcome(
          result: PairingClaimResult.rateLimited,
          retryAfterSeconds:
              rateLimitRetryAfterSecondsFor(clientKey, nonce: p.nonce),
        );
      }
      return const PairingClaimOutcome(
        result: PairingClaimResult.invalidOrExpired,
      );
    }

    // Success — do not clear other IPs' rate limits for this nonce.
    _failTimestamps.remove(key);
    _rateLimitedUntil.remove(key);
    _activePairing = null;
    final now = DateTime.now();
    final token = _randomToken();
    final session = DeviceSession(
      token: token,
      deviceName: deviceName.trim().isEmpty ? 'iPhone' : deviceName.trim(),
      createdAt: now,
      expiresAt: now.add(sessionTtl),
      lastSeenAt: now,
    );
    _sessions[token] = session;
    await _persist();
    return PairingClaimOutcome(
      result: PairingClaimResult.success,
      session: session,
    );
  }

  Future<void> _registerPairIpFailure(String key) async {
    final now = DateTime.now();
    final cutoff = now.subtract(failWindow);
    final list = _failTimestamps.putIfAbsent(key, () => <DateTime>[]);
    list.removeWhere((t) => t.isBefore(cutoff));
    list.add(now);
    if (list.length >= maxFailedAttemptsPerPairingIp) {
      _rateLimitedUntil[key] = now.add(failWindow);
      // Never cancel _activePairing here — other IPs may still claim.
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
    if (s.isExpired) {
      _sessions.remove(token);
      unawaited(_persist());
      return null;
    }
    s.lastSeenAt = DateTime.now();
    return s;
  }

  Future<bool> revoke(String token) async {
    final removed = _sessions.remove(token) != null;
    if (removed) await _persist();
    return removed;
  }

  Future<int> revokeDevice(String deviceName) async {
    final keys = _sessions.entries
        .where((e) => e.value.deviceName == deviceName)
        .map((e) => e.key)
        .toList();
    for (final k in keys) {
      _sessions.remove(k);
    }
    if (keys.isNotEmpty) await _persist();
    return keys.length;
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
