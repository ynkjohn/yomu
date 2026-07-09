import 'package:flutter/material.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

class ExtensionsScreen extends StatefulWidget {
  const ExtensionsScreen({
    super.key,
    required this.api,
    required this.engineReady,
  });

  final SuwayomiApi? api;
  final bool engineReady;

  @override
  State<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends State<ExtensionsScreen> {
  bool _loading = false;
  String? _error;
  String _filter = '';
  List<ExtensionStoreInfo> _stores = [];

  /// Full catalog loaded once; filtered in memory.
  List<ExtensionInfo> _allExtensions = [];
  String? _busyPkg;

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
    if (widget.engineReady && !oldWidget.engineReady) {
      _loadCatalog();
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
    final api = widget.api;
    if (api == null || !widget.engineReady) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stores = await api.listExtensionStores();
      // No server-side filter — full list once, filter locally.
      final exts = await api.listExtensions();
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _allExtensions = exts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _ensureKeiyoushi() async {
    final api = widget.api;
    if (api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await api.ensureKeiyoushiStore();
      final n = await api.fetchExtensions();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Keiyoushi OK. Catálogo: $n extensões.')),
      );
      await _loadCatalog();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _install(String pkg) async {
    final api = widget.api;
    if (api == null) return;
    setState(() => _busyPkg = pkg);
    try {
      final ext = await api.installExtension(pkg);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Instalado: ${ext.name}')),
      );
      // Patch local cache without full re-fetch when possible.
      setState(() {
        _allExtensions = [
          for (final e in _allExtensions)
            if (e.pkgName == pkg)
              ExtensionInfo(
                pkgName: ext.pkgName,
                name: ext.name,
                isInstalled: ext.isInstalled,
                versionName: ext.versionName,
                lang: ext.lang,
                apkName: e.apkName,
              )
            else
              e,
        ];
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro install: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyPkg = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.engineReady) {
      return const AsyncBody(
        isLoading: false,
        emptyMessage:
            'Inicie o Suwayomi na aba Servidor antes de gerenciar extensões.',
        isEmpty: true,
        child: SizedBox.shrink(),
      );
    }

    final filtered = _filtered;
    final mangadex =
        _allExtensions.where((e) => e.pkgName == SuwayomiApi.mangaDexPkg);
    final installed = _allExtensions.where((e) => e.isInstalled).toList();
    final catalogView = filtered.take(_catalogCap).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(YomuTokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Extensões & Stores',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Catálogo carregado uma vez; filtro local (sem re-fetch a cada tecla).',
                style: TextStyle(color: YomuTokens.textMuted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _loading ? null : _ensureKeiyoushi,
                    child: const Text('Garantir Keiyoushi + atualizar catálogo'),
                  ),
                  OutlinedButton(
                    onPressed: _loading ? null : _loadCatalog,
                    child: const Text('Recarregar lista'),
                  ),
                  if (mangadex.isEmpty || !mangadex.first.isInstalled)
                    FilledButton.tonal(
                      onPressed: _busyPkg != null
                          ? null
                          : () => _install(SuwayomiApi.mangaDexPkg),
                      child: Text(
                        _busyPkg == SuwayomiApi.mangaDexPkg
                            ? 'Instalando MangaDex…'
                            : 'Instalar MangaDex',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  labelText:
                      'Filtrar localmente (${_allExtensions.length} no cache)',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: const TextStyle(color: YomuTokens.danger)),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Stores (${_stores.length})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (_stores.isEmpty)
                const Text(
                  'Nenhuma store. Use “Garantir Keiyoushi”.',
                  style: TextStyle(color: YomuTokens.textMuted),
                ),
              ..._stores.map(
                (s) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(s.name),
                  subtitle: Text(s.indexUrl, maxLines: 2),
                  trailing: s.isLegacy
                      ? const StatusPill(
                          label: 'legacy',
                          color: YomuTokens.warning,
                        )
                      : const StatusPill(
                          label: 'store',
                          color: YomuTokens.accent,
                        ),
                ),
              ),
              const Divider(height: 32),
              Text(
                'Instaladas (${installed.length})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              ...installed.map(_extTile),
              const Divider(height: 32),
              Text(
                'Catálogo filtrado (${catalogView.length}'
                '${filtered.length > _catalogCap ? ' de ${filtered.length}' : ''})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              ...catalogView.map(_extTile),
            ],
          ),
        ),
      ],
    );
  }

  Widget _extTile(ExtensionInfo e) {
    final busy = _busyPkg == e.pkgName;
    return ListTile(
      dense: true,
      title: Text(e.name),
      subtitle: Text('${e.pkgName}\n${e.lang ?? ''} · ${e.versionName ?? ''}'),
      isThreeLine: true,
      trailing: e.isInstalled
          ? const StatusPill(label: 'instalada', color: YomuTokens.success)
          : TextButton(
              onPressed: busy ? null : () => _install(e.pkgName),
              child: Text(busy ? '…' : 'Instalar'),
            ),
    );
  }
}
