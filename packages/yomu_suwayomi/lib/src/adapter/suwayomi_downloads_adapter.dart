import 'dart:async';

import 'package:yomu_core/yomu_core.dart';

import '../client/suwayomi_api.dart';
import '../client/suwayomi_models.dart';

/// Normalizes downloader protocol state before it reaches Yomu consumers.
final class SuwayomiDownloadsAdapter implements DownloadsGateway {
  SuwayomiDownloadsAdapter(this._api);

  final SuwayomiApi _api;

  @override
  Future<DownloadsSnapshot> getStatus() => _guard(
    code: 'engine_downloads_unavailable',
    message: 'Não foi possível carregar os downloads.',
    operation: () async => _mapSnapshot(await _api.getDownloadStatus()),
  );

  @override
  Future<void> enqueueChapters(List<int> chapterIds) => _guard(
    code: 'engine_download_enqueue_failed',
    message: 'Não foi possível enfileirar os capítulos.',
    operation: () => _api.enqueueChapterDownloads(chapterIds),
  );

  @override
  Future<void> dequeueChapters(List<int> chapterIds) => _guard(
    code: 'engine_download_dequeue_failed',
    message: 'Não foi possível remover os capítulos da fila.',
    operation: () => _api.dequeueChapterDownloads(chapterIds),
  );

  @override
  Future<DownloadPauseAck> pause() => _guard(
    code: 'engine_download_pause_failed',
    message: 'Não foi possível pausar os downloads.',
    operation: () async {
      await _api.stopDownloader();
      final state = _managerState((await _api.getDownloadStatus()).state);
      return DownloadPauseAck(
        managerState: state,
        acknowledged: state == DownloadManagerState.paused,
      );
    },
  );

  @override
  Future<void> resume() => _guard(
    code: 'engine_download_resume_failed',
    message: 'Não foi possível retomar os downloads.',
    operation: _api.startDownloader,
  );

  @override
  Future<void> clear() => _guard(
    code: 'engine_download_clear_failed',
    message: 'Não foi possível limpar a fila de downloads.',
    operation: _api.clearDownloader,
  );

  @override
  Future<bool> hasActivity() async => (await getStatus()).hasActivity;

  @override
  Future<DownloadPauseAck> pauseAndAwaitAck({required Duration timeout}) async {
    if (timeout <= Duration.zero) throw _pauseTimeout;
    final stopwatch = Stopwatch()..start();
    try {
      await _guard<void>(
        code: 'engine_download_pause_failed',
        message: 'Não foi possível pausar os downloads.',
        operation: _api.stopDownloader,
      ).timeout(timeout);
      while (stopwatch.elapsed < timeout) {
        final remaining = timeout - stopwatch.elapsed;
        final state = await getStatus().timeout(remaining);
        if (state.managerState == DownloadManagerState.paused) {
          return const DownloadPauseAck(
            managerState: DownloadManagerState.paused,
            acknowledged: true,
          );
        }
        final afterRequest = timeout - stopwatch.elapsed;
        if (afterRequest <= Duration.zero) break;
        await Future<void>.delayed(
          afterRequest < const Duration(milliseconds: 100)
              ? afterRequest
              : const Duration(milliseconds: 100),
        );
      }
      throw _pauseTimeout;
    } on TimeoutException {
      throw _pauseTimeout;
    } finally {
      stopwatch.stop();
    }
  }

  DownloadsSnapshot _mapSnapshot(DownloadStatusInfo upstream) {
    return DownloadsSnapshot(
      managerState: _managerState(upstream.state),
      queue: upstream.queue.map(_mapItem).toList(growable: false),
    );
  }

  EngineDownloadItem _mapItem(DownloadQueueItem upstream) {
    final progress = upstream.progress;
    if (progress != null &&
        (!progress.isFinite || progress < 0 || progress > 1)) {
      throw _unsupportedState;
    }
    return EngineDownloadItem(
      state: _itemState(upstream.state),
      progress: progress,
      chapterId: upstream.chapter?.id,
      chapterName: upstream.chapter?.name,
      mangaId: upstream.manga?.id ?? upstream.chapter?.mangaId,
      mangaTitle: upstream.manga?.title,
    );
  }

  static DownloadManagerState _managerState(String upstream) {
    return switch (upstream.trim().toUpperCase()) {
      'STARTED' => DownloadManagerState.running,
      'STOPPED' => DownloadManagerState.paused,
      _ => throw _unsupportedState,
    };
  }

  static DownloadItemState _itemState(String upstream) {
    return switch (upstream.trim().toUpperCase()) {
      'QUEUED' => DownloadItemState.queued,
      'DOWNLOADING' => DownloadItemState.downloading,
      'COMPLETED' || 'COMPLETE' || 'FINISHED' => DownloadItemState.completed,
      'ERROR' || 'FAILED' => DownloadItemState.failed,
      _ => throw _unsupportedState,
    };
  }

  Future<T> _guard<T>({
    required String code,
    required String message,
    required Future<T> Function() operation,
  }) async {
    try {
      return await operation();
    } on EngineException {
      rethrow;
    } catch (_) {
      throw EngineException(
        EngineFailure(
          kind: EngineFailureKind.temporarilyUnavailable,
          code: code,
          message: message,
          retryable: true,
        ),
      );
    }
  }
}

const _unsupportedState = EngineException(
  EngineFailure(
    kind: EngineFailureKind.incompatible,
    code: 'engine_download_state_unsupported',
    message: 'O motor retornou um estado de download incompatível.',
    retryable: false,
  ),
);

const _pauseTimeout = EngineException(
  EngineFailure(
    kind: EngineFailureKind.temporarilyUnavailable,
    code: 'engine_download_pause_timeout',
    message: 'O motor não confirmou a pausa dos downloads a tempo.',
    retryable: true,
  ),
);
