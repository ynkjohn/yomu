import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';

void main() {
  final enabled = Platform.environment['YOMU_RUN_LIVE_ENGINE_TEST'] == '1';

  test(
    'pinned engine starts, reattaches, shuts down and reopens',
    () async {
      final root = await Directory.systemTemp.createTemp('yomu-r7-live-');
      final manifest = await VendorManifest.load(
        VendorManifest.resolveRuntimeFile(),
      );
      ReadingEngineSupervisor? primary;
      SuwayomiProcessManager? observer;
      ReadingEngineSupervisor? reopened;
      var safeToDelete = false;

      try {
        final paths = SuwayomiPaths(root);
        await paths.ensureLayout();
        final primaryManager = _manager(paths, manifest);
        final liveProbe = SuwayomiCompatibilityProbe(
          client: primaryManager.createClient(),
          manifest: manifest,
          artifact: paths.jarFile(manifest.suwayomi.jarFile),
        );
        primary = _supervisor(primaryManager, paths, manifest);

        final first = primary.ensureStarted();
        final concurrent = primary.ensureStarted();
        expect(identical(first, concurrent), isTrue);
        final ready = await first;
        if (!ready.isReady) {
          final observed = await liveProbe.run();
          final rawProbe = await _rawSchemaProbe();
          fail(
            'supervisor=${ready.failure?.code}; '
            'probe=${observed.failure?.code}; $rawProbe',
          );
        }
        expect(
          primary.diagnostics.compatibility,
          EngineCompatibilityStatus.compatible,
        );
        expect(primary.diagnostics.ownership, EngineOwnershipStatus.owned);
        final firstPid = primary.diagnostics.processId;
        expect(firstPid, isNotNull);

        final compatibility = await liveProbe.run();
        expect(compatibility.compatible, isTrue);
        expect(compatibility.protocolVersion, 'v1');
        expect(compatibility.capabilities, contains('downloads'));

        final observerManager = _manager(paths, manifest);
        observer = observerManager;
        final reattached = await observerManager.start(
          readyTimeout: const Duration(seconds: 30),
        );
        reattached.when(
          ok: (status) => expect(status.pid, firstPid),
          err: (message, _) => fail('reattach failed: $message'),
        );
        expect(observerManager.identity?.pid, firstPid);

        await primary.shutdown();
        primary = null;
        await observerManager.shutdown();
        await observerManager.closeAfterShutdown();
        observer = null;
        await _expectPortClosed();

        final reopenedManager = _manager(paths, manifest);
        final reopenedSupervisor = _supervisor(
          reopenedManager,
          paths,
          manifest,
        );
        reopened = reopenedSupervisor;
        final reopenedReady = await reopenedSupervisor.ensureStarted();
        expect(reopenedReady.state, EngineReadinessState.ready);
        expect(
          reopenedSupervisor.diagnostics.ownership,
          EngineOwnershipStatus.owned,
        );
        await reopenedSupervisor.shutdown();
        reopened = null;
        await _expectPortClosed();
        safeToDelete = true;
      } finally {
        if (primary != null) await primary.shutdown();
        if (reopened != null) await reopened.shutdown();
        if (observer != null) {
          await observer.shutdown();
          await observer.closeAfterShutdown();
        }
        if (safeToDelete && root.existsSync()) {
          await root.delete(recursive: true);
        }
      }
    },
    skip: enabled ? false : 'live engine proof is opt-in',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

SuwayomiProcessManager _manager(SuwayomiPaths paths, VendorManifest manifest) =>
    SuwayomiProcessManager(
      paths: paths,
      manifest: manifest,
      javaResolver: const JavaResolver(mode: JavaResolutionMode.development),
      allowArtifactDownload: false,
      packagedArtifactsOnly: false,
      host: '127.0.0.1',
      port: kYomuSuwayomiPort,
    );

ReadingEngineSupervisor _supervisor(
  SuwayomiProcessManager manager,
  SuwayomiPaths paths,
  VendorManifest manifest,
) => ReadingEngineSupervisor(
  process: SuwayomiManagedReadingEngineProcess(
    manager: manager,
    probe: SuwayomiCompatibilityProbe(
      client: manager.createClient(),
      manifest: manifest,
      artifact: paths.jarFile(manifest.suwayomi.jarFile),
    ),
  ),
);

Future<void> _expectPortClosed() async {
  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      kYomuSuwayomiPort,
      timeout: const Duration(seconds: 1),
    );
    socket.destroy();
    fail('engine port remained open after owned shutdown');
  } on SocketException {
    // Expected: no listener remains on the fixed loopback port.
  }
}

Future<String> _rawSchemaProbe() async {
  try {
    Future<String> probe(String rootName) async {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:$kYomuSuwayomiPort/api/graphql'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'query':
              '''
            query YomuRawCompatibilityProbe {
              __schema {
                $rootName { fields { name } }
              }
            }
          ''',
        }),
      );
      final body = response.body.length > 2000
          ? '${response.body.substring(0, 2000)}...'
          : response.body;
      return 'status=${response.statusCode},body=$body';
    }

    return 'rawQuery=${await probe('queryType')}; '
        'rawMutation=${await probe('mutationType')}';
  } catch (error) {
    return 'rawProbeError=${error.runtimeType}';
  }
}
