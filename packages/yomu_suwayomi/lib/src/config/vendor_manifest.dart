import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Single source of truth for the pinned reading-engine distribution.
final class VendorManifest {
  const VendorManifest({
    required this.suwayomi,
    this.jre,
    this.schemaVersion = 1,
    this.noticesFile = 'THIRD_PARTY_NOTICES.md',
  });

  static const fileName = 'engine_manifest.json';

  final int schemaVersion;
  final String noticesFile;
  final SuwayomiArtifact suwayomi;
  final JreArtifact? jre;

  factory VendorManifest.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != 1) {
      throw FormatException(
        'Unsupported engine manifest schema: $schemaVersion',
      );
    }
    final jreJson = json['jre'];
    if (jreJson is! Map<String, dynamic>) {
      throw const FormatException('Engine manifest is missing JRE metadata.');
    }
    return VendorManifest(
      schemaVersion: schemaVersion as int,
      noticesFile: _leafFileName(json, 'noticesFile'),
      suwayomi: SuwayomiArtifact.fromJson(_requiredMap(json, 'suwayomi')),
      jre: JreArtifact.fromJson(jreJson),
    );
  }

  static Future<VendorManifest> load(File file) async {
    final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return VendorManifest.fromJson(map);
  }

  static Future<VendorManifest> loadForRuntime({
    bool packagedOnly = false,
    String? resolvedExecutableForTest,
    Directory? currentDirectoryForTest,
  }) {
    return load(
      resolveRuntimeFile(
        packagedOnly: packagedOnly,
        resolvedExecutableForTest: resolvedExecutableForTest,
        currentDirectoryForTest: currentDirectoryForTest,
      ),
    );
  }

  static File resolveRuntimeFile({
    bool packagedOnly = false,
    String? resolvedExecutableForTest,
    Directory? currentDirectoryForTest,
  }) {
    final executable = resolvedExecutableForTest ?? Platform.resolvedExecutable;
    final packaged = File(
      p.join(File(executable).parent.path, 'engine', fileName),
    );
    if (packaged.existsSync()) return packaged;
    if (packagedOnly) {
      throw StateError(
        '$fileName is missing from the packaged engine directory: '
        '${packaged.path}',
      );
    }

    final candidates = <File>[packaged];

    void addRepositoryCandidates(Directory start) {
      var dir = start.absolute;
      for (var i = 0; i < 14; i++) {
        candidates.add(
          File(
            p.join(dir.path, 'packages', 'yomu_suwayomi', 'vendor', fileName),
          ),
        );
        candidates.add(File(p.join(dir.path, 'vendor', fileName)));
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }

    addRepositoryCandidates(currentDirectoryForTest ?? Directory.current);
    addRepositoryCandidates(File(executable).parent);

    final seen = <String>{};
    for (final candidate in candidates) {
      final key = p.normalize(candidate.absolute.path).toLowerCase();
      if (seen.add(key) && candidate.existsSync()) return candidate;
    }
    throw StateError(
      '$fileName not found. Tried:\n${candidates.map((f) => f.path).join('\n')}',
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'noticesFile': noticesFile,
    'suwayomi': suwayomi.toJson(),
    if (jre != null) 'jre': jre!.toJson(),
  };
}

final class SuwayomiArtifact {
  const SuwayomiArtifact({
    required this.version,
    required this.revision,
    required this.jarFile,
    required this.downloadUrl,
    this.sourceUrl = '',
    this.sourceCommit = '',
    this.sourceArchiveFile = '',
    this.sourceArchiveUrl = '',
    this.sourceSha256 = '',
    this.sourceRequiredEntries = const [],
    this.checksumUrl = '',
    required this.sha256,
    required this.minJre,
    this.license = '',
    this.licenseUrl = '',
  });

  final String version;
  final String revision;
  final String jarFile;
  final String downloadUrl;
  final String sourceUrl;
  final String sourceCommit;
  final String sourceArchiveFile;
  final String sourceArchiveUrl;
  final String sourceSha256;
  final List<String> sourceRequiredEntries;
  final String checksumUrl;
  final String sha256;
  final int minJre;
  final String license;
  final String licenseUrl;

  String get displayVersion => '$version-$revision';

  factory SuwayomiArtifact.fromJson(Map<String, dynamic> json) {
    return SuwayomiArtifact(
      version: _requiredString(json, 'version'),
      revision: _requiredString(json, 'revision'),
      jarFile: _leafFileName(json, 'jarFile'),
      downloadUrl: _httpsUrl(json, 'downloadUrl'),
      sourceUrl: _httpsUrl(json, 'sourceUrl'),
      sourceCommit: _commitSha(json, 'sourceCommit'),
      sourceArchiveFile: _leafFileName(json, 'sourceArchiveFile'),
      sourceArchiveUrl: _httpsUrl(json, 'sourceArchiveUrl'),
      sourceSha256: _sha256(json, 'sourceSha256'),
      sourceRequiredEntries: _requiredRelativePaths(
        json,
        'sourceRequiredEntries',
      ),
      checksumUrl: _httpsUrl(json, 'checksumUrl'),
      sha256: _sha256(json, 'sha256'),
      minJre: _requiredPositiveInt(json, 'minJre'),
      license: _requiredString(json, 'license'),
      licenseUrl: _httpsUrl(json, 'licenseUrl'),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'revision': revision,
    'jarFile': jarFile,
    'downloadUrl': downloadUrl,
    'sourceUrl': sourceUrl,
    'sourceCommit': sourceCommit,
    'sourceArchiveFile': sourceArchiveFile,
    'sourceArchiveUrl': sourceArchiveUrl,
    'sourceSha256': sourceSha256,
    'sourceRequiredEntries': sourceRequiredEntries,
    'checksumUrl': checksumUrl,
    'sha256': sha256,
    'minJre': minJre,
    'license': license,
    'licenseUrl': licenseUrl,
  };
}

final class JreArtifact {
  const JreArtifact({
    required this.vendor,
    required this.version,
    required this.os,
    required this.arch,
    required this.archiveFile,
    required this.downloadUrl,
    required this.checksumUrl,
    required this.sha256,
    required this.license,
    required this.licenseUrl,
    required this.noticeFile,
    required this.requiredNoticePaths,
    required this.executable,
    required this.localVendorPath,
    required this.source,
  });

  final String vendor;
  final String version;
  final String os;
  final String arch;
  final String archiveFile;
  final String downloadUrl;
  final String checksumUrl;
  final String sha256;
  final String license;
  final String licenseUrl;
  final String noticeFile;
  final List<String> requiredNoticePaths;
  final String executable;
  final String localVendorPath;
  final JreSourceArtifact source;

  factory JreArtifact.fromJson(Map<String, dynamic> json) {
    return JreArtifact(
      vendor: _requiredString(json, 'vendor'),
      version: _requiredString(json, 'version'),
      os: _requiredString(json, 'os'),
      arch: _requiredString(json, 'arch'),
      archiveFile: _leafFileName(json, 'archiveFile'),
      downloadUrl: _httpsUrl(json, 'downloadUrl'),
      checksumUrl: _httpsUrl(json, 'checksumUrl'),
      sha256: _sha256(json, 'sha256'),
      license: _requiredString(json, 'license'),
      licenseUrl: _httpsUrl(json, 'licenseUrl'),
      noticeFile: _leafFileName(json, 'noticeFile'),
      requiredNoticePaths: _requiredRelativePaths(json, 'requiredNoticePaths'),
      executable: _relativePath(json, 'executable'),
      localVendorPath: _leafFileName(json, 'localVendorPath'),
      source: JreSourceArtifact.fromJson(_requiredMap(json, 'source')),
    );
  }

  Map<String, dynamic> toJson() => {
    'vendor': vendor,
    'version': version,
    'os': os,
    'arch': arch,
    'archiveFile': archiveFile,
    'downloadUrl': downloadUrl,
    'checksumUrl': checksumUrl,
    'sha256': sha256,
    'license': license,
    'licenseUrl': licenseUrl,
    'noticeFile': noticeFile,
    'requiredNoticePaths': requiredNoticePaths,
    'executable': executable,
    'localVendorPath': localVendorPath,
    'source': source.toJson(),
  };
}

final class JreSourceArtifact {
  const JreSourceArtifact({
    required this.archiveFile,
    required this.downloadUrl,
    required this.checksumUrl,
    required this.sha256,
    required this.distributionPolicy,
    required this.scmRef,
    required this.openJdkSourceCommit,
    required this.requiredEntries,
    required this.build,
    required this.provenance,
  });

  final String archiveFile;
  final String downloadUrl;
  final String checksumUrl;
  final String sha256;
  final String distributionPolicy;
  final String scmRef;
  final String openJdkSourceCommit;
  final List<String> requiredEntries;
  final JreBuildSourceArtifact build;
  final JreBuildProvenance provenance;

  factory JreSourceArtifact.fromJson(Map<String, dynamic> json) {
    return JreSourceArtifact(
      archiveFile: _leafFileName(json, 'archiveFile'),
      downloadUrl: _httpsUrl(json, 'downloadUrl'),
      checksumUrl: _httpsUrl(json, 'checksumUrl'),
      sha256: _sha256(json, 'sha256'),
      distributionPolicy: _requiredString(json, 'distributionPolicy'),
      scmRef: _requiredString(json, 'scmRef'),
      openJdkSourceCommit: _commitSha(json, 'openJdkSourceCommit'),
      requiredEntries: _requiredRelativePaths(json, 'requiredEntries'),
      build: JreBuildSourceArtifact.fromJson(_requiredMap(json, 'build')),
      provenance: JreBuildProvenance.fromJson(_requiredMap(json, 'provenance')),
    );
  }

  Map<String, dynamic> toJson() => {
    'archiveFile': archiveFile,
    'downloadUrl': downloadUrl,
    'checksumUrl': checksumUrl,
    'sha256': sha256,
    'distributionPolicy': distributionPolicy,
    'scmRef': scmRef,
    'openJdkSourceCommit': openJdkSourceCommit,
    'requiredEntries': requiredEntries,
    'build': build.toJson(),
    'provenance': provenance.toJson(),
  };
}

final class JreBuildSourceArtifact {
  const JreBuildSourceArtifact({
    required this.commit,
    required this.archiveFile,
    required this.downloadUrl,
    required this.sha256,
    required this.license,
    required this.requiredEntries,
  });

  final String commit;
  final String archiveFile;
  final String downloadUrl;
  final String sha256;
  final String license;
  final List<String> requiredEntries;

  factory JreBuildSourceArtifact.fromJson(Map<String, dynamic> json) {
    return JreBuildSourceArtifact(
      commit: _commitSha(json, 'commit'),
      archiveFile: _leafFileName(json, 'archiveFile'),
      downloadUrl: _httpsUrl(json, 'downloadUrl'),
      sha256: _sha256(json, 'sha256'),
      license: _requiredString(json, 'license'),
      requiredEntries: _requiredRelativePaths(json, 'requiredEntries'),
    );
  }

  Map<String, dynamic> toJson() => {
    'commit': commit,
    'archiveFile': archiveFile,
    'downloadUrl': downloadUrl,
    'sha256': sha256,
    'license': license,
    'requiredEntries': requiredEntries,
  };
}

final class JreBuildProvenance {
  const JreBuildProvenance({
    required this.metadataFile,
    required this.downloadUrl,
    required this.sha256,
  });

  final String metadataFile;
  final String downloadUrl;
  final String sha256;

  factory JreBuildProvenance.fromJson(Map<String, dynamic> json) {
    return JreBuildProvenance(
      metadataFile: _leafFileName(json, 'metadataFile'),
      downloadUrl: _httpsUrl(json, 'downloadUrl'),
      sha256: _sha256(json, 'sha256'),
    );
  }

  Map<String, dynamic> toJson() => {
    'metadataFile': metadataFile,
    'downloadUrl': downloadUrl,
    'sha256': sha256,
  };
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Manifest field $key must be a non-empty string.');
  }
  return value;
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map<String, dynamic>) {
    throw FormatException('Manifest field $key must be an object.');
  }
  return value;
}

int _requiredPositiveInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value <= 0) {
    throw FormatException('Manifest field $key must be a positive integer.');
  }
  return value;
}

String _sha256(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key).toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('Manifest field $key must be a SHA-256 digest.');
  }
  return value;
}

String _commitSha(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key).toLowerCase();
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(value)) {
    throw FormatException('Manifest field $key must be a 40-char commit SHA.');
  }
  return value;
}

String _httpsUrl(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw FormatException('Manifest field $key must be a plain HTTPS URL.');
  }
  return value;
}

String _leafFileName(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  if (p.isAbsolute(value) ||
      value.contains('/') ||
      value.contains(r'\') ||
      p.basename(value) != value ||
      value == '.' ||
      value == '..') {
    throw FormatException('Manifest field $key must be a leaf file name.');
  }
  return value;
}

String _relativePath(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  _validateRelativePath(value, key);
  return value;
}

void _validateRelativePath(String value, String key) {
  final portable = value.replaceAll(r'\', '/');
  final parts = portable.split('/').where((part) => part.isNotEmpty).toList();
  if (portable.startsWith('/') ||
      RegExp(r'^[a-zA-Z]:').hasMatch(portable) ||
      parts.isEmpty ||
      parts.any((part) => part == '.' || part == '..')) {
    throw FormatException(
      'Manifest field $key must stay within its declared artifact root.',
    );
  }
}

List<String> _requiredRelativePaths(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List ||
      value.isEmpty ||
      value.any((e) => e is! String || e.trim().isEmpty)) {
    throw FormatException(
      'Manifest field $key must be a non-empty string list.',
    );
  }
  final paths = value.cast<String>();
  for (final path in paths) {
    _validateRelativePath(path, key);
  }
  return List<String>.unmodifiable(paths);
}
