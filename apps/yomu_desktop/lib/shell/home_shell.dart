import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_local_server/yomu_local_server.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

import '../screens/downloads_screen.dart';
import '../screens/explore_screen.dart';
import '../screens/extensions_screen.dart';
import '../screens/library_screen.dart';
import '../screens/manga_detail_screen.dart';
import '../screens/maya_screen.dart';
import '../screens/placeholder_screen.dart';
import '../screens/server_screen.dart';
import '../services/suwayomi_maya_port.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _nav = <YomuNavItem>[
    YomuNavItem(
      id: 'server',
      label: 'Servidor',
      icon: Icons.dns_outlined,
    ),
    YomuNavItem(
      id: 'extensions',
      label: 'Extensões',
      icon: Icons.extension_outlined,
    ),
    YomuNavItem(
      id: 'explore',
      label: 'Explorar',
      icon: Icons.explore_outlined,
    ),
    YomuNavItem(
      id: 'library',
      label: 'Biblioteca',
      icon: Icons.collections_bookmark_outlined,
    ),
    YomuNavItem(
      id: 'downloads',
      label: 'Downloads',
      icon: Icons.download_outlined,
    ),
    YomuNavItem(
      id: 'history',
      label: 'Histórico',
      icon: Icons.history,
    ),
    YomuNavItem(
      id: 'maya',
      label: 'Maya',
      icon: Icons.smart_toy_outlined,
    ),
    YomuNavItem(
      id: 'source_builder',
      label: 'Criador de fontes',
      icon: Icons.construction_outlined,
    ),
    YomuNavItem(
      id: 'settings',
      label: 'Configurações',
      icon: Icons.settings_outlined,
    ),
  ];

  String _selected = 'server';
  SuwayomiProcessManager? _manager;
  SuwayomiApi? _api;
  YomuServer? _yomuServer;
  DeviceAuthStore? _auth;
  MayaService? _maya;
  Directory? _pwaDir;
  String? _bootstrapError;
  bool _bootstrapping = true;
  bool _busyEngine = false;
  bool _busyHttp = false;
  bool _lanEnabled = false;
  String? _aboutVersion;
  String? _pairingCode;
  DateTime? _pairingExpiresAt;
  List<String> _lanAddresses = const [];
  StreamSubscription<SuwayomiStatus>? _statusSub;
  SuwayomiStatus _suwayomiStatus =
      const SuwayomiStatus(state: SuwayomiProcessState.stopped);


  bool get _engineReady =>
      _manager != null &&
      _api != null &&
      _suwayomiStatus.state == SuwayomiProcessState.running;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      final support = await getApplicationSupportDirectory();
      final root = Directory(p.join(support.path, 'yomu'));
      await root.create(recursive: true);
      final paths = SuwayomiPaths(root);
      await paths.ensureLayout();

      final auth = DeviceAuthStore(
        persistFile: File(p.join(root.path, 'device_sessions.json')),
      );
      await auth.load();

      final mayaStore = MayaStore(File(p.join(root.path, 'maya_chat.json')));
      await mayaStore.load();
      final maya = MayaService(
        store: mayaStore,
        libraryPort: SuwayomiMayaPort(() => _api),
      );

      final manifestJson =
          await rootBundle.loadString('assets/vendor/manifest.json');
      final manifest = VendorManifest.fromJson(
        jsonDecode(manifestJson) as Map<String, dynamic>,
      );

      final manager = SuwayomiProcessManager(
        paths: paths,
        manifest: manifest,
        host: '127.0.0.1',
        port: kYomuSuwayomiPort,
      );

      final pwaDir = await _resolvePwaDir();
      final server = _buildYomuServer(
        manager: manager,
        auth: auth,
        pwaDir: pwaDir,
        lanEnabled: false,
      );
      await server.start();

      _statusSub = manager.statusStream.listen((s) {
        if (mounted) {
          setState(() {
            _suwayomiStatus = s;
            if (s.isReady) {
              _api = SuwayomiApi(manager.createClient());
            }
          });
        }
      });

      if (!mounted) return;
      setState(() {
        _manager = manager;
        _api = SuwayomiApi(manager.createClient());
        _auth = auth;
        _maya = maya;
        _pwaDir = pwaDir;
        _yomuServer = server;
        _suwayomiStatus = manager.status;
        _lanEnabled = false;
        _bootstrapping = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootstrapError = e.toString();
        _bootstrapping = false;
      });
    }
  }

  YomuServer _buildYomuServer({
    required SuwayomiProcessManager manager,
    required DeviceAuthStore auth,
    required Directory? pwaDir,
    required bool lanEnabled,
  }) {
    return YomuServer(
      host: lanEnabled ? '0.0.0.0' : '127.0.0.1',
      port: 8787,
      pwaDir: pwaDir,
      allowLanCors: lanEnabled,
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

  Future<void> _restartYomuHttp({required bool lanEnabled}) async {
    final manager = _manager;
    final auth = _auth;
    if (manager == null || auth == null) return;

    setState(() => _busyHttp = true);
    try {
      await _yomuServer?.stop();
      _yomuServer?.close();
      final server = _buildYomuServer(
        manager: manager,
        auth: auth,
        pwaDir: _pwaDir,
        lanEnabled: lanEnabled,
      );
      await server.start();
      final addrs = lanEnabled ? await listLanIpv4Addresses() : <String>[];
      if (!mounted) return;
      setState(() {
        _yomuServer = server;
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

  Future<Directory?> _resolvePwaDir() async {
    final candidates = [
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
          p.join(
            Directory.current.path,
            '..',
            '..',
            'apps',
            'yomu_mobile_pwa',
          ),
        ),
      ),
    ];
    for (final d in candidates) {
      if (File(p.join(d.path, 'index.html')).existsSync()) return d;
    }
    return null;
  }

  @override
  void dispose() {
    unawaited(_statusSub?.cancel() ?? Future<void>.value());
    unawaited(() async {
      await _yomuServer?.stop();
      _yomuServer?.close();
    }());
    unawaited(_manager?.dispose() ?? Future<void>.value());
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
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
      'server' => ServerScreen(
          status: _suwayomiStatus,
          yomuPort: _yomuServer?.boundPort ?? 8787,
          managedRootDir: _manager?.managedRootDir ?? '—',
          aboutVersion: _aboutVersion,
          busy: _busyEngine || _busyHttp,
          lanEnabled: _lanEnabled,
          onToggleLan: (v) => unawaited(_toggleLan(v)),
          pairingCode: displayCode,
          pairingExpiresAt: displayExpiry,
          onStartPairing: _startPairing,
          onCancelPairing: _cancelPairing,
          lanAddresses: _lanAddresses,
          sessionCount: _auth?.sessions.length ?? 0,
          onStart: () => unawaited(_startSuwayomi()),
          onStop: () => unawaited(_stopSuwayomi()),
          onRestart: () => unawaited(_restartSuwayomi()),
          onHealthCheck: () async {
            await _manager?.checkHealth();
            if (_engineReady) {
              final about = await _api?.about();
              if (mounted) {
                setState(() {
                  _suwayomiStatus = _manager!.status;
                  _aboutVersion = about == null
                      ? _aboutVersion
                      : '${about['version']} / ${about['revision']}';
                });
              }
            } else if (mounted) {
              setState(() => _suwayomiStatus = _manager!.status);
            }
          },
        ),
      'extensions' => ExtensionsScreen(
          api: _api,
          engineReady: _engineReady,
        ),
      'explore' => ExploreScreen(
          api: _api,
          engineReady: _engineReady,
        ),
      'library' => LibraryScreen(
          api: _api,
          engineReady: _engineReady,
        ),
      'downloads' => DownloadsScreen(
          api: _api,
          engineReady: _engineReady,
        ),
      'source_builder' => const PlaceholderScreen(
          title: 'Criador de fontes',
          message: 'Bloqueado — fase posterior (após Maya estável).',
        ),
      'maya' => MayaScreen(
          service: _maya,
          engineReady: _engineReady,
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
          message: 'Ainda não implementado nesta fase.',
        ),
    };
  }

  Color _stateColor(SuwayomiProcessState s) => switch (s) {
        SuwayomiProcessState.running => YomuTokens.success,
        SuwayomiProcessState.starting ||
        SuwayomiProcessState.stopping =>
          YomuTokens.warning,
        SuwayomiProcessState.unhealthy ||
        SuwayomiProcessState.crashed =>
          YomuTokens.danger,
        SuwayomiProcessState.stopped => YomuTokens.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    return YomuAppShell(
      items: _nav,
      selectedId: _selected,
      onSelect: (id) => setState(() => _selected = id),
      statusBar: Row(
        children: [
          StatusPill(
            label: 'Suwayomi: ${_suwayomiStatus.state.name}',
            color: _stateColor(_suwayomiStatus.state),
          ),
          const SizedBox(width: 12),
          StatusPill(
            label: 'loopback :$kYomuSuwayomiPort',
            color: YomuTokens.accent,
          ),
          const SizedBox(width: 12),
          StatusPill(
            label: _lanEnabled
                ? 'Yomu LAN :${_yomuServer?.boundPort ?? 8787}'
                : 'Yomu local :${_yomuServer?.boundPort ?? 8787}',
            color: _lanEnabled ? YomuTokens.warning : YomuTokens.textMuted,
          ),
          if (_suwayomiStatus.message != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _suwayomiStatus.message!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: YomuTokens.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
      body: _body(),
    );
  }
}
