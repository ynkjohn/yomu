import 'reading_models.dart';

abstract interface class ReadingProgressGateway {
  Future<ReadingProgressSnapshot> updateProgress({
    required int chapterId,
    required int lastPageRead,
    required bool isRead,
  });
}
