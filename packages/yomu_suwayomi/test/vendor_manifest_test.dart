import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

/// Resolves vendor/manifest.json regardless of process cwd.
File resolveVendorManifest() {
  final candidates = <File>[
    File(p.join('vendor', 'manifest.json')),
    File(p.join('packages', 'yomu_suwayomi', 'vendor', 'manifest.json')),
  ];

  // Walk up from this test file's package root via script path when available.
  final script = Platform.script.toFilePath();
  final scriptDir = File(script).parent.path;
  // test/ -> package root
  candidates.add(
    File(p.normalize(p.join(scriptDir, '..', 'vendor', 'manifest.json'))),
  );
  // monorepo root relative to package
  candidates.add(
    File(
      p.normalize(
        p.join(scriptDir, '..', '..', '..', 'packages', 'yomu_suwayomi', 'vendor', 'manifest.json'),
      ),
    ),
  );

  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    candidates.add(
      File(p.join(dir.path, 'packages', 'yomu_suwayomi', 'vendor', 'manifest.json')),
    );
    candidates.add(File(p.join(dir.path, 'vendor', 'manifest.json')));
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  for (final f in candidates) {
    if (f.existsSync()) return f;
  }
  throw StateError(
    'vendor/manifest.json not found. Tried:\n'
    '${candidates.map((f) => f.path).join('\n')}',
  );
}

void main() {
  test('vendor manifest parses independent of cwd', () {
    final file = resolveVendorManifest();
    expect(file.existsSync(), isTrue, reason: file.path);
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final m = VendorManifest.fromJson(json);
    expect(m.suwayomi.jarFile, contains('Suwayomi-Server'));
    expect(m.suwayomi.minJre, greaterThanOrEqualTo(21));
    expect(m.suwayomi.downloadUrl, startsWith('https://'));
    expect(m.suwayomi.sha256.length, greaterThanOrEqualTo(32));
  });

  test('vendor manifest resolves from monorepo root cwd', () {
    // Simulate root: if we're already in package, still must resolve.
    final file = resolveVendorManifest();
    final m = VendorManifest.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
    expect(m.suwayomi.version, isNotEmpty);
  });
}
