import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

import 'manga_detail_screen.dart';
import 'reader_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.engineReady,
    required this.onNavigate,
  });

  final SuwayomiApi? api;
  final bool engineReady;
  final ValueChanged<String> onNavigate;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MangaSummary> _library = const [];
  bool _loading = false;
  String? _error;
  int _loadGeneration = 0;

  @override
  void dispose() {
    _loadGeneration++;
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.engineReady) _load();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.engineReady && !oldWidget.engineReady) {
      _load();
    } else if (!widget.engineReady && oldWidget.engineReady) {
      _loadGeneration++;
      _loading = false;
      _error = null;
      _library = const [];
    }
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
      final library = await api.listLibrary();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _library = library;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  void _openDetail(MangaSummary manga) {
    final api = widget.api;
    if (api == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => MangaDetailScreen(api: api, mangaId: manga.id),
          ),
        )
        .then((_) => _load());
  }

  Future<void> _resume(MangaSummary manga) async {
    final api = widget.api;
    final last = manga.lastReadChapter;
    if (api == null || last == null) {
      _openDetail(manga);
      return;
    }
    try {
      var chapters = await api.listMangaChapters(manga.id);
      if (chapters.isEmpty) chapters = await api.fetchMangaChapters(manga.id);
      final matching = chapters.where((chapter) => chapter.id == last.id);
      final chapter = matching.isEmpty ? last : matching.first;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            api: api,
            mangaId: manga.id,
            mangaTitle: manga.title,
            chapter: chapter,
            chapters: chapters.isEmpty ? [chapter] : chapters,
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível retomar a leitura: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ongoing = _library
        .where((manga) => manga.lastReadChapter != null)
        .take(6)
        .toList();
    final unreadTitles = _library
        .where((manga) => (manga.unreadCount ?? 0) > 0)
        .toList(growable: false);
    final updates = unreadTitles.take(3).toList(growable: false);
    final unreadChapterCount = unreadTitles.fold<int>(
      0,
      (sum, manga) => sum + (manga.unreadCount ?? 0),
    );
    final resume = ongoing.isEmpty ? null : ongoing.first;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            widget.onNavigate('explore'),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
              child: Row(
                children: [
                  const Text(
                    'Home',
                    style: TextStyle(
                      color: YomuTokens.text,
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.46,
                    ),
                  ),
                  const Spacer(),
                  Semantics(
                    button: true,
                    label: 'Buscar nas fontes. Atalho Control K',
                    child: SizedBox(
                      width: 300,
                      height: 44,
                      child: Center(
                        child: InkWell(
                          excludeFromSemantics: true,
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => widget.onNavigate('explore'),
                          child: Container(
                            width: 300,
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: YomuTokens.surface2,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0x14FFFFFF),
                              ),
                            ),
                            child: const Row(
                              children: [
                                YomuIcon(
                                  YomuIcons.search,
                                  size: 14,
                                  color: YomuTokens.textSubtle,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Buscar nas fontes…',
                                    style: TextStyle(
                                      color: YomuTokens.textSubtle,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                _ShortcutKey(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const _HomeSkeleton()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
                      children: [
                        if (_error != null)
                          _HomeNotice(
                            color: YomuTokens.danger,
                            message:
                                'Não foi possível carregar a biblioteca. $_error',
                            action: 'Tentar de novo',
                            onPressed: _load,
                          ),
                        if (!widget.engineReady)
                          _HomeNotice(
                            color: YomuTokens.warning,
                            message:
                                'O motor local está parado. Biblioteca remota e novidades estão indisponíveis.',
                            action: 'Abrir Servidor e Motor',
                            onPressed: () => widget.onNavigate('server'),
                          )
                        else if (!_loading && _library.isEmpty)
                          _EmptyHome(
                            onExplore: () => widget.onNavigate('explore'),
                          )
                        else ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: resume == null
                                    ? const _UnavailableCard(
                                        title: 'Continuar lendo',
                                        message:
                                            'Nenhuma leitura em andamento.',
                                      )
                                    : _ResumeCard(
                                        manga: resume,
                                        api: widget.api,
                                        onPressed: () => _resume(resume),
                                      ),
                              ),
                              const SizedBox(width: 14),
                              SizedBox(
                                width: 300,
                                child: _SystemHealthCard(
                                  engineReady: widget.engineReady,
                                  onServer: () => widget.onNavigate('server'),
                                  onDownloads: () =>
                                      widget.onNavigate('downloads'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Em andamento',
                            style: TextStyle(
                              color: Color(0xFFEAECF2),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.15,
                            ),
                          ),
                          const SizedBox(height: 10),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final columns = constraints.maxWidth >= 840
                                  ? 6
                                  : 4;
                              const gap = 14.0;
                              final cardWidth =
                                  (constraints.maxWidth - gap * (columns - 1)) /
                                  columns;
                              if (ongoing.isEmpty) {
                                return const SizedBox(
                                  height: 150,
                                  child: _UnavailableCard(
                                    title: 'Sem leituras em andamento',
                                    message:
                                        'Abra uma obra da biblioteca para começar.',
                                  ),
                                );
                              }
                              return SizedBox(
                                height: cardWidth * 4 / 3 + 48,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (
                                      var index = 0;
                                      index < ongoing.length;
                                      index++
                                    ) ...[
                                      SizedBox(
                                        width: cardWidth,
                                        child: _MediaCard(
                                          manga: ongoing[index],
                                          api: widget.api,
                                          onPressed: () =>
                                              _openDetail(ongoing[index]),
                                        ),
                                      ),
                                      if (index != ongoing.length - 1)
                                        const SizedBox(width: gap),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          _UpdatesPanel(
                            updates: updates,
                            unreadChapterCount: unreadChapterCount,
                            api: widget.api,
                            onOpen: _openDetail,
                            onSeeAll: () => widget.onNavigate('updates'),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeSkeleton extends StatefulWidget {
  const _HomeSkeleton();

  @override
  State<_HomeSkeleton> createState() => _HomeSkeletonState();
}

class _HomeSkeletonState extends State<_HomeSkeleton>
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
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
      child: TickerMode(
        enabled: !reduceMotion,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final opacity = reduceMotion
                ? 1.0
                : 0.55 + _controller.value * 0.45;
            return Opacity(
              opacity: opacity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SkeletonBlock(height: 108, radius: 16),
                  const SizedBox(height: 16),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const gap = 14.0;
                        final width = (constraints.maxWidth - gap * 5) / 6;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var index = 0; index < 6; index++) ...[
                              SizedBox(
                                width: width,
                                child: const AspectRatio(
                                  aspectRatio: 3 / 4,
                                  child: _SkeletonBlock(radius: 12),
                                ),
                              ),
                              if (index != 5) const SizedBox(width: gap),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({this.height, required this.radius});

  final double? height;
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

class _ShortcutKey extends StatelessWidget {
  const _ShortcutKey();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0x1FFFFFFF)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: const Text(
      'Ctrl K',
      style: TextStyle(
        color: YomuTokens.textSubtle,
        fontFamily: 'Consolas',
        fontSize: 10,
      ),
    ),
  );
}

class _HomeNotice extends StatelessWidget {
  const _HomeNotice({
    required this.color,
    required this.message,
    required this.action,
    required this.onPressed,
  });

  final Color color;
  final String message;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(28, 0, 28, 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      border: Border.all(color: color.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(message, style: TextStyle(color: color, fontSize: 12.5)),
        ),
        TextButton(onPressed: onPressed, child: Text(action)),
      ],
    ),
  );
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.onExplore});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 120, 24, 120),
    child: Column(
      children: [
        Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: YomuTokens.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Text(
            'Y',
            style: TextStyle(
              color: YomuTokens.accent,
              fontSize: 36,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Bem-vindo ao Yomu',
          style: TextStyle(
            color: YomuTokens.text,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: const Text(
            'Sua biblioteca está vazia. Explore as fontes para adicionar uma obra.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: YomuTokens.textMuted,
              fontSize: 14.5,
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: onExplore,
          style: FilledButton.styleFrom(
            backgroundColor: YomuTokens.accent,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: BorderSide.none,
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: const Text('Explorar fontes'),
        ),
      ],
    ),
  );
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.manga,
    required this.api,
    required this.onPressed,
  });

  final MangaSummary manga;
  final SuwayomiApi? api;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final chapter = manga.lastReadChapter!;
    final total = chapter.pageCount ?? 0;
    final currentPage = _displayedPageNumber(chapter);
    final progress = total <= 0 ? 0.0 : (currentPage / total).clamp(0.0, 1.0);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF151A24),
            border: Border.all(color: const Color(0x14FFFFFF)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _Cover(
                url: api?.absoluteUrl(manga.thumbnailUrl),
                width: 66,
                height: 90,
                title: manga.title,
                radius: 10,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CONTINUAR LENDO',
                      style: TextStyle(
                        color: YomuTokens.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${manga.title} · ${chapter.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: YomuTokens.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 9),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: YomuTokens.progressTrack,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      total > 0
                          ? 'pág. $currentPage de $total · progresso sincronizado'
                          : 'progresso salvo',
                      style: const TextStyle(
                        color: YomuTokens.textSubtle,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 11,
                  ),
                ),
                icon: const YomuIcon(
                  YomuIcons.play,
                  size: 14,
                  color: Colors.white,
                ),
                label: const Text('Retomar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemHealthCard extends StatelessWidget {
  const _SystemHealthCard({
    required this.engineReady,
    required this.onServer,
    required this.onDownloads,
  });

  final bool engineReady;
  final VoidCallback onServer;
  final VoidCallback onDownloads;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(15, 13, 15, 11),
    decoration: BoxDecoration(
      color: const Color(0xFF121721),
      border: Border.all(color: const Color(0x0FFFFFFF)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SAÚDE DO SISTEMA',
          style: TextStyle(
            color: YomuTokens.textSubtle,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        _HealthRow(
          color: engineReady ? YomuTokens.success : YomuTokens.danger,
          label: engineReady ? 'Motor operando' : 'Motor parado',
          onPressed: onServer,
        ),
        _HealthRow(
          color: YomuTokens.accent,
          label: 'Ver fila de downloads',
          onPressed: onDownloads,
        ),
      ],
    ),
  );
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.color,
    required this.label,
    required this.onPressed,
  });

  final Color color;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: true,
    label: label,
    onTap: onPressed,
    child: ExcludeSemantics(
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: YomuTokens.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ),
              const YomuIcon(
                YomuIcons.chevronRight,
                size: 14,
                color: YomuTokens.textSubtle,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.manga,
    required this.api,
    required this.onPressed,
  });

  final MangaSummary manga;
  final SuwayomiApi? api;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final chapter = manga.lastReadChapter;
    final total = chapter?.pageCount ?? 0;
    final currentPage = chapter == null ? 0 : _displayedPageNumber(chapter);
    final progress = total <= 0 ? 0.0 : (currentPage / total).clamp(0.0, 1.0);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Cover(
            url: api?.absoluteUrl(manga.thumbnailUrl),
            title: manga.title,
            radius: 12,
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: YomuTokens.progressTrack,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            manga.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFD9DCE4),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            chapter?.name ?? 'Sem progresso',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: YomuTokens.textSubtle,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

int _displayedPageNumber(ChapterInfo chapter) {
  final page = (chapter.lastPageRead ?? 0) + 1;
  final safePage = page < 1 ? 1 : page;
  final total = chapter.pageCount ?? 0;
  return total > 0 && safePage > total ? total : safePage;
}

class _UpdatesPanel extends StatelessWidget {
  const _UpdatesPanel({
    required this.updates,
    required this.unreadChapterCount,
    required this.api,
    required this.onOpen,
    required this.onSeeAll,
  });

  final List<MangaSummary> updates;
  final int unreadChapterCount;
  final SuwayomiApi? api;
  final ValueChanged<MangaSummary> onOpen;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          const Text(
            'Capítulos não lidos',
            style: TextStyle(
              color: YomuTokens.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (updates.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: YomuTokens.accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$unreadChapterCount',
                style: const TextStyle(
                  color: Color(0xFFC3CEFF),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          const Spacer(),
          TextButton(onPressed: onSeeAll, child: const Text('Ver todas')),
        ],
      ),
      const SizedBox(height: 6),
      if (updates.isEmpty)
        const _UnavailableCard(
          title: 'Tudo lido',
          message: 'Não há capítulos não lidos na biblioteca.',
        )
      else
        ...updates.map(
          (manga) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _UpdateRow(
              manga: manga,
              api: api,
              onPressed: () => onOpen(manga),
            ),
          ),
        ),
    ],
  );
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({
    required this.manga,
    required this.api,
    required this.onPressed,
  });

  final MangaSummary manga;
  final SuwayomiApi? api;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF141923),
          border: Border.all(color: const Color(0x0FFFFFFF)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _Cover(
              url: api?.absoluteUrl(manga.thumbnailUrl),
              width: 32,
              height: 43,
              title: manga.title,
              radius: 6,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    manga.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: YomuTokens.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${manga.unreadCount ?? 0} capítulos não lidos',
                    style: const TextStyle(
                      color: YomuTokens.textSubtle,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            const YomuIcon(
              YomuIcons.chevronRight,
              size: 14,
              color: YomuTokens.textSubtle,
            ),
          ],
        ),
      ),
    ),
  );
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: YomuTokens.surface.withValues(alpha: 0.82),
      border: Border.all(color: YomuTokens.border),
      borderRadius: BorderRadius.circular(YomuTokens.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: YomuTokens.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          message,
          style: const TextStyle(color: YomuTokens.textSubtle, fontSize: 11.5),
        ),
      ],
    ),
  );
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.url,
    required this.title,
    this.width,
    this.height,
    this.radius = 9,
  });

  final String? url;
  final String title;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final image = url == null || url!.isEmpty
        ? _fallback()
        : ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Image.network(
              url!,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(),
            ),
          );
    if (height != null) {
      return SizedBox(width: width, height: height, child: image);
    }
    return AspectRatio(aspectRatio: 3 / 4, child: image);
  }

  Widget _fallback() => Container(
    width: width,
    height: height,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF34457F), Color(0xFF1A2030)],
      ),
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Text(
      title.isEmpty ? 'Y' : title[0].toUpperCase(),
      style: const TextStyle(
        color: Color(0xD9FFFFFF),
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
