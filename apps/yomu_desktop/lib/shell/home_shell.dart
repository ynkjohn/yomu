import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../screens/server_screen.dart';
import '../services/maya_credential_store.dart';
import '../services/maya_provider_adapters.dart';
import '../services/maya_provider_controller.dart';
import '../services/suwayomi_maya_port.dart';
import '../services/windows_maya_credential_store.dart';
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

  @override
  void initState() {
    super.initState();
    _exitCoordinator = DesktopExitCoordinator(shutdown: _coordinatedShutdown);
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

            final manifestJson = await rootBundle.loadString(
              'assets/vendor/manifest.json',
            );
            final manifest = VendorManifest.fromJson(
              jsonDecode(manifestJson) as Map<String, dynamic>,
            );

            manager = SuwayomiProcessManager(
              paths: paths,
              manifest: manifest,
              host: '127.0.0.1',
              port: kYomuSuwayomiPort,
            );

            final pwaDir = await _resolvePwaDir();
            server = _buildYomuServer(
              manager: manager!,
              auth: auth!,
              pwaDir: pwaDir,
              lanEnabled: false,
              lanAddresses: const [],
            );
            await server!.start();

            // Capture a non-null manager for the stream listener. The bootstrap
            // locals are nulled after transfer; the listener must not close over
            // those locals or a later running status will null-check-crash.
            final listenedManager = manager!;
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
    required SuwayomiProcessManager manager,
    required DeviceAuthStore auth,
    required Directory? pwaDir,
    required bool lanEnabled,
    required List<String> lanAddresses,
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
      suwayomiStatus: () => manager.status,
      apiProvider: () {
        if (_api != null) return _api;
        if (manager.status.isReady) {
          return SuwayomiApi(manager.createClient());
        }
        return null;
      },
    );
  }

  Future<void> _restartYomuHttp({required bool lanEnabled}) {
    // Same lifecycle queue as bootstrap/shutdown — shutdown waits for this.
    return _lifecycle.run(() async {
      if (_lifecycle.shuttingDown) return;
      final manager = _manager;
      final auth = _auth;
      if (manager == null || auth == null) return;

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
              manager: manager,
              auth: auth,
              pwaDir: _pwaDir,
              lanEnabled: lanEnabled,
              lanAddresses: addrs,
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
        api: _api,
        engineReady: _engineReady,
        onNavigate: (id) => setState(() => _selected = id),
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
      'explore' => ExploreScreen(api: _api, engineReady: _engineReady),
      'library' => LibraryScreen(api: _api, engineReady: _engineReady),
      'downloads' => DownloadsScreen(api: _api, engineReady: _engineReady),
      'maya' => MayaScreen(
        service: _maya,
        engineReady: _engineReady,
        providerController: _mayaProvider,
        unavailableReason: _mayaUnavailableReason,
        onOpenManga: (id, title) {
          final api = _api;
          if (api == null) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MangaDetailScreen(api: api, mangaId: id),
            ),
          );
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
      body: _body(),
    );
  }
}

const _mayaLegacyMigrationBlockedMessage =
    'A migração do histórico da Maya foi bloqueada. '
    'O arquivo original foi preservado.';

/// Clean abort for unmount/shutdown mid-bootstrap (not user-facing).
class _BootstrapAborted implements Exception {}
