import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:yomu_storage/yomu_storage.dart';

import 'device_token_hash.dart';

const kLegacyDeviceSessionsMigrationMetaKey =
    'migration.device_sessions_json.v1';

@immutable
class LegacyDeviceSessionsMigrationHooks {
  const LegacyDeviceSessionsMigrationHooks({
    this.afterRowsInsertedBeforeMarker,
    this.afterCommitBeforeCleanup,
  });

  /// Simulates a crash inside the SQLite transaction.
  final Future<void> Function()? afterRowsInsertedBeforeMarker;

  /// Simulates a crash after commit while the plaintext source still exists.
  final Future<void> Function()? afterCommitBeforeCleanup;
}

class LegacyDeviceSessionsMigrationException implements Exception {
  const LegacyDeviceSessionsMigrationException(this.code);

  final String code;

  @override
  String toString() => 'LegacyDeviceSessionsMigrationException($code)';
}

/// Imports the legacy plaintext JSON exactly once and then removes it.
///
/// Session rows and the fingerprint marker are committed in one transaction.
/// A committed marker always wins over a still-present source file so a
/// revoked session can never be imported again after a crash.
class LegacyDeviceSessionMigrator {
  static const int maxLegacySourceBytes = 4 * 1024 * 1024;

  LegacyDeviceSessionMigrator({
    required this.database,
    required this.legacyFile,
    this.hooks = const LegacyDeviceSessionsMigrationHooks(),
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final YomuDatabase database;
  final File legacyFile;
  final LegacyDeviceSessionsMigrationHooks hooks;
  final DateTime Function() _clock;
  final Random _random;

  Future<void> migrate() async {
    try {
      await _migrate();
    } on LegacyDeviceSessionsMigrationException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        const LegacyDeviceSessionsMigrationException('migration_failed'),
        stackTrace,
      );
    }
  }

  Future<void> _migrate() async {
    final markerRaw = await database.getMeta(
      kLegacyDeviceSessionsMigrationMetaKey,
    );
    final marker = markerRaw == null ? null : _MigrationMarker.parse(markerRaw);
    final exists = await legacyFile.exists();

    if (marker != null) {
      if (!exists) return;
      if (marker.fingerprint == null) {
        throw const LegacyDeviceSessionsMigrationException(
          'legacy_source_appeared_after_absent_marker',
        );
      }
      final bytes = await _readSourceBytes();
      final fingerprint = sha256.convert(bytes).toString();
      if (fingerprint != marker.fingerprint) {
        throw const LegacyDeviceSessionsMigrationException(
          'legacy_source_changed_after_migration',
        );
      }
      await _deleteIfUnchanged(expectedFingerprint: fingerprint);
      return;
    }

    if (!exists) {
      final absent = _MigrationMarker.absent();
      await _commitMarkerAndRows(absent, const []);
      await _verifyMarker(absent);
      return;
    }

    final bytes = await _readSourceBytes();
    final fingerprint = sha256.convert(bytes).toString();
    final parsed = _parseSource(bytes);
    final markerForSource = _MigrationMarker(
      state: parsed.sourceWasEmpty ? 'empty' : 'imported',
      fingerprint: fingerprint,
    );

    await _commitMarkerAndRows(markerForSource, parsed.sessions);
    await _verifyMarker(markerForSource);
    await hooks.afterCommitBeforeCleanup?.call();
    await _deleteIfUnchanged(expectedFingerprint: fingerprint);
  }

  Future<List<int>> _readSourceBytes() async {
    try {
      if (await legacyFile.length() > maxLegacySourceBytes) {
        throw const LegacyDeviceSessionsMigrationException(
          'legacy_source_too_large',
        );
      }
      final bytes = await legacyFile.readAsBytes();
      if (bytes.length > maxLegacySourceBytes) {
        throw const LegacyDeviceSessionsMigrationException(
          'legacy_source_too_large',
        );
      }
      return bytes;
    } on LegacyDeviceSessionsMigrationException {
      rethrow;
    } catch (_) {
      throw const LegacyDeviceSessionsMigrationException(
        'legacy_source_unreadable',
      );
    }
  }

  _ParsedLegacySource _parseSource(List<int> bytes) {
    final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      throw const LegacyDeviceSessionsMigrationException('legacy_utf8_invalid');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const LegacyDeviceSessionsMigrationException('legacy_json_invalid');
    }
    if (decoded is! Map) {
      throw const LegacyDeviceSessionsMigrationException(
        'legacy_root_not_object',
      );
    }
    final rawSessions = decoded['sessions'];
    if (rawSessions is! List) {
      throw const LegacyDeviceSessionsMigrationException(
        'legacy_sessions_not_list',
      );
    }

    final nowMs = _clock().millisecondsSinceEpoch;
    final byTokenHash = <String, NewDeviceSession>{};
    for (final raw in rawSessions) {
      if (raw is! Map) {
        throw const LegacyDeviceSessionsMigrationException(
          'legacy_session_not_object',
        );
      }
      final tokenValue = raw['token'];
      if (tokenValue is! String || tokenValue.isEmpty) {
        throw const LegacyDeviceSessionsMigrationException(
          'legacy_token_invalid',
        );
      }
      final createdAt = _requiredDate(raw['createdAt'], 'created_at_invalid');
      final expiresValue = raw['expiresAt'];
      final expiresAt = expiresValue == null
          ? createdAt.add(const Duration(days: 30))
          : _requiredDate(expiresValue, 'expires_at_invalid');
      final lastSeenValue = raw['lastSeenAt'];
      final lastSeenAt = lastSeenValue == null
          ? null
          : _requiredDate(lastSeenValue, 'last_seen_at_invalid');
      final deviceValue = raw['deviceName'];
      if (deviceValue != null && deviceValue is! String) {
        throw const LegacyDeviceSessionsMigrationException(
          'device_name_invalid',
        );
      }
      final normalizedDevice = (deviceValue as String?)?.trim() ?? '';
      final tokenHash = hashDeviceBearer(tokenValue);

      // Expired entries are not candidates. Among active duplicates, the last
      // occurrence wins, matching the legacy map-overwrite behavior.
      if (expiresAt.millisecondsSinceEpoch <= nowMs) continue;
      byTokenHash[tokenHash] = NewDeviceSession(
        sessionId: _randomId(18),
        tokenHash: tokenHash,
        deviceName: normalizedDevice.isEmpty ? 'device' : normalizedDevice,
        createdAtMs: createdAt.millisecondsSinceEpoch,
        expiresAtMs: expiresAt.millisecondsSinceEpoch,
        lastSeenAtMs: lastSeenAt?.millisecondsSinceEpoch,
      );
    }
    return _ParsedLegacySource(
      sourceWasEmpty: rawSessions.isEmpty,
      sessions: byTokenHash.values.toList(growable: false),
    );
  }

  DateTime _requiredDate(Object? value, String code) {
    if (value is! String) {
      throw LegacyDeviceSessionsMigrationException(code);
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw LegacyDeviceSessionsMigrationException(code);
    }
    return parsed;
  }

  Future<void> _commitMarkerAndRows(
    _MigrationMarker marker,
    List<NewDeviceSession> sessions,
  ) async {
    try {
      await database.runInTransaction((transaction) async {
        for (final session in sessions) {
          await transaction.insertDeviceSession(session);
        }
        await hooks.afterRowsInsertedBeforeMarker?.call();
        await transaction.setMeta(
          kLegacyDeviceSessionsMigrationMetaKey,
          marker.encode(),
        );
      });
    } catch (_) {
      throw const LegacyDeviceSessionsMigrationException(
        'legacy_transaction_failed',
      );
    }
  }

  Future<void> _verifyMarker(_MigrationMarker expected) async {
    final actual = await database.getMeta(
      kLegacyDeviceSessionsMigrationMetaKey,
    );
    if (actual != expected.encode()) {
      throw const LegacyDeviceSessionsMigrationException(
        'legacy_marker_readback_failed',
      );
    }
  }

  Future<void> _deleteIfUnchanged({required String expectedFingerprint}) async {
    if (!await legacyFile.exists()) return;
    final current = sha256.convert(await _readSourceBytes()).toString();
    if (current != expectedFingerprint) {
      throw const LegacyDeviceSessionsMigrationException(
        'legacy_source_changed_before_cleanup',
      );
    }
    try {
      await legacyFile.delete();
    } catch (_) {
      throw const LegacyDeviceSessionsMigrationException(
        'legacy_cleanup_failed',
      );
    }
  }

  String _randomId(int byteCount) {
    final bytes = List<int>.generate(byteCount, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

class _ParsedLegacySource {
  const _ParsedLegacySource({
    required this.sourceWasEmpty,
    required this.sessions,
  });

  final bool sourceWasEmpty;
  final List<NewDeviceSession> sessions;
}

class _MigrationMarker {
  const _MigrationMarker({required this.state, required this.fingerprint});

  factory _MigrationMarker.absent() {
    return const _MigrationMarker(state: 'absent', fingerprint: null);
  }

  factory _MigrationMarker.parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != 1) {
        throw const FormatException();
      }
      final state = decoded['state'];
      final fingerprint = decoded['fingerprint'];
      if (state is! String ||
          !const {'absent', 'empty', 'imported'}.contains(state) ||
          (fingerprint != null &&
              (fingerprint is! String ||
                  !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)))) {
        throw const FormatException();
      }
      if ((state == 'absent') != (fingerprint == null)) {
        throw const FormatException();
      }
      return _MigrationMarker(
        state: state,
        fingerprint: fingerprint as String?,
      );
    } catch (_) {
      throw const LegacyDeviceSessionsMigrationException(
        'legacy_marker_invalid',
      );
    }
  }

  final String state;
  final String? fingerprint;

  String encode() =>
      jsonEncode({'version': 1, 'state': state, 'fingerprint': fingerprint});
}
