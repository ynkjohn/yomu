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
  });

  final int id;
  final String title;
  final String? thumbnailUrl;
  final bool inLibrary;

  factory MangaSummary.fromJson(Map<String, dynamic> json) {
    return MangaSummary(
      id: json['id'] is int ? json['id'] as int : int.parse('${json['id']}'),
      title: '${json['title'] ?? ''}',
      thumbnailUrl: json['thumbnailUrl']?.toString(),
      inLibrary: json['inLibrary'] == true,
    );
  }
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
  });

  final int id;
  final String name;
  final double? chapterNumber;
  final int? pageCount;
  final int? sourceOrder;
  final String? scanlator;

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
    );
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
