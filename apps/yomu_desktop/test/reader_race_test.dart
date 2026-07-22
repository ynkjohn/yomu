import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_desktop/screens/reader_screen.dart';

ReadingChapter chapter(int id, {int? readingOrder}) =>
    ReadingChapter(id: id, name: 'Capítulo $id', readingOrder: readingOrder);

void main() {
  test('chronologicalChapters ordena por readingOrder ascendente', () {
    final ordered = chronologicalChapters([
      chapter(30, readingOrder: 3),
      chapter(10, readingOrder: 1),
      chapter(20, readingOrder: 2),
    ]);
    expect(ordered.map((value) => value.id), [10, 20, 30]);
  });

  test('chronologicalChapters usa id quando readingOrder ausente', () {
    final ordered = chronologicalChapters([chapter(5), chapter(2), chapter(9)]);
    expect(ordered.map((value) => value.id), [2, 5, 9]);
  });

  test('visiblePageFromScroll usa extents medidos quando disponíveis', () {
    expect(
      visiblePageFromScroll(
        pixels: 350,
        maxScrollExtent: 900,
        pageCount: 3,
        itemExtents: const [200, 400, 300],
      ),
      1,
    );
  });

  test('visiblePageFromScroll cai no mapeamento linear sem extents', () {
    expect(
      visiblePageFromScroll(pixels: 50, maxScrollExtent: 100, pageCount: 5),
      2,
    );
  });

  test('snapshot final preserva 0-based e marca última página', () {
    const zero = ReaderSaveSnapshot(chapterId: 1, page: 0, pageCount: 10);
    const last = ReaderSaveSnapshot(chapterId: 1, page: 9, pageCount: 10);
    const reopened = ReaderSaveSnapshot(
      chapterId: 1,
      page: 0,
      pageCount: 10,
      wasRead: true,
    );

    expect(zero.page, 0);
    expect(zero.isRead, isFalse);
    expect(last.isRead, isTrue);
    expect(reopened.isRead, isTrue);
  });
}
