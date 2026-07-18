import 'package:collection/collection.dart';

import 'media_gateway.dart';

enum ReadingPublicationStatus {
  ongoing,
  completed,
  licensed,
  publishingFinished,
  cancelled,
  onHiatus,
  unknown,
}

/// Yomu-owned manga details used by product surfaces and the local API.
final class ReadingMangaDetails {
  const ReadingMangaDetails({
    required this.id,
    required this.title,
    this.description,
    this.author,
    this.artist,
    this.status,
    this.thumbnail,
    this.sourceId,
    this.inLibrary = false,
  });

  final int id;
  final String title;
  final String? description;
  final String? author;
  final String? artist;
  final ReadingPublicationStatus? status;
  final MediaReference? thumbnail;
  final String? sourceId;
  final bool inLibrary;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadingMangaDetails &&
          id == other.id &&
          title == other.title &&
          description == other.description &&
          author == other.author &&
          artist == other.artist &&
          status == other.status &&
          thumbnail == other.thumbnail &&
          sourceId == other.sourceId &&
          inLibrary == other.inLibrary;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    author,
    artist,
    status,
    thumbnail,
    sourceId,
    inLibrary,
  );
}

/// Yomu-owned chapter state. Page positions remain 0-based.
final class ReadingChapter {
  const ReadingChapter({
    required this.id,
    required this.name,
    this.chapterNumber,
    this.pageCount,
    this.readingOrder,
    this.scanlator,
    this.lastPageRead,
    this.isRead = false,
    this.isDownloaded = false,
    this.mangaId,
  });

  final int id;
  final String name;
  final double? chapterNumber;
  final int? pageCount;
  final int? readingOrder;
  final String? scanlator;
  final int? lastPageRead;
  final bool isRead;
  final bool isDownloaded;
  final int? mangaId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadingChapter &&
          id == other.id &&
          name == other.name &&
          chapterNumber == other.chapterNumber &&
          pageCount == other.pageCount &&
          readingOrder == other.readingOrder &&
          scanlator == other.scanlator &&
          lastPageRead == other.lastPageRead &&
          isRead == other.isRead &&
          isDownloaded == other.isDownloaded &&
          mangaId == other.mangaId;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    chapterNumber,
    pageCount,
    readingOrder,
    scanlator,
    lastPageRead,
    isRead,
    isDownloaded,
    mangaId,
  );
}

/// Chapter pages represented only by opaque media identities.
final class ReadingChapterPages {
  ReadingChapterPages({
    required this.chapterId,
    required List<MediaReference> pages,
    this.pageCount,
    this.chapterName,
  }) : pages = List<MediaReference>.unmodifiable(pages);

  final int chapterId;
  final List<MediaReference> pages;
  final int? pageCount;
  final String? chapterName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadingChapterPages &&
          chapterId == other.chapterId &&
          const ListEquality<MediaReference>().equals(pages, other.pages) &&
          pageCount == other.pageCount &&
          chapterName == other.chapterName;

  @override
  int get hashCode => Object.hash(
    chapterId,
    const ListEquality<MediaReference>().hash(pages),
    pageCount,
    chapterName,
  );
}

/// Result of a persisted reading-progress mutation.
final class ReadingProgressSnapshot {
  const ReadingProgressSnapshot({
    required this.chapterId,
    required this.lastPageRead,
    required this.isRead,
  });

  final int chapterId;
  final int lastPageRead;
  final bool isRead;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadingProgressSnapshot &&
          chapterId == other.chapterId &&
          lastPageRead == other.lastPageRead &&
          isRead == other.isRead;

  @override
  int get hashCode => Object.hash(chapterId, lastPageRead, isRead);
}
