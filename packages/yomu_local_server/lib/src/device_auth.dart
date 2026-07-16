import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:yomu_storage/yomu_storage.dart';

import 'device_token_hash.dart';
import 'legacy_device_session_migrator.dart';

class DeviceSession {
  DeviceSession._({
    required this.sessionId,
    required this.deviceName,
    required this.createdAt,
    required this.expiresAt,
    DateTime? lastSeenAt,
  }) : _lastSeenAt = lastSeenAt;

  final String sessionId;
  final String deviceName;
  final DateTime createdAt;
  final DateTime expiresAt;
  DateTime? _lastSeenAt;

  DateTime? get lastSeenAt => _lastSeenAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  void _markSeen(DateTime at) {
    _lastSeenAt = at;
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

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);
}

enum PairingClaimResult { success, invalidOrExpired, rateLimited }

class PairingClaimOutcome {
  const PairingClaimOutcome({
    required this.result,
    this.session,
    this.bearerToken,
    this.retryAfterSeconds,
  });

  final PairingClaimResult result;
  final DeviceSession? session;

  /// Present only for a successful pairing response and never persisted.
  final String? bearerToken;
  final int? retryAfterSeconds;
}

sealed class DeviceAuthException implements Exception {
  const DeviceAuthException();
}

class DeviceAuthClosedException extends DeviceAuthException {
  const DeviceAuthClosedException();

  @override
  String toString() => 'DeviceAuthClosedException';
}

class DeviceAuthPersistenceException extends DeviceAuthException {
  const DeviceAuthPersistenceException();

  @override
  String toString() => 'DeviceAuthPersistenceException';
}

enum DeviceAuthMutationKind {
  issue,
  authenticate,
  expire,
  revoke,
  revokeDevice,
  revokeAll,
}

@immutable
class DeviceAuthTestHooks {
  const DeviceAuthTestHooks({this.beforeDatabaseMutation});

  final Future<void> Function(DeviceAuthMutationKind kind)?
  beforeDatabaseMutation;
}

class DeviceAuthStore {
  DeviceAuthStore._({
    required YomuDatabase? database,
    required this.maxFailedAttemptsPerPairingIp,
    required this.failWindow,
    required this.sessionTtl,
    required DeviceAuthTestHooks testHooks,
    required DateTime Function() clock,
    required Random random,
  }) : _database = database,
       _testHooks = testHooks,
       _clock = clock,
       _rng = random;

  static Future<DeviceAuthStore> open({
    required YomuDatabase database,
    required File legacyFile,
    int maxFailedAttemptsPerPairingIp = 5,
    Duration failWindow = const Duration(minutes: 10),
    Duration sessionTtl = const Duration(days: 30),
    LegacyDeviceSessionsMigrationHooks migrationHooks =
        const LegacyDeviceSessionsMigrationHooks(),
    DeviceAuthTestHooks testHooks = const DeviceAuthTestHooks(),
    DateTime Function()? clock,
    Random? random,
  }) async {
    final effectiveClock = clock ?? DateTime.now;
    await LegacyDeviceSessionMigrator(
      database: database,
      legacyFile: legacyFile,
      hooks: migrationHooks,
      clock: effectiveClock,
      random: random,
    ).migrate();
    final store = DeviceAuthStore._(
      database: database,
      maxFailedAttemptsPerPairingIp: maxFailedAttemptsPerPairingIp,
      failWindow: failWindow,
      sessionTtl: sessionTtl,
      testHooks: testHooks,
      clock: effectiveClock,
      random: random ?? Random.secure(),
    );
    await store._load();
    return store;
  }

  @visibleForTesting
  DeviceAuthStore.inMemory({
    this.maxFailedAttemptsPerPairingIp = 5,
    this.failWindow = const Duration(minutes: 10),
    this.sessionTtl = const Duration(days: 30),
    DeviceAuthTestHooks testHooks = const DeviceAuthTestHooks(),
    DateTime Function()? clock,
    Random? random,
  }) : _database = null,
       _testHooks = testHooks,
       _clock = clock ?? DateTime.now,
       _rng = random ?? Random.secure();

  final YomuDatabase? _database;
  final int maxFailedAttemptsPerPairingIp;
  final Duration failWindow;
  final Duration sessionTtl;
  final DeviceAuthTestHooks _testHooks;
  final DateTime Function() _clock;
  final Random _rng;

  final _sessionsById = <String, _DeviceSessionEntry>{};
  final _sessionIdByTokenHash = <String, String>{};
  Future<void> _mutationTail = Future<void>.value();
  Future<void>? _closeFuture;
  bool _acceptingMutations = true;
  bool _closed = false;
  PairingCode? _activePairing;

  /// Failures keyed by `nonce|ip` only — never cancels pairing for other IPs.
  final _failTimestamps = <String, List<DateTime>>{};
  final _rateLimitedUntil = <String, DateTime>{};

  bool get isClosed => _closed;

  List<DeviceSession> get sessions {
    final now = _clock();
    return _sessionsById.values
        .map((entry) => entry.session)
        .where((session) => !session.isExpiredAt(now))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  PairingCode? get activePairing {
    final pairing = _activePairing;
    return pairing != null && !pairing.isExpiredAt(_clock()) ? pairing : null;
  }

  Future<void> _load() async {
    final database = _database;
    if (database == null) return;
    try {
      final rows = await database.listDeviceSessions();
      final now = _clock();
      final expiredIds = <String>[];
      for (final row in rows) {
        final session = _sessionFromRow(row);
        if (session.isExpiredAt(now)) {
          expiredIds.add(row.sessionId);
          continue;
        }
        _cacheSession(session: session, tokenHash: row.tokenHash);
      }
      if (expiredIds.isNotEmpty) {
        await database.runInTransaction((transaction) async {
          for (final sessionId in expiredIds) {
            await transaction.deleteDeviceSession(sessionId);
          }
        });
      }
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        const DeviceAuthPersistenceException(),
        stackTrace,
      );
    }
  }

  String _pairIpKey(String nonce, String clientKey) => '$nonce|$clientKey';

  bool isRateLimitedFor(String clientKey, {String? nonce}) {
    final n = nonce ?? _activePairing?.nonce;
    if (n == null) return false;
    final until = _rateLimitedUntil[_pairIpKey(n, clientKey)];
    return until != null && _clock().isBefore(until);
  }

  int? rateLimitRetryAfterSecondsFor(String clientKey, {String? nonce}) {
    final n = nonce ?? _activePairing?.nonce;
    if (n == null) return null;
    final until = _rateLimitedUntil[_pairIpKey(n, clientKey)];
    if (until == null) return null;
    final seconds = until.difference(_clock()).inSeconds;
    return seconds > 0 ? seconds : null;
  }

  PairingCode startPairing({Duration ttl = const Duration(minutes: 5)}) {
    _ensureOpen();
    final code = (_rng.nextInt(900000) + 100000).toString();
    final nonce = _randomId(9);
    _activePairing = PairingCode(
      code: code,
      expiresAt: _clock().add(ttl),
      nonce: nonce,
    );
    _failTimestamps.clear();
    _rateLimitedUntil.clear();
    return _activePairing!;
  }

  void cancelPairing() {
    _ensureOpen();
    _activePairing = null;
  }

  Future<PairingClaimOutcome> claimPairing({
    required String code,
    required String deviceName,
    String clientKey = 'unknown',
  }) {
    return _enqueueMutation(() async {
      final pairing = _activePairing;
      if (pairing == null || pairing.isExpiredAt(_clock())) {
        return const PairingClaimOutcome(
          result: PairingClaimResult.invalidOrExpired,
        );
      }

      final key = _pairIpKey(pairing.nonce, clientKey);
      if (isRateLimitedFor(clientKey, nonce: pairing.nonce)) {
        return PairingClaimOutcome(
          result: PairingClaimResult.rateLimited,
          retryAfterSeconds: rateLimitRetryAfterSecondsFor(
            clientKey,
            nonce: pairing.nonce,
          ),
        );
      }

      if (pairing.code != code.trim()) {
        _registerPairIpFailure(key);
        if (isRateLimitedFor(clientKey, nonce: pairing.nonce)) {
          return PairingClaimOutcome(
            result: PairingClaimResult.rateLimited,
            retryAfterSeconds: rateLimitRetryAfterSecondsFor(
              clientKey,
              nonce: pairing.nonce,
            ),
          );
        }
        return const PairingClaimOutcome(
          result: PairingClaimResult.invalidOrExpired,
        );
      }

      final now = _clock();
      final bearerToken = _randomId(32);
      final tokenHash = hashDeviceBearer(bearerToken);
      final session = DeviceSession._(
        sessionId: _randomId(18),
        deviceName: deviceName.trim().isEmpty ? 'iPhone' : deviceName.trim(),
        createdAt: now,
        expiresAt: now.add(sessionTtl),
        lastSeenAt: now,
      );

      await _beforeDatabaseMutation(DeviceAuthMutationKind.issue);
      final database = _database;
      if (database != null) {
        await database.insertDeviceSession(
          NewDeviceSession(
            sessionId: session.sessionId,
            tokenHash: tokenHash,
            deviceName: session.deviceName,
            createdAtMs: session.createdAt.millisecondsSinceEpoch,
            expiresAtMs: session.expiresAt.millisecondsSinceEpoch,
            lastSeenAtMs: session.lastSeenAt?.millisecondsSinceEpoch,
          ),
        );
      }
      _cacheSession(session: session, tokenHash: tokenHash);
      _failTimestamps.remove(key);
      _rateLimitedUntil.remove(key);
      if (identical(_activePairing, pairing)) {
        _activePairing = null;
      }
      return PairingClaimOutcome(
        result: PairingClaimResult.success,
        session: session,
        bearerToken: bearerToken,
      );
    });
  }

  void _registerPairIpFailure(String key) {
    final now = _clock();
    final cutoff = now.subtract(failWindow);
    final list = _failTimestamps.putIfAbsent(key, () => <DateTime>[]);
    list.removeWhere((time) => time.isBefore(cutoff));
    list.add(now);
    if (list.length >= maxFailedAttemptsPerPairingIp) {
      _rateLimitedUntil[key] = now.add(failWindow);
    }
  }

  Future<DeviceSession?> authenticate(String? bearer) {
    final token = _extractBearer(bearer);
    if (token == null) return Future<DeviceSession?>.value();
    final tokenHash = hashDeviceBearer(token);
    return _enqueueMutation(() async {
      final sessionId = _sessionIdByTokenHash[tokenHash];
      if (sessionId == null) return null;
      final entry = _sessionsById[sessionId];
      if (entry == null) return null;
      final session = entry.session;
      if (session.isExpiredAt(_clock())) {
        await _beforeDatabaseMutation(DeviceAuthMutationKind.expire);
        await _database?.deleteDeviceSession(sessionId);
        _removeCachedSession(entry);
        return null;
      }

      final lastSeenAt = _clock();
      await _beforeDatabaseMutation(DeviceAuthMutationKind.authenticate);
      final database = _database;
      if (database != null) {
        final updated = await database.updateDeviceSessionLastSeen(
          sessionId,
          lastSeenAt.millisecondsSinceEpoch,
        );
        if (!updated) throw const DeviceAuthPersistenceException();
      }
      session._markSeen(lastSeenAt);
      return session;
    });
  }

  Future<bool> revoke(String sessionId) {
    return _enqueueMutation(() async {
      final entry = _sessionsById[sessionId];
      if (entry == null) return false;
      await _beforeDatabaseMutation(DeviceAuthMutationKind.revoke);
      await _database?.deleteDeviceSession(sessionId);
      _removeCachedSession(entry);
      return true;
    });
  }

  Future<int> revokeDevice(String deviceName) {
    return _enqueueMutation(() async {
      final entries = _sessionsById.values
          .where((entry) => entry.session.deviceName == deviceName)
          .toList(growable: false);
      if (entries.isEmpty) return 0;
      await _beforeDatabaseMutation(DeviceAuthMutationKind.revokeDevice);
      await _database?.deleteDeviceSessionsByDeviceName(deviceName);
      for (final entry in entries) {
        _removeCachedSession(entry);
      }
      return entries.length;
    });
  }

  Future<void> revokeAll() {
    return _enqueueMutation(() async {
      await _beforeDatabaseMutation(DeviceAuthMutationKind.revokeAll);
      await _database?.deleteAllDeviceSessions();
      _sessionsById.clear();
      _sessionIdByTokenHash.clear();
    });
  }

  Future<void> drain() => _mutationTail;

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _acceptingMutations = false;
    final future = _mutationTail.then((_) {
      _activePairing = null;
      _failTimestamps.clear();
      _rateLimitedUntil.clear();
      _closed = true;
    });
    _closeFuture = future;
    return future;
  }

  Future<T> _enqueueMutation<T>(Future<T> Function() mutation) {
    if (!_acceptingMutations) {
      return Future<T>.error(const DeviceAuthClosedException());
    }
    final operation = _mutationTail.then((_) async {
      try {
        return await mutation();
      } on DeviceAuthException {
        rethrow;
      } catch (error, stackTrace) {
        Error.throwWithStackTrace(
          const DeviceAuthPersistenceException(),
          stackTrace,
        );
      }
    });
    _mutationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> _beforeDatabaseMutation(DeviceAuthMutationKind kind) async {
    await _testHooks.beforeDatabaseMutation?.call(kind);
  }

  void _ensureOpen() {
    if (!_acceptingMutations) throw const DeviceAuthClosedException();
  }

  void _cacheSession({
    required DeviceSession session,
    required String tokenHash,
  }) {
    if (_sessionsById.containsKey(session.sessionId) ||
        _sessionIdByTokenHash.containsKey(tokenHash)) {
      throw const DeviceAuthPersistenceException();
    }
    final entry = _DeviceSessionEntry(session: session, tokenHash: tokenHash);
    _sessionsById[session.sessionId] = entry;
    _sessionIdByTokenHash[tokenHash] = session.sessionId;
  }

  void _removeCachedSession(_DeviceSessionEntry entry) {
    _sessionsById.remove(entry.session.sessionId);
    _sessionIdByTokenHash.remove(entry.tokenHash);
  }

  DeviceSession _sessionFromRow(StoredDeviceSession row) {
    return DeviceSession._(
      sessionId: row.sessionId,
      deviceName: row.deviceName,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAtMs),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(row.expiresAtMs),
      lastSeenAt: row.lastSeenAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.lastSeenAtMs!),
    );
  }

  String? _extractBearer(String? bearer) {
    if (bearer == null || bearer.isEmpty) return null;
    var token = bearer;
    if (token.toLowerCase().startsWith('bearer ')) {
      token = token.substring(7).trim();
    }
    return token.isEmpty ? null : token;
  }

  String _randomId(int byteCount) {
    final bytes = List<int>.generate(byteCount, (_) => _rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

class _DeviceSessionEntry {
  const _DeviceSessionEntry({required this.session, required this.tokenHash});

  final DeviceSession session;
  final String tokenHash;
}
