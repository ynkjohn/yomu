import 'package:flutter/material.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

import 'manga_detail_screen.dart';

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
  final _queryCtrl = TextEditingController(text: 'berserk');
  List<SourceInfo> _sources = [];
  SourceInfo? _selected;
  List<MangaSummary> _results = [];
  bool _loadingSources = false;
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.engineReady) {
      _loadSources();
    }
  }

  @override
  void didUpdateWidget(covariant ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.engineReady && !oldWidget.engineReady) {
      _loadSources();
    }
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    final api = widget.api;
    if (api == null || !widget.engineReady) return;
    setState(() {
      _loadingSources = true;
      _error = null;
    });
    try {
      final sources = await api.listSources();
      final usable = sources.where((s) => s.id != '0').toList();
      SourceInfo? preferred;
      for (final s in usable) {
        if (s.name == 'MangaDex' && s.lang == 'en') {
          preferred = s;
          break;
        }
      }
      preferred ??= usable.isEmpty ? null : usable.first;
      if (!mounted) return;
      setState(() {
        _sources = usable;
        _selected = preferred;
        _loadingSources = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingSources = false;
      });
    }
  }

  Future<void> _search() async {
    final api = widget.api;
    final source = _selected;
    if (api == null || source == null) return;
    final q = _queryCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await api.searchManga(sourceId: source.id, query: q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _searching = false;
        _results = [];
      });
    }
  }

  void _openManga(MangaSummary m) {
    final api = widget.api;
    if (api == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MangaDetailScreen(api: api, mangaId: m.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.engineReady) {
      return const AsyncBody(
        isLoading: false,
        isEmpty: true,
        emptyMessage: 'Inicie o Suwayomi e instale uma extensão (ex.: MangaDex).',
        child: SizedBox.shrink(),
      );
    }

    final api = widget.api;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(YomuTokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Explorar', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                'Busca via fetchSourceManga (SEARCH). Source MangaDex EN preferida.',
                style: TextStyle(color: YomuTokens.textMuted),
              ),
              const SizedBox(height: 12),
              if (_loadingSources)
                const LinearProgressIndicator(minHeight: 2)
              else
                DropdownButtonFormField<SourceInfo>(
                  // ignore: deprecated_member_use
                  value: _selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Source',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _sources
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text('${s.name} (${s.lang}) · ${s.id}'),
                        ),
                      )
                      .toList(),
                  onChanged: (s) => setState(() => _selected = s),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Busca',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _searching || _selected == null ? null : _search,
                    child: Text(_searching ? '…' : 'Buscar'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _loadingSources ? null : _loadSources,
                    child: const Text('Sources'),
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
        if (_searching) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: AsyncBody(
            isLoading: false,
            isEmpty: _results.isEmpty && !_searching,
            emptyMessage: 'Sem resultados. Tente “berserk” com MangaDex EN.',
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final m = _results[i];
                final thumb = api?.absoluteUrl(m.thumbnailUrl);
                return ListTile(
                  leading: _Thumb(url: thumb),
                  title: Text(m.title),
                  subtitle: Text('id=${m.id}'),
                  onTap: () => _openManga(m),
                  trailing: const Icon(Icons.chevron_right),
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
