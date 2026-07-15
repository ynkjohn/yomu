import 'package:flutter/material.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

class _ExtensionsSkeleton extends StatefulWidget {
  const _ExtensionsSkeleton({required this.label});

  final String label;

  @override
  State<_ExtensionsSkeleton> createState() => _ExtensionsSkeletonState();
}

class _ExtensionsSkeletonState extends State<_ExtensionsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      liveRegion: true,
      label: widget.label,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 18, 28, 30),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Opacity(
                opacity: reduceMotion ? 1 : 0.55 + _controller.value * 0.45,
                child: Column(
                  children: [
                    const _ExtensionSkeletonBlock(height: 44, radius: 10),
                    const SizedBox(height: 16),
                    for (var index = 0; index < 5; index++) ...[
                      const _ExtensionSkeletonBlock(height: 70, radius: 14),
                      if (index != 4) const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtensionSkeletonBlock extends StatelessWidget {
  const _ExtensionSkeletonBlock({required this.height, required this.radius});

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFF171C27),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class ExtensionsScreen extends StatefulWidget {
  const ExtensionsScreen({
    super.key,
    required this.api,
    required this.engineReady,
    this.embedded = false,
    this.repositoriesOnly = false,
    this.onSourcesChanged,
  });

  final SuwayomiApi? api;
  final bool engineReady;
  final bool embedded;
  final bool repositoriesOnly;
  final Future<void> Function()? onSourcesChanged;

  @override
  State<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends State<ExtensionsScreen> {
  final _filterCtrl = TextEditingController();
  bool _loadingStores = false;
  bool _loadingExtensions = false;
  bool _actionBusy = false;
  String? _storesError;
  String? _extensionsError;
  String _filter = '';
  List<ExtensionStoreInfo> _stores = [];

  /// Full catalog loaded once; filtered in memory.
  List<ExtensionInfo> _allExtensions = [];
  String? _busyPkg;
  int _storesGeneration = 0;
  int _extensionsGeneration = 0;
  int _actionGeneration = 0;
  int _installGeneration = 0;

  static const _catalogCap = 80;

  @override
  void initState() {
    super.initState();
    if (widget.engineReady) {
      _loadCatalog();
    }
  }

  @override
  void didUpdateWidget(covariant ExtensionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final apiChanged = !identical(widget.api, oldWidget.api);
    if (!widget.engineReady || widget.api == null) {
      _invalidateRequests(clearData: true);
      return;
    }
    if (!oldWidget.engineReady || apiChanged) {
      _invalidateRequests(clearData: true);
      _loadCatalog();
    }
  }

  @override
  void dispose() {
    _invalidateRequests(clearData: false);
    _filterCtrl.dispose();
    super.dispose();
  }

  void _invalidateRequests({required bool clearData}) {
    _storesGeneration++;
    _extensionsGeneration++;
    _actionGeneration++;
    _installGeneration++;
    _loadingStores = false;
    _loadingExtensions = false;
    _actionBusy = false;
    _busyPkg = null;
    _storesError = null;
    _extensionsError = null;
    if (clearData) {
      _stores = [];
      _allExtensions = [];
      _filter = '';
      _filterCtrl.clear();
    }
  }

  List<ExtensionInfo> get _filtered {
    final q = _filter.trim().toLowerCase();
    if (q.isEmpty) return _allExtensions;
    return _allExtensions
        .where(
          (e) =>
              e.name.toLowerCase().contains(q) ||
              e.pkgName.toLowerCase().contains(q) ||
              (e.lang?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  Future<void> _loadCatalog() async {
    await Future.wait([_loadStores(), _loadExtensions()]);
  }

  Future<void> _loadStores() async {
    final api = widget.api;
    if (api == null || !widget.engineReady) return;
    final generation = ++_storesGeneration;
    setState(() {
      _loadingStores = true;
      _storesError = null;
    });
    try {
      final stores = await api.listExtensionStores();
      if (!mounted ||
          generation != _storesGeneration ||
          !widget.engineReady ||
          !identical(widget.api, api)) {
        return;
      }
      setState(() {
        _stores = stores;
        _loadingStores = false;
      });
    } catch (e) {
      if (!mounted ||
          generation != _storesGeneration ||
          !widget.engineReady ||
          !identical(widget.api, api)) {
        return;
      }
      setState(() {
        _storesError = e.toString();
        _loadingStores = false;
      });
    }
  }

  Future<void> _loadExtensions() async {
    final api = widget.api;
    if (api == null || !widget.engineReady) return;
    final generation = ++_extensionsGeneration;
    setState(() {
      _loadingExtensions = true;
      _extensionsError = null;
    });
    try {
      // No server-side filter — full list once, filter locally.
      final extensions = await api.listExtensions();
      if (!mounted ||
          generation != _extensionsGeneration ||
          !widget.engineReady ||
          !identical(widget.api, api)) {
        return;
      }
      setState(() {
        _allExtensions = extensions;
        _loadingExtensions = false;
      });
    } catch (e) {
      if (!mounted ||
          generation != _extensionsGeneration ||
          !widget.engineReady ||
          !identical(widget.api, api)) {
        return;
      }
      setState(() {
        _extensionsError = e.toString();
        _loadingExtensions = false;
      });
    }
  }

  Future<void> _syncCatalog() async {
    final api = widget.api;
    if (api == null || _actionBusy || _busyPkg != null || _loadingExtensions) {
      return;
    }
    final generation = ++_actionGeneration;
    setState(() {
      _actionBusy = true;
      _extensionsError = null;
    });
    try {
      final n = await api.fetchExtensions();
      if (!mounted ||
          generation != _actionGeneration ||
          !identical(widget.api, api) ||
          !widget.engineReady) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Catálogo sincronizado: $n extensões.')),
      );
      await _loadExtensions();
    } catch (e) {
      if (!mounted ||
          generation != _actionGeneration ||
          !identical(widget.api, api)) {
        return;
      }
      setState(() => _extensionsError = e.toString());
    } finally {
      if (mounted &&
          generation == _actionGeneration &&
          identical(widget.api, api)) {
        setState(() => _actionBusy = false);
      }
    }
  }

  Future<void> _ensureKeiyoushi() async {
    final api = widget.api;
    if (api == null || _actionBusy || _busyPkg != null || _loadingExtensions) {
      return;
    }
    final generation = ++_actionGeneration;
    setState(() {
      _actionBusy = true;
      _storesError = null;
      _extensionsError = null;
    });
    try {
      try {
        await api.ensureKeiyoushiStore();
      } catch (e) {
        if (mounted &&
            generation == _actionGeneration &&
            identical(widget.api, api)) {
          setState(() => _storesError = e.toString());
        }
        return;
      }
      int n;
      try {
        n = await api.fetchExtensions();
      } catch (e) {
        if (mounted &&
            generation == _actionGeneration &&
            identical(widget.api, api)) {
          setState(() => _extensionsError = e.toString());
        }
        return;
      }
      if (!mounted ||
          generation != _actionGeneration ||
          !identical(widget.api, api) ||
          !widget.engineReady) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Keiyoushi OK. Catálogo: $n extensões.')),
      );
      await _loadCatalog();
    } finally {
      if (mounted &&
          generation == _actionGeneration &&
          identical(widget.api, api)) {
        setState(() => _actionBusy = false);
      }
    }
  }

  void _upsertExtension(ExtensionInfo ext) {
    final idx = _allExtensions.indexWhere((e) => e.pkgName == ext.pkgName);
    if (idx < 0) {
      _allExtensions = [..._allExtensions, ext];
      return;
    }
    final previous = _allExtensions[idx];
    _allExtensions = [
      for (var i = 0; i < _allExtensions.length; i++)
        if (i == idx)
          ExtensionInfo(
            pkgName: ext.pkgName,
            name: ext.name,
            isInstalled: ext.isInstalled,
            versionName: ext.versionName,
            lang: ext.lang ?? previous.lang,
            apkName: ext.apkName ?? previous.apkName,
          )
        else
          _allExtensions[i],
    ];
  }

  Future<void> _install(String pkg) async {
    final api = widget.api;
    if (api == null || _busyPkg != null || _loadingExtensions || _actionBusy) {
      return;
    }
    final onSourcesChanged = widget.onSourcesChanged;
    final messenger = ScaffoldMessenger.of(context);
    final generation = ++_installGeneration;
    setState(() => _busyPkg = pkg);
    bool ownsUiState() =>
        mounted &&
        generation == _installGeneration &&
        widget.engineReady &&
        identical(widget.api, api);
    try {
      final ext = await api.installExtension(pkg);
      if (ownsUiState()) {
        setState(() => _upsertExtension(ext));
      }
      Object? refreshError;
      try {
        await onSourcesChanged?.call();
      } catch (e) {
        refreshError = e;
      }
      if (ownsUiState()) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              refreshError == null
                  ? 'Instalado: ${ext.name}'
                  : 'Extensão instalada, mas as fontes não foram atualizadas: '
                        '$refreshError',
            ),
          ),
        );
      }
    } catch (e) {
      if (!ownsUiState()) return;
      messenger.showSnackBar(SnackBar(content: Text('Erro install: $e')));
    } finally {
      if (ownsUiState()) {
        setState(() => _busyPkg = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.engineReady) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Inicie o Suwayomi na aba Servidor e Motor antes de gerenciar extensões e repositórios.',
            textAlign: TextAlign.center,
            style: TextStyle(color: YomuTokens.textMuted),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded)
          const YomuScreenHeader(
            title: 'Extensões & Stores',
            subtitle: 'Catálogo local, fontes instaladas e repositórios',
          ),
        if ((widget.repositoriesOnly
            ? _loadingStores && _stores.isEmpty
            : _loadingExtensions && _allExtensions.isEmpty))
          Expanded(
            child: _ExtensionsSkeleton(
              label: widget.repositoriesOnly
                  ? 'Carregando repositórios'
                  : 'Carregando extensões',
            ),
          )
        else
          Expanded(
            child: widget.repositoriesOnly
                ? _repositoriesBody()
                : _extensionsBody(),
          ),
      ],
    );
  }

  Widget _errorBanner(String? error) {
    if (error == null) return const SizedBox.shrink();
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Erro: $error',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              color: YomuTokens.danger.withValues(alpha: 0.1),
              border: Border.all(
                color: YomuTokens.danger.withValues(alpha: 0.35),
              ),
              borderRadius: BorderRadius.circular(YomuTokens.radiusMd),
            ),
            child: Text(
              error,
              style: const TextStyle(color: YomuTokens.danger, fontSize: 12.5),
            ),
          ),
        ),
      ),
    );
  }

  // ---- Repositórios ----

  Widget _repositoriesBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 30),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _errorBanner(_storesError),
              _errorBanner(_extensionsError),
              if (_stores.isEmpty && !_loadingStores)
                _repoEmptyCard()
              else ...[
                _catalogSyncCard(),
                const SizedBox(height: 10),
                for (final s in _stores) ...[
                  _repoCard(s),
                  const SizedBox(height: 10),
                ],
              ],
              const SizedBox(height: 0),
              _addRepoButton(),
              const SizedBox(height: 10),
              const Text(
                'Repositórios fora da lista de confiáveis exigem confirmação '
                'explícita — extensões executam no motor local.',
                style: TextStyle(
                  color: YomuTokens.textSubtle,
                  fontSize: 11.5,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _repoEmptyCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: YomuTokens.surface.withValues(alpha: 0.82),
        border: Border.all(color: YomuTokens.border),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nenhum repositório configurado',
            style: TextStyle(
              color: YomuTokens.text,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Adicione o repositório confiável Keiyoushi para instalar '
            'extensões reais.',
            style: TextStyle(color: YomuTokens.textSubtle, fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          _smallButton(
            label: _actionBusy
                ? 'Configurando Keiyoushi…'
                : 'Garantir Keiyoushi',
            accent: true,
            busy: _actionBusy,
            onTap:
                _loadingStores ||
                    _loadingExtensions ||
                    _actionBusy ||
                    _busyPkg != null
                ? null
                : _ensureKeiyoushi,
          ),
        ],
      ),
    );
  }

  Widget _repoCard(ExtensionStoreInfo s) {
    final isKeiyoushi = SuwayomiApi.isTrustedKeiyoushiStore(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: YomuTokens.surface.withValues(alpha: 0.82),
        border: Border.all(color: YomuTokens.border),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatar(s.name, size: 42, radius: 11, fontSize: 17),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: YomuTokens.text,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isKeiyoushi) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: YomuTokens.success.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Text(
                              'CONFIÁVEL',
                              style: TextStyle(
                                color: YomuTokens.success,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.isLegacy
                          ? 'repositório legacy'
                          : 'repositório ativo no catálogo agregado',
                      style: const TextStyle(
                        color: YomuTokens.textSubtle,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Indisponível — remoção ainda não implementada',
                child: _smallButton(label: 'Remover', danger: true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            s.indexUrl,
            style: const TextStyle(
              color: YomuTokens.textSubtle,
              fontSize: 10.5,
              fontFamily: 'Consolas',
            ),
          ),
        ],
      ),
    );
  }

  Widget _catalogSyncCard() {
    final count = _allExtensions.length;
    final status = _loadingExtensions
        ? 'Carregando catálogo agregado…'
        : _extensionsError != null
        ? 'Catálogo agregado indisponível'
        : 'Catálogo agregado · $count ${count == 1 ? 'extensão' : 'extensões'}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: YomuTokens.surface.withValues(alpha: 0.82),
        border: Border.all(color: YomuTokens.border),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              status,
              style: const TextStyle(
                color: YomuTokens.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _smallButton(
            label: _actionBusy
                ? 'Sincronizando catálogo…'
                : 'Sincronizar catálogo',
            icon: YomuIcons.refresh,
            busy: _actionBusy,
            onTap: _loadingExtensions || _actionBusy || _busyPkg != null
                ? null
                : _syncCatalog,
          ),
        ],
      ),
    );
  }

  Widget _addRepoButton() {
    return Tooltip(
      message: 'Indisponível — adição por URL ainda não implementada',
      child: Semantics(
        container: true,
        button: true,
        enabled: false,
        label: 'Adicionar repositório por URL. Não implementado.',
        child: ExcludeSemantics(
          child: Opacity(
            opacity: 0.55,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0x2EFFFFFF),
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(YomuTokens.radiusMd),
              ),
              alignment: Alignment.center,
              child: const Text(
                '+ Adicionar repositório por URL',
                style: TextStyle(
                  color: YomuTokens.textSubtle,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- Extensões ----

  Widget _extensionsBody() {
    final filtered = _filtered;
    final mangadex = _allExtensions.where(
      (e) => e.pkgName == SuwayomiApi.mangaDexPkg,
    );
    final installed = filtered.where((e) => e.isInstalled).toList();
    final available = filtered
        .where((e) => !e.isInstalled)
        .take(_catalogCap)
        .toList();
    final hiddenCount = filtered.length - installed.length - available.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 30),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _errorBanner(_extensionsError),
              Row(
                children: [
                  Expanded(child: _searchField()),
                  const SizedBox(width: 8),
                  _smallButton(
                    label: _loadingExtensions ? 'Recarregando…' : 'Recarregar',
                    busy: _loadingExtensions,
                    onTap: _loadingExtensions || _actionBusy || _busyPkg != null
                        ? null
                        : _loadExtensions,
                  ),
                  if (mangadex.isEmpty || !mangadex.first.isInstalled) ...[
                    const SizedBox(width: 6),
                    _smallButton(
                      label: _busyPkg == SuwayomiApi.mangaDexPkg
                          ? 'Instalando MangaDex…'
                          : 'Instalar MangaDex',
                      accent: true,
                      busy: _busyPkg == SuwayomiApi.mangaDexPkg,
                      onTap:
                          _busyPkg != null || _loadingExtensions || _actionBusy
                          ? null
                          : () => _install(SuwayomiApi.mangaDexPkg),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              if (installed.isNotEmpty) ...[
                YomuSectionLabel('Instaladas · ${installed.length}'),
                const SizedBox(height: 8),
                for (final e in installed) ...[
                  _extRow(e),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
              ],
              YomuSectionLabel(
                'Disponíveis · ${available.length}'
                '${hiddenCount > 0 ? ' de ${hiddenCount + available.length}' : ''}',
              ),
              const SizedBox(height: 8),
              if (available.isEmpty && installed.isEmpty && !_loadingExtensions)
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 44,
                    horizontal: 20,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: YomuTokens.surface.withValues(alpha: 0.82),
                    border: Border.all(color: YomuTokens.border),
                    borderRadius: BorderRadius.circular(YomuTokens.radiusMd),
                  ),
                  child: const Text(
                    'Nenhuma extensão no catálogo local. Sincronize um '
                    'repositório em Repositórios.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: YomuTokens.textSubtle,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                for (final e in available) ...[
                  _extRow(e),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 4),
              const Text(
                'Extensões executam no motor local (nunca exposto na rede).',
                style: TextStyle(
                  color: YomuTokens.textSubtle,
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _searchField() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        border: Border.all(color: YomuTokens.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const YomuIcon(
            YomuIcons.search,
            size: 14,
            color: YomuTokens.textSubtle,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _filterCtrl,
                onChanged: (v) => setState(() => _filter = v),
                style: const TextStyle(color: YomuTokens.text, fontSize: 11.5),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText:
                      'Filtrar extensões (${_allExtensions.length} no catálogo)',
                  hintStyle: const TextStyle(
                    color: Color(0xFF6F798D),
                    fontSize: 11.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _extRow(ExtensionInfo e) {
    final busy = _busyPkg == e.pkgName;
    final meta = [
      if (e.lang != null && e.lang!.isNotEmpty) e.lang!.toUpperCase(),
      if (e.versionName != null && e.versionName!.isNotEmpty) e.versionName!,
      e.pkgName,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: YomuTokens.surface.withValues(alpha: 0.82),
        border: Border.all(color: YomuTokens.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _avatar(e.name),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: YomuTokens.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: YomuTokens.textSubtle,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (busy)
            Semantics(
              container: true,
              liveRegion: true,
              label: 'Instalando ${e.name}',
              child: const ExcludeSemantics(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: YomuTokens.accent,
                  ),
                ),
              ),
            )
          else if (e.isInstalled)
            const StatusPill(label: 'instalada', color: YomuTokens.success)
          else
            _smallButton(
              label: 'Instalar',
              accent: true,
              onTap: _busyPkg != null || _loadingExtensions || _actionBusy
                  ? null
                  : () => _install(e.pkgName),
            ),
        ],
      ),
    );
  }

  // ---- Elementos compartilhados ----

  Widget _avatar(
    String name, {
    double size = 44,
    double radius = 12,
    double fontSize = 18,
  }) {
    final hue = (name.codeUnits.fold<int>(0, (a, b) => a + b) * 37) % 360;
    final base = HSLColor.fromAHSL(1, hue.toDouble(), 0.35, 0.38).toColor();
    final dark = HSLColor.fromAHSL(1, hue.toDouble(), 0.3, 0.22).toColor();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, dark],
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _smallButton({
    required String label,
    VoidCallback? onTap,
    bool accent = false,
    bool danger = false,
    bool busy = false,
    YomuIconData? icon,
  }) {
    final enabled = onTap != null;
    final bg = accent
        ? YomuTokens.accentStrong
        : danger
        ? YomuTokens.danger.withValues(alpha: 0.12)
        : YomuTokens.surface3;
    final fg = accent
        ? Colors.white
        : danger
        ? YomuTokens.danger
        : YomuTokens.textMuted;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      liveRegion: busy,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Opacity(
            opacity: enabled || busy ? 1 : 0.5,
            child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (busy) ...[
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: fg,
                          ),
                        ),
                        const SizedBox(width: 7),
                      ] else if (icon != null) ...[
                        YomuIcon(icon, size: 14, color: fg),
                        const SizedBox(width: 7),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          color: fg,
                          fontSize: 12,
                          fontWeight: accent || danger
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
