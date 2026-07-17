import 'dart:convert';

const String kMayaCredentialTargetPrefix = 'app.yomu/maya/provider/';
const int kMayaCredentialMaxApiKeyBytes = 2048;

final RegExp _providerIdPattern = RegExp(r'^[a-z][a-z0-9-]{0,39}$');
final RegExp _credentialBindingPattern = RegExp(r'^[a-f0-9]{64}$');

enum MayaCredentialStoreErrorCode {
  invalidProviderId,
  invalidBinding,
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
    MayaCredentialStoreErrorCode.invalidBinding =>
      'Vínculo de credencial inválido.',
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
  Future<void> save({
    required String providerId,
    required String apiKey,
    String? credentialBinding,
  });

  /// Returns null when the target is absent or is bound to a different
  /// non-secret context. A custom endpoint therefore cannot inherit a key
  /// saved for another endpoint when the key field is left blank.
  Future<String?> read({required String providerId, String? credentialBinding});

  /// Whether any credential exists at the deterministic provider target,
  /// regardless of its endpoint binding. Used to verify destructive cleanup.
  Future<bool> exists({required String providerId});

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
    String? credentialBinding,
  }) async {
    throw const MayaCredentialStoreException(
      MayaCredentialStoreErrorCode.unavailable,
    );
  }

  @override
  Future<String?> read({
    required String providerId,
    String? credentialBinding,
  }) async {
    throw const MayaCredentialStoreException(
      MayaCredentialStoreErrorCode.unavailable,
    );
  }

  @override
  Future<bool> exists({required String providerId}) async {
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

String? validateMayaCredentialBinding(String? credentialBinding) {
  if (credentialBinding == null) return null;
  if (!_credentialBindingPattern.hasMatch(credentialBinding)) {
    throw const MayaCredentialStoreException(
      MayaCredentialStoreErrorCode.invalidBinding,
    );
  }
  return credentialBinding;
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
  final Map<String, ({String apiKey, String? binding})> _values =
      <String, ({String apiKey, String? binding})>{};

  @override
  Future<void> save({
    required String providerId,
    required String apiKey,
    String? credentialBinding,
  }) async {
    final target = mayaCredentialTargetForProvider(providerId);
    validateMayaApiKey(apiKey);
    final binding = validateMayaCredentialBinding(credentialBinding);
    _values[target] = (apiKey: apiKey, binding: binding);
  }

  @override
  Future<String?> read({
    required String providerId,
    String? credentialBinding,
  }) async {
    final target = mayaCredentialTargetForProvider(providerId);
    final binding = validateMayaCredentialBinding(credentialBinding);
    final stored = _values[target];
    if (stored == null || stored.binding != binding) return null;
    return stored.apiKey;
  }

  @override
  Future<bool> exists({required String providerId}) async {
    final target = mayaCredentialTargetForProvider(providerId);
    return _values.containsKey(target);
  }

  @override
  Future<void> delete({required String providerId}) async {
    final target = mayaCredentialTargetForProvider(providerId);
    _values.remove(target);
  }
}
