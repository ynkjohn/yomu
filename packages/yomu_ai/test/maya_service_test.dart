import 'dart:io';

import 'package:test/test.dart';
import 'package:yomu_ai/yomu_ai.dart';

class _FakePort implements MayaLibraryPort {
  final items = <MayaLibraryItem>[
    const MayaLibraryItem(
      id: 7,
      title: 'One Piece',
      unreadCount: 2,
      lastChapterId: 99,
      lastChapterName: 'Cap 1000',
    ),
  ];
  final downloads = <int>[];
  final libraryToggles = <int, bool>{};

  @override
  Future<List<MayaLibraryItem>> listLibrary() async => items;

  @override
  Future<void> enqueueChapterDownload(int chapterId) async {
    downloads.add(chapterId);
  }

  @override
  Future<void> setInLibrary(int mangaId, bool inLibrary) async {
    libraryToggles[mangaId] = inLibrary;
  }
}

void main() {
  test('send + confirm download executes only after confirm', () async {
    final dir = await Directory.systemTemp.createTemp('maya_test_');
    addTearDown(() => dir.delete(recursive: true));
    final store = MayaStore(File('${dir.path}/maya.json'));
    final port = _FakePort();
    final maya = MayaService(store: store, libraryPort: port);

    final turn = await maya.sendUserMessage('baixar');
    expect(turn.proposals, isNotEmpty);
    expect(port.downloads, isEmpty);

    final p = turn.proposals.first;
    final done = await maya.confirmProposal(p.id);
    expect(done.status, ActionProposalStatus.executed);
    expect(port.downloads, [99]);
  });

  test('reject does not execute', () async {
    final dir = await Directory.systemTemp.createTemp('maya_test_');
    addTearDown(() => dir.delete(recursive: true));
    final store = MayaStore(File('${dir.path}/maya.json'));
    final port = _FakePort();
    final maya = MayaService(store: store, libraryPort: port);

    final turn = await maya.sendUserMessage('continuar');
    final p = turn.proposals.first;
    await maya.rejectProposal(p.id);
    expect(maya.proposalById(p.id)!.status, ActionProposalStatus.rejected);
    expect(port.downloads, isEmpty);
  });
}
