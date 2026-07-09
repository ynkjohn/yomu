import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_local_server/yomu_local_server.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

import '../screens/downloads_screen.dart';
import '../screens/explore_screen.dart';
import '../screens/extensions_screen.dart';
import '../screens/library_screen.dart';
import '../screens/placeholder_screen.dart';
import '../screens/server_screen.dart';

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
  String? _bootstrapError;
  bool _bootstrapping = true;
  bool _busyEngine = false;
  String? _aboutVersion;
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
      final paths = SuwayomiPaths(root);
      await paths.ensureLayout();

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
      // Phase 2B: loopback only. LAN/PWA needs future explicit opt-in + auth.
      final server = YomuServer(
        host: '127.0.0.1',
        port: 8787,
        pwaDir: pwaDir,
        allowOpenCors: false,
        suwayomiStatus: () => manager.status,
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
        _yomuServer = server;
        _suwayomiStatus = manager.status;
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
    unawaited(_yomuServer?.stop() ?? Future<void>.value());
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

    return switch (_selected) {
      'server' => ServerScreen(
          status: _suwayomiStatus,
          yomuPort: _yomuServer?.boundPort ?? 8787,
          managedRootDir: _manager?.managedRootDir ?? '—',
          aboutVersion: _aboutVersion,
          busy: _busyEngine,
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
          message: 'Bloqueado — após hard gate e PWA/Maya na sequência.',
        ),
      'maya' => const PlaceholderScreen(
          title: 'Maya',
          message: 'Bloqueado — após hard gate (biblioteca + progresso + downloads).',
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
            label: 'Yomu local :${_yomuServer?.boundPort ?? 8787}',
            color: YomuTokens.textMuted,
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
