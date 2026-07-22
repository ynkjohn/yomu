import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_local_server/yomu_local_server.dart';
import 'package:yomu_storage/yomu_storage.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

import '../screens/downloads_screen.dart';
import '../screens/explore_screen.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/manga_detail_screen.dart';
import '../screens/maya_screen.dart';
import '../screens/placeholder_screen.dart';
import '../screens/reader_screen.dart';
import '../screens/server_screen.dart';
import '../services/maya_credential_store.dart';
import '../services/maya_provider_adapters.dart';
import '../services/maya_provider_controller.dart';
import '../services/windows_maya_credential_store.dart';
import '../services/windows_window_chrome.dart';
import 'desktop_lifecycle.dart';

Color _motorStateColor(EngineReadinessState state) => switch (state) {
  EngineReadinessState.ready => YomuTokens.success,
  EngineReadinessState.initializing ||
  EngineReadinessState.starting ||
  EngineReadinessState.recovering ||
  EngineReadinessState.shuttingDown => YomuTokens.warning,
  EngineReadinessState.temporarilyUnavailable ||
  EngineReadinessState.actionRequired => YomuTokens.danger,
};

@visibleForTesting
({String label, Color color}) deriveYomuCoreStatus({
  required int? boundPort,
  required EngineReadinessSnapshot readiness,
}) {
  if (boundPort == null) {
    return (
      label: 'Yomu Core indisponível · Motor ${readiness.state.name}',
      color: YomuTokens.danger,
    );
  }
  if (readiness.isReady) {
    return (label: 'Yomu Core ativo · :$boundPort', color: YomuTokens.success);
  }
  return (
    label: 'Yomu Core ativo · :$boundPort · Motor ${readiness.state.name}',
    color: _motorStateColor(readiness.state),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  static const _nav = <YomuNavItem>[
    YomuNavItem(id: 'home', label: 'Home', icon: YomuIcons.home),
    YomuNavItem(id: 'library', label: 'Biblioteca', icon: YomuIcons.library),
    YomuNavItem(id: 'updates', label: 'Novidades', icon: YomuIcons.updates),
    YomuNavItem(id: 'history', label: 'Histórico', icon: YomuIcons.history),
    YomuNavItem(id: 'explore', label: 'Explorar', icon: YomuIcons.explore),
    YomuNavItem(id: 'maya', label: 'Maya', icon: YomuIcons.maya),
    YomuNavItem(id: 'downloads', label: 'Downloads', icon: YomuIcons.download),
    YomuNavItem(
      id: 'settings',
      label: 'Configurações',
      icon: YomuIcons.settings,
      group: YomuNavGroup.system,
    ),
    YomuNavItem(
      id: 'server',
      label: 'Servidor e Motor',
      icon: YomuIcons.server,
      group: YomuNavGroup.system,
    ),
    YomuNavItem(
      id: 'backup',
      label: 'Backup',
      icon: YomuIcons.backup,
      group: YomuNavGroup.system,
    ),
    YomuNavItem(
      id: 'diag',
      label: 'Diagnóstico',
      icon: YomuIcons.diagnostics,
      group: YomuNavGroup.system,
    ),
  ];

  String _selected = 'home';

  /// Sole P0 storage instance — opened before Auth/Maya/Core/Suwayomi.
  YomuDatabase? _db;
  SuwayomiProcessManager? _manager;
  SuwayomiLibraryAdapter? _libraryAdapter;
  LibraryGateway? _libraryGateway;
  SuwayomiCoreAdapter? _coreAdapter;
  MangaDetailsGateway? _mangaDetailsGateway;
  SuwayomiDownloadsAdapter? _downloadsAdapter;
  DownloadsGateway? _downloadsGateway;
  ExtensionsGateway? _extensionsGateway;
  EngineMutationGate? _mutationGate;
  ReadingEngineSupervisor? _engineLifecycle;
  ReadingProgressCoordinator? _progressCoordinator;
  YomuServer? _yomuServer;
  DeviceAuthStore? _auth;
  MayaService? _maya;
  MayaProviderController? _mayaProvider;
  String? _mayaUnavailableReason;
  Directory? _pwaDir;
  String? _bootstrapError;
  bool _bootstrapping = true;
  bool _busyEngine = false;
  bool _busyHttp = false;
  bool _busyAuth = false;
  bool _lanEnabled = false;
  String? _pairingCode;
  DateTime? _pairingExpiresAt;
  List<String> _lanAddresses = const [];
  StreamSubscription<EngineReadinessSnapshot>? _readinessSub;

  /// Serializes bootstrap / HTTP restart / shutdown (shared queue).
  final DesktopLifecycleQueue _lifecycle = DesktopLifecycleQueue();
  late final DesktopExitCoordinator _exitCoordinator;

  bool get _engineReady => _readingEngineReadiness.isReady;

  EngineReadinessSnapshot get _readingEngineReadiness =>
      _engineLifecycle?.current ??
      const EngineReadinessSnapshot(state: EngineReadinessState.initializing);

  EngineDiagnosticsSnapshot? get _engineDiagnostics =>
      _engineLifecycle?.diagnostics;

  SuwayomiStatus get _technicalEngineStatus {
    final readiness = _readingEngineReadiness;
    final diagnostics = _engineDiagnostics;
    final state = switch (readiness.state) {
      EngineReadinessState.initializing => SuwayomiProcessState.stopped,
      EngineReadinessState.starting ||
      EngineReadinessState.recovering => SuwayomiProcessState.starting,
      EngineReadinessState.ready => SuwayomiProcessState.running,
      EngineReadinessState.temporarilyUnavailable =>
        SuwayomiProcessState.unhealthy,
      EngineReadinessState.actionRequired => SuwayomiProcessState.crashed,
      EngineReadinessState.shuttingDown => SuwayomiProcessState.stopping,
    };
    return SuwayomiStatus(
      state: state,
      version: diagnostics?.engineVersion,
      baseUrl: diagnostics?.host == null || diagnostics?.port == null
          ? null
          : 'http://${diagnostics!.host}:${diagnostics.port}',
      message: readiness.failure?.message,
      pid: diagnostics?.processId,
      lastHealthCheck: diagnostics?.lastHealthCheck,
    );
  }

  @override
  void initState() {
    super.initState();
    _exitCoordinator = DesktopExitCoordinator(
      confirmExit: _confirmExit,
      shutdown: _coordinatedShutdown,
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  @override
  Future<ui.AppExitResponse> didRequestAppExit() {
    return _exitCoordinator.requestExit();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(_coordinatedShutdown());
    }
  }

  Future<void> _bootstrap() {
    return _lifecycle.run(() async {
      if (_lifecycle.shuttingDown) return;
      await _teardownOwnedResources();
      YomuDatabase? db;
      DeviceAuthStore? auth;
      MayaService? maya;
      MayaStore? mayaStore;
      MayaProviderController? mayaProvider;
      SuwayomiProcessManager? manager;
      ReadingEngineSupervisor? supervisor;
      ReadingProgressCoordinator? progressCoordinator;
      SuwayomiDownloadsAdapter? downloadsAdapter;
      EngineMutationGate? mutationGate;
      YomuServer? server;
      StreamSubscription<EngineReadinessSnapshot>? readinessSub;
      String? mayaUnavailableReason;
      try {
        final appData = Platform.environment['APPDATA'];
        if (appData == null || appData.trim().isEmpty) {
          throw StateError('APPDATA não está disponível neste Windows.');
        }
        final support = Directory(p.join(appData, 'app.yomu', 'yomu_desktop'));
        final root = Directory(p.join(support.path, 'yomu'));
        await root.create(recursive: true);

        // Storage first — Auth/Core/Suwayomi only after open succeeds.
        await StorageFirstBootstrap.run(
          openStorage: () async {
            db = await YomuDatabase.open(root);
            if (!mounted || _lifecycle.shuttingDown) {
              await db?.close();
              db = null;
              throw _BootstrapAborted();
            }
            _db = db;
          },
          initializeAuth: () async {
            auth = await DeviceAuthStore.open(
              database: db!,
              legacyFile: File(p.join(root.path, 'device_sessions.json')),
            );
            if (!mounted || _lifecycle.shuttingDown) {
              await mayaProvider?.close();
              await _teardownResources(auth: auth, db: db);
              auth = null;
              db = null;
              _db = null;
              throw _BootstrapAborted();
            }
          },
          initializeOptionalMaya: () async {
            mayaStore = await MayaStore.open(
              database: db!,
              legacyFile: File(p.join(root.path, 'maya_chat.json')),
            );
            MayaCredentialStore credentialStore;
            try {
              credentialStore = WindowsMayaCredentialStore();
            } catch (_) {
              credentialStore = const UnavailableMayaCredentialStore();
            }
            mayaProvider = await OptionalMayaProviderBootstrap.openAbortable(
              initialize: () => MayaProviderController.open(
                database: db!,
                credentialStore: credentialStore,
                adapterFactory: createMayaProviderAdapterFactory(),
              ),
              shouldAbort: () => !mounted || _lifecycle.shuttingDown,
              dispose: (provider) => provider.close(),
            );
            if (!mounted || _lifecycle.shuttingDown) {
              await _teardownResources(auth: auth, db: db);
              mayaStore = null;
              mayaProvider = null;
              auth = null;
              db = null;
              _db = null;
              throw _BootstrapAborted();
            }
          },
          onMayaUnavailable: (_) {
            maya = null;
            mayaStore = null;
            mayaUnavailableReason = _mayaLegacyMigrationBlockedMessage;
          },
          startRemainingServices: () async {
            final paths = SuwayomiPaths(root);
            await paths.ensureLayout();

            final packagedRuntime = kReleaseMode || kProfileMode;
            final manifest = await VendorManifest.loadForRuntime(
              packagedOnly: packagedRuntime,
            );

            manager = SuwayomiProcessManager(
              paths: paths,
              manifest: manifest,
              javaResolver: JavaResolver(
                mode: packagedRuntime
                    ? JavaResolutionMode.packagedOnly
                    : JavaResolutionMode.development,
              ),
              allowArtifactDownload: !packagedRuntime,
              packagedArtifactsOnly: packagedRuntime,
              host: '127.0.0.1',
              port: kYomuSuwayomiPort,
            );

            final listenedManager = manager!;
            final readingApi = SuwayomiApi(listenedManager.createClient());
            mutationGate = EngineMutationGate();
            final libraryAdapter = SuwayomiLibraryAdapter(readingApi);
            final libraryGateway = GuardedLibraryGateway(
              delegate: libraryAdapter,
              gate: mutationGate!,
            );
            final safeExternalMedia = SafeHttpFetch();
            final coreAdapter = SuwayomiCoreAdapter(
              readingApi,
              safeExternalMediaFetch: (uri, {required maxBytes}) async {
                final result = await safeExternalMedia.get(uri);
                if (result.body.length > maxBytes) {
                  throw StateError('body_too_large');
                }
                return MediaPayload(
                  bytes: result.body,
                  contentType: result.contentType,
                  statusCode: result.statusCode,
                );
              },
            );
            progressCoordinator = ReadingProgressCoordinator(coreAdapter);
            downloadsAdapter = SuwayomiDownloadsAdapter(readingApi);
            final mangaDetailsGateway = GuardedMangaDetailsGateway(
              delegate: coreAdapter,
              gate: mutationGate!,
            );
            final downloadsGateway = GuardedDownloadsGateway(
              delegate: downloadsAdapter!,
              gate: mutationGate!,
            );
            final extensionsAdapter = SuwayomiExtensionsAdapter(readingApi);
            final extensionsGateway = GuardedExtensionsGateway(
              delegate: extensionsAdapter,
              gate: mutationGate!,
            );
            final compatibilityProbe = SuwayomiCompatibilityProbe(
              client: listenedManager.createClient(),
              manifest: manifest,
              artifact: paths.jarFile(manifest.suwayomi.jarFile),
            );
            supervisor = ReadingEngineSupervisor(
              process: SuwayomiManagedReadingEngineProcess(
                manager: listenedManager,
                probe: compatibilityProbe,
              ),
            );
            final store = mayaStore;
            if (store != null) {
              maya = MayaService(
                store: store,
                libraryPort: ReadingEngineMayaPort(
                  library: libraryAdapter,
                  downloads: downloadsAdapter!,
                ),
                llm: mayaProvider,
                mutationGate: mutationGate,
              );
            }

            final pwaDir = await _resolvePwaDir();
            server = _buildYomuServer(
              auth: auth!,
              pwaDir: pwaDir,
              lanEnabled: false,
              lanAddresses: const [],
              libraryAdapter: libraryAdapter,
              coreAdapter: coreAdapter,
              progressCoordinator: progressCoordinator!,
              engineReadiness: supervisor!,
            );
            await server!.start();

            final listenedSupervisor = supervisor!;
            readinessSub = listenedSupervisor.changes.listen((_) {
              if (!mounted || _lifecycle.shuttingDown) return;
              setState(() {});
            });

            if (!mounted || _lifecycle.shuttingDown) {
              await _teardownResources(
                readinessSub: readinessSub,
                server: server,
                maya: maya,
                auth: auth,
                supervisor: supervisor,
                progressCoordinator: progressCoordinator,
                downloads: downloadsAdapter,
                mutationGate: mutationGate,
                manager: manager,
                db: db,
              );
              db = null;
              auth = null;
              manager = null;
              server = null;
              readinessSub = null;
              supervisor = null;
              progressCoordinator = null;
              downloadsAdapter = null;
              mutationGate = null;
              maya = null;
              throw _BootstrapAborted();
            }

            final liveManager = manager!;
            final liveSupervisor = supervisor!;
            final liveServer = server!;
            final liveSub = readinessSub!;
            final liveDb = db!;
            final liveAuth = auth!;
            final liveMaya = maya;
            final liveMayaProvider = mayaProvider;
            final liveMayaUnavailableReason = mayaUnavailableReason;
            _readinessSub = liveSub;
            _manager = liveManager;
            _engineLifecycle = liveSupervisor;
            _yomuServer = liveServer;
            _db = liveDb;
            _auth = liveAuth;
            auth = null;
            setState(() {
              _libraryAdapter = libraryAdapter;
              _libraryGateway = libraryGateway;
              _coreAdapter = coreAdapter;
              _mangaDetailsGateway = mangaDetailsGateway;
              _downloadsAdapter = downloadsAdapter;
              _downloadsGateway = downloadsGateway;
              _extensionsGateway = extensionsGateway;
              _mutationGate = mutationGate;
              _progressCoordinator = progressCoordinator;
              _maya = liveMaya;
              _mayaProvider = liveMayaProvider;
              _mayaUnavailableReason = liveMayaUnavailableReason;
              _pwaDir = pwaDir;
              _lanEnabled = false;
              _bootstrapping = false;
              _bootstrapError = null;
            });
            db = null;
            manager = null;
            supervisor = null;
            server = null;
            readinessSub = null;
            progressCoordinator = null;
            downloadsAdapter = null;
            mutationGate = null;
            maya = null;
            mayaProvider = null;
            // UI and Yomu Core are already available; engine startup continues
            // independently under the single supervisor readiness.
            unawaited(liveSupervisor.ensureStarted());
          },
        );
      } on _BootstrapAborted {
        // Clean abort (unmount/shutdown) — resources already handled.
      } catch (e) {
        if (maya == null) {
          await mayaProvider?.close();
        }
        await _teardownResources(
          readinessSub: readinessSub ?? _readinessSub,
          server: server ?? _yomuServer,
          maya: maya ?? _maya,
          auth: auth ?? _auth,
          supervisor: supervisor ?? _engineLifecycle,
          progressCoordinator: progressCoordinator ?? _progressCoordinator,
          downloads: downloadsAdapter ?? _downloadsAdapter,
          mutationGate: mutationGate ?? _mutationGate,
          manager: manager ?? _manager,
          db: db ?? _db ?? YomuDatabase.instance,
        );
        _readinessSub = null;
        _yomuServer = null;
        _manager = null;
        _db = null;
        _auth = null;
        _maya = null;
        _mayaProvider = null;
        _mayaUnavailableReason = null;
        _libraryAdapter = null;
        _libraryGateway = null;
        _coreAdapter = null;
        _mangaDetailsGateway = null;
        _downloadsAdapter = null;
        _downloadsGateway = null;
        _extensionsGateway = null;
        _mutationGate = null;
        _engineLifecycle = null;
        _progressCoordinator = null;
        if (!mounted) return;
        final msg = e is YomuAlreadyRunningException
            ? e.toString()
            : e.toString();
        setState(() {
          _bootstrapError = msg;
          _bootstrapping = false;
        });
      }
    });
  }

  /// Blocks mutations, drains admitted work, then stops Core, owned engine and DB.
  Future<void> _teardownResources({
    StreamSubscription<EngineReadinessSnapshot>? readinessSub,
    YomuServer? server,
    MayaService? maya,
    DeviceAuthStore? auth,
    ReadingEngineSupervisor? supervisor,
    ReadingProgressCoordinator? progressCoordinator,
    DownloadsGateway? downloads,
    EngineMutationGate? mutationGate,
    SuwayomiProcessManager? manager,
    YomuDatabase? db,
  }) {
    return ResourceTeardown.run(
      beginShutdown: () async {
        DesktopShutdownAdmission.stopAccepting(
          engineMutations: mutationGate,
          maya: maya,
          beginCoreShutdown: server?.beginShutdown,
          stopProgressWrites: progressCoordinator?.stopAccepting,
          beginEngineShutdown: supervisor?.beginShutdown,
        );
      },
      cancelSubscription: () async {
        await readinessSub?.cancel();
      },
      flushFinalProgress: () async {
        await progressCoordinator?.flushRegisteredFinalSaves();
      },
      sealFinalProgress: () async {
        progressCoordinator?.sealFinalSaves();
      },
      drainProgress: () async {
        await progressCoordinator?.drain(timeout: const Duration(seconds: 10));
      },
      drainRequests: () async {
        return await server?.drain(timeout: const Duration(seconds: 10)) ==
            YomuServerDrainResult.timedOut;
      },
      sealAdmittedProgress: () async {
        progressCoordinator?.sealAdmittedWrites();
      },
      pauseDownloads: () async {
        await downloads?.pauseAndAwaitAck(timeout: const Duration(seconds: 10));
      },
      stopServer: ({required bool force}) async {
        await server?.stop(force: force);
      },
      closeServer: () async {
        server?.close();
      },
      closeMaya: () async {
        await maya?.close();
      },
      closeAuth: () async {
        await auth?.close();
      },
      shutdownEngine: supervisor == null
          ? null
          : () async {
              await supervisor.shutdown();
            },
      disposeManager: () async {
        await manager?.dispose();
      },
      closeDb: () async {
        if (db != null) await db.close();
      },
    );
  }

  Future<void> _teardownOwnedResources() async {
    final sub = _readinessSub;
    final server = _yomuServer;
    final maya = _maya;
    final auth = _auth;
    final manager = _manager;
    final supervisor = _engineLifecycle;
    final progressCoordinator = _progressCoordinator;
    final downloads = _downloadsAdapter;
    final mutationGate = _mutationGate;
    final db = _db ?? YomuDatabase.instance;
    await _teardownResources(
      readinessSub: sub,
      server: server,
      maya: maya,
      auth: auth,
      supervisor: supervisor,
      progressCoordinator: progressCoordinator,
      downloads: downloads,
      mutationGate: mutationGate,
      manager: manager,
      db: db,
    );
    _readinessSub = null;
    _yomuServer = null;
    _maya = null;
    _mayaProvider = null;
    _mayaUnavailableReason = null;
    _auth = null;
    _manager = null;
    _libraryAdapter = null;
    _libraryGateway = null;
    _coreAdapter = null;
    _mangaDetailsGateway = null;
    _downloadsAdapter = null;
    _downloadsGateway = null;
    _extensionsGateway = null;
    _mutationGate = null;
    _engineLifecycle = null;
    _progressCoordinator = null;
    _db = null;
  }

  YomuServer _buildYomuServer({
    required DeviceAuthStore auth,
    required Directory? pwaDir,
    required bool lanEnabled,
    required List<String> lanAddresses,
    required SuwayomiLibraryAdapter libraryAdapter,
    required SuwayomiCoreAdapter coreAdapter,
    required ReadingProgressCoordinator progressCoordinator,
    required EngineReadiness engineReadiness,
  }) {
    final port = 8787;
    final origins = lanEnabled
        ? lanAddresses.map((ip) => 'http://$ip:$port').toList()
        : <String>[];
    return YomuServer(
      host: lanEnabled ? '0.0.0.0' : '127.0.0.1',
      port: port,
      pwaDir: pwaDir,
      allowLanCors: lanEnabled,
      allowedOrigins: origins,
      auth: auth,
      engineReadiness: engineReadiness,
      library: libraryAdapter,
      mangaDetails: coreAdapter,
      reader: coreAdapter,
      progress: progressCoordinator,
      catalog: coreAdapter,
      media: coreAdapter,
    );
  }

  Future<void> _restartYomuHttp({required bool lanEnabled}) {
    // Same lifecycle queue as bootstrap/shutdown — shutdown waits for this.
    return _lifecycle.run(() async {
      if (_lifecycle.shuttingDown) return;
      final manager = _manager;
      final auth = _auth;
      final libraryAdapter = _libraryAdapter;
      final coreAdapter = _coreAdapter;
      final progressCoordinator = _progressCoordinator;
      final engineReadiness = _engineLifecycle;
      if (manager == null ||
          auth == null ||
          libraryAdapter == null ||
          coreAdapter == null ||
          progressCoordinator == null ||
          engineReadiness == null) {
        return;
      }

      if (mounted) setState(() => _busyHttp = true);
      try {
        final addrs = lanEnabled ? await listLanIpv4Addresses() : <String>[];
        await HttpServerRestartCoordinator.replaceServer<YomuServer>(
          stopOld: () async {
            final old = _yomuServer;
            _yomuServer = null;
            if (old == null) return;
            try {
              await old.stop();
            } catch (_) {}
            try {
              old.close();
            } catch (_) {}
          },
          startNew: () async {
            final server = _buildYomuServer(
              auth: auth,
              pwaDir: _pwaDir,
              lanEnabled: lanEnabled,
              lanAddresses: addrs,
              libraryAdapter: libraryAdapter,
              coreAdapter: coreAdapter,
              progressCoordinator: progressCoordinator,
              engineReadiness: engineReadiness,
            );
            try {
              await server.start();
            } catch (_) {
              // start failed — never leave a dangling new server.
              try {
                await server.stop();
              } catch (_) {}
              try {
                server.close();
              } catch (_) {}
              rethrow;
            }
            return server;
          },
          disposeServer: (server) async {
            try {
              await server.stop();
            } catch (_) {}
            try {
              server.close();
            } catch (_) {}
          },
          shouldAbort: () => !mounted || _lifecycle.shuttingDown,
          commit: (server) {
            _yomuServer = server;
          },
        );
        if (!mounted || _lifecycle.shuttingDown) {
          if (mounted) setState(() => _busyHttp = false);
          return;
        }
        setState(() {
          _lanEnabled = lanEnabled;
          _lanAddresses = addrs;
          if (!lanEnabled) {
            _pairingCode = null;
            _pairingExpiresAt = null;
            auth.cancelPairing();
          }
          _busyHttp = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _busyHttp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao reiniciar HTTP Yomu: $e')),
        );
      }
    });
  }

  Future<void> _toggleLan(bool enabled) async {
    if (_lifecycle.shuttingDown) return;
    if (enabled) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Permitir acesso na LAN?'),
          content: const Text(
            'O Yomu Core passará a escutar em 0.0.0.0:8787 na rede local. '
            'O Suwayomi continua só em 127.0.0.1:14567.\n\n'
            'API autenticada por pareamento. Use só em Wi‑Fi de confiança.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ativar LAN'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _restartYomuHttp(lanEnabled: enabled);
  }

  void _startPairing() {
    if (_lifecycle.shuttingDown) return;
    final auth = _auth;
    if (auth == null) return;
    final code = auth.startPairing();
    setState(() {
      _pairingCode = code.code;
      _pairingExpiresAt = code.expiresAt;
    });
  }

  void _cancelPairing() {
    if (_lifecycle.shuttingDown) return;
    _auth?.cancelPairing();
    setState(() {
      _pairingCode = null;
      _pairingExpiresAt = null;
    });
  }

  Future<void> _revokeSession(String sessionId) async {
    final auth = _auth;
    if (auth == null) return;
    await _runAuthMutation(auth, () async {
      await auth.revoke(sessionId);
    });
  }

  Future<void> _revokeAllSessions() async {
    final auth = _auth;
    if (auth == null) return;
    await _runAuthMutation(auth, auth.revokeAll);
  }

  Future<void> _runAuthMutation(
    DeviceAuthStore auth,
    Future<void> Function() mutation,
  ) async {
    if (_busyAuth || _lifecycle.shuttingDown || !identical(_auth, auth)) {
      return;
    }
    if (mounted) setState(() => _busyAuth = true);
    try {
      await mutation();
    } on DeviceAuthException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha ao persistir a revogação.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyAuth = false);
    }
  }

  /// Prefer packaged `{exeDir}/pwa` (Release); fall back to monorepo only in dev.
  Future<Directory?> _resolvePwaDir() async {
    final candidates = <Directory>[];
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      candidates.add(Directory(p.join(exeDir, 'pwa')));
      candidates.add(Directory(p.join(exeDir, 'data', 'pwa')));
    } catch (_) {}
    // Dev fallbacks (flutter run from monorepo)
    candidates.addAll([
      Directory(
        p.normalize(
          p.join(Directory.current.path, 'apps', 'yomu_mobile_pwa', 'dist'),
        ),
      ),
      Directory(
        p.normalize(p.join(Directory.current.path, 'apps', 'yomu_mobile_pwa')),
      ),
      Directory(
        p.normalize(p.join(Directory.current.path, '..', 'yomu_mobile_pwa')),
      ),
      Directory(
        p.normalize(
          p.join(Directory.current.path, '..', '..', 'apps', 'yomu_mobile_pwa'),
        ),
      ),
    ]);
    for (final d in candidates) {
      if (File(p.join(d.path, 'index.html')).existsSync()) return d;
    }
    return null;
  }

  /// Idempotent shutdown: waits for in-flight bootstrap/restart, then tears down.
  Future<void> _coordinatedShutdown() {
    return _lifecycle.shutdown(
      _teardownOwnedResources,
      beginShutdown: () {
        DesktopShutdownAdmission.stopAccepting(
          engineMutations: _mutationGate,
          maya: _maya,
          beginCoreShutdown: _yomuServer?.beginShutdown,
          stopProgressWrites: _progressCoordinator?.stopAccepting,
          beginEngineShutdown: _engineLifecycle?.beginShutdown,
        );
      },
    );
  }

  Future<bool> _confirmExit() async {
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('yomu-exit-dialog'),
        title: const Text('Fechar o Yomu?'),
        content: Text(
          _lanEnabled
              ? 'O Yomu drenará as leituras e downloads ativos antes de sair. '
                    'A PWA na rede local ficará indisponível.'
              : 'O Yomu drenará as leituras e downloads ativos antes de '
                    'encerrar o Core e o motor interno.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('yomu-exit-cancel'),
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('yomu-exit-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: YomuTokens.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Fechar Yomu'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Shared Future with detached — no duplicated teardown.
    unawaited(_coordinatedShutdown());
    super.dispose();
  }

  Future<void> _startSuwayomi() async {
    final lifecycle = _engineLifecycle;
    if (lifecycle == null || _lifecycle.shuttingDown) return;
    setState(() => _busyEngine = true);
    final result = await lifecycle.retry();
    if (!mounted) return;
    setState(() => _busyEngine = false);
    final failure = result.failure;
    if (failure != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _stopSuwayomi() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'O motor interno é gerenciado automaticamente pelo Yomu.',
        ),
      ),
    );
  }

  Future<void> _restartSuwayomi() => _startSuwayomi();

  Future<void> _openLibraryManga(LibraryManga manga) async {
    await _openMangaDetails(manga.id);
  }

  Future<void> _continueLibraryManga(LibraryManga manga) async {
    final core = _coreAdapter;
    if (core == null || !_engineReady || _lifecycle.shuttingDown) {
      throw _readingUnavailableException;
    }
    final last = manga.lastReadChapter;
    if (last == null) {
      await _openLibraryManga(manga);
      return;
    }
    try {
      final chapters = await core.listChapters(manga.id);
      final matches = chapters.where((chapter) => chapter.id == last.id);
      final chapter = matches.isEmpty
          ? ReadingChapter(
              id: last.id,
              name: last.name,
              lastPageRead: last.lastPageRead,
              pageCount: last.pageCount,
              mangaId: manga.id,
            )
          : matches.first;
      await _openReadingChapter(
        mangaId: manga.id,
        mangaTitle: manga.title,
        chapter: chapter,
        chapters: chapters.isEmpty ? [chapter] : chapters,
        openSettings: false,
      );
    } catch (_) {
      throw const EngineException(
        EngineFailure(
          kind: EngineFailureKind.temporarilyUnavailable,
          code: 'engine_reader_unavailable',
          message: 'Não foi possível continuar a leitura.',
          retryable: true,
        ),
      );
    }
  }

  Future<void> _openMangaDetails(int mangaId) async {
    final core = _coreAdapter;
    final details = _mangaDetailsGateway;
    final downloads = _downloadsGateway;
    if (core == null ||
        details == null ||
        downloads == null ||
        !_engineReady ||
        _lifecycle.shuttingDown) {
      throw _readingUnavailableException;
    }
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MangaDetailScreen(
            details: details,
            reader: core,
            catalog: core,
            media: core,
            downloads: downloads,
            mangaId: mangaId,
            onOpenChapter: _openReadingChapter,
          ),
        ),
      );
    } catch (error) {
      if (error is EngineException) rethrow;
      throw const EngineException(
        EngineFailure(
          kind: EngineFailureKind.temporarilyUnavailable,
          code: 'engine_manga_unavailable',
          message: 'Não foi possível abrir este título.',
          retryable: true,
        ),
      );
    }
  }

  Future<void> _openReadingChapter({
    required int mangaId,
    required String mangaTitle,
    required ReadingChapter chapter,
    required List<ReadingChapter> chapters,
    required bool openSettings,
  }) async {
    final reader = _coreAdapter;
    final progress = _progressCoordinator;
    if (reader == null ||
        progress == null ||
        !_engineReady ||
        _lifecycle.shuttingDown) {
      throw _readingUnavailableException;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          reader: reader,
          progress: progress,
          media: reader,
          mangaId: mangaId,
          mangaTitle: mangaTitle,
          chapter: chapter,
          chapters: chapters,
          openSettingsOnStart: openSettings,
        ),
      ),
    );
  }

  Widget _body() {
    if (_bootstrapping) {
      return const AsyncBody(isLoading: true, child: SizedBox.shrink());
    }
    if (_bootstrapError != null) {
      return AsyncBody(
        isLoading: false,
        error: _bootstrapError,
        onRetry: () {
          setState(() {
            _bootstrapping = true;
            _bootstrapError = null;
          });
          unawaited(_bootstrap());
        },
        child: const SizedBox.shrink(),
      );
    }

    // Refresh expired pairing display.
    final pairing = _auth?.activePairing;
    final displayCode = pairing?.code ?? _pairingCode;
    final displayExpiry = pairing?.expiresAt ?? _pairingExpiresAt;
    if (pairing == null && _pairingCode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _auth?.activePairing == null && _pairingCode != null) {
          setState(() {
            _pairingCode = null;
            _pairingExpiresAt = null;
          });
        }
      });
    }

    return switch (_selected) {
      'home' => HomeScreen(
        library: _libraryGateway,
        media: _libraryAdapter,
        engineReady: _engineReady,
        onNavigate: (id) => setState(() => _selected = id),
        onOpenManga: _openLibraryManga,
        onContinueReading: _continueLibraryManga,
      ),
      'server' => ServerScreen(
        status: _technicalEngineStatus,
        yomuPort: _yomuServer?.boundPort ?? 8787,
        managedRootDir: _engineDiagnostics?.dataRoot ?? '—',
        aboutVersion: _engineDiagnostics?.engineVersion,
        busy: _busyEngine || _busyHttp || _busyAuth,
        lanEnabled: _lanEnabled,
        onToggleLan: (v) => unawaited(_toggleLan(v)),
        pairingCode: displayCode,
        pairingExpiresAt: displayExpiry,
        onStartPairing: _startPairing,
        onCancelPairing: _cancelPairing,
        lanAddresses: _lanAddresses,
        sessionCount: _auth?.sessions.length ?? 0,
        sessions: (_auth?.sessions ?? [])
            .map(
              (s) => PairedSessionRow(
                sessionId: s.sessionId,
                deviceName: s.deviceName,
                createdAt: s.createdAt,
                lastSeenAt: s.lastSeenAt,
              ),
            )
            .toList(),
        onRevokeSession: _revokeSession,
        onRevokeAllSessions: _revokeAllSessions,
        onStart: () => unawaited(_startSuwayomi()),
        onStop: () => unawaited(_stopSuwayomi()),
        onRestart: () => unawaited(_restartSuwayomi()),
        onHealthCheck: () async {
          final lifecycle = _engineLifecycle;
          if (lifecycle == null || _lifecycle.shuttingDown) return;
          if (_engineReady) {
            await lifecycle.checkNow();
          } else {
            await lifecycle.retry();
          }
          if (mounted && !_lifecycle.shuttingDown) setState(() {});
        },
      ),
      'explore' => ExploreScreen(
        catalog: _coreAdapter,
        extensions: _extensionsGateway,
        media: _coreAdapter,
        engineReady: _engineReady,
        onOpenManga: _openMangaDetails,
      ),
      'library' => LibraryScreen(
        library: _libraryGateway,
        media: _libraryAdapter,
        readiness: _readingEngineReadiness,
        onOpenManga: _openLibraryManga,
        onContinueReading: _continueLibraryManga,
      ),
      'downloads' => DownloadsScreen(
        downloads: _downloadsGateway,
        engineReady: _engineReady,
      ),
      'maya' => MayaScreen(
        service: _maya,
        engineReady: _engineReady,
        providerController: _mayaProvider,
        unavailableReason: _mayaUnavailableReason,
        onOpenManga: (id, title) {
          unawaited(_openMangaDetails(id));
        },
      ),
      _ => PlaceholderScreen(
        title: _nav.firstWhere((e) => e.id == _selected).label,
        phase: _selected == 'updates'
            ? 'A verificacao real de novidades sera conectada em uma fase posterior.'
            : _selected == 'history'
            ? 'O historico persistente sera conectado em uma fase posterior.'
            : _selected == 'backup'
            ? 'Backup e restauracao serao conectados em uma fase posterior.'
            : _selected == 'diag'
            ? 'A coleta e exportacao de diagnostico serao conectadas em uma fase posterior.'
            : 'Destino preservado conforme o design_prod.',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final coreStatus = deriveYomuCoreStatus(
      boundPort: _yomuServer?.boundPort,
      readiness: _readingEngineReadiness,
    );
    return YomuAppShell(
      items: _nav,
      selectedId: _selected,
      onSelect: (id) => setState(() => _selected = id),
      serverLabel: coreStatus.label,
      serverColor: coreStatus.color,
      onServerTap: () => setState(() => _selected = 'server'),
      onWindowDrag: () => unawaited(WindowsWindowChrome.startDrag()),
      onWindowMinimize: () => unawaited(WindowsWindowChrome.minimize()),
      onWindowToggleMaximize: () =>
          unawaited(WindowsWindowChrome.toggleMaximize()),
      onWindowClose: () => unawaited(WindowsWindowChrome.close()),
      onWindowResize: (edge) =>
          unawaited(WindowsWindowChrome.startResize(edge.name)),
      body: _body(),
    );
  }
}

const _mayaLegacyMigrationBlockedMessage =
    'A migração do histórico da Maya foi bloqueada. '
    'O arquivo original foi preservado.';

/// Clean abort for unmount/shutdown mid-bootstrap (not user-facing).
class _BootstrapAborted implements Exception {}

const _readingUnavailableException = EngineException(
  EngineFailure(
    kind: EngineFailureKind.temporarilyUnavailable,
    code: 'engine_temporarily_unavailable',
    message: 'Recursos de leitura temporariamente indisponíveis.',
    retryable: true,
  ),
);
