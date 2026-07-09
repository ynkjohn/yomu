import 'package:test/test.dart';
import 'package:yomu_ai/yomu_ai.dart';

void main() {
  final lib = [
    const MayaLibraryItem(
      id: 33,
      title: 'Dandadan',
      unreadCount: 12,
      lastChapterId: 500,
      lastChapterName: 'Cap. 10',
      lastPageRead: 3,
    ),
    const MayaLibraryItem(
      id: 1,
      title: 'Berserk',
      unreadCount: 0,
      lastChapterId: 10,
      lastChapterName: 'Vol 1',
    ),
  ];

  final engine = HeuristicMayaEngine();

  test('biblioteca lists titles', () {
    final turn = engine.handle(userText: 'mostrar biblioteca', library: lib);
    expect(turn.assistantMessage.text, contains('Dandadan'));
    expect(turn.assistantMessage.text, contains('Berserk'));
    expect(turn.proposals, isEmpty);
  });

  test('continuar proposes openManga without auto-exec', () {
    final turn = engine.handle(userText: 'continuar lendo', library: lib);
    expect(turn.proposals, isNotEmpty);
    expect(turn.proposals.first.kind, MayaActionKind.openManga);
    expect(turn.proposals.first.status, ActionProposalStatus.pending);
    expect(turn.proposals.first.payload['mangaId'], 33);
  });

  test('busca finds title', () {
    final turn = engine.handle(userText: 'busca danda', library: lib);
    expect(turn.proposals, isNotEmpty);
    expect(turn.proposals.first.payload['title'], 'Dandadan');
  });

  test('baixar proposes download', () {
    final turn = engine.handle(userText: 'baixar offline', library: lib);
    expect(turn.proposals.single.kind, MayaActionKind.downloadChapter);
    expect(turn.proposals.single.payload['chapterId'], 500);
  });

  test('empty library message', () {
    final turn = engine.handle(userText: 'biblioteca', library: const []);
    expect(turn.assistantMessage.text.toLowerCase(), contains('vazia'));
  });
}
