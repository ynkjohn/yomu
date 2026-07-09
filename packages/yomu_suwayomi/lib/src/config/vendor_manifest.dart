import 'dart:convert';
import 'dart:io';

/// Pinned Suwayomi + optional JRE coordinates (checksum-enforced).
class VendorManifest {
  const VendorManifest({
    required this.suwayomi,
    this.jre,
  });

  final SuwayomiArtifact suwayomi;
  final JreArtifact? jre;

  factory VendorManifest.fromJson(Map<String, dynamic> json) {
    return VendorManifest(
      suwayomi: SuwayomiArtifact.fromJson(
        json['suwayomi'] as Map<String, dynamic>,
      ),
      jre: json['jre'] == null
          ? null
          : JreArtifact.fromJson(json['jre'] as Map<String, dynamic>),
    );
  }

  static Future<VendorManifest> load(File file) async {
    final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return VendorManifest.fromJson(map);
  }

  Map<String, dynamic> toJson() => {
        'suwayomi': suwayomi.toJson(),
        if (jre != null) 'jre': jre!.toJson(),
      };
}

class SuwayomiArtifact {
  const SuwayomiArtifact({
    required this.version,
    required this.revision,
    required this.jarFile,
    required this.downloadUrl,
    required this.sha256,
    required this.minJre,
  });

  final String version;
  final String revision;
  final String jarFile;
  final String downloadUrl;
  final String sha256;
  final int minJre;

  String get displayVersion => '$version-$revision';

  factory SuwayomiArtifact.fromJson(Map<String, dynamic> json) {
    return SuwayomiArtifact(
      version: json['version'] as String,
      revision: json['revision'] as String,
      jarFile: json['jarFile'] as String,
      downloadUrl: json['downloadUrl'] as String,
      sha256: (json['sha256'] as String).toLowerCase(),
      minJre: json['minJre'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'revision': revision,
        'jarFile': jarFile,
        'downloadUrl': downloadUrl,
        'sha256': sha256,
        'minJre': minJre,
      };
}

class JreArtifact {
  const JreArtifact({
    required this.vendor,
    required this.version,
    required this.platforms,
  });

  final String vendor;
  final String version;
  final Map<String, PlatformArtifact> platforms;

  factory JreArtifact.fromJson(Map<String, dynamic> json) {
    final platformsJson = json['platforms'] as Map<String, dynamic>? ?? {};
    return JreArtifact(
      vendor: json['vendor'] as String,
      version: json['version'] as String,
      platforms: platformsJson.map(
        (k, v) => MapEntry(k, PlatformArtifact.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'vendor': vendor,
        'version': version,
        'platforms': platforms.map((k, v) => MapEntry(k, v.toJson())),
      };
}

class PlatformArtifact {
  const PlatformArtifact({required this.url, required this.sha256});

  final String url;
  final String sha256;

  factory PlatformArtifact.fromJson(Map<String, dynamic> json) {
    return PlatformArtifact(
      url: json['url'] as String,
      sha256: (json['sha256'] as String).toLowerCase(),
    );
  }

  Map<String, dynamic> toJson() => {'url': url, 'sha256': sha256};
}
