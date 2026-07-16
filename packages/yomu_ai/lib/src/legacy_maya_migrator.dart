import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:yomu_storage/yomu_storage.dart';

import 'models.dart';

const kLegacyMayaMigrationMetaKey = 'migration.maya_chat_json.v1';

@immutable
class LegacyMayaMigrationHooks {
  const LegacyMayaMigrationHooks({
    this.afterRowsInsertedBeforeMarker,
    this.afterCommitBeforeArchive,
    this.afterArchiveSourceCapturedBeforeVerify,
    this.beforeArchiveCapturePublished,
    this.afterClearSourceCapturedBeforeVerify,
  });

  /// Test-only crash point inside the SQLite import transaction.
  final Future<void> Function()? afterRowsInsertedBeforeMarker;

  /// Test-only crash point after commit/readback while the source still exists.
  final Future<void> Function()? afterCommitBeforeArchive;

  /// Test-only crash/race point after the source is atomically captured for
  /// archival and before its fingerprint is verified.
  final Future<void> Function()? afterArchiveSourceCapturedBeforeVerify;

  /// Test-only crash/race point after capture verification and immediately
  /// before its atomic no-replace publication as the legacy archive.
  final Future<void> Function()? beforeArchiveCapturePublished;

  /// Test-only crash/race point after a residual source is atomically captured
  /// for clear and before its fingerprint is verified.
  final Future<void> Function()? afterClearSourceCapturedBeforeVerify;
}

/// A safe, source-file-only migration failure.
///
/// Drift/SQLite failures are intentionally not wrapped in this type. Desktop
/// may degrade Maya for this exception, while shared storage failures remain
/// fatal to storage-first bootstrap.
class LegacyMayaMigrationException implements Exception {
  const LegacyMayaMigrationException(this.code);

  final String code;

  @override
  String toString() => 'LegacyMayaMigrationException($code)';
}

@internal
enum LegacyMayaMoveNoReplaceResult { moved, destinationExists }

/// Windows-only file primitives shared by migration and explicit clear.
///
/// Legacy Maya files always move within one directory. `MoveFileExW` without
/// `MOVEFILE_REPLACE_EXISTING` or `MOVEFILE_COPY_ALLOWED` therefore provides
/// the required atomic, same-volume, no-replace publication semantics.
@internal
abstract final class LegacyMayaFileOps {
  static const int _readChunkBytes = 64 * 1024;

  static LegacyMayaMoveNoReplaceResult moveNoReplaceSync({
    required File source,
    required File destination,
  }) {
    if (!Platform.isWindows) {
      throw UnsupportedError('Atomic legacy Maya moves require Windows');
    }

    final sourcePath = _NativeUtf16(source.absolute.path);
    try {
      final destinationPath = _NativeUtf16(destination.absolute.path);
      try {
        final moved = _Kernel32.moveFileExW(
          sourcePath.pointer,
          destinationPath.pointer,
          0,
        );
        final error = moved == 0 ? _Kernel32.getLastError() : 0;
        if (moved != 0) return LegacyMayaMoveNoReplaceResult.moved;
        if (error == _errorFileExists ||
            error == _errorAlreadyExists ||
            _destinationExists(destination)) {
          return LegacyMayaMoveNoReplaceResult.destinationExists;
        }
        throw FileSystemException(
          'Atomic legacy Maya move failed',
          source.path,
          OSError('MoveFileExW failed', error),
        );
      } finally {
        destinationPath.free();
      }
    } finally {
      sourcePath.free();
    }
  }

  /// Reads at most the configured legacy-source limit plus one byte.
  ///
  /// `null` means the file exceeded the limit. Reading through a fixed-size
  /// handle loop prevents a concurrently grown/replaced file from causing an
  /// unbounded `readAsBytes` allocation.
  static Future<List<int>?> readBounded(File file) async {
    final input = await file.open();
    try {
      final bytes = BytesBuilder(copy: false);
      var total = 0;
      while (true) {
        final remaining =
            LegacyMayaChatMigrator.maxLegacySourceBytes + 1 - total;
        final chunk = await input.read(min(_readChunkBytes, remaining));
        if (chunk.isEmpty) return bytes.takeBytes();
        bytes.add(chunk);
        total += chunk.length;
        if (total > LegacyMayaChatMigrator.maxLegacySourceBytes) return null;
      }
    } finally {
      await input.close();
    }
  }

  static bool _destinationExists(File destination) {
    try {
      return FileSystemEntity.typeSync(destination.path, followLinks: false) !=
          FileSystemEntityType.notFound;
    } catch (_) {
      return false;
    }
  }
}

const int _errorFileExists = 80;
const int _errorAlreadyExists = 183;

final class _NativeUtf16 {
  _NativeUtf16(String value) : pointer = _allocate(value);

  final ffi.Pointer<ffi.Uint16> pointer;

  static ffi.Pointer<ffi.Uint16> _allocate(String value) {
    final units = value.codeUnits;
    if (units.contains(0)) {
      throw ArgumentError.value(value, 'value', 'Path contains NUL');
    }
    final count = units.length + 1;
    final raw = _Kernel32.localAlloc(0, count * ffi.sizeOf<ffi.Uint16>());
    if (raw == ffi.nullptr) {
      throw StateError('LocalAlloc failed for UTF-16 path');
    }
    final pointer = raw.cast<ffi.Uint16>();
    final buffer = pointer.asTypedList(count);
    buffer.setAll(0, units);
    buffer[units.length] = 0;
    return pointer;
  }

  void free() {
    _Kernel32.localFree(pointer.cast<ffi.Void>());
  }
}

final class _Kernel32 {
  static final ffi.DynamicLibrary _library = ffi.DynamicLibrary.open(
    'kernel32.dll',
  );

  static final _MoveFileExWDart moveFileExW = _library
      .lookupFunction<_MoveFileExWNative, _MoveFileExWDart>('MoveFileExW');
  static final _GetLastErrorDart getLastError = _library
      .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');
  static final _LocalAllocDart localAlloc = _library
      .lookupFunction<_LocalAllocNative, _LocalAllocDart>('LocalAlloc');
  static final _LocalFreeDart localFree = _library
      .lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
}

typedef _MoveFileExWNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint16>,
      ffi.Pointer<ffi.Uint16>,
      ffi.Uint32,
    );
typedef _MoveFileExWDart =
    int Function(ffi.Pointer<ffi.Uint16>, ffi.Pointer<ffi.Uint16>, int);
typedef _GetLastErrorNative = ffi.Uint32 Function();
typedef _GetLastErrorDart = int Function();
typedef _LocalAllocNative =
    ffi.Pointer<ffi.Void> Function(ffi.Uint32, ffi.UintPtr);
typedef _LocalAllocDart = ffi.Pointer<ffi.Void> Function(int, int);
typedef _LocalFreeNative =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>);
typedef _LocalFreeDart = ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>);

class LegacyMayaChatMigrator {
  static const int maxLegacySourceBytes = 4 * 1024 * 1024;

  LegacyMayaChatMigrator({
    required this.database,
    required this.legacyFile,
    this.hooks = const LegacyMayaMigrationHooks(),
  });

  final YomuDatabase database;
  final File legacyFile;
  final LegacyMayaMigrationHooks hooks;

  Future<void> migrate() async {
    final markerRaw = await database.getMeta(kLegacyMayaMigrationMetaKey);
    final marker = markerRaw == null
        ? null
        : _MayaMigrationMarker.parse(markerRaw);
    final sourceExists = await _sourceExists();

    if (marker != null) {
      await _finishCommittedMigration(marker, sourceExists: sourceExists);
      return;
    }

    if (await _hasDeterministicArchive()) {
      throw const LegacyMayaMigrationException('legacy_archive_without_marker');
    }
    if (await _hasStagingArtifact()) {
      throw const LegacyMayaMigrationException('legacy_staging_without_marker');
    }

    if (!sourceExists) {
      final absent = _MayaMigrationMarker.absent();
      await database.importMayaSnapshot(
        messages: const [],
        proposals: const [],
        markerKey: kLegacyMayaMigrationMetaKey,
        markerValue: absent.encode(),
        afterRowsInsertedBeforeMarker: hooks.afterRowsInsertedBeforeMarker,
      );
      await _verifyCommitted(absent, const _ParsedMayaSource.empty());
      return;
    }

    final bytes = await _readSourceBytes();
    final fingerprint = sha256.convert(bytes).toString();
    final parsed = _parseSource(bytes);
    final markerForSource = _MayaMigrationMarker(
      state: parsed.isEmpty ? 'empty' : 'imported',
      fingerprint: fingerprint,
      archiveNonce: _secureNonce(),
    );

    await database.importMayaSnapshot(
      messages: parsed.messages,
      proposals: parsed.proposals,
      markerKey: kLegacyMayaMigrationMetaKey,
      markerValue: markerForSource.encode(),
      afterRowsInsertedBeforeMarker: hooks.afterRowsInsertedBeforeMarker,
    );
    await _verifyCommitted(markerForSource, parsed);
    await hooks.afterCommitBeforeArchive?.call();
    await _archiveIfUnchanged(markerForSource);
  }

  Future<void> _finishCommittedMigration(
    _MayaMigrationMarker originalMarker, {
    required bool sourceExists,
  }) async {
    var marker = originalMarker;
    final expected = marker.fingerprint;
    if (expected == null) {
      if (sourceExists || await _hasStagingArtifact()) {
        throw const LegacyMayaMigrationException(
          'legacy_source_appeared_after_absent_marker',
        );
      }
      return;
    }
    if (marker.archiveNonce == null) {
      final legacyCapture = await _findArchiveCapture(marker);
      if (legacyCapture != null) {
        final bytes = await _readBoundedBytes(
          legacyCapture,
          unreadableCode: 'legacy_archive_capture_unreadable',
        );
        if (sha256.convert(bytes).toString() != expected) {
          await _restoreCaptureWithoutReplace(legacyCapture, legacyFile, bytes);
          throw const LegacyMayaMigrationException(
            'legacy_source_changed_before_archive',
          );
        }
        final parsed = _parseSource(bytes);
        await _verifyCommitted(marker, parsed);
        await _finalizeLegacyArchiveCapture(marker, legacyCapture);
        return;
      }
      if (await _archiveFile(marker).exists()) {
        if (sourceExists) {
          throw const LegacyMayaMigrationException('legacy_archive_conflict');
        }
        return;
      }
      if (!sourceExists) return;
      marker = marker.withArchiveNonce(_secureNonce());
      await database.setMeta(kLegacyMayaMigrationMetaKey, marker.encode());
    }
    final capture = await _findArchiveCapture(marker);
    if (capture != null) {
      final bytes = await _readBoundedBytes(
        capture,
        unreadableCode: 'legacy_archive_capture_unreadable',
      );
      if (sha256.convert(bytes).toString() != expected) {
        await _restoreCaptureWithoutReplace(capture, legacyFile, bytes);
        throw const LegacyMayaMigrationException(
          'legacy_source_changed_before_archive',
        );
      }
      final parsed = _parseSource(bytes);
      await _verifyCommitted(marker, parsed);
      await _archiveIfUnchanged(marker);
      return;
    }
    if (!sourceExists) return;
    final bytes = await _readSourceBytes();
    final current = sha256.convert(bytes).toString();
    if (current != expected) {
      throw const LegacyMayaMigrationException(
        'legacy_source_changed_after_migration',
      );
    }
    final parsed = _parseSource(bytes);
    await _verifyCommitted(marker, parsed);
    await _archiveIfUnchanged(marker);
  }

  Future<bool> _sourceExists() async {
    try {
      return await legacyFile.exists();
    } catch (_) {
      throw const LegacyMayaMigrationException('legacy_source_unreadable');
    }
  }

  Future<bool> _hasDeterministicArchive() async {
    final parent = legacyFile.parent;
    try {
      if (!await parent.exists()) return false;
      final archivePattern = RegExp(
        '^${RegExp.escape(legacyFile.path)}'
        r'\.migrated-v1\.[0-9a-f]{64}(?:\.[0-9a-f]{32})?\.bak$',
      );
      await for (final entity in parent.list(followLinks: false)) {
        if (entity is File && archivePattern.hasMatch(entity.path)) return true;
      }
      return false;
    } catch (_) {
      throw const LegacyMayaMigrationException('legacy_archive_scan_failed');
    }
  }

  Future<bool> _hasStagingArtifact() async {
    final parent = legacyFile.parent;
    try {
      if (!await parent.exists()) return false;
      final artifactPattern = RegExp(
        '^${RegExp.escape(legacyFile.path)}'
        r'(?:'
        r'\.migrating-v1\.[0-9a-f]{64}'
        r'(?:\.[0-9a-f]{32}\.[0-9a-f]{32})?\.tmp'
        r'|\.clearing-v1\.[0-9a-f]{64}\.source\.[0-9a-f]{32}\.tmp'
        r'|\.migrated-v1\.[0-9a-f]{64}'
        r'(?:\.[0-9a-f]{32})?\.bak\.clearing\.[0-9a-f]{32}\.tmp'
        r')$',
      );
      await for (final entity in parent.list(followLinks: false)) {
        if (entity is File && artifactPattern.hasMatch(entity.path)) {
          return true;
        }
      }
      return false;
    } catch (_) {
      throw const LegacyMayaMigrationException('legacy_archive_scan_failed');
    }
  }

  Future<List<int>> _readSourceBytes() async {
    return _readBoundedBytes(
      legacyFile,
      unreadableCode: 'legacy_source_unreadable',
    );
  }

  Future<List<int>> _readBoundedBytes(
    File file, {
    required String unreadableCode,
  }) async {
    try {
      final bytes = await LegacyMayaFileOps.readBounded(file);
      if (bytes == null) {
        throw const LegacyMayaMigrationException('legacy_source_too_large');
      }
      return bytes;
    } on LegacyMayaMigrationException {
      rethrow;
    } catch (_) {
      throw LegacyMayaMigrationException(unreadableCode);
    }
  }

  _ParsedMayaSource _parseSource(List<int> bytes) {
    if (bytes.isEmpty) {
      throw const LegacyMayaMigrationException('legacy_source_zero_bytes');
    }
    final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      throw const LegacyMayaMigrationException('legacy_utf8_invalid');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const LegacyMayaMigrationException('legacy_json_invalid');
    }
    if (decoded is! Map) {
      throw const LegacyMayaMigrationException('legacy_root_not_object');
    }
    final Map<String, dynamic> root;
    try {
      root = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const LegacyMayaMigrationException('legacy_root_keys_invalid');
    }
    if (!_hasExactKeys(root, const {'messages', 'proposals'})) {
      throw const LegacyMayaMigrationException('legacy_root_fields_invalid');
    }
    final rawMessages = root['messages'];
    final rawProposals = root['proposals'];
    if (rawMessages is! List) {
      throw const LegacyMayaMigrationException('legacy_messages_not_list');
    }
    if (rawProposals is! List) {
      throw const LegacyMayaMigrationException('legacy_proposals_not_list');
    }

    try {
      return _parseRecords(rawMessages, rawProposals);
    } on FormatException catch (error) {
      throw LegacyMayaMigrationException(error.message);
    } catch (_) {
      throw const LegacyMayaMigrationException('legacy_record_invalid');
    }
  }

  _ParsedMayaSource _parseRecords(
    List<dynamic> rawMessages,
    List<dynamic> rawProposals,
  ) {
    final messages = <MayaMessage>[];
    final messageIds = <String>{};
    for (final raw in rawMessages) {
      if (raw is! Map) {
        throw const FormatException('legacy_message_not_object');
      }
      final message = _sanitizeLegacyExceptionMessage(
        MayaMessage.fromJson(Map<String, dynamic>.from(raw)),
      );
      if (!messageIds.add(message.id)) {
        throw const FormatException('legacy_message_id_duplicate');
      }
      messages.add(message);
    }

    final proposalsById = <String, ActionProposal>{};
    for (final raw in rawProposals) {
      if (raw is! Map) {
        throw const FormatException('legacy_proposal_not_object');
      }
      final proposalJson = Map<String, dynamic>.from(raw);
      final rawLegacyError = proposalJson['error'];
      final hadLegacyError = rawLegacyError != null;
      if (hadLegacyError) {
        if (rawLegacyError is! String) {
          throw const FormatException('proposal_error_invalid');
        }
        // Legacy Yomu persisted raw exception strings with no length bound.
        // Replace them before strict domain validation so valid old output can
        // migrate without retaining or exposing sensitive diagnostics.
        proposalJson['error'] = 'Falha registrada no histórico legado.';
      }
      var proposal = ActionProposal.fromJson(proposalJson);
      if (proposalsById.containsKey(proposal.id)) {
        throw const FormatException('legacy_proposal_id_duplicate');
      }
      // The legacy service dispatched mutating ports before saving JSON. A
      // residual `pending` row may therefore represent an already-applied
      // effect after a crash; quarantine it behind the durable barrier.
      if (proposal.status == ActionProposalStatus.pending &&
          _legacyPendingMayHaveDispatched(proposal.kind)) {
        proposal = proposal.copyWith(
          status: ActionProposalStatus.confirmed,
          error: kMayaLegacyPendingOutcomeUncertainError,
        );
      } else if (hadLegacyError) {
        proposal = proposal.copyWith(
          error: proposal.status == ActionProposalStatus.confirmed
              ? 'Resultado não verificado após migração.'
              : 'Falha registrada no histórico legado.',
        );
      } else if (proposal.status == ActionProposalStatus.confirmed) {
        proposal = proposal.copyWith(
          error: 'Resultado não verificado após migração.',
        );
      }
      proposalsById[proposal.id] = proposal;
    }

    final ownerByProposal = <String, ({String messageId, int order})>{};
    for (final message in messages) {
      if (message.proposalIds.isNotEmpty &&
          message.role != MayaRole.assistant) {
        throw const FormatException('legacy_proposal_owner_role_invalid');
      }
      for (var order = 0; order < message.proposalIds.length; order++) {
        final proposalId = message.proposalIds[order];
        if (!proposalsById.containsKey(proposalId)) {
          throw const FormatException('legacy_proposal_reference_missing');
        }
        if (ownerByProposal.containsKey(proposalId)) {
          throw const FormatException('legacy_proposal_reference_duplicate');
        }
        ownerByProposal[proposalId] = (messageId: message.id, order: order);
      }
    }
    if (ownerByProposal.length != proposalsById.length) {
      throw const FormatException('legacy_proposal_unreferenced');
    }

    final newMessages = messages
        .map(
          (message) => NewMayaMessage(
            messageId: message.id,
            role: message.role.name,
            text: message.text,
            createdAtMs: message.createdAt.millisecondsSinceEpoch,
          ),
        )
        .toList(growable: false);
    final newProposals = <NewMayaProposal>[];
    for (final proposal in proposalsById.values) {
      final owner = ownerByProposal[proposal.id]!;
      newProposals.add(
        NewMayaProposal(
          proposalId: proposal.id,
          messageId: owner.messageId,
          proposalOrder: owner.order,
          kind: proposal.kind.name,
          title: proposal.title,
          description: proposal.description,
          payloadJson: jsonEncode(proposal.payload),
          status: proposal.status.name,
          createdAtMs: proposal.createdAt.millisecondsSinceEpoch,
          confirmedAtMs: _requiresConfirmationTimestamp(proposal.status)
              ? proposal.createdAt.millisecondsSinceEpoch
              : null,
          completedAtMs: _isTerminal(proposal.status)
              ? proposal.createdAt.millisecondsSinceEpoch
              : null,
          error: proposal.error,
        ),
      );
    }
    return _ParsedMayaSource(messages: newMessages, proposals: newProposals);
  }

  Future<void> _verifyCommitted(
    _MayaMigrationMarker expected,
    _ParsedMayaSource parsed,
  ) async {
    final markerRaw = await database.getMeta(kLegacyMayaMigrationMetaKey);
    final marker = markerRaw == null
        ? null
        : _MayaMigrationMarker.parse(markerRaw);
    if (marker == null || !marker.semanticallyEquals(expected)) {
      throw StateError('Maya migration marker readback failed');
    }
    final stateMatches = expected.state == 'absent'
        ? expected.fingerprint == null && parsed.isEmpty
        : expected.fingerprint != null &&
              expected.state == (parsed.isEmpty ? 'empty' : 'imported');
    if (!stateMatches) {
      throw StateError('Maya migration marker state mismatch');
    }
    final snapshot = await database.loadMayaSnapshot();
    if (snapshot.messages.length != parsed.messages.length ||
        snapshot.proposals.length != parsed.proposals.length) {
      throw StateError('Maya migration readback failed');
    }
    for (var index = 0; index < parsed.messages.length; index++) {
      final expectedMessage = parsed.messages[index];
      final actual = snapshot.messages[index];
      if (actual.messageId != expectedMessage.messageId ||
          actual.sortOrder != index ||
          actual.role != expectedMessage.role ||
          actual.content != expectedMessage.text ||
          actual.createdAtMs != expectedMessage.createdAtMs) {
        throw StateError('Maya migration message readback failed');
      }
    }
    final actualProposals = <String, StoredMayaProposal>{
      for (final proposal in snapshot.proposals) proposal.proposalId: proposal,
    };
    for (final expectedProposal in parsed.proposals) {
      final actual = actualProposals[expectedProposal.proposalId];
      if (actual == null ||
          actual.messageId != expectedProposal.messageId ||
          actual.proposalOrder != expectedProposal.proposalOrder ||
          actual.kind != expectedProposal.kind ||
          actual.title != expectedProposal.title ||
          actual.description != expectedProposal.description ||
          actual.payloadJson != expectedProposal.payloadJson ||
          actual.status != expectedProposal.status ||
          actual.createdAtMs != expectedProposal.createdAtMs ||
          actual.confirmedAtMs != expectedProposal.confirmedAtMs ||
          actual.completedAtMs != expectedProposal.completedAtMs ||
          actual.error != expectedProposal.error) {
        throw StateError('Maya migration proposal readback failed');
      }
    }
  }

  Future<void> _archiveIfUnchanged(_MayaMigrationMarker marker) async {
    final expectedFingerprint = marker.fingerprint!;
    final archive = _archiveFile(marker);
    var capture = await _findArchiveCapture(marker);
    var capturedNow = false;
    try {
      if (await archive.exists()) {
        throw const LegacyMayaMigrationException('legacy_archive_conflict');
      }
      if (capture == null) {
        if (!await _sourceExists()) return;
        capture = _newArchiveCaptureFile(marker);
        final result = LegacyMayaFileOps.moveNoReplaceSync(
          source: legacyFile,
          destination: capture,
        );
        if (result == LegacyMayaMoveNoReplaceResult.destinationExists) {
          throw const LegacyMayaMigrationException(
            'legacy_archive_capture_conflict',
          );
        }
        capturedNow = true;
      }
    } on LegacyMayaMigrationException {
      rethrow;
    } catch (_) {
      throw const LegacyMayaMigrationException('legacy_archive_failed');
    }
    if (capturedNow) {
      await hooks.afterArchiveSourceCapturedBeforeVerify?.call();
    }

    final current = sha256
        .convert(
          await _readBoundedBytes(
            capture,
            unreadableCode: 'legacy_archive_capture_unreadable',
          ),
        )
        .toString();
    if (current != expectedFingerprint) {
      final bytes = await _readBoundedBytes(
        capture,
        unreadableCode: 'legacy_archive_capture_unreadable',
      );
      await _restoreCaptureWithoutReplace(capture, legacyFile, bytes);
      throw const LegacyMayaMigrationException(
        'legacy_source_changed_before_archive',
      );
    }

    await hooks.beforeArchiveCapturePublished?.call();
    try {
      final result = LegacyMayaFileOps.moveNoReplaceSync(
        source: capture,
        destination: archive,
      );
      if (result == LegacyMayaMoveNoReplaceResult.destinationExists) {
        throw const LegacyMayaMigrationException('legacy_archive_conflict');
      }
    } on LegacyMayaMigrationException {
      rethrow;
    } catch (_) {
      throw const LegacyMayaMigrationException('legacy_archive_failed');
    }
    if (await _sourceExists()) {
      throw const LegacyMayaMigrationException(
        'legacy_source_reappeared_during_archive',
      );
    }
  }

  File _archiveFile(_MayaMigrationMarker marker) {
    final nonce = marker.archiveNonce;
    return File(
      nonce == null
          ? '${legacyFile.path}.migrated-v1.${marker.fingerprint}.bak'
          : '${legacyFile.path}.migrated-v1.${marker.fingerprint}.$nonce.bak',
    );
  }

  File _newArchiveCaptureFile(_MayaMigrationMarker marker) => File(
    '${legacyFile.path}.migrating-v1.${marker.fingerprint}.'
    '${marker.archiveNonce}.${_secureNonce()}.tmp',
  );

  Future<File?> _findArchiveCapture(_MayaMigrationMarker marker) async {
    final nonce = marker.archiveNonce;
    final pattern = RegExp(
      nonce == null
          ? '^${RegExp.escape(legacyFile.path)}'
                r'\.migrating-v1\.'
                '${marker.fingerprint}'
                r'\.tmp$'
          : '^${RegExp.escape(legacyFile.path)}'
                r'\.migrating-v1\.'
                '${marker.fingerprint}\\.$nonce'
                r'\.[0-9a-f]{32}\.tmp$',
    );
    File? found;
    try {
      await for (final entity in legacyFile.parent.list(followLinks: false)) {
        if (entity is! File || !pattern.hasMatch(entity.path)) continue;
        if (found != null) {
          throw const LegacyMayaMigrationException(
            'legacy_archive_capture_conflict',
          );
        }
        found = entity;
      }
      return found;
    } on LegacyMayaMigrationException {
      rethrow;
    } catch (_) {
      throw const LegacyMayaMigrationException('legacy_archive_scan_failed');
    }
  }

  Future<void> _finalizeLegacyArchiveCapture(
    _MayaMigrationMarker marker,
    File capture,
  ) async {
    final archive = _archiveFile(marker);
    final expected = marker.fingerprint!;
    if (await archive.exists()) {
      try {
        final archived = sha256
            .convert(
              await _readBoundedBytes(
                archive,
                unreadableCode: 'legacy_archive_unreadable',
              ),
            )
            .toString();
        if (archived != expected) {
          throw const LegacyMayaMigrationException('legacy_archive_conflict');
        }
        await capture.delete();
      } on LegacyMayaMigrationException {
        rethrow;
      } catch (_) {
        throw const LegacyMayaMigrationException('legacy_archive_failed');
      }
    } else {
      await hooks.beforeArchiveCapturePublished?.call();
      try {
        final result = LegacyMayaFileOps.moveNoReplaceSync(
          source: capture,
          destination: archive,
        );
        if (result == LegacyMayaMoveNoReplaceResult.destinationExists) {
          throw const LegacyMayaMigrationException('legacy_archive_conflict');
        }
      } on LegacyMayaMigrationException {
        rethrow;
      } catch (_) {
        throw const LegacyMayaMigrationException('legacy_archive_failed');
      }
    }
    if (await _sourceExists()) {
      throw const LegacyMayaMigrationException(
        'legacy_source_reappeared_during_archive',
      );
    }
  }
}

Future<void> _restoreCaptureWithoutReplace(
  File capture,
  File destination,
  List<int> bytes,
) async {
  final expected = sha256.convert(bytes).toString();
  try {
    if (await destination.exists()) {
      final currentBytes = await LegacyMayaFileOps.readBounded(destination);
      if (currentBytes != null &&
          sha256.convert(currentBytes).toString() == expected) {
        await capture.delete();
      }
      return;
    }
    final result = LegacyMayaFileOps.moveNoReplaceSync(
      source: capture,
      destination: destination,
    );
    if (result == LegacyMayaMoveNoReplaceResult.destinationExists) {
      final currentBytes = await LegacyMayaFileOps.readBounded(destination);
      if (currentBytes != null &&
          sha256.convert(currentBytes).toString() == expected) {
        await capture.delete();
      }
    }
  } catch (_) {
    // The capture remains authoritative when no-replace restoration cannot be
    // proven. Never overwrite a path that may have reappeared concurrently.
  }
}

String _secureNonce() {
  final random = Random.secure();
  return List<String>.generate(
    4,
    (_) => random.nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
  ).join();
}

bool _isTerminal(ActionProposalStatus status) {
  return status == ActionProposalStatus.rejected ||
      status == ActionProposalStatus.executed ||
      status == ActionProposalStatus.failed;
}

bool _requiresConfirmationTimestamp(ActionProposalStatus status) {
  return status == ActionProposalStatus.confirmed ||
      status == ActionProposalStatus.executed ||
      status == ActionProposalStatus.failed;
}

bool _legacyPendingMayHaveDispatched(MayaActionKind kind) {
  return switch (kind) {
    MayaActionKind.openManga => false,
    MayaActionKind.downloadChapter || MayaActionKind.setInLibrary => true,
  };
}

MayaMessage _sanitizeLegacyExceptionMessage(MayaMessage message) {
  if (message.role != MayaRole.assistant) return message;
  final replacement = switch (message.id) {
    final id when id.startsWith('m-err-') =>
      'Não foi possível consultar a biblioteca naquele momento.',
    final id when id.startsWith('m-fail-') =>
      'Uma ação da Maya falhou naquele momento.',
    _ => null,
  };
  if (replacement == null) return message;
  return MayaMessage(
    id: message.id,
    role: message.role,
    text: replacement,
    createdAt: message.createdAt,
    proposalIds: message.proposalIds,
  );
}

bool _hasExactKeys(Map<String, dynamic> map, Set<String> expected) {
  return map.length == expected.length && expected.every(map.containsKey);
}

class _ParsedMayaSource {
  const _ParsedMayaSource({required this.messages, required this.proposals});

  const _ParsedMayaSource.empty() : messages = const [], proposals = const [];

  final List<NewMayaMessage> messages;
  final List<NewMayaProposal> proposals;

  bool get isEmpty => messages.isEmpty && proposals.isEmpty;
}

class _MayaMigrationMarker {
  const _MayaMigrationMarker({
    required this.state,
    required this.fingerprint,
    required this.archiveNonce,
  });

  factory _MayaMigrationMarker.absent() {
    return const _MayaMigrationMarker(
      state: 'absent',
      fingerprint: null,
      archiveNonce: null,
    );
  }

  factory _MayaMigrationMarker.parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != 1) {
        throw const FormatException();
      }
      final state = decoded['state'];
      final fingerprint = decoded['fingerprint'];
      final archiveNonce = decoded['archiveNonce'];
      if (state is! String ||
          !const {'absent', 'empty', 'imported'}.contains(state) ||
          (fingerprint != null &&
              (fingerprint is! String ||
                  !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint))) ||
          (archiveNonce != null &&
              (archiveNonce is! String ||
                  !RegExp(r'^[0-9a-f]{32}$').hasMatch(archiveNonce)))) {
        throw const FormatException();
      }
      if ((state == 'absent') != (fingerprint == null) ||
          (state == 'absent' && archiveNonce != null)) {
        throw const FormatException();
      }
      return _MayaMigrationMarker(
        state: state,
        fingerprint: fingerprint as String?,
        archiveNonce: archiveNonce as String?,
      );
    } catch (_) {
      throw StateError('Invalid Maya migration marker');
    }
  }

  final String state;
  final String? fingerprint;
  final String? archiveNonce;

  _MayaMigrationMarker withArchiveNonce(String value) => _MayaMigrationMarker(
    state: state,
    fingerprint: fingerprint,
    archiveNonce: value,
  );

  bool semanticallyEquals(_MayaMigrationMarker other) {
    return state == other.state &&
        fingerprint == other.fingerprint &&
        archiveNonce == other.archiveNonce;
  }

  String encode() => jsonEncode({
    'version': 1,
    'state': state,
    'fingerprint': fingerprint,
    if (archiveNonce != null) 'archiveNonce': archiveNonce,
  });
}
