import 'dart:convert';
import 'dart:math';

import 'package:yomu_core/yomu_core.dart';

/// Opaque media ticket issued only by Yomu Core (never client-supplied URLs).
class MediaTicket {
  MediaTicket({
    required this.id,
    required this.sessionId,
    required this.reference,
    required this.expiresAt,
  });

  final String id;
  final String sessionId;

  /// Opaque reading-engine media identity. Transport details never enter Core.
  final MediaReference reference;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// In-memory session-bound media tickets (short-lived).
class MediaTicketStore {
  MediaTicketStore({this.ttl = const Duration(hours: 2), Random? random})
    : _rng = random ?? Random.secure();

  final Duration ttl;
  final Random _rng;
  final _tickets = <String, MediaTicket>{};

  /// Create a ticket for [sessionId] pointing at [reference].
  String issue({required String sessionId, required MediaReference reference}) {
    _purge();
    final id = _randomId();
    _tickets[id] = MediaTicket(
      id: id,
      sessionId: sessionId,
      reference: reference,
      expiresAt: DateTime.now().add(ttl),
    );
    return id;
  }

  MediaTicket? resolve({required String ticketId, required String sessionId}) {
    _purge();
    final t = _tickets[ticketId];
    if (t == null || t.isExpired) return null;
    if (t.sessionId != sessionId) return null;
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
