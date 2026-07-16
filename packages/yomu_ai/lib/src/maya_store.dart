import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:yomu_storage/yomu_storage.dart';

import 'legacy_maya_migrator.dart';
import 'models.dart';

/// SQLite-backed Maya history with a private read-through cache.
///
/// Production instances never own or close [YomuDatabase]. Every mutation is
/// persisted before the cache changes, so a failed write cannot fabricate a
/// successful in-memory state. [MayaStore.inMemory] is deliberately limited
/// to tests and widget fixtures.
class MayaStore {
  MayaStore._({
    required YomuDatabase? database,
    required File? legacyFile,
    required String? legacyFingerprint,
    required String? legacyArchiveNonce,
    required LegacyMayaMigrationHooks legacyHooks,
  }) : _database = database,
       _legacyFile = legacyFile,
       _legacyFingerprint = legacyFingerprint,
       _legacyArchiveNonce = legacyArchiveNonce,
       _legacyHooks = legacyHooks;

  final YomuDatabase? _database;
  final File? _legacyFile;
  final String? _legacyFingerprint;
  final String? _legacyArchiveNonce;
  final LegacyMayaMigrationHooks _legacyHooks;
  final List<MayaMessage> _messages = <MayaMessage>[];
  final Map<String, ActionProposal> _proposals = <String, ActionProposal>{};

  static Future<MayaStore> open({
    required YomuDatabase database,
    required File legacyFile,
    LegacyMayaMigrationHooks migrationHooks = const LegacyMayaMigrationHooks(),
  }) async {
    await LegacyMayaChatMigrator(
      database: database,
      legacyFile: legacyFile,
      hooks: migrationHooks,
    ).migrate();

    final migration = _migrationArchive(
      await database.getMeta(kLegacyMayaMigrationMetaKey),
    );
    final store = MayaStore._(
      database: database,
      legacyFile: legacyFile,
      legacyFingerprint: migration.fingerprint,
      legacyArchiveNonce: migration.archiveNonce,
      legacyHooks: migrationHooks,
    );
    await store._reloadFromDatabase();
    await store._recoverConfirmedOutcomes();
    return store;
  }

  factory MayaStore.inMemory({
    Iterable<MayaMessage> seedMessages = const <MayaMessage>[],
    Iterable<ActionProposal> seedProposals = const <ActionProposal>[],
  }) {
    final store = MayaStore._(
      database: null,
      legacyFile: null,
      legacyFingerprint: null,
      legacyArchiveNonce: null,
      legacyHooks: const LegacyMayaMigrationHooks(),
    );
    final proposals = seedProposals
        .map(_normalizeInMemorySeedProposal)
        .map(_canonicalProposal)
        .toList(growable: false);
    store._replaceCache(
      seedMessages.map(_canonicalMessage).toList(growable: false),
      proposals,
    );
    return store;
  }

  bool get isPersistent => _database != null;

  List<MayaMessage> get messages => List<MayaMessage>.unmodifiable(_messages);

  Map<String, ActionProposal> get proposals =>
      UnmodifiableMapView<String, ActionProposal>(_proposals);

  MayaMessage? messageById(String id) {
    for (final message in _messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  ActionProposal? proposalById(String id) => _proposals[id];

  /// Compatibility reload. Production [open] already performs this once.
  Future<void> load() async {
    if (_database == null) return;
    await _reloadFromDatabase();
    await _recoverConfirmedOutcomes();
  }

  Future<void> appendTurn({
    required List<MayaMessage> messages,
    required List<ActionProposal> proposals,
  }) async {
    if (messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'must not be empty');
    }

    final canonicalMessages = messages
        .map(_canonicalMessage)
        .toList(growable: false);
    final canonicalProposals = proposals
        .map(_canonicalProposal)
        .toList(growable: false);
    _validateNewIds(canonicalMessages, canonicalProposals);
    final owners = _proposalOwners(canonicalMessages, canonicalProposals);

    final database = _database;
    if (database != null) {
      await database.appendMayaTurn(
        messages: canonicalMessages.map(_newStoredMessage).toList(),
        proposals: canonicalProposals.map((proposal) {
          final owner = owners[proposal.id]!;
          return _newStoredProposal(
            proposal,
            messageId: owner.messageId,
            proposalOrder: owner.order,
          );
        }).toList(),
      );
    }

    _messages.addAll(canonicalMessages);
    for (final proposal in canonicalProposals) {
      _proposals[proposal.id] = proposal;
    }
  }

  Future<bool> confirmPending(String proposalId, DateTime confirmedAt) async {
    final current = _proposals[proposalId];
    if (current == null || current.status != ActionProposalStatus.pending) {
      return false;
    }
    final effectiveAt = _notBefore(confirmedAt, current.createdAt);

    final database = _database;
    if (database != null &&
        !await database.confirmMayaProposal(
          proposalId,
          effectiveAt.millisecondsSinceEpoch,
        )) {
      await _reloadFromDatabase();
      return false;
    }

    _proposals[proposalId] = current.copyWith(
      status: ActionProposalStatus.confirmed,
      confirmedAt: effectiveAt,
      clearCompletedAt: true,
      clearError: true,
    );
    return true;
  }

  Future<bool> completeConfirmed(
    String proposalId, {
    required ActionProposalStatus status,
    required DateTime completedAt,
    String? error,
    MayaMessage? outcomeMessage,
  }) async {
    if (status != ActionProposalStatus.executed &&
        status != ActionProposalStatus.failed) {
      throw ArgumentError.value(status, 'status', 'must be executed or failed');
    }
    final current = _proposals[proposalId];
    if (current == null || current.status != ActionProposalStatus.confirmed) {
      return false;
    }
    final effectiveAt = _notBefore(
      completedAt,
      current.confirmedAt ?? current.createdAt,
    );
    final safeError = error == null ? null : sanitizeMayaError(error);
    final canonicalOutcome = outcomeMessage == null
        ? null
        : _canonicalMessage(outcomeMessage);

    final database = _database;
    if (database != null &&
        !await database.completeConfirmedMayaProposal(
          proposalId,
          status: status.name,
          completedAtMs: effectiveAt.millisecondsSinceEpoch,
          error: safeError,
          outcomeMessage: canonicalOutcome == null
              ? null
              : _newStoredMessage(canonicalOutcome),
        )) {
      await _reloadFromDatabase();
      return false;
    }

    _proposals[proposalId] = current.copyWith(
      status: status,
      completedAt: effectiveAt,
      error: safeError,
      clearError: safeError == null,
    );
    if (canonicalOutcome != null) _messages.add(canonicalOutcome);
    return true;
  }

  Future<bool> resolvePending(
    String proposalId, {
    required ActionProposalStatus status,
    required DateTime completedAt,
    String? error,
    MayaMessage? outcomeMessage,
  }) async {
    if (status != ActionProposalStatus.rejected &&
        status != ActionProposalStatus.failed) {
      throw ArgumentError.value(status, 'status', 'must be rejected or failed');
    }
    final current = _proposals[proposalId];
    if (current == null || current.status != ActionProposalStatus.pending) {
      return false;
    }
    final effectiveAt = _notBefore(completedAt, current.createdAt);
    final safeError = error == null ? null : sanitizeMayaError(error);
    final canonicalOutcome = outcomeMessage == null
        ? null
        : _canonicalMessage(outcomeMessage);

    final database = _database;
    if (database != null &&
        !await database.resolvePendingMayaProposal(
          proposalId,
          status: status.name,
          completedAtMs: effectiveAt.millisecondsSinceEpoch,
          error: safeError,
          outcomeMessage: canonicalOutcome == null
              ? null
              : _newStoredMessage(canonicalOutcome),
        )) {
      await _reloadFromDatabase();
      return false;
    }

    _proposals[proposalId] = current.copyWith(
      status: status,
      completedAt: effectiveAt,
      clearConfirmedAt: true,
      error: safeError,
      clearError: safeError == null,
    );
    if (canonicalOutcome != null) _messages.add(canonicalOutcome);
    return true;
  }

  Future<bool> markConfirmedOutcomeUncertain(
    String proposalId, {
    MayaMessage? outcomeMessage,
  }) async {
    final current = _proposals[proposalId];
    if (current == null || current.status != ActionProposalStatus.confirmed) {
      return false;
    }
    final canonicalOutcome = outcomeMessage == null
        ? null
        : _canonicalMessage(outcomeMessage);

    final database = _database;
    if (database != null &&
        !await database.markConfirmedMayaProposalOutcomeUncertain(
          proposalId,
          error: kMayaOutcomeUncertainError,
          outcomeMessage: canonicalOutcome == null
              ? null
              : _newStoredMessage(canonicalOutcome),
        )) {
      await _reloadFromDatabase();
      return false;
    }

    _proposals[proposalId] = current.copyWith(
      error: kMayaOutcomeUncertainError,
    );
    if (canonicalOutcome != null) _messages.add(canonicalOutcome);
    return true;
  }

  Future<void> clear() async {
    final database = _database;
    if (database == null &&
        _proposals.values.any(
          (proposal) => proposal.status == ActionProposalStatus.confirmed,
        )) {
      throw StateError(
        'O histórico não pode ser limpo enquanto há resultado não verificado.',
      );
    }

    if (database == null) {
      await _deleteLegacyHistoryFiles();
    } else if (!await database.runInTransaction((database) async {
      if (await database.hasConfirmedMayaProposal()) return false;
      await _deleteLegacyHistoryFiles();
      return database.clearMayaData();
    })) {
      await _reloadFromDatabase();
      throw StateError(
        'O histórico não pode ser limpo enquanto há resultado não verificado.',
      );
    }
    _messages.clear();
    _proposals.clear();
  }

  Future<void> _deleteLegacyHistoryFiles() async {
    final legacyFile = _legacyFile;
    if (legacyFile == null) return;
    final fingerprint = _legacyFingerprint;

    try {
      if (fingerprint == null) {
        if (await legacyFile.exists()) {
          throw const LegacyMayaMigrationException(
            'legacy_source_changed_before_clear',
          );
        }
      } else {
        await _captureVerifyAndDeleteLegacyFile(
          source: legacyFile,
          capturePrefix: '${legacyFile.path}.clearing-v1.$fingerprint.source',
          expectedFingerprint: fingerprint,
          changedCode: 'legacy_source_changed_before_clear',
          reappearedCode: 'legacy_source_reappeared_during_clear',
          afterCapture: _legacyHooks.afterClearSourceCapturedBeforeVerify,
        );
      }

      final archivePattern = RegExp(
        '^${RegExp.escape(legacyFile.path)}'
        r'\.migrated-v1\.[0-9a-f]{64}(?:\.[0-9a-f]{32})?\.bak$',
      );
      File? expectedArchive;
      await for (final entity in legacyFile.parent.list(followLinks: false)) {
        if (entity is File && archivePattern.hasMatch(entity.path)) {
          final expectedPath = fingerprint == null
              ? null
              : _legacyArchiveNonce == null
              ? '${legacyFile.path}.migrated-v1.$fingerprint.bak'
              : '${legacyFile.path}.migrated-v1.$fingerprint.'
                    '$_legacyArchiveNonce.bak';
          if (entity.path != expectedPath || expectedArchive != null) {
            throw const LegacyMayaMigrationException(
              'legacy_archive_changed_before_clear',
            );
          }
          expectedArchive = entity;
        }
      }
      if (fingerprint != null) {
        final archive =
            expectedArchive ??
            File(
              _legacyArchiveNonce == null
                  ? '${legacyFile.path}.migrated-v1.$fingerprint.bak'
                  : '${legacyFile.path}.migrated-v1.$fingerprint.'
                        '$_legacyArchiveNonce.bak',
            );
        await _captureVerifyAndDeleteLegacyFile(
          source: archive,
          capturePrefix: '${archive.path}.clearing',
          expectedFingerprint: fingerprint,
          changedCode: 'legacy_archive_changed_before_clear',
          reappearedCode: 'legacy_archive_reappeared_during_clear',
        );
      }
    } on LegacyMayaMigrationException {
      rethrow;
    } catch (_) {
      throw const LegacyMayaMigrationException('legacy_cleanup_failed');
    }
  }

  Future<void> _captureVerifyAndDeleteLegacyFile({
    required File source,
    required String capturePrefix,
    required String expectedFingerprint,
    required String changedCode,
    required String reappearedCode,
    Future<void> Function()? afterCapture,
  }) async {
    var capture = await _findLegacyClearCapture(capturePrefix);
    if (capture == null) {
      if (!await source.exists()) return;
      capture = File('$capturePrefix.${_legacyFileNonce()}.tmp');
      final result = LegacyMayaFileOps.moveNoReplaceSync(
        source: source,
        destination: capture,
      );
      if (result == LegacyMayaMoveNoReplaceResult.destinationExists) {
        throw const LegacyMayaMigrationException(
          'legacy_clear_capture_conflict',
        );
      }
      await afterCapture?.call();
    }

    final bytes = await LegacyMayaFileOps.readBounded(capture);
    if (bytes == null) {
      throw LegacyMayaMigrationException(changedCode);
    }
    if (sha256.convert(bytes).toString() != expectedFingerprint) {
      await _restoreLegacyCapture(
        source: source,
        capture: capture,
        bytes: bytes,
      );
      throw LegacyMayaMigrationException(changedCode);
    }

    await capture.delete();
    if (await source.exists()) {
      throw LegacyMayaMigrationException(reappearedCode);
    }
  }

  Future<void> _restoreLegacyCapture({
    required File source,
    required File capture,
    required List<int> bytes,
  }) async {
    final expected = sha256.convert(bytes).toString();
    try {
      if (await source.exists()) {
        final currentBytes = await LegacyMayaFileOps.readBounded(source);
        if (currentBytes != null &&
            sha256.convert(currentBytes).toString() == expected) {
          await capture.delete();
        }
        return;
      }
      final result = LegacyMayaFileOps.moveNoReplaceSync(
        source: capture,
        destination: source,
      );
      if (result == LegacyMayaMoveNoReplaceResult.destinationExists) {
        final currentBytes = await LegacyMayaFileOps.readBounded(source);
        if (currentBytes != null &&
            sha256.convert(currentBytes).toString() == expected) {
          await capture.delete();
        }
      }
    } catch (_) {
      // Preserve the capture when no-replace restoration cannot be proven.
    }
  }

  Future<File?> _findLegacyClearCapture(String capturePrefix) async {
    final pattern = RegExp(
      '^${RegExp.escape(capturePrefix)}\\.[0-9a-f]{32}\\.tmp\$',
    );
    File? found;
    await for (final entity in _legacyFile!.parent.list(followLinks: false)) {
      if (entity is! File || !pattern.hasMatch(entity.path)) continue;
      if (found != null) {
        throw const LegacyMayaMigrationException(
          'legacy_clear_capture_conflict',
        );
      }
      found = entity;
    }
    return found;
  }

  Future<void> _reloadFromDatabase() async {
    final database = _database;
    if (database == null) return;
    final decoded = _decodeSnapshot(await database.loadMayaSnapshot());
    _replaceCache(decoded.messages, decoded.proposals);
  }

  Future<void> _recoverConfirmedOutcomes() async {
    final confirmed = _proposals.values
        .where(
          (proposal) =>
              proposal.status == ActionProposalStatus.confirmed &&
              proposal.error == null,
        )
        .map((proposal) => proposal.id)
        .toList(growable: false);
    for (final proposalId in confirmed) {
      if (!await markConfirmedOutcomeUncertain(proposalId)) {
        throw StateError('Persisted Maya confirmation recovery failed');
      }
    }
  }

  void _replaceCache(
    Iterable<MayaMessage> messages,
    Iterable<ActionProposal> proposals,
  ) {
    final nextMessages = messages.toList(growable: false);
    final nextProposals = proposals.toList(growable: false);
    final messageIds = <String>{};
    for (final message in nextMessages) {
      if (!messageIds.add(message.id)) {
        throw StateError('Duplicate Maya message id');
      }
    }
    final proposalIds = <String>{};
    for (final proposal in nextProposals) {
      if (!proposalIds.add(proposal.id)) {
        throw StateError('Duplicate Maya proposal id');
      }
    }
    final ownedProposalIds = <String>{};
    for (final message in nextMessages) {
      if (message.proposalIds.isNotEmpty &&
          message.role != MayaRole.assistant) {
        throw StateError('Maya proposals must belong to an assistant message');
      }
      for (final proposalId in message.proposalIds) {
        if (!proposalIds.contains(proposalId) ||
            !ownedProposalIds.add(proposalId)) {
          throw StateError('Invalid Maya message proposal reference');
        }
      }
    }

    _messages
      ..clear()
      ..addAll(nextMessages);
    _proposals
      ..clear()
      ..addEntries(
        nextProposals.map(
          (proposal) => MapEntry<String, ActionProposal>(proposal.id, proposal),
        ),
      );
  }

  void _validateNewIds(
    List<MayaMessage> messages,
    List<ActionProposal> proposals,
  ) {
    final newMessageIds = <String>{};
    for (final message in messages) {
      if (messageById(message.id) != null || !newMessageIds.add(message.id)) {
        throw StateError('Duplicate Maya message id');
      }
    }
    final newProposalIds = <String>{};
    for (final proposal in proposals) {
      if (_proposals.containsKey(proposal.id) ||
          !newProposalIds.add(proposal.id)) {
        throw StateError('Duplicate Maya proposal id');
      }
      if (proposal.status != ActionProposalStatus.pending) {
        throw ArgumentError('New Maya proposals must be pending');
      }
    }
  }
}

Map<String, ({String messageId, int order})> _proposalOwners(
  List<MayaMessage> messages,
  List<ActionProposal> proposals,
) {
  final proposalIds = proposals.map((proposal) => proposal.id).toSet();
  final owners = <String, ({String messageId, int order})>{};
  for (final message in messages) {
    if (message.proposalIds.isNotEmpty && message.role != MayaRole.assistant) {
      throw ArgumentError('Maya proposals must belong to an assistant message');
    }
    for (var order = 0; order < message.proposalIds.length; order++) {
      final proposalId = message.proposalIds[order];
      if (!proposalIds.contains(proposalId)) {
        throw ArgumentError('Maya message references an unknown proposal');
      }
      if (owners.containsKey(proposalId)) {
        throw ArgumentError('Maya proposal is referenced more than once');
      }
      owners[proposalId] = (messageId: message.id, order: order);
    }
  }
  if (owners.length != proposals.length) {
    throw ArgumentError('Every new Maya proposal must belong to one message');
  }
  return owners;
}

_DecodedMayaSnapshot _decodeSnapshot(MayaStorageSnapshot snapshot) {
  final messageRows = <String, StoredMayaMessage>{};
  final proposalIdsByMessage = <String, SplayTreeMap<int, String>>{};
  for (final row in snapshot.messages) {
    if (messageRows.putIfAbsent(row.messageId, () => row) != row) {
      throw StateError('Duplicate persisted Maya message id');
    }
    proposalIdsByMessage[row.messageId] = SplayTreeMap<int, String>();
  }

  final proposals = <ActionProposal>[];
  final seenProposalIds = <String>{};
  for (final row in snapshot.proposals) {
    if (!seenProposalIds.add(row.proposalId)) {
      throw StateError('Duplicate persisted Maya proposal id');
    }
    proposals.add(_proposalFromStored(row));
    final messageId = row.messageId;
    final order = row.proposalOrder;
    if ((messageId == null) != (order == null)) {
      throw StateError('Invalid persisted Maya proposal owner');
    }
    if (messageId != null) {
      final ordered = proposalIdsByMessage[messageId];
      final owner = messageRows[messageId];
      if (ordered == null ||
          owner == null ||
          owner.role != MayaRole.assistant.name ||
          ordered.putIfAbsent(order!, () => row.proposalId) != row.proposalId) {
        throw StateError('Invalid persisted Maya proposal ordering');
      }
    }
  }

  final messages = <MayaMessage>[];
  for (final row in snapshot.messages) {
    final proposalIds = proposalIdsByMessage[row.messageId]!.values.toList();
    messages.add(
      _canonicalMessage(
        MayaMessage(
          id: row.messageId,
          role: _parseRole(row.role),
          text: row.content,
          createdAt: _dateFromMs(row.createdAtMs),
          proposalIds: proposalIds,
        ),
      ),
    );
  }
  return _DecodedMayaSnapshot(messages: messages, proposals: proposals);
}

MayaMessage _canonicalMessage(MayaMessage message) {
  try {
    return MayaMessage.fromJson(message.toJson());
  } on FormatException {
    throw ArgumentError('Invalid Maya message');
  }
}

ActionProposal _canonicalProposal(ActionProposal proposal) {
  try {
    final parsed = ActionProposal.fromJson(proposal.toJson());
    final confirmedAt = proposal.confirmedAt;
    final completedAt = proposal.completedAt;
    _validateProposalLifecycle(
      parsed.status,
      parsed.createdAt,
      confirmedAt,
      completedAt,
    );
    return parsed.copyWith(
      confirmedAt: confirmedAt,
      completedAt: completedAt,
      clearConfirmedAt: confirmedAt == null,
      clearCompletedAt: completedAt == null,
    );
  } on FormatException {
    throw ArgumentError('Invalid Maya proposal');
  }
}

ActionProposal _proposalFromStored(StoredMayaProposal row) {
  try {
    final decodedPayload = jsonDecode(row.payloadJson);
    if (decodedPayload is! Map) throw const FormatException();
    final createdAt = _dateFromMs(row.createdAtMs);
    final confirmedAt = row.confirmedAtMs == null
        ? null
        : _dateFromMs(row.confirmedAtMs!);
    final completedAt = row.completedAtMs == null
        ? null
        : _dateFromMs(row.completedAtMs!);
    final parsed = ActionProposal.fromJson({
      'id': row.proposalId,
      'kind': row.kind,
      'title': row.title,
      'description': row.description,
      'payload': Map<String, dynamic>.from(decodedPayload),
      'status': row.status,
      'createdAt': createdAt.toIso8601String(),
      'error': row.error == null ? null : sanitizeMayaError(row.error!),
    });
    _validateProposalLifecycle(
      parsed.status,
      createdAt,
      confirmedAt,
      completedAt,
    );
    return parsed.copyWith(
      confirmedAt: confirmedAt,
      completedAt: completedAt,
      clearConfirmedAt: confirmedAt == null,
      clearCompletedAt: completedAt == null,
    );
  } catch (_) {
    throw StateError('Invalid persisted Maya proposal');
  }
}

void _validateProposalLifecycle(
  ActionProposalStatus status,
  DateTime createdAt,
  DateTime? confirmedAt,
  DateTime? completedAt,
) {
  if (confirmedAt != null && confirmedAt.isBefore(createdAt) ||
      completedAt != null && completedAt.isBefore(createdAt) ||
      confirmedAt != null &&
          completedAt != null &&
          completedAt.isBefore(confirmedAt)) {
    throw const FormatException('proposal_timestamps_invalid');
  }
  final valid = switch (status) {
    ActionProposalStatus.pending => confirmedAt == null && completedAt == null,
    ActionProposalStatus.confirmed =>
      confirmedAt != null && completedAt == null,
    ActionProposalStatus.rejected => confirmedAt == null && completedAt != null,
    ActionProposalStatus.executed => confirmedAt != null && completedAt != null,
    ActionProposalStatus.failed => completedAt != null,
  };
  if (!valid) throw const FormatException('proposal_lifecycle_invalid');
}

ActionProposal _normalizeInMemorySeedProposal(ActionProposal proposal) {
  final createdAt = proposal.createdAt;
  return switch (proposal.status) {
    ActionProposalStatus.pending => proposal.copyWith(
      clearConfirmedAt: true,
      clearCompletedAt: true,
    ),
    ActionProposalStatus.confirmed => proposal.copyWith(
      confirmedAt: proposal.confirmedAt ?? createdAt,
      clearCompletedAt: true,
      error: proposal.error ?? kMayaOutcomeUncertainError,
    ),
    ActionProposalStatus.rejected => proposal.copyWith(
      clearConfirmedAt: true,
      completedAt: proposal.completedAt ?? createdAt,
    ),
    ActionProposalStatus.executed => proposal.copyWith(
      confirmedAt: proposal.confirmedAt ?? createdAt,
      completedAt: proposal.completedAt ?? createdAt,
    ),
    ActionProposalStatus.failed => proposal.copyWith(
      completedAt: proposal.completedAt ?? createdAt,
    ),
  };
}

NewMayaMessage _newStoredMessage(MayaMessage message) {
  return NewMayaMessage(
    messageId: message.id,
    role: message.role.name,
    text: message.text,
    createdAtMs: message.createdAt.millisecondsSinceEpoch,
  );
}

NewMayaProposal _newStoredProposal(
  ActionProposal proposal, {
  required String? messageId,
  required int? proposalOrder,
}) {
  return NewMayaProposal(
    proposalId: proposal.id,
    messageId: messageId,
    proposalOrder: proposalOrder,
    kind: proposal.kind.name,
    title: proposal.title,
    description: proposal.description,
    payloadJson: jsonEncode(proposal.payload),
    status: proposal.status.name,
    createdAtMs: proposal.createdAt.millisecondsSinceEpoch,
    confirmedAtMs: proposal.confirmedAt?.millisecondsSinceEpoch,
    completedAtMs: proposal.completedAt?.millisecondsSinceEpoch,
    error: proposal.error,
  );
}

MayaRole _parseRole(String value) {
  for (final role in MayaRole.values) {
    if (role.name == value) return role;
  }
  throw StateError('Invalid persisted Maya role');
}

DateTime _dateFromMs(int value) {
  if (value < 0) throw StateError('Invalid persisted Maya timestamp');
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}

DateTime _notBefore(DateTime value, DateTime minimum) {
  return value.isBefore(minimum) ? minimum : value;
}

({String? fingerprint, String? archiveNonce}) _migrationArchive(String? raw) {
  if (raw == null) throw StateError('Missing Maya migration marker');
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['version'] != 1) {
      throw const FormatException();
    }
    final state = decoded['state'];
    final fingerprint = decoded['fingerprint'];
    final archiveNonce = decoded['archiveNonce'];
    if (state is! String ||
        !const <String>{'absent', 'empty', 'imported'}.contains(state) ||
        (fingerprint != null &&
            (fingerprint is! String ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint))) ||
        (archiveNonce != null &&
            (archiveNonce is! String ||
                !RegExp(r'^[0-9a-f]{32}$').hasMatch(archiveNonce))) ||
        (state == 'absent' && archiveNonce != null) ||
        ((state == 'absent') != (fingerprint == null))) {
      throw const FormatException();
    }
    return (
      fingerprint: fingerprint as String?,
      archiveNonce: archiveNonce as String?,
    );
  } catch (_) {
    throw StateError('Invalid Maya migration marker');
  }
}

String _legacyFileNonce() {
  final random = Random.secure();
  return List<String>.generate(
    4,
    (_) => random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
  ).join();
}

class _DecodedMayaSnapshot {
  const _DecodedMayaSnapshot({required this.messages, required this.proposals});

  final List<MayaMessage> messages;
  final List<ActionProposal> proposals;
}
