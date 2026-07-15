import 'package:flutter/material.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

import 'extensions_screen.dart';
import 'manga_detail_screen.dart';

enum _ExploreTab { sources, extensions, repositories, migration, creator }

@immutable
class ExploreCatalogQuery {
  const ExploreCatalogQuery({
    required this.sourceId,
    required this.fetchType,
    required this.normalizedQuery,
  });

  final String sourceId;
  final SourceMangaFetchType fetchType;
  final String normalizedQuery;

  @override
  bool operator ==(Object other) =>
      other is ExploreCatalogQuery &&
      other.sourceId == sourceId &&
      other.fetchType == fetchType &&
      other.normalizedQuery == normalizedQuery;

  @override
  int get hashCode => Object.hash(sourceId, fetchType, normalizedQuery);
}

@immutable
class ExploreCatalogRequest {
  const ExploreCatalogRequest({
    required this.query,
    required this.page,
    required this.generation,
  });

  final ExploreCatalogQuery query;
  final int page;
  final int generation;

  @override
  bool operator ==(Object other) =>
      other is ExploreCatalogRequest &&
      other.query == query &&
      other.page == page &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(query, page, generation);
}

class ExploreCatalogRequestGate {
  int _generation = 0;
  ExploreCatalogQuery? _activeQuery;
  final Set<ExploreCatalogRequest> _inFlight = {};

  int get generation => _generation;
  ExploreCatalogQuery? get activeQuery => _activeQuery;

  /// Starts a page-1 request. Skips only a true double-fire of the same
  /// in-flight page-1 (same generation, no higher pages pending).
  ExploreCatalogRequest? reset(ExploreCatalogQuery query) {
    final existing = ExploreCatalogRequest(
      query: query,
      page: 1,
      generation: _generation,
    );
    if (query == _activeQuery &&
        _inFlight.contains(existing) &&
        _inFlight.length == 1) {
      return null;
    }
    _activeQuery = query;
    _generation++;
    _inFlight.clear();
    final request = ExploreCatalogRequest(
      query: query,
      page: 1,
      generation: _generation,
    );
    _inFlight.add(request);
    return request;
  }

  ExploreCatalogRequest? next(ExploreCatalogQuery query, int page) {
    if (query != _activeQuery || page <= 1) return null;
    final request = ExploreCatalogRequest(
      query: query,
      page: page,
      generation: _generation,
    );
    if (!_inFlight.add(request)) return null;
    return request;
  }

  /// Accept only by generation + active query snapshot. Do not compare against
  /// the live search field — typing mid-flight must not permanently stick the
  /// spinner when the in-flight request is still the active generation.
  bool accepts(ExploreCatalogRequest request) =>
      request.generation == _generation && request.query == _activeQuery;

  void complete(ExploreCatalogRequest request) => _inFlight.remove(request);

  void invalidate() {
    _generation++;
    _activeQuery = null;
    _inFlight.clear();
  }
}

String normalizeExploreQuery(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.api,
    required this.engineReady,
  });

  final SuwayomiApi? api;
  final bool engineReady;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _queryCtrl = TextEditingController();
  final _catalogGate = ExploreCatalogRequestGate();
  List<SourceInfo> _sources = [];
  SourceInfo? _selected;
  List<MangaSummary> _results = [];
  bool _loadingSources = false;
  bool _loadingCatalog = false;
  bool _loadingMore = false;
  bool _catalogOpen = false;
  bool _hasNextPage = false;
  int _page = 1;
  int _sourcesGeneration = 0;
  String? _sourcesError;
  String? _catalogError;
  String? _paginationError;
  String _submittedQuery = '';
  _ExploreTab _tab = _ExploreTab.sources;
  SourceMangaFetchType _fetchType = SourceMangaFetchType.popular;

  @override
  void initState() {
    super.initState();
    if (widget.engineReady) _loadSources();
  }

  @override
  void didUpdateWidget(covariant ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final apiChanged = !identical(widget.api, oldWidget.api);
    if (!widget.engineReady || widget.api == null) {
      _invalidateEngineState(clearSources: true);
      return;
    }
    if (!oldWidget.engineReady || apiChanged) {
      _invalidateEngineState(clearSources: true);
      _loadSources();
    }
  }

  @override
  void dispose() {
    _sourcesGeneration++;
    _catalogGate.invalidate();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _invalidateEngineState({required bool clearSources}) {
    _sourcesGeneration++;
    _catalogGate.invalidate();
    if (clearSources) _sources = [];
    _selected = null;
    _results = [];
    _loadingSources = false;
    _loadingCatalog = false;
    _loadingMore = false;
    _catalogOpen = false;
    _hasNextPage = false;
    _page = 1;
    _sourcesError = null;
    _catalogError = null;
    _paginationError = null;
    _submittedQuery = '';
    _queryCtrl.clear();
  }

  Future<void> _loadSources({bool propagateError = false}) async {
    final api = widget.api;
    if (!mounted || api == null || !widget.engineReady) return;
    final generation = ++_sourcesGeneration;
    setState(() {
      _loadingSources = true;
      _sourcesError = null;
    });
    try {
      final sources = await api.listSources();
      final usable = sources.where((source) => source.id != '0').toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted ||
          generation != _sourcesGeneration ||
          !widget.engineReady ||
          !identical(widget.api, api)) {
        return;
      }
      setState(() {
        _sources = usable;
        _loadingSources = false;
      });
    } catch (error, stackTrace) {
      if (!mounted ||
          generation != _sourcesGeneration ||
          !widget.engineReady ||
          !identical(widget.api, api)) {
        return;
      }
      setState(() {
        _sourcesError = '$error';
        _loadingSources = false;
      });
      if (propagateError) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  /// Call after extension install/uninstall so Explore sources stay fresh.
  Future<void> refreshSources() => _loadSources(propagateError: true);

  Future<void> _openSource(SourceInfo source) async {
    setState(() {
      _selected = source;
      _catalogOpen = true;
      _fetchType = SourceMangaFetchType.popular;
      _queryCtrl.clear();
      _submittedQuery = '';
      _catalogError = null;
      _paginationError = null;
    });
    await _loadCatalog(reset: true);
  }

  Future<void> _loadCatalog({required bool reset}) async {
    final api = widget.api;
    final source = _selected;
    if (api == null || source == null || !widget.engineReady) return;
    if (!reset && (_loadingMore || !_hasNextPage)) return;
    late final String query;
    late final SourceMangaFetchType type;
    late final ExploreCatalogQuery catalogQuery;
    if (reset) {
      query = _queryCtrl.text.trim();
      final normalizedQuery = normalizeExploreQuery(query);
      type = normalizedQuery.isEmpty ? _fetchType : SourceMangaFetchType.search;
      catalogQuery = ExploreCatalogQuery(
        sourceId: source.id,
        fetchType: type,
        normalizedQuery: normalizedQuery,
      );
    } else {
      final activeQuery = _catalogGate.activeQuery;
      if (activeQuery == null || activeQuery.sourceId != source.id) return;
      catalogQuery = activeQuery;
      type = activeQuery.fetchType;
      query = _submittedQuery;
    }
    final requestedPage = reset ? 1 : _page + 1;
    final request = reset
        ? _catalogGate.reset(catalogQuery)
        : _catalogGate.next(catalogQuery, requestedPage);
    if (request == null) return;
    if (reset) {
      _submittedQuery = query;
      setState(() {
        _loadingCatalog = true;
        _loadingMore = false;
        _catalogError = null;
        _paginationError = null;
        _page = 1;
        _results = [];
        _hasNextPage = false;
      });
    } else {
      setState(() {
        _loadingMore = true;
        _paginationError = null;
      });
    }
    try {
      final result = await api.fetchSourceManga(
        sourceId: source.id,
        type: type,
        query: type == SourceMangaFetchType.search ? query : null,
        page: requestedPage,
      );
      if (!mounted ||
          !_catalogGate.accepts(request) ||
          !widget.engineReady ||
          !identical(widget.api, api)) {
        return;
      }
      setState(() {
        _results = reset ? result.items : [..._results, ...result.items];
        _page = requestedPage;
        _hasNextPage = result.hasNextPage;
        _loadingCatalog = false;
        _loadingMore = false;
        if (reset) {
          _catalogError = null;
        } else {
          _paginationError = null;
        }
      });
    } catch (error) {
      if (!mounted ||
          !_catalogGate.accepts(request) ||
          !widget.engineReady ||
          !identical(widget.api, api)) {
        return;
      }
      setState(() {
        if (reset) {
          _catalogError = '$error';
        } else {
          _paginationError = '$error';
        }
        _loadingCatalog = false;
        _loadingMore = false;
      });
    } finally {
      _catalogGate.complete(request);
    }
  }

  void _openManga(MangaSummary manga) {
    final api = widget.api;
    if (api == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MangaDetailScreen(api: api, mangaId: manga.id),
      ),
    );
  }

  bool _catalogTypeSelected(SourceMangaFetchType type) {
    final active = _catalogGate.activeQuery;
    return active != null &&
        active.sourceId == _selected?.id &&
        active.fetchType == type &&
        active.normalizedQuery.isEmpty;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      YomuScreenHeader(
        title: 'Explorar',
        subtitle: 'Descubra obras e gerencie como o Yomu encontra conteúdo',
        trailing: _ExploreSegments(
          selected: _tab,
          onSelected: (tab) => setState(() => _tab = tab),
        ),
      ),
      Expanded(child: _tabBody()),
    ],
  );

  Widget _tabBody() => switch (_tab) {
    _ExploreTab.sources => _sourcesBody(),
    _ExploreTab.extensions => ExtensionsScreen(
      api: widget.api,
      engineReady: widget.engineReady,
      embedded: true,
      onSourcesChanged: refreshSources,
    ),
    _ExploreTab.repositories => ExtensionsScreen(
      api: widget.api,
      engineReady: widget.engineReady,
      embedded: true,
      repositoriesOnly: true,
      onSourcesChanged: refreshSources,
    ),
    _ExploreTab.migration => const _ExplorePlaceholder(
      title: 'Migrar obras entre fontes',
      phase: 'Esta função ainda não foi implementada.',
    ),
    _ExploreTab.creator => const _ExplorePlaceholder(
      title: 'Criador de fontes',
      phase: 'Esta função ainda não foi implementada.',
    ),
  };

  Widget _sourcesBody() {
    if (!widget.engineReady) {
      return const _ExplorePlaceholder(
        title: 'Fontes indisponíveis',
        phase:
            'Inicie o Suwayomi em Servidor e Motor para carregar fontes reais.',
      );
    }
    if (_catalogOpen && _selected != null) return _catalogBody();
    final languages = _sources.map((source) => source.lang).toSet();
    return RefreshIndicator(
      onRefresh: _loadSources,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 18, 28, 30),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    value: '${_sources.length} fontes',
                    label: 'prontas para navegar',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    value: '${languages.length} idiomas',
                    label: languages.isEmpty
                        ? 'nenhum disponível'
                        : languages
                              .map((lang) => lang.toUpperCase())
                              .join(' · '),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: _MetricCard(
                    value: 'Motor ativo',
                    label: 'catálogos disponíveis',
                    success: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const YomuSectionLabel('Fontes disponíveis'),
          const SizedBox(height: 10),
          if (_loadingSources)
            Semantics(
              container: true,
              liveRegion: true,
              label: 'Carregando fontes',
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 44),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_sourcesError != null)
            _InlineError(message: _sourcesError!, onRetry: _loadSources)
          else if (_sources.isEmpty)
            const _EmptyPanel(
              icon: YomuIcons.library,
              title: 'Nenhuma fonte disponível',
              message: 'Instale uma extensão real ou configure um repositório.',
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 70,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _sources.length,
                itemBuilder: (context, index) {
                  final source = _sources[index];
                  return _SourceCard(
                    source: source,
                    iconUrl: widget.api?.absoluteUrl(source.iconUrl),
                    onTap: () => _openSource(source),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _catalogBody() {
    final source = _selected!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 4),
          child: Row(
            children: [
              YomuIconButton(
                tooltip: 'Voltar às fontes',
                icon: YomuIcons.chevronLeft,
                size: 32,
                iconSize: 16,
                onTap: () => setState(() {
                  _catalogGate.invalidate();
                  _catalogOpen = false;
                  _results = [];
                  _loadingCatalog = false;
                  _loadingMore = false;
                  _catalogError = null;
                  _paginationError = null;
                }),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: YomuTokens.text,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              _CatalogChip(
                label: 'Popular',
                selected: _catalogTypeSelected(SourceMangaFetchType.popular),
                onTap: () {
                  _queryCtrl.clear();
                  setState(() => _fetchType = SourceMangaFetchType.popular);
                  _loadCatalog(reset: true);
                },
              ),
              const SizedBox(width: 5),
              _CatalogChip(
                label: 'Recentes',
                selected: _catalogTypeSelected(SourceMangaFetchType.latest),
                onTap: () {
                  _queryCtrl.clear();
                  setState(() => _fetchType = SourceMangaFetchType.latest);
                  _loadCatalog(reset: true);
                },
              ),
              const Spacer(),
              SizedBox(
                width: 270,
                height: 44,
                child: TextField(
                  controller: _queryCtrl,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Buscar nesta fonte…',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: YomuIcon(
                        YomuIcons.search,
                        size: 14,
                        color: YomuTokens.textSubtle,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    suffixIcon: _queryCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpar busca',
                            onPressed: () {
                              _queryCtrl.clear();
                              _loadCatalog(reset: true);
                            },
                            icon: const YomuIcon(
                              YomuIcons.close,
                              size: 14,
                              color: YomuTokens.textSubtle,
                            ),
                          ),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _loadCatalog(reset: true),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 0, 28, 8),
          child: Text(
            'Catálogo requer internet · via motor local',
            style: TextStyle(color: YomuTokens.textSubtle, fontSize: 11),
          ),
        ),
        if (_loadingCatalog)
          Semantics(
            container: true,
            liveRegion: true,
            label: 'Carregando catálogo',
            child: LinearProgressIndicator(minHeight: 2),
          ),
        Expanded(
          child: _loadingCatalog && _results.isEmpty
              ? Center(
                  child: ExcludeSemantics(child: CircularProgressIndicator()),
                )
              : _catalogError != null && _results.isEmpty
              ? Center(
                  child: _InlineError(
                    message: _catalogError!,
                    onRetry: () => _loadCatalog(reset: true),
                  ),
                )
              : _results.isEmpty
              ? const _EmptyPanel(
                  icon: YomuIcons.search,
                  title: 'Nenhuma obra encontrada',
                  message: 'Tente outra busca ou volte ao catálogo Popular.',
                )
              : Column(
                  children: [
                    if (_paginationError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
                        child: _InlineError(
                          message: _paginationError!,
                          onRetry: () => _loadCatalog(reset: false),
                        ),
                      ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 940
                              ? 6
                              : constraints.maxWidth >= 850
                              ? 5
                              : constraints.maxWidth >= 650
                              ? 4
                              : 3;
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(28, 8, 28, 30),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  childAspectRatio: 0.66,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 18,
                                ),
                            itemCount: _results.length + (_hasNextPage ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _results.length) {
                                return Center(
                                  child: FilledButton.tonal(
                                    onPressed: _loadingMore
                                        ? null
                                        : () => _loadCatalog(reset: false),
                                    child: Text(
                                      _loadingMore
                                          ? 'Carregando…'
                                          : 'Carregar mais',
                                    ),
                                  ),
                                );
                              }
                              final manga = _results[index];
                              return _CatalogCard(
                                manga: manga,
                                imageUrl: widget.api?.absoluteUrl(
                                  manga.thumbnailUrl,
                                ),
                                onTap: () => _openManga(manga),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ExploreSegments extends StatelessWidget {
  const _ExploreSegments({required this.selected, required this.onSelected});
  final _ExploreTab selected;
  final ValueChanged<_ExploreTab> onSelected;
  static const labels = {
    _ExploreTab.sources: 'Fontes',
    _ExploreTab.extensions: 'Extensões',
    _ExploreTab.repositories: 'Repositórios',
    _ExploreTab.migration: 'Migração',
    _ExploreTab.creator: 'Criador de fontes',
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0xFF0B0E14),
      border: Border.all(color: YomuTokens.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: _ExploreTab.values.map((tab) {
        final active = tab == selected;
        return Semantics(
          container: true,
          button: true,
          selected: active,
          label: labels[tab],
          onTap: () => onSelected(tab),
          child: ExcludeSemantics(
            child: TextButton(
              onPressed: () => onSelected(tab),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: active
                    ? const Color(0xFFEEF1FF)
                    : YomuTokens.textMuted,
                backgroundColor: active
                    ? const Color(0xFF34457F)
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(labels[tab]!),
            ),
          ),
        );
      }).toList(),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.value,
    required this.label,
    this.success = false,
  });
  final String value;
  final String label;
  final bool success;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 130),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: YomuTokens.cardWash,
      border: Border.all(color: YomuTokens.cardBorder),
      borderRadius: BorderRadius.circular(YomuTokens.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: success ? YomuTokens.success : YomuTokens.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: YomuTokens.textSubtle, fontSize: 10),
        ),
      ],
    ),
  );
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.iconUrl,
    required this.onTap,
  });
  final SourceInfo source;
  final String? iconUrl;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => YomuSectionCard(
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _SourceLogo(source: source, iconUrl: iconUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: YomuTokens.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${source.lang.toUpperCase()} · Extensão · Suwayomi',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: YomuTokens.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const YomuIcon(
              YomuIcons.chevronRight,
              color: YomuTokens.textSubtle,
              size: 15,
            ),
          ],
        ),
      ),
    ),
  );
}

class _SourceLogo extends StatelessWidget {
  const _SourceLogo({required this.source, required this.iconUrl});
  final SourceInfo source;
  final String? iconUrl;
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF29365F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        source.name.isEmpty ? '?' : source.name.substring(0, 1).toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFDCE2FF),
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (iconUrl == null || iconUrl!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        iconUrl!,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _CatalogChip extends StatelessWidget {
  const _CatalogChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    child: ExcludeSemantics(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          backgroundColor: selected ? YomuTokens.accent : YomuTokens.surface2,
          foregroundColor: selected ? Colors.white : YomuTokens.textMuted,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Text(label),
      ),
    ),
  );
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    required this.manga,
    required this.imageUrl,
    required this.onTap,
  });
  final MangaSummary manga;
  final String? imageUrl;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              color: YomuTokens.surface2,
              child: imageUrl == null || imageUrl!.isEmpty
                  ? Center(
                      child: Text(
                        manga.title.isEmpty ? '?' : manga.title.substring(0, 1),
                        style: const TextStyle(
                          color: YomuTokens.textMuted,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: YomuIcon(
                          YomuIcons.bookOpen,
                          size: 24,
                          color: YomuTokens.textSubtle,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          manga.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: YomuTokens.text,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          manga.inLibrary ? 'Na biblioteca' : 'Catálogo',
          style: const TextStyle(color: YomuTokens.textSubtle, fontSize: 10.5),
        ),
      ],
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 640),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: YomuTokens.danger.withValues(alpha: 0.09),
      border: Border.all(color: YomuTokens.danger.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          liveRegion: true,
          label: 'A fonte não respondeu. $message',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A fonte não respondeu',
                  style: TextStyle(
                    color: YomuTokens.danger,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: YomuTokens.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
      ],
    ),
  );
}

class _ExplorePlaceholder extends StatelessWidget {
  const _ExplorePlaceholder({required this.title, required this.phase});
  final String title;
  final String phase;
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 560,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: YomuTokens.surface.withValues(alpha: 0.82),
        border: Border.all(color: YomuTokens.border),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: YomuTokens.text,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            phase,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: YomuTokens.textMuted,
              fontSize: 12.5,
              height: 1.55,
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final YomuIconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 405,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: YomuTokens.surface,
        border: Border.all(color: YomuTokens.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          YomuIcon(icon, color: YomuTokens.focus, size: 28),
          const SizedBox(height: 13),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: YomuTokens.text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: YomuTokens.textMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    ),
  );
}
