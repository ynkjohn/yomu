import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_desktop/services/maya_credential_store.dart';

void main() {
  test(
    'unavailable store fails closed without accepting credentials',
    () async {
      const store = UnavailableMayaCredentialStore();

      await expectLater(
        store.save(providerId: 'openai', apiKey: 'secret'),
        throwsA(isA<MayaCredentialStoreException>()),
      );
      await expectLater(
        store.read(providerId: 'openai'),
        throwsA(isA<MayaCredentialStoreException>()),
      );
      await expectLater(
        store.delete(providerId: 'openai'),
        throwsA(isA<MayaCredentialStoreException>()),
      );
    },
  );

  test('target is deterministic and provider ids are canonical', () {
    expect(
      mayaCredentialTargetForProvider('openai'),
      'app.yomu/maya/provider/openai',
    );
    expect(
      () => mayaCredentialTargetForProvider('OpenAI'),
      throwsA(
        isA<MayaCredentialStoreException>().having(
          (error) => error.code,
          'code',
          MayaCredentialStoreErrorCode.invalidProviderId,
        ),
      ),
    );
    expect(
      () => mayaCredentialTargetForProvider('../openai'),
      throwsA(isA<MayaCredentialStoreException>()),
    );
  });

  test('fake save, read, replace and delete are idempotent', () async {
    final store = FakeMayaCredentialStore();

    expect(await store.read(providerId: 'openai'), isNull);
    await store.save(providerId: 'openai', apiKey: 'sk-first-value');
    expect(await store.read(providerId: 'openai'), 'sk-first-value');

    await store.save(providerId: 'openai', apiKey: 'sk-replacement');
    expect(await store.read(providerId: 'openai'), 'sk-replacement');

    await store.delete(providerId: 'openai');
    await store.delete(providerId: 'openai');
    expect(await store.read(providerId: 'openai'), isNull);
  });

  test('providers are isolated by deterministic target', () async {
    final store = FakeMayaCredentialStore();
    await store.save(providerId: 'openai', apiKey: 'sk-openai');
    await store.save(providerId: 'anthropic', apiKey: 'sk-anthropic');

    expect(await store.read(providerId: 'openai'), 'sk-openai');
    expect(await store.read(providerId: 'anthropic'), 'sk-anthropic');

    await store.delete(providerId: 'openai');
    expect(await store.read(providerId: 'openai'), isNull);
    expect(await store.read(providerId: 'anthropic'), 'sk-anthropic');
  });

  test('invalid API keys fail without echoing plaintext', () async {
    const plaintext = 'sk-do-not-echo-this-value';
    final store = FakeMayaCredentialStore();

    for (final invalid in <String>[
      '',
      '$plaintext\n',
      'key with spaces',
      'á-$plaintext',
      'x' * (kMayaCredentialMaxApiKeyBytes + 1),
    ]) {
      Object? failure;
      try {
        await store.save(providerId: 'openai', apiKey: invalid);
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<MayaCredentialStoreException>());
      expect('$failure', isNot(contains(plaintext)));
      expect(
        (failure! as MayaCredentialStoreException).code,
        MayaCredentialStoreErrorCode.invalidApiKey,
      );
    }
  });

  test('all public errors have bounded sanitized text', () {
    for (final code in MayaCredentialStoreErrorCode.values) {
      final text = '${MayaCredentialStoreException(code)}';
      expect(text, isNotEmpty);
      expect(text.length, lessThan(120));
      expect(text, isNot(contains('sk-')));
      expect(text, isNot(contains('Win32')));
    }
  });
}
