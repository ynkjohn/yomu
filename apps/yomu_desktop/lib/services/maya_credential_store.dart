import 'dart:convert';

const String kMayaCredentialTargetPrefix = 'app.yomu/maya/provider/';
const int kMayaCredentialMaxApiKeyBytes = 2048;

final RegExp _providerIdPattern = RegExp(r'^[a-z][a-z0-9-]{0,39}$');

enum MayaCredentialStoreErrorCode {
  invalidProviderId,
  invalidApiKey,
  unavailable,
  readFailed,
  writeFailed,
  deleteFailed,
  corruptCredential,
}

/// Sanitized credential failure.
///
/// The original API key, Win32 error text and native buffers are deliberately
/// not retained, exposed through [toString], or attached as a cause.
final class MayaCredentialStoreException implements Exception {
  const MayaCredentialStoreException(this.code);

  final MayaCredentialStoreErrorCode code;

  String get message => switch (code) {
    MayaCredentialStoreErrorCode.invalidProviderId =>
      'Identificador de provider inválido.',
    MayaCredentialStoreErrorCode.invalidApiKey =>
      'A chave do provider é inválida.',
    MayaCredentialStoreErrorCode.unavailable =>
      'O armazenamento seguro de credenciais não está disponível.',
    MayaCredentialStoreErrorCode.readFailed =>
      'Não foi possível ler a credencial do provider.',
    MayaCredentialStoreErrorCode.writeFailed =>
      'Não foi possível salvar a credencial do provider.',
    MayaCredentialStoreErrorCode.deleteFailed =>
      'Não foi possível remover a credencial do provider.',
    MayaCredentialStoreErrorCode.corruptCredential =>
      'A credencial salva não pôde ser validada.',
  };

  @override
  String toString() => message;
}

/// Secure credential boundary used by the native desktop composition root.
///
/// Implementations must not persist API keys in SQLite, JSON, environment
/// variables, command-line arguments, logs, or exception messages.
abstract interface class MayaCredentialStore {
  Future<void> save({required String providerId, required String apiKey});

  Future<String?> read({required String providerId});

  /// Idempotent: deleting an absent credential succeeds.
  Future<void> delete({required String providerId});
}

/// Fail-closed production fallback when Windows Credential Manager cannot be
/// loaded. It keeps local/Ollama configuration available without ever
/// redirecting cloud credentials to an insecure store.
final class UnavailableMayaCredentialStore implements MayaCredentialStore {
  const UnavailableMayaCredentialStore();

  @override
  Future<void> save({
    required String providerId,
    required String apiKey,
  }) async {
    throw const MayaCredentialStoreException(
      MayaCredentialStoreErrorCode.unavailable,
    );
  }

  @override
  Future<String?> read({required String providerId}) async {
    throw const MayaCredentialStoreException(
      MayaCredentialStoreErrorCode.unavailable,
    );
  }

  @override
  Future<void> delete({required String providerId}) async {
    throw const MayaCredentialStoreException(
      MayaCredentialStoreErrorCode.unavailable,
    );
  }
}

/// Returns the deterministic, non-secret WinCred target for [providerId].
String mayaCredentialTargetForProvider(String providerId) {
  final canonical = validateMayaCredentialProviderId(providerId);
  return '$kMayaCredentialTargetPrefix$canonical';
}

String validateMayaCredentialProviderId(String providerId) {
  if (!_providerIdPattern.hasMatch(providerId)) {
    throw const MayaCredentialStoreException(
      MayaCredentialStoreErrorCode.invalidProviderId,
    );
  }
  return providerId;
}

/// Validates the narrow API-key format accepted by the credential boundary.
///
/// Provider API keys are opaque printable ASCII. Whitespace/control characters
/// are rejected so an accidental pasted newline cannot alter an HTTP header.
void validateMayaApiKey(String apiKey) {
  if (apiKey.isEmpty) {
    throw const MayaCredentialStoreException(
      MayaCredentialStoreErrorCode.invalidApiKey,
    );
  }

  List<int> encoded;
  try {
    encoded = utf8.encode(apiKey);
  } catch (_) {
    throw const MayaCredentialStoreException(
      MayaCredentialStoreErrorCode.invalidApiKey,
    );
  }

  try {
    if (encoded.length > kMayaCredentialMaxApiKeyBytes ||
        encoded.any((byte) => byte < 0x21 || byte > 0x7e)) {
      throw const MayaCredentialStoreException(
        MayaCredentialStoreErrorCode.invalidApiKey,
      );
    }
  } finally {
    encoded.fillRange(0, encoded.length, 0);
  }
}

/// In-memory implementation for deterministic desktop/provider tests only.
///
/// It never writes to disk. Production composition must use the Windows
/// Credential Manager implementation.
final class FakeMayaCredentialStore implements MayaCredentialStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> save({
    required String providerId,
    required String apiKey,
  }) async {
    final target = mayaCredentialTargetForProvider(providerId);
    validateMayaApiKey(apiKey);
    _values[target] = apiKey;
  }

  @override
  Future<String?> read({required String providerId}) async {
    final target = mayaCredentialTargetForProvider(providerId);
    return _values[target];
  }

  @override
  Future<void> delete({required String providerId}) async {
    final target = mayaCredentialTargetForProvider(providerId);
    _values.remove(target);
  }
}
