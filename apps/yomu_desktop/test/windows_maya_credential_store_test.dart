import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_desktop/services/windows_maya_credential_store.dart';

void main() {
  test(
    'Windows Credential Manager round-trip replaces and deletes safely',
    () async {
      final store = WindowsMayaCredentialStore();
      final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
      final providerId = 'test-${pid.toRadixString(16)}-$suffix';
      final first = 'sk-test-first-$suffix';
      final replacement = 'sk-test-replacement-$suffix';
      final binding = 'a' * 64;
      final otherBinding = 'b' * 64;

      try {
        await store.delete(providerId: providerId);
        expect(await store.read(providerId: providerId), isNull);
        expect(await store.exists(providerId: providerId), isFalse);

        await store.save(providerId: providerId, apiKey: first);
        expect(await store.read(providerId: providerId), first);

        await store.save(providerId: providerId, apiKey: replacement);
        expect(await store.read(providerId: providerId), replacement);

        await store.save(
          providerId: providerId,
          apiKey: replacement,
          credentialBinding: binding,
        );
        expect(await store.exists(providerId: providerId), isTrue);
        expect(
          await store.read(providerId: providerId, credentialBinding: binding),
          replacement,
        );
        expect(
          await store.read(
            providerId: providerId,
            credentialBinding: otherBinding,
          ),
          isNull,
        );

        await store.delete(providerId: providerId);
        await store.delete(providerId: providerId);
        expect(await store.read(providerId: providerId), isNull);
        expect(await store.exists(providerId: providerId), isFalse);
      } catch (error) {
        expect('$error', isNot(contains(first)));
        expect('$error', isNot(contains(replacement)));
        rethrow;
      } finally {
        await store.delete(providerId: providerId);
      }
    },
    skip: !Platform.isWindows || !WindowsMayaCredentialStore.isSupported,
  );
}
