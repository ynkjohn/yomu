import 'package:flutter/material.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

import 'manga_detail_screen.dart';
import 'reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.api,
    required this.engineReady,
  });

  final SuwayomiApi? api;
  final bool engineReady;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _filterController = TextEditingController();
  bool _loading = false;
  String? _error;
  List<MangaSummary> _items = [];
  String _filter = '';
  int _loadGeneration = 0;

  @override
  void dispose() {
    _loadGeneration++;
    _filterController.dispose();
    super.dispose();
  }

  void _clearFilter() {
    _filterController.clear();
    setState(() => _filter = '');
  }

  @override
  void initState() {
    super.initState();
    if (widget.engineReady) {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.engineReady && !oldWidget.engineReady) {
      _load();
    } else if (!widget.engineReady && oldWidget.engineReady) {
      _loadGeneration++;
      _loading = false;
      _error = null;
      _items = const [];
    }
  }

  List<MangaSummary> get _filtered {
    final query = _filter.trim().toLowerCase();
    if (query.isEmpty) return _items;
    return _items
        .where((manga) => manga.title.toLowerCase().contains(query))
        .toList(growable: false);
  }

  Future<void> _load() async {
    final api = widget.api;
    if (api == null || !widget.engineReady) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await api.listLibrary();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _continueReading(MangaSummary m) async {
    final api = widget.api;
    if (api == null) return;
    final last = m.lastReadChapter;
    if (last == null) {
      // Open detail so user picks a chapter.
      _openDetail(m.id);
      return;
    }
    try {
      var chapters = await api.listMangaChapters(m.id);
      if (chapters.isEmpty) {
        chapters = await api.fetchMangaChapters(m.id);
      }
      ChapterInfo chapter = last;
      final match = chapters.where((c) => c.id == last.id);
      if (match.isNotEmpty) {
        chapter = match.first;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            api: api,
            mangaId: m.id,
            mangaTitle: m.title,
            chapter: chapter,
            chapters: chapters.isEmpty ? [chapter] : chapters,
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Continuar leitura falhou: $e')));
    }
  }

  void _openDetail(int id) {
    final api = widget.api;
    if (api == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => MangaDetailScreen(api: api, mangaId: id),
          ),
        )
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.engineReady) {
      return const AsyncBody(
        isLoading: false,
        isEmpty: true,
        emptyMessage: 'Inicie o Suwayomi para ver a biblioteca.',
        child: SizedBox.shrink(),
      );
    }

    final list = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YomuScreenHeader(
          title: 'Biblioteca',
          subtitle: 'Sua coleção, progresso e leitura offline em um só lugar',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _LibrarySegments(),
              const SizedBox(width: 14),
              Text(
                '${_items.length} títulos',
                style: const TextStyle(
                  color: YomuTokens.textSubtle,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              YomuIconButton(
                tooltip: 'Atualizar biblioteca',
                icon: YomuIcons.refresh,
                onTap: _loading ? null : _load,
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const _LibrarySkeleton()
              : AsyncBody(
                  isLoading: false,
                  error: _error,
                  onRetry: _load,
                  isEmpty: _items.isEmpty,
                  emptyMessage:
                      'Biblioteca vazia. Em Explorar, abra uma obra e use “Adicionar à biblioteca”.',
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 18, 28, 30),
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Row(
                            children: [
                              Expanded(
                                child: _LibraryMetric(
                                  value: '${_items.length} títulos',
                                  label: 'na coleção',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _LibraryMetric(
                                  value:
                                      '${_items.fold<int>(0, (sum, manga) => sum + (manga.unreadCount ?? 0))} capítulos',
                                  label: 'não lidos',
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: _LibraryMetric(
                                  value: 'Indisponível',
                                  label: 'armazenamento offline',
                                  pending: true,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: _LibraryMetric(
                                  value: 'Indisponível',
                                  label: 'sequência de leitura',
                                  pending: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 18)),
                        SliverToBoxAdapter(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 320,
                              child: TextField(
                                key: const ValueKey('library-title-filter'),
                                controller: _filterController,
                                onChanged: (value) =>
                                    setState(() => _filter = value),
                                style: const TextStyle(
                                  color: YomuTokens.text,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Filtrar por título',
                                  prefixIcon: const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: YomuIcon(
                                      YomuIcons.search,
                                      size: 17,
                                      color: YomuTokens.textSubtle,
                                    ),
                                  ),
                                  suffixIcon: _filter.isEmpty
                                      ? null
                                      : YomuIconButton(
                                          tooltip: 'Limpar filtro',
                                          icon: YomuIcons.close,
                                          onTap: _clearFilter,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 14)),
                        if (list.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 56),
                              child: Column(
                                children: [
                                  const Text(
                                    'Nenhum título corresponde à busca.',
                                    style: TextStyle(
                                      color: YomuTokens.textMuted,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: _clearFilter,
                                    child: const Text('Limpar filtro'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 6,
                                  childAspectRatio: 0.62,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final manga = list[index];
                              return _LibraryCard(
                                manga: manga,
                                thumbnailUrl: widget.api?.absoluteUrl(
                                  manga.thumbnailUrl,
                                ),
                                onOpen: () => _openDetail(manga.id),
                                onContinue: manga.lastReadChapter == null
                                    ? null
                                    : () => _continueReading(manga),
                              );
                            }, childCount: list.length),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _LibrarySkeleton extends StatefulWidget {
  const _LibrarySkeleton();

  @override
  State<_LibrarySkeleton> createState() => _LibrarySkeletonState();
}

class _LibrarySkeletonState extends State<_LibrarySkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 30),
      child: TickerMode(
        enabled: !reduceMotion,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Opacity(
            opacity: reduceMotion ? 1 : 0.55 + _controller.value * 0.45,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                childAspectRatio: 3 / 4,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: 6,
              itemBuilder: (_, _) => DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF171C27),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LibrarySegments extends StatelessWidget {
  const _LibrarySegments();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0xFF0B0E14),
      border: Border.all(color: YomuTokens.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LibrarySegment(label: 'Tudo', selected: true),
        _LibrarySegment(label: 'Lendo'),
        _LibrarySegment(label: 'Pausados'),
        _LibrarySegment(label: 'Concluídos'),
      ],
    ),
  );
}

class _LibrarySegment extends StatelessWidget {
  const _LibrarySegment({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: selected,
    selected: selected,
    label: selected ? '$label, filtro ativo' : '$label, Not implemented yet',
    child: ExcludeSemantics(
      child: Tooltip(
        message: selected
            ? 'Filtro ativo'
            : 'Not implemented yet — estado pessoal previsto para P2+.',
        child: SizedBox(
          height: 44,
          child: Center(
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF34457F) : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFFEEF1FF)
                      : YomuTokens.textSubtle,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _LibraryMetric extends StatelessWidget {
  const _LibraryMetric({
    required this.value,
    required this.label,
    this.pending = false,
  });

  final String value;
  final String label;
  final bool pending;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0x06FFFFFF),
      border: Border.all(color: const Color(0x0FFFFFFF)),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: pending ? YomuTokens.textSubtle : YomuTokens.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(color: YomuTokens.textSubtle, fontSize: 10),
        ),
      ],
    ),
  );
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.manga,
    required this.thumbnailUrl,
    required this.onOpen,
    this.onContinue,
  });

  final MangaSummary manga;
  final String? thumbnailUrl;
  final VoidCallback onOpen;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final unread = manga.unreadCount ?? 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        onDoubleTap: onContinue,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _LibraryCover(url: thumbnailUrl, title: manga.title),
                  if (unread > 0)
                    Positioned(
                      top: 7,
                      right: 7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: YomuTokens.accentStrong,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              manga.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFDCE0E8),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              manga.lastReadChapter?.name ?? 'Sem progresso',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: YomuTokens.textSubtle,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryCover extends StatelessWidget {
  const _LibraryCover({required this.url, required this.title});

  final String? url;
  final String title;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF34457F), Color(0xFF1A2030)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        title.isEmpty ? 'Y' : title[0].toUpperCase(),
        style: const TextStyle(
          color: Color(0xBFFFFFFF),
          fontSize: 30,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
