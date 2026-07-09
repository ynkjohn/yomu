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

class DeviceAuthStore {
  DeviceAuthStore({this.persistFile});

  final File? persistFile;
  final _sessions = <String, DeviceSession>{};
  PairingCode? _activePairing;
  final _rng = Random.secure();

  List<DeviceSession> get sessions =>
      _sessions.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  PairingCode? get activePairing =>
      (_activePairing != null && !_activePairing!.isExpired)
          ? _activePairing
          : null;

  Future<void> load() async {
    final file = persistFile;
    if (file == null || !file.existsSync()) return;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return;
      final list = raw['sessions'];
      if (list is List) {
        for (final item in list.whereType<Map>()) {
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
  PairingCode startPairing({Duration ttl = const Duration(minutes: 5)}) {
    final code = (_rng.nextInt(900000) + 100000).toString();
    _activePairing = PairingCode(
      code: code,
      expiresAt: DateTime.now().add(ttl),
    );
    return _activePairing!;
  }

  void cancelPairing() {
    _activePairing = null;
  }

  /// Claims pairing code and returns a bearer token.
  Future<DeviceSession?> claimPairing({
    required String code,
    required String deviceName,
  }) async {
    final p = _activePairing;
    if (p == null || p.isExpired) return null;
    if (p.code != code.trim()) return null;
    _activePairing = null;
    final token = _randomToken();
    final session = DeviceSession(
      token: token,
      deviceName: deviceName.trim().isEmpty ? 'iPhone' : deviceName.trim(),
      createdAt: DateTime.now(),
      lastSeenAt: DateTime.now(),
    );
    _sessions[token] = session;
    await _persist();
    return session;
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
