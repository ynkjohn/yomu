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

      try {
        await store.delete(providerId: providerId);
        expect(await store.read(providerId: providerId), isNull);

        await store.save(providerId: providerId, apiKey: first);
        expect(await store.read(providerId: providerId), first);

        await store.save(providerId: providerId, apiKey: replacement);
        expect(await store.read(providerId: providerId), replacement);

        await store.delete(providerId: providerId);
        await store.delete(providerId: providerId);
        expect(await store.read(providerId: providerId), isNull);
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
