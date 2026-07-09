import 'package:flutter/material.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

import 'reader_screen.dart';

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
  bool _loading = true;
  String? _error;
  MangaDetails? _manga;
  List<ChapterInfo> _chapters = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details = await widget.api.getManga(widget.mangaId);
      var chapters = await widget.api.fetchMangaChapters(widget.mangaId);
      if (chapters.isEmpty) {
        chapters = await widget.api.listMangaChapters(widget.mangaId);
      }
      if (!mounted) return;
      setState(() {
        _manga = details;
        _chapters = chapters;
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

  void _openChapter(ChapterInfo ch) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          api: widget.api,
          mangaId: widget.mangaId,
          mangaTitle: _manga?.title ?? 'Manga',
          chapter: ch,
          chapters: _chapters,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = _manga;
    final thumb = m == null ? null : widget.api.absoluteUrl(m.thumbnailUrl);

    return Scaffold(
      appBar: AppBar(
        title: Text(m?.title ?? 'Obra #${widget.mangaId}'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: AsyncBody(
        isLoading: _loading,
        error: _error,
        onRetry: _load,
        child: m == null
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(YomuTokens.space4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (thumb != null && thumb.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              thumb,
                              width: 120,
                              height: 170,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 120,
                                height: 170,
                                color: YomuTokens.surfaceHover,
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 120,
                            height: 170,
                            color: YomuTokens.surfaceHover,
                          ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              if (m.author != null) Text('Autor: ${m.author}'),
                              if (m.artist != null) Text('Artista: ${m.artist}'),
                              if (m.status != null) Text('Status: ${m.status}'),
                              Text(
                                'id=${m.id} sourceId=${m.sourceId ?? "—"}',
                                style: const TextStyle(
                                  color: YomuTokens.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_chapters.isNotEmpty)
                                FilledButton(
                                  onPressed: () => _openChapter(_chapters.first),
                                  child: Text(
                                    'Abrir primeiro capítulo (${_chapters.first.name})',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (m.description != null && m.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        m.description!,
                        maxLines: 8,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: YomuTokens.textMuted),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Capítulos (${_chapters.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (_chapters.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Nenhum capítulo encontrado para esta obra. '
                        'No MangaDex isso pode ocorrer em alguns títulos; '
                        'volte e escolha outra obra da busca.',
                        style: TextStyle(color: YomuTokens.warning),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: _chapters.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final ch = _chapters[i];
                          return ListTile(
                            title: Text(ch.name),
                            subtitle: Text(
                              [
                                if (ch.chapterNumber != null)
                                  'nº ${ch.chapterNumber}',
                                if (ch.scanlator != null) ch.scanlator!,
                                'id=${ch.id}',
                              ].join(' · '),
                            ),
                            trailing: const Icon(Icons.menu_book_outlined),
                            onTap: () => _openChapter(ch),
                          );
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
