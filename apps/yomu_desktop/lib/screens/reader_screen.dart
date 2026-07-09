import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

/// Minimal paged reader — real images + progress save/resume via Suwayomi.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.api,
    required this.mangaId,
    required this.mangaTitle,
    required this.chapter,
    required this.chapters,
  });

  final SuwayomiApi api;
  final int mangaId;
  final String mangaTitle;
  final ChapterInfo chapter;
  final List<ChapterInfo> chapters;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  bool _loading = true;
  String? _error;
  List<String> _pages = [];
  int _index = 0;
  late ChapterInfo _chapter;
  final _focus = FocusNode();
  Timer? _saveDebounce;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _chapter = widget.chapter;
    _load();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    // Best-effort flush progress on leave.
    unawaited(_saveProgress(force: true));
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Refresh chapter progress from server for resume.
      final remote = await widget.api.getChapter(_chapter.id);
      if (remote != null) {
        _chapter = remote;
      }
      final result = await widget.api.fetchChapterPages(_chapter.id);
      if (!mounted) return;
      var start = 0;
      final last = _chapter.lastPageRead ?? 0;
      if (result.pages.isNotEmpty && last > 0) {
        start = last.clamp(0, result.pages.length - 1);
      }
      setState(() {
        _pages = result.pages;
        _index = start;
        _loading = false;
        if (_pages.isEmpty) {
          _error = 'Nenhuma página retornada para o capítulo ${_chapter.id}.';
        }
      });
      if (_pages.isNotEmpty) {
        unawaited(_saveProgress(force: true));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_saveProgress());
    });
  }

  Future<void> _saveProgress({bool force = false}) async {
    if (_pages.isEmpty) return;
    if (_saving && !force) return;
    _saving = true;
    try {
      final lastPage = _index;
      final isRead = _index >= _pages.length - 1;
      final updated = await widget.api.updateChapterProgress(
        chapterId: _chapter.id,
        lastPageRead: lastPage,
        isRead: isRead,
      );
      _chapter = updated;
    } catch (e) {
      // Non-fatal: show subtle error only if forced (leave/chapter end).
      if (force && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Progresso não salvo: $e')),
        );
      }
    } finally {
      _saving = false;
    }
  }

  void _next() {
    if (_index < _pages.length - 1) {
      setState(() => _index++);
      _scheduleSave();
    } else {
      unawaited(_saveProgress(force: true));
      _openAdjacentChapter(1);
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
      _scheduleSave();
    } else {
      unawaited(_saveProgress(force: true));
      _openAdjacentChapter(-1);
    }
  }

  void _openAdjacentChapter(int delta) {
    final idx = widget.chapters.indexWhere((c) => c.id == _chapter.id);
    if (idx < 0) return;
    final next = idx + delta;
    if (next < 0 || next >= widget.chapters.length) return;
    setState(() => _chapter = widget.chapters[next]);
    _load();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _next();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _prev();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final pageUrl =
        _pages.isEmpty ? null : widget.api.absoluteUrl(_pages[_index]);

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(
            '${widget.mangaTitle} · ${_chapter.name}',
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (_pages.isNotEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '${_index + 1} / ${_pages.length}'
                    '${(_chapter.lastPageRead ?? 0) > 0 ? ' · salvo' : ''}',
                  ),
                ),
              ),
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: AsyncBody(
          isLoading: _loading,
          error: _error,
          onRetry: _load,
          child: Column(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final w = MediaQuery.sizeOf(context).width;
                    if (d.localPosition.dx < w * 0.35) {
                      _prev();
                    } else {
                      _next();
                    }
                  },
                  child: pageUrl == null
                      ? const Center(
                          child: Text(
                            'Sem páginas',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 4,
                          child: Center(
                            child: Image.network(
                              pageUrl,
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              },
                              errorBuilder: (_, err, __) => Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Erro ao carregar imagem:\n$err\n$pageUrl',
                                  style: const TextStyle(color: YomuTokens.danger),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              Material(
                color: YomuTokens.surface,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        OutlinedButton(
                          onPressed: _prev,
                          child: const Text('Anterior'),
                        ),
                        const Spacer(),
                        Text(
                          _pages.isEmpty
                              ? '—'
                              : 'Pág. ${_index + 1}/${_pages.length}',
                          style: const TextStyle(color: YomuTokens.textMuted),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: _next,
                          child: const Text('Próxima'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
