import 'media_gateway.dart';

/// Minimal chapter state required by library resume surfaces.
final class LibraryResumePoint {
  const LibraryResumePoint({
    required this.id,
    required this.name,
    this.lastPageRead,
    this.pageCount,
  });

  final int id;
  final String name;
  final int? lastPageRead;
  final int? pageCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryResumePoint &&
          id == other.id &&
          name == other.name &&
          lastPageRead == other.lastPageRead &&
          pageCount == other.pageCount;

  @override
  int get hashCode => Object.hash(id, name, lastPageRead, pageCount);
}

/// Yomu-owned library summary. It contains no protocol DTO or transport URL.
final class LibraryManga {
  const LibraryManga({
    required this.id,
    required this.title,
    this.thumbnail,
    this.inLibrary = false,
    this.unreadCount,
    this.lastReadChapter,
  });

  final int id;
  final String title;
  final MediaReference? thumbnail;
  final bool inLibrary;
  final int? unreadCount;
  final LibraryResumePoint? lastReadChapter;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryManga &&
          id == other.id &&
          title == other.title &&
          thumbnail == other.thumbnail &&
          inLibrary == other.inLibrary &&
          unreadCount == other.unreadCount &&
          lastReadChapter == other.lastReadChapter;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    thumbnail,
    inLibrary,
    unreadCount,
    lastReadChapter,
  );
}
