import 'dart:convert';
import 'dart:math';

/// Opaque media ticket issued only by Yomu Core (never client-supplied URLs).
class MediaTicket {
  MediaTicket({
    required this.id,
    required this.sessionToken,
    required this.target,
    required this.expiresAt,
  });

  final String id;
  final String sessionToken;

  /// Suwayomi-relative path (`/api/v1/...`) or absolute http(s) from Suwayomi.
  final String target;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// In-memory session-bound media tickets (short-lived).
class MediaTicketStore {
  MediaTicketStore({
    this.ttl = const Duration(hours: 2),
    Random? random,
  }) : _rng = random ?? Random.secure();

  final Duration ttl;
  final Random _rng;
  final _tickets = <String, MediaTicket>{};

  /// Create a ticket for [sessionToken] pointing at [target].
  String issue({
    required String sessionToken,
    required String target,
  }) {
    _purge();
    final id = _randomId();
    _tickets[id] = MediaTicket(
      id: id,
      sessionToken: sessionToken,
      target: target,
      expiresAt: DateTime.now().add(ttl),
    );
    return id;
  }

  MediaTicket? resolve({
    required String ticketId,
    required String sessionToken,
  }) {
    _purge();
    final t = _tickets[ticketId];
    if (t == null || t.isExpired) return null;
    if (t.sessionToken != sessionToken) return null;
    return t;
  }

  void _purge() {
    _tickets.removeWhere((_, t) => t.isExpired);
  }

  String _randomId() {
    final bytes = List<int>.generate(18, (_) => _rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  int get length {
    _purge();
    return _tickets.length;
  }
}
