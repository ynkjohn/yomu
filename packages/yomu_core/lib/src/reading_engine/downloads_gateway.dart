import 'dart:async';

import 'package:collection/collection.dart';

enum DownloadManagerState { running, paused }

enum DownloadItemState { queued, downloading, completed, failed }

final class EngineDownloadItem {
  const EngineDownloadItem({
    required this.state,
    this.chapterId,
    this.chapterName,
    this.mangaId,
    this.mangaTitle,
    this.progress,
  });

  final DownloadItemState state;
  final int? chapterId;
  final String? chapterName;
  final int? mangaId;
  final String? mangaTitle;
  final double? progress;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EngineDownloadItem &&
          state == other.state &&
          chapterId == other.chapterId &&
          chapterName == other.chapterName &&
          mangaId == other.mangaId &&
          mangaTitle == other.mangaTitle &&
          progress == other.progress;

  @override
  int get hashCode =>
      Object.hash(state, chapterId, chapterName, mangaId, mangaTitle, progress);
}

final class DownloadsSnapshot {
  DownloadsSnapshot({
    required this.managerState,
    required List<EngineDownloadItem> queue,
  }) : queue = List<EngineDownloadItem>.unmodifiable(queue);

  final DownloadManagerState managerState;
  final List<EngineDownloadItem> queue;

  int get activeCount =>
      queue.where((item) => item.state == DownloadItemState.downloading).length;

  bool get hasQueuedItems => queue.isNotEmpty;

  bool get hasActivity => queue.any(
    (item) =>
        item.state == DownloadItemState.queued ||
        item.state == DownloadItemState.downloading,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadsSnapshot &&
          managerState == other.managerState &&
          const ListEquality<EngineDownloadItem>().equals(queue, other.queue);

  @override
  int get hashCode => Object.hash(
    managerState,
    const ListEquality<EngineDownloadItem>().hash(queue),
  );
}

final class DownloadPauseAck {
  const DownloadPauseAck({
    required this.managerState,
    required this.acknowledged,
  });

  final DownloadManagerState managerState;
  final bool acknowledged;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadPauseAck &&
          managerState == other.managerState &&
          acknowledged == other.acknowledged;

  @override
  int get hashCode => Object.hash(managerState, acknowledged);
}

abstract interface class DownloadsGateway {
  Future<DownloadsSnapshot> getStatus();

  Future<void> enqueueChapters(List<int> chapterIds);

  Future<void> dequeueChapters(List<int> chapterIds);

  Future<DownloadPauseAck> pause();

  Future<void> resume();

  Future<void> clear();

  Future<bool> hasActivity();

  Future<DownloadPauseAck> pauseAndAwaitAck({required Duration timeout});
}
