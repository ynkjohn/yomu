import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_desktop/screens/reader_screen.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

ChapterInfo chapter(int id, {int? page, bool read = false, int? sourceOrder}) =>
    ChapterInfo(
      id: id,
      name: 'Capítulo $id',
      lastPageRead: page,
      isRead: read,
      sourceOrder: sourceOrder,
    );

void main() {
  test('duas cargas concluindo fora de ordem aceitam somente a mais nova', () {
    final gate = ReaderLoadGate();
    final first = gate.begin(1);
    final second = gate.begin(1);

    expect(gate.accepts(second, 1), isTrue);
    expect(gate.accepts(first, 1), isFalse);
  });

  test('troca de capítulo invalida a carga anterior antes de mutações', () {
    final gate = ReaderLoadGate();
    final firstChapter = gate.begin(1);
    final secondChapter = gate.begin(2);

    expect(gate.accepts(firstChapter, 2), isFalse);
    expect(gate.accepts(secondChapter, 2), isTrue);
  });

  test(
    'troca de capítulo durante save preserva snapshots independentes',
    () async {
      final firstSave = Completer<ChapterInfo>();
      final calls = <ReaderProgressSnapshot>[];
      final queue = ReaderProgressSaveQueue(
        save: (snapshot) {
          calls.add(snapshot);
          if (calls.length == 1) return firstSave.future;
          return Future.value(
            chapter(
              snapshot.chapterId,
              page: snapshot.page,
              read: snapshot.isRead,
            ),
          );
        },
      );

      final drain = queue.enqueue(
        const ReaderProgressSnapshot(chapterId: 1, page: 3, pageCount: 10),
      );
      queue.enqueue(
        const ReaderProgressSnapshot(chapterId: 2, page: 0, pageCount: 20),
      );
      firstSave.complete(chapter(1, page: 3));
      await drain;

      expect(calls, hasLength(2));
      expect(calls[0].chapterId, 1);
      expect(calls[0].page, 3);
      expect(calls[0].pageCount, 10);
      expect(calls[1].chapterId, 2);
      expect(calls[1].page, 0);
      expect(calls[1].pageCount, 20);
    },
  );

  test(
    'save pendente permanece associado ao capítulo e página capturados',
    () async {
      final blocker = Completer<ChapterInfo>();
      final calls = <ReaderProgressSnapshot>[];
      final queue = ReaderProgressSaveQueue(
        save: (snapshot) {
          calls.add(snapshot);
          return calls.length == 1
              ? blocker.future
              : Future.value(chapter(snapshot.chapterId, page: snapshot.page));
        },
      );

      final drain = queue.enqueue(
        const ReaderProgressSnapshot(chapterId: 8, page: 4, pageCount: 12),
      );
      queue.enqueue(
        const ReaderProgressSnapshot(chapterId: 9, page: 6, pageCount: 7),
      );
      blocker.complete(chapter(8, page: 4));
      await drain;

      expect(calls.last.chapterId, 9);
      expect(calls.last.page, 6);
      expect(calls.last.isRead, isTrue);
    },
  );

  test('save final de A não é substituído pelo primeiro save de B', () async {
    final firstSave = Completer<ChapterInfo>();
    final calls = <ReaderProgressSnapshot>[];
    final queue = ReaderProgressSaveQueue(
      save: (snapshot) {
        calls.add(snapshot);
        if (calls.length == 1) return firstSave.future;
        return Future.value(
          chapter(
            snapshot.chapterId,
            page: snapshot.page,
            read: snapshot.isRead,
          ),
        );
      },
    );

    final drain = queue.enqueue(
      const ReaderProgressSnapshot(chapterId: 1, page: 3, pageCount: 12),
    );
    queue.enqueue(
      const ReaderProgressSnapshot(chapterId: 1, page: 11, pageCount: 12),
    );
    queue.enqueue(
      const ReaderProgressSnapshot(chapterId: 2, page: 0, pageCount: 20),
    );

    firstSave.complete(chapter(1, page: 3));
    await drain;

    expect(calls.map((snapshot) => (snapshot.chapterId, snapshot.page)), [
      (1, 3),
      (1, 11),
      (2, 0),
    ]);
  });

  test('coalesce somente o save mais novo do mesmo capítulo', () async {
    final firstSave = Completer<ChapterInfo>();
    final calls = <ReaderProgressSnapshot>[];
    final queue = ReaderProgressSaveQueue(
      save: (snapshot) {
        calls.add(snapshot);
        if (calls.length == 1) return firstSave.future;
        return Future.value(
          chapter(
            snapshot.chapterId,
            page: snapshot.page,
            read: snapshot.isRead,
          ),
        );
      },
    );

    final drain = queue.enqueue(
      const ReaderProgressSnapshot(chapterId: 7, page: 1, pageCount: 10),
    );
    queue.enqueue(
      const ReaderProgressSnapshot(chapterId: 7, page: 2, pageCount: 10),
    );
    queue.enqueue(
      const ReaderProgressSnapshot(chapterId: 7, page: 6, pageCount: 10),
    );

    firstSave.complete(chapter(7, page: 1));
    await drain;

    expect(calls.map((snapshot) => snapshot.page), [1, 6]);
  });

  test('A → B → A não regride progresso final durante save lento', () async {
    final finalSave = Completer<ChapterInfo>();
    final calls = <ReaderProgressSnapshot>[];
    final queue = ReaderProgressSaveQueue(
      save: (snapshot) {
        calls.add(snapshot);
        if (calls.length == 1) return finalSave.future;
        return Future.value(
          chapter(
            snapshot.chapterId,
            page: snapshot.page,
            read: snapshot.isRead,
          ),
        );
      },
    );

    final drain = queue.enqueue(
      const ReaderProgressSnapshot(chapterId: 1, page: 11, pageCount: 12),
    );
    queue.enqueue(
      const ReaderProgressSnapshot(chapterId: 2, page: 0, pageCount: 20),
    );
    queue.enqueue(
      const ReaderProgressSnapshot(chapterId: 1, page: 0, pageCount: 12),
    );

    finalSave.complete(chapter(1, page: 11, read: true));
    await drain;

    expect(
      calls.map(
        (snapshot) => (snapshot.chapterId, snapshot.page, snapshot.isRead),
      ),
      [(1, 11, true), (2, 0, false), (1, 11, true)],
    );
  });

  test('falha de save antigo não corrompe o capítulo atual', () async {
    var activeChapterId = 2;
    String? visibleError;
    ChapterInfo current = chapter(activeChapterId);
    final queue = ReaderProgressSaveQueue(
      save: (_) => Future<ChapterInfo>.error(StateError('falha antiga')),
      onSaved: (snapshot, updated) {
        if (snapshot.chapterId == activeChapterId) current = updated;
      },
      onFailed: (snapshot, error) {
        if (snapshot.chapterId == activeChapterId) visibleError = '$error';
      },
    );

    await queue.enqueue(
      const ReaderProgressSnapshot(chapterId: 1, page: 5, pageCount: 10),
    );

    expect(current.id, 2);
    expect(visibleError, isNull);
  });

  test('dispose destaca callbacks mas preserva o save final', () async {
    final saved = <ReaderProgressSnapshot>[];
    var callbackTouchedDisposedState = false;
    final queue = ReaderProgressSaveQueue(
      save: (snapshot) async {
        saved.add(snapshot);
        return chapter(snapshot.chapterId, page: snapshot.page);
      },
      onSaved: (_, _) => callbackTouchedDisposedState = true,
      onFailed: (_, _) => callbackTouchedDisposedState = true,
    );

    queue.detachCallbacks();
    await queue.enqueue(
      const ReaderProgressSnapshot(chapterId: 4, page: 11, pageCount: 12),
    );

    expect(saved.single.chapterId, 4);
    expect(saved.single.page, 11);
    expect(saved.single.isRead, isTrue);
    expect(callbackTouchedDisposedState, isFalse);
  });

  test('chronologicalChapters ordena por sourceOrder ascendente', () {
    final ordered = chronologicalChapters([
      chapter(30, sourceOrder: 3),
      chapter(10, sourceOrder: 1),
      chapter(20, sourceOrder: 2),
    ]);
    expect(ordered.map((c) => c.id), [10, 20, 30]);
  });

  test('chronologicalChapters usa id quando sourceOrder ausente', () {
    final ordered = chronologicalChapters([chapter(5), chapter(2), chapter(9)]);
    expect(ordered.map((c) => c.id), [2, 5, 9]);
  });

  test('visiblePageFromScroll usa extents medidos quando disponíveis', () {
    final index = visiblePageFromScroll(
      pixels: 350,
      maxScrollExtent: 900,
      pageCount: 3,
      itemExtents: const [200, 400, 300],
    );
    // 350 is past first page midpoint (100) and into second (200..600).
    expect(index, 1);
  });

  test('visiblePageFromScroll cai no mapeamento linear sem extents', () {
    final index = visiblePageFromScroll(
      pixels: 50,
      maxScrollExtent: 100,
      pageCount: 5,
    );
    expect(index, 2);
  });

  test('isRead no snapshot marca última página', () {
    const mid = ReaderProgressSnapshot(chapterId: 1, page: 3, pageCount: 10);
    const last = ReaderProgressSnapshot(chapterId: 1, page: 9, pageCount: 10);
    expect(mid.isRead, isFalse);
    expect(last.isRead, isTrue);
  });

  test('isRead preserva o estado capturado do próprio capítulo', () {
    const reopened = ReaderProgressSnapshot(
      chapterId: 1,
      page: 0,
      pageCount: 10,
      wasRead: true,
    );
    const otherChapter = ReaderProgressSnapshot(
      chapterId: 2,
      page: 0,
      pageCount: 10,
    );

    expect(reopened.isRead, isTrue);
    expect(otherChapter.isRead, isFalse);
  });
}
