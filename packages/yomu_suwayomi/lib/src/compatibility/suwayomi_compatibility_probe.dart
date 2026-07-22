import 'dart:io';

import 'package:crypto/crypto.dart';

import '../client/suwayomi_client.dart';
import '../config/vendor_manifest.dart';

enum SuwayomiCompatibilityFailureKind {
  artifactInvalid,
  unavailable,
  versionMismatch,
  protocolMismatch,
  capabilityMismatch,
}

final class SuwayomiCompatibilityFailure {
  const SuwayomiCompatibilityFailure(this.kind, this.code);

  final SuwayomiCompatibilityFailureKind kind;
  final String code;
}

final class SuwayomiCompatibilityResult {
  SuwayomiCompatibilityResult.compatible({
    required this.engineVersion,
    required this.protocolVersion,
    required Iterable<String> capabilities,
  }) : compatible = true,
       capabilities = List<String>.unmodifiable(capabilities),
       failure = null;

  const SuwayomiCompatibilityResult.incompatible(this.failure)
    : compatible = false,
      engineVersion = null,
      protocolVersion = null,
      capabilities = const [];

  final bool compatible;
  final String? engineVersion;
  final String? protocolVersion;
  final List<String> capabilities;
  final SuwayomiCompatibilityFailure? failure;
}

/// Verifies the pinned artifact, REST version and GraphQL capability surface.
final class SuwayomiCompatibilityProbe {
  const SuwayomiCompatibilityProbe({
    required this.client,
    required this.manifest,
    required this.artifact,
  });

  final SuwayomiClient client;
  final VendorManifest manifest;
  final File artifact;

  Future<bool> checkPinnedHealth() async {
    final about = (await client.probeAbout()).value;
    if (about == null) return false;
    return _samePinnedValue(
          '${about['version'] ?? ''}',
          manifest.suwayomi.version,
        ) &&
        _samePinnedValue(
          '${about['revision'] ?? ''}',
          manifest.suwayomi.revision,
        );
  }

  Future<SuwayomiCompatibilityResult> run() async {
    if (!await _artifactMatches()) {
      return const SuwayomiCompatibilityResult.incompatible(
        SuwayomiCompatibilityFailure(
          SuwayomiCompatibilityFailureKind.artifactInvalid,
          'engine_artifact_invalid',
        ),
      );
    }

    final aboutProbe = await client.probeAbout();
    final about = aboutProbe.value;
    if (about == null &&
        aboutProbe.failure == SuwayomiProbeFailure.unavailable) {
      return const SuwayomiCompatibilityResult.incompatible(
        SuwayomiCompatibilityFailure(
          SuwayomiCompatibilityFailureKind.unavailable,
          'engine_compatibility_unavailable',
        ),
      );
    }
    if (about == null) {
      return const SuwayomiCompatibilityResult.incompatible(
        SuwayomiCompatibilityFailure(
          SuwayomiCompatibilityFailureKind.protocolMismatch,
          'engine_about_incompatible',
        ),
      );
    }
    final observedVersion = '${about['version'] ?? ''}'.trim();
    final observedRevision = '${about['revision'] ?? ''}'.trim();
    if (!_samePinnedValue(observedVersion, manifest.suwayomi.version) ||
        !_samePinnedValue(observedRevision, manifest.suwayomi.revision)) {
      return const SuwayomiCompatibilityResult.incompatible(
        SuwayomiCompatibilityFailure(
          SuwayomiCompatibilityFailureKind.versionMismatch,
          'engine_version_incompatible',
        ),
      );
    }

    final schemaProbe = await client.probeGraphqlSchema(
      path: manifest.compatibility.graphqlPath,
    );
    final schema = schemaProbe.value;
    if (schema == null) {
      if (schemaProbe.failure == SuwayomiProbeFailure.unavailable) {
        return const SuwayomiCompatibilityResult.incompatible(
          SuwayomiCompatibilityFailure(
            SuwayomiCompatibilityFailureKind.unavailable,
            'engine_compatibility_unavailable',
          ),
        );
      }
      return const SuwayomiCompatibilityResult.incompatible(
        SuwayomiCompatibilityFailure(
          SuwayomiCompatibilityFailureKind.protocolMismatch,
          'engine_protocol_incompatible',
        ),
      );
    }
    final queryFields = schema.queryFields.toSet();
    final mutationFields = schema.mutationFields.toSet();
    if (!queryFields.containsAll(manifest.compatibility.requiredQueryFields) ||
        !mutationFields.containsAll(
          manifest.compatibility.requiredMutationFields,
        )) {
      return const SuwayomiCompatibilityResult.incompatible(
        SuwayomiCompatibilityFailure(
          SuwayomiCompatibilityFailureKind.capabilityMismatch,
          'engine_capabilities_incompatible',
        ),
      );
    }

    return SuwayomiCompatibilityResult.compatible(
      engineVersion: manifest.suwayomi.displayVersion,
      protocolVersion: manifest.compatibility.restApiVersion,
      capabilities: manifest.compatibility.capabilities,
    );
  }

  Future<bool> _artifactMatches() async {
    try {
      if (!artifact.existsSync()) return false;
      final digest = await sha256.bind(artifact.openRead()).first;
      return digest.toString().toLowerCase() ==
          manifest.suwayomi.sha256.toLowerCase();
    } catch (_) {
      return false;
    }
  }

  static bool _samePinnedValue(String observed, String expected) {
    String normalize(String value) =>
        value.trim().toLowerCase().replaceFirst(RegExp(r'^[vr]'), '');
    return observed.isNotEmpty && normalize(observed) == normalize(expected);
  }
}
