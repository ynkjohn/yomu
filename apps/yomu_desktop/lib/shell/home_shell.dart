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
import '../services/suwayomi_maya_port.dart';
import '../services/windows_maya_credential_store.dart';
import '../services/windows_window_chrome.dart';
import 'desktop_lifecycle.dart';

Color _motorStateColor(SuwayomiProcessState state) => switch (state) {
  SuwayomiProcessState.running => YomuTokens.success,
  SuwayomiProcessState.starting ||
  SuwayomiProcessState.stopping => YomuTokens.warning,
  SuwayomiProcessState.unhealthy ||
  SuwayomiProcessState.crashed => YomuTokens.danger,
  SuwayomiProcessState.stopped => YomuTokens.textMuted,
};

@visibleForTesting
({String label, Color color}) deriveYomuCoreStatus({
  required int? boundPort,
  required SuwayomiProcessState motorState,
}) {
  if (boundPort == null) {
    return (
      label: 'Yomu Core indisponível · Motor ${motorState.name}',
      color: YomuTokens.danger,
    );
  }
  if (motorState == SuwayomiProcessState.running) {
    return (label: 'Yomu Core ativo · :$boundPort', color: YomuTokens.success);
  }
  return (
    label: 'Yomu Core ativo · :$boundPort · Motor ${motorState.name}',
    color: _motorStateColor(motorState),
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
  SuwayomiApi? _api;
  SuwayomiLibraryAdapter? _libraryAdapter;
  SuwayomiCoreAdapter? _coreAdapter;
  SuwayomiExtensionsAdapter? _extensionsAdapter;
  SuwayomiEngineReadinessAdapter? _engineReadiness;
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
  String? _aboutVersion;
  String? _pairingCode;
  DateTime? _pairingExpiresAt;
  List<String> _lanAddresses = const [];
  StreamSubscription<SuwayomiStatus>? _statusSub;
  SuwayomiStatus _suwayomiStatus = const SuwayomiStatus(
    state: SuwayomiProcessState.stopped,
  );

  /// Serializes bootstrap / HTTP restart / shutdown (shared queue).
  final DesktopLifecycleQueue _lifecycle = DesktopLifecycleQueue();
  late final DesktopExitCoordinator _exitCoordinator;

  bool get _engineReady =>
      _manager != null &&
      _api != null &&
      _suwayomiStatus.state == SuwayomiProcessState.running;

  EngineReadinessSnapshot get _readingEngineReadiness =>
      _engineReadiness?.current ??
      const EngineReadinessSnapshot(state: EngineReadinessState.initializing);

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
      MayaProviderController? mayaProvider;
      SuwayomiProcessManager? manager;
      YomuServer? server;
      StreamSubscription<SuwayomiStatus>? statusSub;
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
              await _teardownResources(auth: auth, db: db);
              auth = null;
              db = null;
              _db = null;
              throw _BootstrapAborted();
            }
          },
          initializeOptionalMaya: () async {
            final store = await MayaStore.open(
              database: db!,
              legacyFile: File(p.join(root.path, 'maya_chat.json')),
            );
            MayaCredentialStore credentialStore;
            try {
              credentialStore = WindowsMayaCredentialStore();
            } catch (_) {
              credentialStore = const UnavailableMayaCredentialStore();
            }
            mayaProvider = await OptionalMayaProviderBootstrap.open(
              () => MayaProviderController.open(
                database: db!,
                credentialStore: credentialStore,
                adapterFactory: createMayaProviderAdapterFactory(),
              ),
            );
            maya = MayaService(
              store: store,
              libraryPort: SuwayomiMayaPort(() => _api),
              llm: mayaProvider,
            );
            if (!mounted || _lifecycle.shuttingDown) {
              await _teardownResources(maya: maya, auth: auth, db: db);
              maya = null;
              mayaProvider = null;
              auth = null;
              db = null;
              _db = null;
              throw _BootstrapAborted();
            }
          },
          onMayaUnavailable: (_) {
            maya = null;
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
            final libraryAdapter = SuwayomiLibraryAdapter(readingApi);
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
            final extensionsAdapter = SuwayomiExtensionsAdapter(readingApi);
            final engineReadiness = SuwayomiEngineReadinessAdapter.fromManager(
              listenedManager,
            );

            final pwaDir = await _resolvePwaDir();
            server = _buildYomuServer(
              auth: auth!,
              pwaDir: pwaDir,
              lanEnabled: false,
              lanAddresses: const [],
              libraryAdapter: libraryAdapter,
              coreAdapter: coreAdapter,
              engineReadiness: engineReadiness,
            );
            await server!.start();

            // Capture a non-null manager for the stream listener. The bootstrap
            // locals are nulled after transfer; the listener must not close over
            // those locals or a later running status will null-check-crash.
            statusSub = listenedManager.statusStream.listen((s) {
              if (!mounted) return;
              setState(() {
                _suwayomiStatus = s;
                if (s.isReady) {
                  final live = _manager ?? listenedManager;
                  _api = SuwayomiApi(live.createClient());
                }
              });
            });

            if (!mounted || _lifecycle.shuttingDown) {
              await _teardownResources(
                statusSub: statusSub,
                server: server,
                maya: maya,
                auth: auth,
                manager: manager,
                db: db,
              );
              db = null;
              auth = null;
              manager = null;
              server = null;
              statusSub = null;
              maya = null;
              throw _BootstrapAborted();
            }

            final liveManager = manager!;
            final liveServer = server!;
            final liveSub = statusSub!;
            final liveDb = db!;
            final liveAuth = auth!;
            final liveMaya = maya;
            final liveMayaProvider = mayaProvider;
            final liveMayaUnavailableReason = mayaUnavailableReason;
            _statusSub = liveSub;
            _manager = liveManager;
            _yomuServer = liveServer;
            _db = liveDb;
            _auth = liveAuth;
            auth = null;
            setState(() {
              _api = SuwayomiApi(liveManager.createClient());
              _libraryAdapter = libraryAdapter;
              _coreAdapter = coreAdapter;
              _extensionsAdapter = extensionsAdapter;
              _engineReadiness = engineReadiness;
              _maya = liveMaya;
              _mayaProvider = liveMayaProvider;
              _mayaUnavailableReason = liveMayaUnavailableReason;
              _pwaDir = pwaDir;
              _suwayomiStatus = liveManager.status;
              _lanEnabled = false;
              _bootstrapping = false;
              _bootstrapError = null;
            });
            db = null;
            manager = null;
            server = null;
            statusSub = null;
            maya = null;
            mayaProvider = null;
          },
        );
      } on _BootstrapAborted {
        // Clean abort (unmount/shutdown) — resources already handled.
      } catch (e) {
        await _teardownResources(
          statusSub: statusSub ?? _statusSub,
          server: server ?? _yomuServer,
          maya: maya ?? _maya,
          auth: auth ?? _auth,
          manager: manager ?? _manager,
          db: db ?? _db ?? YomuDatabase.instance,
        );
        _statusSub = null;
        _yomuServer = null;
        _manager = null;
        _db = null;
        _auth = null;
        _maya = null;
        _mayaProvider = null;
        _mayaUnavailableReason = null;
        _api = null;
        _libraryAdapter = null;
        _coreAdapter = null;
        _extensionsAdapter = null;
        _engineReadiness = null;
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

  /// Core → Maya → Auth → Suwayomi → DB. [close] runs even if [stop] throws.
  Future<void> _teardownResources({
    StreamSubscription<SuwayomiStatus>? statusSub,
    YomuServer? server,
    MayaService? maya,
    Future<void> Function()? releaseMayaPort,
    DeviceAuthStore? auth,
    SuwayomiProcessManager? manager,
    YomuDatabase? db,
  }) {
    return ResourceTeardown.run(
      cancelSubscription: () async {
        await statusSub?.cancel();
      },
      stopServer: () async {
        await server?.stop();
      },
      closeServer: () async {
        server?.close();
      },
      closeMaya: () async {
        await maya?.close();
      },
      releaseMayaPort: releaseMayaPort,
      closeAuth: () async {
        await auth?.close();
      },
      disposeManager: () async {
        try {
          await manager?.dispose();
        } catch (_) {
          await manager?.shutdown();
        }
      },
      closeDb: () async {
        if (db != null) await db.close();
      },
    );
  }

  Future<void> _teardownOwnedResources() async {
    final sub = _statusSub;
    final server = _yomuServer;
    final maya = _maya;
    final auth = _auth;
    final manager = _manager;
    final db = _db ?? YomuDatabase.instance;
    final api = _api;
    _statusSub = null;
    _yomuServer = null;
    _maya = null;
    _mayaProvider = null;
    _mayaUnavailableReason = null;
    _auth = null;
    _manager = null;
    _libraryAdapter = null;
    _coreAdapter = null;
    _extensionsAdapter = null;
    _engineReadiness = null;
    _db = null;
    await _teardownResources(
      statusSub: sub,
      server: server,
      maya: maya,
      // Maya's Suwayomi port resolves through `_api`. Keep this exact client
      // available until all already-admitted Maya mutations have drained.
      releaseMayaPort: () async {
        if (identical(_api, api)) _api = null;
      },
      auth: auth,
      manager: manager,
      db: db,
    );
  }

  YomuServer _buildYomuServer({
    required DeviceAuthStore auth,
    required Directory? pwaDir,
    required bool lanEnabled,
    required List<String> lanAddresses,
    required SuwayomiLibraryAdapter libraryAdapter,
    required SuwayomiCoreAdapter coreAdapter,
    required SuwayomiEngineReadinessAdapter engineReadiness,
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
      progress: coreAdapter,
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
      final engineReadiness = _engineReadiness;
      if (manager == null ||
          auth == null ||
          libraryAdapter == null ||
          coreAdapter == null ||
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
    final auth = _auth;
    if (auth == null) return;
    final code = auth.startPairing();
    setState(() {
      _pairingCode = code.code;
      _pairingExpiresAt = code.expiresAt;
    });
  }

  void _cancelPairing() {
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
    return _lifecycle.shutdown(_teardownOwnedResources);
  }

  Future<bool> _confirmExit() async {
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('yomu-exit-dialog'),
        title: const Text('Fechar o Yomu?'),
        content: const Text(
          'O Yomu encerrará o Core e os serviços locais com segurança antes '
          'de sair.',
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
    final m = _manager;
    if (m == null) return;
    setState(() => _busyEngine = true);
    final result = await m.start();
    if (!mounted) return;
    result.when(
      ok: (_) async {
        _api = SuwayomiApi(m.createClient());
        final about = await _api!.about();
        if (mounted) {
          setState(() {
            _aboutVersion = about == null
                ? null
                : '${about['version']} / ${about['revision']}';
            _suwayomiStatus = m.status;
            _busyEngine = false;
          });
        }
      },
      err: (msg, _) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        setState(() {
          _suwayomiStatus = m.status;
          _busyEngine = false;
        });
      },
    );
  }

  Future<void> _stopSuwayomi() async {
    setState(() => _busyEngine = true);
    await _manager?.stop();
    if (mounted) {
      setState(() {
        _suwayomiStatus = _manager?.status ?? _suwayomiStatus;
        _busyEngine = false;
      });
      if (_suwayomiStatus.state != SuwayomiProcessState.stopped) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _suwayomiStatus.message ??
                  'Stop incompleto — porta pode ainda estar ativa.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _restartSuwayomi() async {
    final m = _manager;
    if (m == null) return;
    setState(() => _busyEngine = true);
    final result = await m.restart();
    if (!mounted) return;
    result.when(
      ok: (_) async {
        _api = SuwayomiApi(m.createClient());
        final about = await _api!.about();
        if (mounted) {
          setState(() {
            _aboutVersion = about == null
                ? null
                : '${about['version']} / ${about['revision']}';
            _suwayomiStatus = m.status;
            _busyEngine = false;
          });
        }
      },
      err: (msg, _) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        setState(() {
          _suwayomiStatus = m.status;
          _busyEngine = false;
        });
      },
    );
  }

  Future<void> _openLibraryManga(LibraryManga manga) async {
    await _openMangaDetails(manga.id);
  }

  Future<void> _continueLibraryManga(LibraryManga manga) async {
    final core = _coreAdapter;
    if (core == null || !_engineReady) throw _readingUnavailableException;
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
    if (core == null || !_engineReady) throw _readingUnavailableException;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MangaDetailScreen(
            details: core,
            reader: core,
            catalog: core,
            media: core,
            mangaId: mangaId,
            onOpenChapter: _openReadingChapter,
            onDownloadChapters: _downloadReadingChapters,
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
    final api = _api;
    if (api == null || !_engineReady) throw _readingUnavailableException;
    ChapterInfo legacy(ReadingChapter value) => ChapterInfo(
      id: value.id,
      name: value.name,
      chapterNumber: value.chapterNumber,
      pageCount: value.pageCount,
      sourceOrder: value.readingOrder,
      scanlator: value.scanlator,
      lastPageRead: value.lastPageRead,
      isRead: value.isRead,
      isDownloaded: value.isDownloaded,
      mangaId: value.mangaId,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          api: api,
          mangaId: mangaId,
          mangaTitle: mangaTitle,
          chapter: legacy(chapter),
          chapters: chapters.map(legacy).toList(growable: false),
          openSettingsOnStart: openSettings,
        ),
      ),
    );
  }

  Future<void> _downloadReadingChapters(List<int> chapterIds) async {
    final api = _api;
    if (api == null || !_engineReady) throw _readingUnavailableException;
    try {
      await api.enqueueChapterDownloads(chapterIds);
      await api.startDownloader();
    } catch (_) {
      throw const EngineException(
        EngineFailure(
          kind: EngineFailureKind.temporarilyUnavailable,
          code: 'engine_download_enqueue_failed',
          message: 'Não foi possível enfileirar o download.',
          retryable: true,
        ),
      );
    }
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
        library: _libraryAdapter,
        media: _libraryAdapter,
        engineReady: _engineReady,
        onNavigate: (id) => setState(() => _selected = id),
        onOpenManga: _openLibraryManga,
        onContinueReading: _continueLibraryManga,
      ),
      'server' => ServerScreen(
        status: _suwayomiStatus,
        yomuPort: _yomuServer?.boundPort ?? 8787,
        managedRootDir: _manager?.managedRootDir ?? '—',
        aboutVersion: _aboutVersion,
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
          final manager = _manager;
          if (manager == null || _lifecycle.shuttingDown) return;
          await manager.checkHealth();
          if (!mounted ||
              _lifecycle.shuttingDown ||
              !identical(_manager, manager)) {
            return;
          }
          if (_engineReady) {
            final about = await _api?.about();
            if (!mounted ||
                _lifecycle.shuttingDown ||
                !identical(_manager, manager)) {
              return;
            }
            setState(() {
              _suwayomiStatus = manager.status;
              _aboutVersion = about == null
                  ? _aboutVersion
                  : '${about['version']} / ${about['revision']}';
            });
          } else {
            setState(() => _suwayomiStatus = manager.status);
          }
        },
      ),
      'explore' => ExploreScreen(
        catalog: _coreAdapter,
        extensions: _extensionsAdapter,
        media: _coreAdapter,
        engineReady: _engineReady,
        onOpenManga: _openMangaDetails,
      ),
      'library' => LibraryScreen(
        library: _libraryAdapter,
        media: _libraryAdapter,
        readiness: _readingEngineReadiness,
        onOpenManga: _openLibraryManga,
        onContinueReading: _continueLibraryManga,
      ),
      'downloads' => DownloadsScreen(api: _api, engineReady: _engineReady),
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
      motorState: _suwayomiStatus.state,
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
