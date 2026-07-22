import 'reading_models.dart';

abstract interface class ReadingProgressGateway {
  Future<ReadingProgressSnapshot> updateProgress({
    required int chapterId,
    required int lastPageRead,
    required bool isRead,
  });
}

/// Narrow capability for requests admitted before coordinated shutdown.
///
/// The HTTP admission gate must reject every request that arrives after the
/// shutdown boundary; this method only preserves work already admitted.
abstract interface class AdmittedReadingProgressGateway
    implements ReadingProgressGateway {
  Future<ReadingProgressSnapshot> updateAdmittedProgress({
    required int chapterId,
    required int lastPageRead,
    required bool isRead,
  });
}
