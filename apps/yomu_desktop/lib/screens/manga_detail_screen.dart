import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

import 'reader_screen.dart';

enum _ChapterFilter { all, unread, downloaded }

class MangaDetailScreen extends StatefulWidget {
  const MangaDetailScreen({
    super.key,
    required this.api,
    required this.mangaId,
  });

  final SuwayomiApi api;
  final int mangaId;

  @override
  State<MangaDetailScreen> createState() => _MangaDetailScreenState();
}

class _MangaDetailScreenState extends State<MangaDetailScreen> {
  final _chapterQuery = TextEditingController();
  bool _loading = true;
  bool _loadingChapters = false;
  bool _busy = false;
  bool _sortDescending = true;
  String? _error;
  String? _chapterError;
  String? _sourceName;
  MangaDetails? _manga;
  List<ChapterInfo> _chapters = [];
  _ChapterFilter _filter = _ChapterFilter.all;

  @override
  void initState() {
    super.initState();
    _chapterQuery.addListener(_refreshFilter);
    _load();
  }

  @override
  void dispose() {
    _chapterQuery.removeListener(_refreshFilter);
    _chapterQuery.dispose();
    super.dispose();
  }

  void _refreshFilter() => setState(() {});

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details = await widget.api.getManga(widget.mangaId);
      if (!mounted) return;
      setState(() {
        _manga = details;
        _loading = false;
      });
      unawaited(_resolveSourceName(details.sourceId));
      unawaited(_loadChapters());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _resolveSourceName(String? sourceId) async {
    if (sourceId == null) return;
    try {
      final sources = await widget.api.listSources();
      for (final source in sources) {
        if (source.id == sourceId) {
          if (mounted) setState(() => _sourceName = source.name);
          return;
        }
      }
    } catch (_) {
      // Source name is supplementary; keep the functional page available.
    }
  }

  Future<void> _loadChapters() async {
    setState(() {
      _loadingChapters = true;
      _chapterError = null;
    });
    try {
      var chapters = await widget.api.fetchMangaChapters(widget.mangaId);
      if (chapters.isEmpty) {
        chapters = await widget.api.listMangaChapters(widget.mangaId);
      }
      if (!mounted) return;
      setState(() {
        _chapters = chapters;
        _loadingChapters = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _chapterError = '$error';
        _loadingChapters = false;
      });
    }
  }

  Future<void> _toggleLibrary() async {
    final manga = _manga;
    if (manga == null) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.api.setInLibrary(manga.id, !manga.inLibrary);
      if (!mounted) return;
      setState(() => _manga = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updated.inLibrary
                ? 'Adicionado à biblioteca'
                : 'Removido da biblioteca',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Biblioteca: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadChapter(ChapterInfo chapter) async {
    setState(() => _busy = true);
    try {
      await widget.api.enqueueChapterDownloads([chapter.id]);
      await widget.api.startDownloader();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download enfileirado: ${chapter.name}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadAll() async {
    if (_chapters.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.api.enqueueChapterDownloads(
        _chapters.map((chapter) => chapter.id).toList(),
      );
      await widget.api.startDownloader();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_chapters.length} capítulos enfileirados')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openChapter(ChapterInfo chapter, {bool openSettings = false}) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ReaderScreen(
              api: widget.api,
              mangaId: widget.mangaId,
              mangaTitle: _manga?.title ?? 'Mangá',
              chapter: chapter,
              chapters: _chronologicalChapters,
              openSettingsOnStart: openSettings,
            ),
          ),
        )
        .then((_) => _load());
  }

  /// Canonical reading order: ascending `sourceOrder` (fallback id).
  /// Reader adjacency must use this list, not the raw API order or UI filter.
  List<ChapterInfo> get _chronologicalChapters {
    final list = List<ChapterInfo>.from(_chapters);
    int order(ChapterInfo chapter) => chapter.sourceOrder ?? chapter.id;
    list.sort((a, b) => order(a).compareTo(order(b)));
    return list;
  }

  ChapterInfo? get _continueChapter {
    final ordered = _chronologicalChapters;
    for (final chapter in ordered) {
      if (!chapter.isRead && (chapter.lastPageRead ?? 0) > 0) return chapter;
    }
    for (final chapter in ordered) {
      if (!chapter.isRead) return chapter;
    }
    return ordered.isEmpty ? null : ordered.first;
  }

  List<ChapterInfo> get _filteredChapters {
    final query = _chapterQuery.text.trim().toLowerCase();
    final filtered = _chapters.where((chapter) {
      if (_filter == _ChapterFilter.unread && chapter.isRead) {
        return false;
      }
      if (_filter == _ChapterFilter.downloaded && !chapter.isDownloaded) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final number = chapter.chapterNumber?.toString() ?? '';
      return chapter.name.toLowerCase().contains(query) ||
          number.contains(query);
    }).toList();
    int order(ChapterInfo chapter) => chapter.sourceOrder ?? chapter.id;
    filtered.sort(
      (a, b) => _sortDescending
          ? order(b).compareTo(order(a))
          : order(a).compareTo(order(b)),
    );
    return filtered;
  }

  String get _statusLabel {
    final raw = _manga?.status?.trim();
    if (raw == null || raw.isEmpty || raw.toUpperCase() == 'UNKNOWN') {
      return 'Status não informado';
    }
    return raw.toLowerCase().replaceFirstMapped(
      RegExp(r'^.'),
      (match) => match.group(0)!.toUpperCase(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manga = _manga;
    return Scaffold(
      backgroundColor: YomuTokens.bg,
      body: AsyncBody(
        isLoading: _loading,
        error: _error,
        onRetry: _load,
        child: manga == null
            ? const SizedBox.shrink()
            : Column(
                children: [
                  _topbar(manga),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _hero(manga),
                            const SizedBox(height: 18),
                            if (constraints.maxWidth >= 920)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _chapterPanel()),
                                  const SizedBox(width: 18),
                                  SizedBox(width: 258, child: _sideStack()),
                                ],
                              )
                            else ...[
                              _sideStack(),
                              const SizedBox(height: 14),
                              _chapterPanel(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _topbar(MangaDetails manga) => Container(
    constraints: const BoxConstraints(minHeight: 60),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0x0EFFFFFF))),
    ),
    child: Row(
      children: [
        YomuIconButton(
          tooltip: 'Voltar',
          icon: YomuIcons.chevronLeft,
          onTap: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 12),
        const Text(
          'Biblioteca',
          style: TextStyle(color: YomuTokens.textSubtle, fontSize: 12),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 7),
          child: YomuIcon(
            YomuIcons.chevronRight,
            size: 14,
            color: YomuTokens.textSubtle,
          ),
        ),
        Expanded(
          child: Text(
            manga.title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: YomuTokens.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        YomuIconButton(
          tooltip: manga.inLibrary
              ? 'Remover da biblioteca'
              : 'Adicionar à biblioteca',
          icon: YomuIcons.bookmark,
          color: manga.inLibrary ? YomuTokens.focus : null,
          onTap: _busy ? null : _toggleLibrary,
        ),
        const SizedBox(width: 7),
        YomuIconButton(
          tooltip: 'Atualizar',
          icon: YomuIcons.refresh,
          onTap: _loading ? null : _load,
        ),
      ],
    ),
  );

  Widget _hero(MangaDetails manga) {
    final cover = widget.api.absoluteUrl(manga.thumbnailUrl);
    final chapter = _continueChapter;
    final pageCount = chapter?.pageCount ?? 0;
    final page = chapter?.lastPageRead ?? 0;
    final progress = pageCount > 0
        ? ((page + 1) / pageCount).clamp(0.0, 1.0)
        : 0.0;
    final progressPct = (progress * 100).round();
    final unread = _chapters.where((item) => !item.isRead).length;
    return Container(
      constraints: const BoxConstraints(minHeight: 246),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(-1, -0.58),
          end: Alignment(1, 0.58),
          colors: [Color(0xF5191E2B), Color(0xFA0E121A)],
        ),
        border: Border.all(color: YomuTokens.border),
        borderRadius: BorderRadius.circular(YomuTokens.radiusXl),
        boxShadow: const [
          BoxShadow(
            color: Color(0x38000000),
            blurRadius: 42,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cover(cover, manga.title, progressPct),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    children: [
                      if (manga.inLibrary)
                        const _MangaChip(label: 'Na biblioteca', accent: true),
                      _MangaChip(label: _statusLabel),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    manga.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: YomuTokens.text,
                      fontSize: 32,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.1,
                    ),
                  ),
                  if (manga.author != null &&
                      manga.author!.trim().isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      manga.author!,
                      style: const TextStyle(
                        color: YomuTokens.focus,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    '${_sourceName ?? 'Fonte Suwayomi'}  ·  ${_chapters.length} capítulos  ·  $unread não lidos',
                    style: const TextStyle(
                      color: YomuTokens.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                  const Spacer(),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: chapter == null
                            ? null
                            : () => _openChapter(chapter),
                        icon: const YomuIcon(
                          YomuIcons.play,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: Text(
                          chapter == null
                              ? 'Sem capítulos'
                              : (page > 0
                                    ? 'Continuar lendo'
                                    : 'Começar leitura'),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy || _chapters.isEmpty
                            ? null
                            : _downloadAll,
                        icon: const YomuIcon(
                          YomuIcons.download,
                          size: 18,
                          color: Color(0xFFD4DAEA),
                        ),
                        label: const Text('Baixar'),
                      ),
                      if (!manga.inLibrary)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _toggleLibrary,
                          icon: const YomuIcon(
                            YomuIcons.library,
                            size: 18,
                            color: Color(0xFFD4DAEA),
                          ),
                          label: const Text('Adicionar'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            SizedBox(
              width: 244,
              child: _checkpoint(chapter, progressPct, pageCount),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover(String? cover, String title, int progressPct) => SizedBox(
    width: 164,
    height: 218,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: YomuTokens.surface3,
            child: cover == null || cover.isEmpty
                ? Center(
                    child: Text(
                      title.isEmpty ? '?' : title.substring(0, 1),
                      style: const TextStyle(
                        color: YomuTokens.textMuted,
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : Image.network(
                    cover,
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
          if (progressPct > 0)
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xB806080E),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: progressPct / 100,
                        minHeight: 3,
                        backgroundColor: const Color(0x2EFFFFFF),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$progressPct%',
                      style: const TextStyle(
                        color: Color(0xFFE8EBF7),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _checkpoint(
    ChapterInfo? chapter,
    int progressPct,
    int pageCount,
  ) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0x78080B12),
      border: Border.all(color: const Color(0x3D91A5FF)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: chapter == null
        ? const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PRONTO PARA COMEÇAR',
                style: TextStyle(
                  color: YomuTokens.textSubtle,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Nenhum capítulo disponível',
                style: TextStyle(
                  color: YomuTokens.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SEU PONTO DE LEITURA',
                style: TextStyle(
                  color: YomuTokens.textSubtle,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                chapter.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: YomuTokens.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                progressPct > 0
                    ? 'Leitura em andamento'
                    : 'Pronto para começar',
                style: const TextStyle(
                  color: YomuTokens.textMuted,
                  fontSize: 10.5,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: progressPct / 100,
                          strokeWidth: 4,
                          backgroundColor: YomuTokens.surface3,
                          color: YomuTokens.focus,
                        ),
                        Text(
                          '$progressPct%',
                          style: const TextStyle(
                            color: YomuTokens.text,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pageCount > 0
                              ? 'Página ${(chapter.lastPageRead ?? 0) + 1} de $pageCount'
                              : 'Progresso sincronizado',
                          style: const TextStyle(
                            color: YomuTokens.text,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Progresso real do Suwayomi',
                          style: TextStyle(
                            color: YomuTokens.textSubtle,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
  );

  Widget _chapterPanel() {
    final chapters = _filteredChapters;
    return Container(
      decoration: BoxDecoration(
        color: YomuTokens.surface,
        border: Border.all(color: YomuTokens.border),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(
                  'Capítulos',
                  style: const TextStyle(
                    color: YomuTokens.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  '${_chapters.length}',
                  style: const TextStyle(
                    color: YomuTokens.textSubtle,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      key: const ValueKey('chapter-number-filter'),
                      controller: _chapterQuery,
                      decoration: const InputDecoration(
                        hintText: 'Buscar número do capítulo',
                        prefixIcon: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: YomuIcon(
                            YomuIcons.search,
                            size: 14,
                            color: YomuTokens.textSubtle,
                          ),
                        ),
                        prefixIconConstraints: BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                _filterButton('Todos', _ChapterFilter.all),
                _filterButton('Não lidos', _ChapterFilter.unread),
                _filterButton('Baixados', _ChapterFilter.downloaded),
                AnimatedRotation(
                  turns: _sortDescending ? 0 : 0.5,
                  duration: const Duration(milliseconds: 180),
                  child: YomuIconButton(
                    tooltip: _sortDescending
                        ? 'Mais antigos primeiro'
                        : 'Mais recentes primeiro',
                    icon: YomuIcons.refresh,
                    onTap: () =>
                        setState(() => _sortDescending = !_sortDescending),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_loadingChapters)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                children: [
                  LinearProgressIndicator(minHeight: 2),
                  SizedBox(height: 12),
                  Text(
                    'Atualizando capítulos pela fonte…',
                    style: TextStyle(color: YomuTokens.textMuted, fontSize: 12),
                  ),
                ],
              ),
            )
          else if (_chapterError != null)
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  Text(
                    _chapterError!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: YomuTokens.danger,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loadChapters,
                    child: const Text('Tentar de novo'),
                  ),
                ],
              ),
            )
          else if (chapters.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'Nenhum capítulo corresponde à busca ou aos filtros.',
                style: TextStyle(color: YomuTokens.textMuted, fontSize: 12),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 560),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: chapters.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) => _chapterRow(chapters[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterButton(String label, _ChapterFilter value) {
    final active = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: TextButton(
        onPressed: () => setState(() => _filter = value),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: active
              ? const Color(0xFF29365F)
              : Colors.transparent,
          foregroundColor: active
              ? const Color(0xFFE4E8FF)
              : YomuTokens.textMuted,
          side: BorderSide(
            color: active ? const Color(0xFF596DAA) : YomuTokens.border,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _chapterRow(ChapterInfo chapter) {
    final pageCount = chapter.pageCount ?? 0;
    final lastPage = chapter.lastPageRead ?? 0;
    final progress = pageCount > 0 && lastPage > 0
        ? ((lastPage + 1) / pageCount).clamp(0.0, 1.0)
        : 0.0;
    return InkWell(
      onTap: () => _openChapter(chapter),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: chapter.isRead
                    ? YomuTokens.success.withValues(alpha: 0.10)
                    : YomuTokens.surface2,
                borderRadius: BorderRadius.circular(9),
              ),
              child: YomuIcon(
                chapter.isRead ? YomuIcons.check : YomuIcons.bookOpen,
                size: 14,
                color: chapter.isRead
                    ? YomuTokens.success
                    : YomuTokens.textSubtle,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chapter.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: chapter.isRead
                          ? YomuTokens.textMuted
                          : YomuTokens.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (chapter.chapterNumber != null)
                        'Cap. ${chapter.chapterNumber}',
                      if (chapter.scanlator != null &&
                          chapter.scanlator!.isNotEmpty)
                        chapter.scanlator!,
                      if (chapter.isRead) 'Lido',
                    ].join(' · '),
                    style: const TextStyle(
                      color: YomuTokens.textSubtle,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (progress > 0 && !chapter.isRead)
              SizedBox(
                width: 112,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: YomuTokens.surface3,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(
                        color: YomuTokens.textSubtle,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 12),
            if (chapter.isDownloaded)
              const Tooltip(
                message: 'Baixado',
                child: YomuIcon(
                  YomuIcons.download,
                  size: 14,
                  color: YomuTokens.success,
                  semanticLabel: 'Baixado',
                ),
              )
            else
              YomuIconButton(
                tooltip: 'Baixar capítulo',
                icon: YomuIcons.download,
                size: 30,
                iconSize: 14,
                onTap: _busy ? null : () => _downloadChapter(chapter),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sideStack() {
    final unread = _chapters.where((chapter) => !chapter.isRead).length;
    final downloaded = _chapters
        .where((chapter) => chapter.isDownloaded)
        .length;
    final chapter = _continueChapter;
    return Column(
      children: [
        _sideCard(
          title: 'Nesta obra',
          child: Column(
            children: [
              _stat('Não lidos', '$unread'),
              _stat('Offline', '$downloaded de ${_chapters.length}'),
              _stat('Fonte ativa', _sourceName ?? 'Suwayomi'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sideCard(
          title: 'Preferência de leitura',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: chapter == null
                    ? null
                    : () => _openChapter(chapter, openSettings: true),
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: YomuTokens.surface2,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Row(
                    children: [
                      YomuIcon(
                        YomuIcons.layoutRtl,
                        size: 18,
                        color: YomuTokens.focus,
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Abrir ajustes do leitor',
                          style: TextStyle(
                            color: YomuTokens.text,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      YomuIcon(
                        YomuIcons.chevronRight,
                        size: 14,
                        color: YomuTokens.textSubtle,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Salva por obra e pode sobrescrever o padrão global.',
                style: TextStyle(
                  color: YomuTokens.textSubtle,
                  fontSize: 9.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sideCard({required String title, required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: YomuTokens.surface,
      border: Border.all(color: YomuTokens.border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: YomuTokens.text,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );

  Widget _stat(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: YomuTokens.textMuted, fontSize: 10.5),
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: YomuTokens.text,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _MangaChip extends StatelessWidget {
  const _MangaChip({required this.label, this.accent = false});
  final String label;
  final bool accent;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: accent
          ? YomuTokens.accent.withValues(alpha: 0.15)
          : YomuTokens.surface2,
      border: Border.all(
        color: accent
            ? YomuTokens.accent.withValues(alpha: 0.45)
            : YomuTokens.border,
      ),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: accent ? YomuTokens.focus : YomuTokens.textMuted,
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
