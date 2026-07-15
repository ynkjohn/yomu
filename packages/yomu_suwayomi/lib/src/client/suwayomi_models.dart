// DTOs matching GraphQL fields confirmed in docs/suwayomi-api-matrix.md.

class ExtensionStoreInfo {
  const ExtensionStoreInfo({
    required this.name,
    required this.indexUrl,
    this.isLegacy = false,
  });

  final String name;
  final String indexUrl;
  final bool isLegacy;

  factory ExtensionStoreInfo.fromJson(Map<String, dynamic> json) {
    return ExtensionStoreInfo(
      name: '${json['name'] ?? ''}',
      indexUrl: '${json['indexUrl'] ?? ''}',
      isLegacy: json['isLegacy'] == true,
    );
  }
}

class ExtensionInfo {
  const ExtensionInfo({
    required this.pkgName,
    required this.name,
    required this.isInstalled,
    this.versionName,
    this.lang,
    this.apkName,
  });

  final String pkgName;
  final String name;
  final bool isInstalled;
  final String? versionName;
  final String? lang;
  final String? apkName;

  factory ExtensionInfo.fromJson(Map<String, dynamic> json) {
    return ExtensionInfo(
      pkgName: '${json['pkgName'] ?? ''}',
      name: '${json['name'] ?? ''}',
      isInstalled: json['isInstalled'] == true,
      versionName: json['versionName']?.toString(),
      lang: json['lang']?.toString(),
      apkName: json['apkName']?.toString(),
    );
  }
}

class SourceInfo {
  const SourceInfo({
    required this.id,
    required this.name,
    required this.lang,
    this.iconUrl,
  });

  final String id;
  final String name;
  final String lang;
  final String? iconUrl;

  factory SourceInfo.fromJson(Map<String, dynamic> json) {
    return SourceInfo(
      id: '${json['id']}',
      name: '${json['name'] ?? ''}',
      lang: '${json['lang'] ?? ''}',
      iconUrl: json['iconUrl']?.toString(),
    );
  }
}

class MangaSummary {
  const MangaSummary({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.inLibrary = false,
    this.unreadCount,
    this.lastReadChapter,
  });

  final int id;
  final String title;
  final String? thumbnailUrl;
  final bool inLibrary;
  final int? unreadCount;
  final ChapterInfo? lastReadChapter;

  factory MangaSummary.fromJson(Map<String, dynamic> json) {
    ChapterInfo? lastRead;
    final raw = json['lastReadChapter'];
    if (raw is Map) {
      lastRead = ChapterInfo.fromJson(Map<String, dynamic>.from(raw));
    }
    return MangaSummary(
      id: json['id'] is int ? json['id'] as int : int.parse('${json['id']}'),
      title: '${json['title'] ?? ''}',
      thumbnailUrl: json['thumbnailUrl']?.toString(),
      inLibrary: json['inLibrary'] == true,
      unreadCount: json['unreadCount'] is int
          ? json['unreadCount'] as int
          : int.tryParse('${json['unreadCount']}'),
      lastReadChapter: lastRead,
    );
  }
}

enum SourceMangaFetchType { search, popular, latest }

class SourceMangaPage {
  const SourceMangaPage({
    required this.items,
    required this.hasNextPage,
    required this.page,
  });

  final List<MangaSummary> items;
  final bool hasNextPage;
  final int page;
}

class MangaDetails {
  const MangaDetails({
    required this.id,
    required this.title,
    this.description,
    this.author,
    this.artist,
    this.status,
    this.thumbnailUrl,
    this.sourceId,
    this.inLibrary = false,
  });

  final int id;
  final String title;
  final String? description;
  final String? author;
  final String? artist;
  final String? status;
  final String? thumbnailUrl;
  final String? sourceId;
  final bool inLibrary;

  factory MangaDetails.fromJson(Map<String, dynamic> json) {
    return MangaDetails(
      id: json['id'] is int ? json['id'] as int : int.parse('${json['id']}'),
      title: '${json['title'] ?? ''}',
      description: json['description']?.toString(),
      author: json['author']?.toString(),
      artist: json['artist']?.toString(),
      status: json['status']?.toString(),
      thumbnailUrl: json['thumbnailUrl']?.toString(),
      sourceId: json['sourceId']?.toString(),
      inLibrary: json['inLibrary'] == true,
    );
  }
}

class ChapterInfo {
  const ChapterInfo({
    required this.id,
    required this.name,
    this.chapterNumber,
    this.pageCount,
    this.sourceOrder,
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
  final int? sourceOrder;
  final String? scanlator;
  final int? lastPageRead;
  final bool isRead;
  final bool isDownloaded;
  final int? mangaId;

  /// 0-based page index for resume (clamped later by reader).
  int get resumePageIndex {
    final p = lastPageRead ?? 0;
    if (p <= 0) return 0;
    // Suwayomi lastPageRead is typically 0-based page index of last viewed.
    return p;
  }

  factory ChapterInfo.fromJson(Map<String, dynamic> json) {
    return ChapterInfo(
      id: json['id'] is int ? json['id'] as int : int.parse('${json['id']}'),
      name: '${json['name'] ?? ''}',
      chapterNumber: json['chapterNumber'] is num
          ? (json['chapterNumber'] as num).toDouble()
          : double.tryParse('${json['chapterNumber']}'),
      pageCount: json['pageCount'] is int
          ? json['pageCount'] as int
          : int.tryParse('${json['pageCount']}'),
      sourceOrder: json['sourceOrder'] is int
          ? json['sourceOrder'] as int
          : int.tryParse('${json['sourceOrder']}'),
      scanlator: json['scanlator']?.toString(),
      lastPageRead: json['lastPageRead'] is int
          ? json['lastPageRead'] as int
          : int.tryParse('${json['lastPageRead']}'),
      isRead: json['isRead'] == true,
      isDownloaded: json['isDownloaded'] == true,
      mangaId: json['mangaId'] is int
          ? json['mangaId'] as int
          : int.tryParse('${json['mangaId']}'),
    );
  }

  ChapterInfo copyWith({int? lastPageRead, bool? isRead, bool? isDownloaded}) {
    return ChapterInfo(
      id: id,
      name: name,
      chapterNumber: chapterNumber,
      pageCount: pageCount,
      sourceOrder: sourceOrder,
      scanlator: scanlator,
      lastPageRead: lastPageRead ?? this.lastPageRead,
      isRead: isRead ?? this.isRead,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      mangaId: mangaId,
    );
  }
}

class DownloadQueueItem {
  const DownloadQueueItem({
    required this.state,
    this.progress,
    this.chapter,
    this.manga,
  });

  final String state;
  final double? progress;
  final ChapterInfo? chapter;
  final MangaSummary? manga;

  factory DownloadQueueItem.fromJson(Map<String, dynamic> json) {
    ChapterInfo? ch;
    MangaSummary? manga;
    final rawCh = json['chapter'];
    if (rawCh is Map) {
      ch = ChapterInfo.fromJson(Map<String, dynamic>.from(rawCh));
    }
    final rawM = json['manga'];
    if (rawM is Map) {
      manga = MangaSummary.fromJson(Map<String, dynamic>.from(rawM));
    }
    return DownloadQueueItem(
      state: '${json['state'] ?? ''}',
      progress: json['progress'] is num
          ? (json['progress'] as num).toDouble()
          : double.tryParse('${json['progress']}'),
      chapter: ch,
      manga: manga,
    );
  }
}

class DownloadStatusInfo {
  const DownloadStatusInfo({required this.state, required this.queue});

  final String state;
  final List<DownloadQueueItem> queue;

  factory DownloadStatusInfo.fromJson(Map<String, dynamic> json) {
    final q = json['queue'];
    final list = <DownloadQueueItem>[];
    if (q is List) {
      for (final item in q.whereType<Map<dynamic, dynamic>>()) {
        list.add(DownloadQueueItem.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return DownloadStatusInfo(state: '${json['state'] ?? ''}', queue: list);
  }
}

class ChapterPages {
  const ChapterPages({
    required this.chapterId,
    required this.pages,
    this.pageCount,
    this.chapterName,
  });

  final int chapterId;
  final List<String> pages;
  final int? pageCount;
  final String? chapterName;
}
