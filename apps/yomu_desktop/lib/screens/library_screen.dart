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
  bool _loading = false;
  String? _error;
  List<MangaSummary> _items = [];
  String _filter = '';

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
    }
  }

  List<MangaSummary> get _filtered {
    final q = _filter.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((m) => m.title.toLowerCase().contains(q)).toList();
  }

  Future<void> _load() async {
    final api = widget.api;
    if (api == null || !widget.engineReady) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await api.listLibrary();
      if (!mounted) return;
      setState(() {
        _items = list;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Continuar leitura falhou: $e')),
      );
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

    final api = widget.api;
    final list = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(YomuTokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Biblioteca',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Obras com inLibrary no Suwayomi. Progresso via lastReadChapter / lastPageRead.',
                style: TextStyle(color: YomuTokens.textMuted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'Filtrar (${_items.length})',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _filter = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _loading ? null : _load,
                    child: const Text('Atualizar'),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: YomuTokens.danger)),
              ],
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: AsyncBody(
            isLoading: false,
            isEmpty: list.isEmpty && !_loading,
            emptyMessage:
                'Biblioteca vazia. Em Explorar, abra uma obra e use “Adicionar à biblioteca”.',
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final m = list[i];
                final thumb = api?.absoluteUrl(m.thumbnailUrl);
                final progress = m.lastReadChapter == null
                    ? 'Sem progresso'
                    : 'Continuar: ${m.lastReadChapter!.name}'
                        '${m.lastReadChapter!.lastPageRead != null ? ' · pág ${m.lastReadChapter!.lastPageRead}' : ''}';
                return ListTile(
                  leading: _Thumb(url: thumb),
                  title: Text(m.title),
                  subtitle: Text(
                    [
                      progress,
                      if (m.unreadCount != null) 'não lidos: ${m.unreadCount}',
                      'id=${m.id}',
                    ].join(' · '),
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      if (m.lastReadChapter != null)
                        TextButton(
                          onPressed: () => _continueReading(m),
                          child: const Text('Continuar'),
                        ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => _openDetail(m.id),
                      ),
                    ],
                  ),
                  onTap: () => _openDetail(m.id),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const SizedBox(
        width: 40,
        height: 56,
        child: ColoredBox(color: YomuTokens.surfaceHover),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        url!,
        width: 40,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox(
          width: 40,
          height: 56,
          child: ColoredBox(color: YomuTokens.surfaceHover),
        ),
      ),
    );
  }
}
