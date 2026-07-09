import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';

void main() {
  const recon = PersonalStatusReconciliation();

  test('completed override with unread chapters surfaces conflict', () {
    final view = recon.resolve(
      manualOverride: PersonalStatus.completed,
      suggested: PersonalStatus.reading,
      hasUnreadChapters: true,
    );
    expect(view.conflictWithCompleted, isTrue);
    expect(view.conflictMessage, isNotNull);
    expect(view.effective, PersonalStatus.completed);
    expect(view.isManualOverride, isTrue);
  });

  test('without override uses suggestion', () {
    final view = recon.resolve(
      suggested: PersonalStatus.reading,
      hasUnreadChapters: true,
    );
    expect(view.effective, PersonalStatus.reading);
    expect(view.isManualOverride, isFalse);
    expect(view.conflictWithCompleted, isFalse);
  });

  test('suggest completed when all chapters read', () {
    final s = recon.suggest(
      inLibrary: true,
      readChapterCount: 10,
      totalChapterCount: 10,
      hasUnreadChapters: false,
    );
    expect(s, PersonalStatus.completed);
  });
}
