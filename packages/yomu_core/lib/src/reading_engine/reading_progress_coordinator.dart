import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'engine_mutation_gate.dart';
import 'engine_readiness.dart';
import 'reading_models.dart';
import 'reading_progress_gateway.dart';

enum ReadingProgressDrainResult { drained, timedOut }

typedef ReadingProgressSnapshotProvider = ReadingProgressSnapshot? Function();

final class ReadingProgressSessionHandle {
  const ReadingProgressSessionHandle._(this.id);

  final int id;
}

/// Serializes and coalesces progress writes across desktop and Yomu Core.
///
/// Page positions remain 0-based. Newer writes for a chapter dominate stale
/// responses and failures, while chapter transitions preserve FIFO order.
final class ReadingProgressCoordinator
    implements ReadingProgressGateway, AdmittedReadingProgressGateway {
  ReadingProgressCoordinator(this._upstream);

  final ReadingProgressGateway _upstream;
  final ListQueue<int> _pendingOrder = ListQueue<int>();
  final Map<int, _ChapterProgressState> _states = {};
  final Map<int, ReadingProgressSnapshot> _highWaterByChapter = {};
  final Map<int, ReadingProgressSnapshotProvider> _finalSnapshotProviders = {};
  Future<void>? _draining;
  Completer<void>? _idleCompleter;
  bool _accepting = true;
  bool _finalSavesAllowed = true;
  bool _admittedWritesAllowed = true;
  int _nextSessionId = 0;

  bool get isAccepting => _accepting;
  bool get hasPendingWrites => _draining != null || _pendingOrder.isNotEmpty;

  @override
  Future<ReadingProgressSnapshot> updateProgress({
    required int chapterId,
    required int lastPageRead,
    required bool isRead,
  }) => _enqueue(
    chapterId: chapterId,
    lastPageRead: lastPageRead,
    isRead: isRead,
    admission: _ProgressAdmission.normal,
  );

  @override
  Future<ReadingProgressSnapshot> updateAdmittedProgress({
    required int chapterId,
    required int lastPageRead,
    required bool isRead,
  }) => _enqueue(
    chapterId: chapterId,
    lastPageRead: lastPageRead,
    isRead: isRead,
    admission: _ProgressAdmission.admittedRequest,
  );

  Future<ReadingProgressSnapshot> saveFinal({
    required int chapterId,
    required int lastPageRead,
    required bool isRead,
  }) => _enqueue(
    chapterId: chapterId,
    lastPageRead: lastPageRead,
    isRead: isRead,
    admission: _ProgressAdmission.finalSnapshot,
  );

  Future<ReadingProgressSnapshot> _enqueue({
    required int chapterId,
    required int lastPageRead,
    required bool isRead,
    required _ProgressAdmission admission,
  }) {
    final allowedAfterStop = switch (admission) {
      _ProgressAdmission.normal => false,
      _ProgressAdmission.finalSnapshot => _finalSavesAllowed,
      _ProgressAdmission.admittedRequest => _admittedWritesAllowed,
    };
    if (!_accepting && !allowedAfterStop) {
      return Future<ReadingProgressSnapshot>.error(
        engineMutationsBlockedException,
      );
    }
    if (chapterId < 0 || lastPageRead < 0) {
      return Future<ReadingProgressSnapshot>.error(
        const EngineException(
          EngineFailure(
            kind: EngineFailureKind.operationRejected,
            code: 'engine_progress_invalid',
            message: 'O progresso informado não é válido.',
            retryable: false,
          ),
        ),
      );
    }

    final requested = ReadingProgressSnapshot(
      chapterId: chapterId,
      lastPageRead: lastPageRead,
      isRead: isRead,
    );
    final highWater = _merge(_highWaterByChapter[chapterId], requested);
    _highWaterByChapter[chapterId] = highWater;

    final state = _states.putIfAbsent(
      chapterId,
      () => _ChapterProgressState(highWater),
    );
    state
      ..desired = _merge(state.desired, highWater)
      ..version += 1;
    final waiter = Completer<ReadingProgressSnapshot>();
    state.waiters.add(waiter);
    if (!state.queued && !state.inFlight) {
      state.queued = true;
      _pendingOrder.addLast(chapterId);
    }
    _idleCompleter ??= Completer<void>();
    _draining ??= _drain();
    return waiter.future;
  }

  void stopAccepting() {
    _accepting = false;
  }

  ReadingProgressSessionHandle registerFinalSnapshotProvider(
    ReadingProgressSnapshotProvider provider,
  ) {
    final handle = ReadingProgressSessionHandle._(++_nextSessionId);
    _finalSnapshotProviders[handle.id] = provider;
    return handle;
  }

  void unregisterFinalSnapshotProvider(ReadingProgressSessionHandle handle) {
    _finalSnapshotProviders.remove(handle.id);
  }

  /// Flushes final snapshots for reader sessions admitted before shutdown.
  Future<void> flushRegisteredFinalSaves() async {
    final providers = List<ReadingProgressSnapshotProvider>.from(
      _finalSnapshotProviders.values,
    );
    for (final provider in providers) {
      try {
        final snapshot = provider();
        if (snapshot == null) continue;
        final save = saveFinal(
          chapterId: snapshot.chapterId,
          lastPageRead: snapshot.lastPageRead,
          isRead: snapshot.isRead,
        );
        // Admission is synchronous. Completion belongs to the single bounded
        // drain that follows this step in coordinated shutdown.
        unawaited(
          save.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
        );
      } catch (_) {
        // A disposed or inconsistent UI session cannot block other final saves.
      }
    }
  }

  /// Rejects every later progress mutation, including widget disposal saves.
  void sealFinalSaves() {
    _finalSavesAllowed = false;
  }

  /// Rejects API mutations whose admitted request exceeded the request drain.
  void sealAdmittedWrites() {
    _admittedWritesAllowed = false;
  }

  Future<ReadingProgressDrainResult> drain({required Duration timeout}) async {
    if (!hasPendingWrites) return ReadingProgressDrainResult.drained;
    if (timeout <= Duration.zero) return ReadingProgressDrainResult.timedOut;
    final idle = _idleCompleter?.future;
    if (idle == null) return ReadingProgressDrainResult.drained;
    try {
      await idle.timeout(timeout);
      return ReadingProgressDrainResult.drained;
    } on TimeoutException {
      return ReadingProgressDrainResult.timedOut;
    }
  }

  Future<void> _drain() async {
    try {
      while (_pendingOrder.isNotEmpty) {
        final chapterId = _pendingOrder.removeFirst();
        final state = _states[chapterId];
        if (state == null) continue;
        state
          ..queued = false
          ..inFlight = true;
        final requested = state.desired;
        final version = state.version;
        ReadingProgressSnapshot? response;
        Object? failure;
        StackTrace? failureStack;
        try {
          response = await _upstream.updateProgress(
            chapterId: requested.chapterId,
            lastPageRead: requested.lastPageRead,
            isRead: requested.isRead,
          );
          if (response.chapterId != chapterId) {
            throw const EngineException(
              EngineFailure(
                kind: EngineFailureKind.incompatible,
                code: 'engine_progress_response_invalid',
                message: 'O motor retornou um progresso incompatível.',
                retryable: false,
              ),
            );
          }
        } catch (error, stackTrace) {
          failure = error;
          failureStack = stackTrace;
        }
        state.inFlight = false;

        if (state.version != version) {
          if (!state.queued) {
            state.queued = true;
            _pendingOrder.addLast(chapterId);
          }
          continue;
        }

        _states.remove(chapterId);
        final waiters = List<Completer<ReadingProgressSnapshot>>.from(
          state.waiters,
        );
        if (failure != null) {
          for (final waiter in waiters) {
            if (!waiter.isCompleted) {
              waiter.completeError(failure, failureStack);
            }
          }
          continue;
        }

        final stable = _merge(requested, response!);
        _highWaterByChapter[chapterId] = _merge(
          _highWaterByChapter[chapterId],
          stable,
        );
        for (final waiter in waiters) {
          if (!waiter.isCompleted) waiter.complete(stable);
        }
      }
    } finally {
      _draining = null;
      if (_pendingOrder.isNotEmpty) {
        _draining = _drain();
      } else {
        final idle = _idleCompleter;
        _idleCompleter = null;
        if (idle != null && !idle.isCompleted) idle.complete();
      }
    }
  }

  static ReadingProgressSnapshot _merge(
    ReadingProgressSnapshot? current,
    ReadingProgressSnapshot newer,
  ) {
    if (current == null) return newer;
    return ReadingProgressSnapshot(
      chapterId: newer.chapterId,
      lastPageRead: math.max(current.lastPageRead, newer.lastPageRead),
      isRead: current.isRead || newer.isRead,
    );
  }
}

enum _ProgressAdmission { normal, finalSnapshot, admittedRequest }

final class _ChapterProgressState {
  _ChapterProgressState(this.desired);

  ReadingProgressSnapshot desired;
  int version = 0;
  bool queued = false;
  bool inFlight = false;
  final List<Completer<ReadingProgressSnapshot>> waiters = [];
}
