import '../entities/personal_status.dart';

/// Dual-layer personal status rules.
///
/// - Suwayomi holds factual chapter read state.
/// - Yomu holds user intention ([PersonalStatus]), optionally as manual override.
/// - Conflicts are always visible; never silently rewrite Suwayomi progress.
class PersonalStatusView {
  const PersonalStatusView({
    required this.effective,
    required this.isManualOverride,
    required this.suggested,
    required this.hasUnreadChapters,
    required this.conflictWithCompleted,
  });

  /// Status to show as primary badge.
  final PersonalStatus effective;

  /// True when the user (or confirmed Maya action) set a Yomu override.
  final bool isManualOverride;

  /// Status derived from Suwayomi facts (never auto-persisted).
  final PersonalStatus? suggested;

  /// Factual unread chapters in Suwayomi.
  final bool hasUnreadChapters;

  /// Override is [PersonalStatus.completed] but Suwayomi still has unread caps.
  final bool conflictWithCompleted;

  String? get conflictMessage {
    if (!conflictWithCompleted) return null;
    return 'Status "Concluído" no Yomu, mas ainda há capítulos não lidos no motor.';
  }
}

class PersonalStatusReconciliation {
  const PersonalStatusReconciliation();

  /// Derive a suggested status from Suwayomi facts. Does not write anything.
  PersonalStatus? suggest({
    required bool inLibrary,
    required int readChapterCount,
    required int totalChapterCount,
    required bool hasUnreadChapters,
  }) {
    if (!inLibrary) return null;
    if (totalChapterCount > 0 &&
        readChapterCount >= totalChapterCount &&
        !hasUnreadChapters) {
      return PersonalStatus.completed;
    }
    if (readChapterCount > 0 || hasUnreadChapters == false && readChapterCount > 0) {
      return PersonalStatus.reading;
    }
    if (readChapterCount > 0) return PersonalStatus.reading;
    return PersonalStatus.wantToRead;
  }

  /// Merge manual override (Yomu) with factual suggestion (Suwayomi).
  PersonalStatusView resolve({
    PersonalStatus? manualOverride,
    required PersonalStatus? suggested,
    required bool hasUnreadChapters,
  }) {
    if (manualOverride != null) {
      final conflict = manualOverride == PersonalStatus.completed &&
          hasUnreadChapters;
      return PersonalStatusView(
        effective: manualOverride,
        isManualOverride: true,
        suggested: suggested,
        hasUnreadChapters: hasUnreadChapters,
        conflictWithCompleted: conflict,
      );
    }

    final effective = suggested ?? PersonalStatus.wantToRead;
    return PersonalStatusView(
      effective: effective,
      isManualOverride: false,
      suggested: suggested,
      hasUnreadChapters: hasUnreadChapters,
      conflictWithCompleted: false,
    );
  }
}
