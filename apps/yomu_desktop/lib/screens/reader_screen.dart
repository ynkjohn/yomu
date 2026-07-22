import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_ui/yomu_ui.dart';

enum _ReaderMode { rtl, ltr, doublePage, vertical, webtoon }

enum _ReaderFit { height, width, original }

enum _ReaderTheme { black, graphite, paper }

/// Canonical chapter order for reader adjacency: ascending readingOrder, then id.
List<ReadingChapter> chronologicalChapters(List<ReadingChapter> chapters) {
  final list = List<ReadingChapter>.from(chapters);
  int order(ReadingChapter chapter) => chapter.readingOrder ?? chapter.id;
  list.sort((a, b) => order(a).compareTo(order(b)));
  return list;
}

/// Maps scroll offset to the nearest page index for vertical/webtoon modes.
/// Prefer measured item extents when available; otherwise fall back to linear.
int visiblePageFromScroll({
  required double pixels,
  required double maxScrollExtent,
  required int pageCount,
  List<double>? itemExtents,
}) {
  if (pageCount <= 1) return 0;
  if (itemExtents != null &&
      itemExtents.length == pageCount &&
      itemExtents.every((extent) => extent > 0)) {
    final total = itemExtents.fold<double>(0, (sum, extent) => sum + extent);
    if (total <= 0) return 0;
    final clamped = pixels.clamp(
      0.0,
      maxScrollExtent > 0 ? maxScrollExtent : total,
    );
    var cursor = 0.0;
    for (var i = 0; i < itemExtents.length; i++) {
      final next = cursor + itemExtents[i];
      final midpoint = cursor + itemExtents[i] / 2;
      if (clamped <= midpoint || i == itemExtents.length - 1) {
        return i.clamp(0, pageCount - 1);
      }
      if (clamped < next) {
        return i.clamp(0, pageCount - 1);
      }
      cursor = next;
    }
  }
  if (maxScrollExtent <= 0) return 0;
  return ((pixels / maxScrollExtent) * (pageCount - 1)).round().clamp(
    0,
    pageCount - 1,
  );
}

@immutable
class ReaderLoadRequest {
  const ReaderLoadRequest({required this.generation, required this.chapterId});

  final int generation;
  final int chapterId;
}

class ReaderLoadGate {
  int _generation = 0;

  ReaderLoadRequest begin(int chapterId) =>
      ReaderLoadRequest(generation: ++_generation, chapterId: chapterId);

  bool accepts(ReaderLoadRequest request, int activeChapterId) =>
      request.generation == _generation && request.chapterId == activeChapterId;
}

@immutable
class ReaderSaveSnapshot {
  const ReaderSaveSnapshot({
    required this.chapterId,
    required this.page,
    required this.pageCount,
    this.wasRead = false,
  });

  final int chapterId;
  final int page;
  final int pageCount;
  final bool wasRead;

  bool get isRead => wasRead || (pageCount > 0 && page >= pageCount - 1);
}

typedef ReaderPageContentBuilder =
    Widget Function(BuildContext context, int index, MediaReference reference);

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.reader,
    required this.progress,
    required this.media,
    required this.mangaId,
    required this.mangaTitle,
    required this.chapter,
    required this.chapters,
    this.openSettingsOnStart = false,
    @visibleForTesting this.pageContentBuilder,
  });

  final ReaderGateway reader;
  final ReadingProgressCoordinator progress;
  final EngineMediaGateway media;
  final int mangaId;
  final String mangaTitle;
  final ReadingChapter chapter;
  final List<ReadingChapter> chapters;
  final bool openSettingsOnStart;
  @visibleForTesting
  final ReaderPageContentBuilder? pageContentBuilder;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _focus = FocusNode();
  final _loadGate = ReaderLoadGate();
  final _scrollController = ScrollController();
  final _scrollViewportKey = GlobalKey();
  final _pageKeys = <int, GlobalKey>{};
  Timer? _saveDebounce;
  bool _loading = true;
  bool _overlay = true;
  bool _settingsOpen = false;
  bool _chaptersOpen = false;
  bool _finished = false;
  bool _saving = false;
  bool _transitioning = false;
  bool _seekingScroll = false;
  int _seekGeneration = 0;
  String? _error;
  String? _saveError;
  List<MediaReference> _pages = [];
  int _index = 0;
  double _zoom = 1;
  late ReadingChapter _chapter;
  late List<ReadingChapter> _orderedChapters;
  late final ReadingProgressSessionHandle _progressSession;
  _ReaderMode _mode = _ReaderMode.rtl;
  _ReaderFit _fit = _ReaderFit.height;
  _ReaderTheme _theme = _ReaderTheme.black;

  bool get _isScrollMode =>
      _mode == _ReaderMode.vertical || _mode == _ReaderMode.webtoon;

  int get _currentChapterIndex =>
      _orderedChapters.indexWhere((chapter) => chapter.id == _chapter.id);

  bool get _hasPreviousChapter => _currentChapterIndex > 0;

  bool get _hasNextChapter {
    final index = _currentChapterIndex;
    return index >= 0 && index + 1 < _orderedChapters.length;
  }

  @override
  void initState() {
    super.initState();
    _chapter = widget.chapter;
    _orderedChapters = chronologicalChapters(widget.chapters);
    _progressSession = widget.progress.registerFinalSnapshotProvider(() {
      final snapshot = _captureSaveSnapshot();
      if (snapshot == null) return null;
      return ReadingProgressSnapshot(
        chapterId: snapshot.chapterId,
        lastPageRead: snapshot.page,
        isRead: snapshot.isRead,
      );
    });
    _settingsOpen = widget.openSettingsOnStart;
    _load();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    final finalSnapshot = _captureSaveSnapshot();
    widget.progress.unregisterFinalSnapshotProvider(_progressSession);
    if (finalSnapshot != null) unawaited(_saveFinal(finalSnapshot));
    _seekGeneration++;
    _seekingScroll = false;
    _focus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final chapterId = _chapter.id;
    final request = _loadGate.begin(chapterId);
    setState(() {
      _loading = true;
      _error = null;
      _finished = false;
    });
    try {
      final remote = await widget.reader.getChapter(chapterId);
      if (!mounted || !_loadGate.accepts(request, _chapter.id)) return;
      final resolvedChapter = remote != null && remote.id == chapterId
          ? remote
          : _chapter;
      final result = await widget.reader.getPages(chapterId);
      if (!mounted ||
          !_loadGate.accepts(request, _chapter.id) ||
          result.chapterId != chapterId) {
        return;
      }
      final start = result.pages.isEmpty
          ? 0
          : (resolvedChapter.lastPageRead ?? 0).clamp(
              0,
              result.pages.length - 1,
            );
      setState(() {
        _chapter = resolvedChapter;
        _pages = result.pages;
        _index = start;
        _loading = false;
        _transitioning = false;
        _pageKeys
          ..clear()
          ..addEntries(
            List.generate(
              result.pages.length,
              (i) => MapEntry(i, GlobalKey(debugLabel: 'reader-page-$i')),
            ),
          );
        if (_pages.isEmpty) {
          _error = 'Nenhuma página retornada para este capítulo.';
        }
      });
      if (_pages.isNotEmpty) {
        // Persist resume page only; do not stamp isRead=false on reopen.
        if (start > 0 || resolvedChapter.isRead) {
          unawaited(_requestSave());
        }
        if (_isScrollMode && start > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_loadGate.accepts(request, _chapter.id)) return;
            _scrollToIndex(start, animate: false);
          });
        }
      }
    } catch (error) {
      if (!mounted || !_loadGate.accepts(request, _chapter.id)) return;
      setState(() {
        _error = _sanitizedEngineMessage(
          error,
          fallback: 'Não foi possível carregar este capítulo.',
        );
        _loading = false;
        _transitioning = false;
      });
    }
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_requestSave());
    });
  }

  ReaderSaveSnapshot? _captureSaveSnapshot() {
    if (_pages.isEmpty) return null;
    return ReaderSaveSnapshot(
      chapterId: _chapter.id,
      page: _index,
      pageCount: _pages.length,
      wasRead: _chapter.isRead,
    );
  }

  Future<void> _requestSave() async {
    final snapshot = _captureSaveSnapshot();
    if (snapshot == null) return;
    if (mounted) {
      setState(() {
        _saving = true;
        _saveError = null;
      });
    }
    try {
      final saved = await widget.progress.updateProgress(
        chapterId: snapshot.chapterId,
        lastPageRead: snapshot.page,
        isRead: snapshot.isRead,
      );
      if (mounted && _chapter.id == snapshot.chapterId) {
        setState(() {
          _chapter = _chapterWithProgress(_chapter, saved);
          _saveError = null;
          _saving = widget.progress.hasPendingWrites;
        });
      }
    } catch (error) {
      if (mounted && _chapter.id == snapshot.chapterId) {
        setState(() {
          _saveError = _sanitizedEngineMessage(
            error,
            fallback: 'Não foi possível salvar o progresso.',
          );
          _saving = widget.progress.hasPendingWrites;
        });
      }
    }
  }

  Future<void> _saveFinal(ReaderSaveSnapshot snapshot) async {
    try {
      await widget.progress.saveFinal(
        chapterId: snapshot.chapterId,
        lastPageRead: snapshot.page,
        isRead: snapshot.isRead,
      );
    } catch (_) {
      // The shared lifecycle drain owns any remaining shutdown outcome.
    }
  }

  GlobalKey _keyForPage(int index) => _pageKeys.putIfAbsent(
    index,
    () => GlobalKey(debugLabel: 'reader-page-$index'),
  );

  void _scrollToIndex(int index, {bool animate = true}) {
    if (!_isScrollMode || !_scrollController.hasClients || _pages.isEmpty) {
      return;
    }
    final target = index.clamp(0, _pages.length - 1);
    final generation = ++_seekGeneration;
    _seekingScroll = true;
    unawaited(
      _performScrollSeek(target, generation: generation, animate: animate),
    );
  }

  Future<void> _performScrollSeek(
    int target, {
    required int generation,
    required bool animate,
  }) async {
    bool isCurrent() =>
        mounted &&
        generation == _seekGeneration &&
        _isScrollMode &&
        _scrollController.hasClients;

    try {
      for (var attempt = 0; attempt < 8 && isCurrent(); attempt++) {
        final context = _pageKeys[target]?.currentContext;
        if (context != null && context.mounted && isCurrent()) {
          await Scrollable.ensureVisible(
            context,
            duration: animate
                ? const Duration(milliseconds: 180)
                : Duration.zero,
            alignment: 0.02,
            curve: Curves.easeOutCubic,
          );
          return;
        }

        final max = _scrollController.position.maxScrollExtent;
        if (max > 0 && _pages.length > 1) {
          final offset = ((target / (_pages.length - 1)) * max).clamp(0.0, max);
          if (animate && attempt == 0) {
            await _scrollController.animateTo(
              offset,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
            );
          } else {
            _scrollController.jumpTo(offset);
          }
        }
        await WidgetsBinding.instance.endOfFrame;
      }
    } catch (_) {
      // A newer seek or route teardown can detach/cancel the active position.
    } finally {
      if (generation == _seekGeneration) {
        _seekingScroll = false;
      }
    }
  }

  int? _visiblePageFromViewport() {
    final viewportContext = _scrollViewportKey.currentContext;
    final viewportBox = viewportContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.hasSize) return null;

    final viewportRect =
        viewportBox.localToGlobal(Offset.zero) & viewportBox.size;
    int? bestIndex;
    var bestVisibleHeight = -1.0;
    var bestCenterDistance = double.infinity;

    for (var index = 0; index < _pages.length; index++) {
      final pageContext = _pageKeys[index]?.currentContext;
      final pageBox = pageContext?.findRenderObject() as RenderBox?;
      if (pageBox == null || !pageBox.hasSize) continue;
      final pageRect = pageBox.localToGlobal(Offset.zero) & pageBox.size;
      if (!pageRect.overlaps(viewportRect)) continue;
      final visibleHeight = pageRect.intersect(viewportRect).height;
      final centerDistance = (pageRect.center.dy - viewportRect.center.dy)
          .abs();
      if (visibleHeight > bestVisibleHeight ||
          (visibleHeight == bestVisibleHeight &&
              centerDistance < bestCenterDistance)) {
        bestIndex = index;
        bestVisibleHeight = visibleHeight;
        bestCenterDistance = centerDistance;
      }
    }
    return bestIndex;
  }

  void _setIndex(int value, {bool seekScroll = true}) {
    if (_pages.isEmpty) return;
    final next = value.clamp(0, _pages.length - 1);
    if (next == _index) {
      if (seekScroll && _isScrollMode) _scrollToIndex(next);
      return;
    }
    setState(() {
      _index = next;
      _finished = false;
    });
    if (seekScroll && _isScrollMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToIndex(next);
      });
    }
    _scheduleSave();
  }

  void _openEndPanel() {
    if (_finished) return;
    setState(() {
      _finished = true;
      _overlay = true;
    });
    unawaited(_requestSave());
  }

  void _step(int delta) {
    if (_pages.isEmpty || _transitioning) return;
    final next = _index + delta;
    if (next >= _pages.length) {
      _openEndPanel();
      return;
    }
    if (next < 0) {
      if (_hasPreviousChapter) {
        _openAdjacentChapter(-1);
      }
      return;
    }
    _setIndex(next);
  }

  void _visualLeft() => _step(
    _mode == _ReaderMode.rtl || _mode == _ReaderMode.doublePage ? 1 : -1,
  );
  void _visualRight() => _step(
    _mode == _ReaderMode.rtl || _mode == _ReaderMode.doublePage ? -1 : 1,
  );

  void _openAdjacentChapter(int delta) {
    if (_transitioning) return;
    final current = _currentChapterIndex;
    if (current < 0) return;
    final next = current + delta;
    if (next < 0 || next >= _orderedChapters.length) return;
    final previousSnapshot = _captureSaveSnapshot();
    _saveDebounce?.cancel();
    if (previousSnapshot != null) {
      unawaited(_saveFinal(previousSnapshot));
    }
    setState(() {
      _transitioning = true;
      _chapter = _orderedChapters[next];
      _pages = const [];
      _index = 0;
      _finished = false;
      _overlay = true;
      _settingsOpen = false;
      _chaptersOpen = false;
      _pageKeys.clear();
    });
    _load();
  }

  void _openChapter(ReadingChapter chapter) {
    if (chapter.id == _chapter.id) {
      setState(() => _chaptersOpen = false);
      return;
    }
    if (_transitioning) return;
    final previousSnapshot = _captureSaveSnapshot();
    _saveDebounce?.cancel();
    if (previousSnapshot != null) {
      unawaited(_saveFinal(previousSnapshot));
    }
    setState(() {
      _transitioning = true;
      _chapter = chapter;
      _pages = const [];
      _index = 0;
      _finished = false;
      _chaptersOpen = false;
      _settingsOpen = false;
      _overlay = true;
      _pageKeys.clear();
    });
    _load();
  }

  void _onScrollNotification(ScrollNotification notification) {
    if (!_isScrollMode || _pages.isEmpty || _seekingScroll) return;
    if (notification is! ScrollUpdateNotification &&
        notification is! ScrollEndNotification) {
      return;
    }
    final metrics = notification.metrics;
    final atEnd =
        metrics.maxScrollExtent > 0 &&
        metrics.pixels >= metrics.maxScrollExtent - 24;
    final calculated = atEnd
        ? _pages.length - 1
        : _visiblePageFromViewport() ??
              visiblePageFromScroll(
                pixels: metrics.pixels,
                maxScrollExtent: metrics.maxScrollExtent,
                pageCount: _pages.length,
              );
    if (calculated != _index) {
      _index = calculated;
      _scheduleSave();
      if (mounted) setState(() {});
    }
    if (atEnd && calculated >= _pages.length - 1) {
      _openEndPanel();
    }
  }

  void _toggleOverlay() => setState(() {
    _overlay = !_overlay;
    _settingsOpen = false;
    _chaptersOpen = false;
  });

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _visualLeft();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _visualRight();
    } else if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.pageDown) {
      _step(1);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _step(-1);
    } else if (key == LogicalKeyboardKey.bracketLeft) {
      _openAdjacentChapter(-1);
    } else if (key == LogicalKeyboardKey.bracketRight) {
      _openAdjacentChapter(1);
    } else if (key == LogicalKeyboardKey.digit1) {
      _setMode(_ReaderMode.rtl);
    } else if (key == LogicalKeyboardKey.digit2) {
      _setMode(_ReaderMode.ltr);
    } else if (key == LogicalKeyboardKey.digit3) {
      _setMode(_ReaderMode.doublePage);
    } else if (key == LogicalKeyboardKey.digit4) {
      _setMode(_ReaderMode.vertical);
    } else if (key == LogicalKeyboardKey.digit5) {
      _setMode(_ReaderMode.webtoon);
    } else if (key == LogicalKeyboardKey.keyM) {
      setState(() {
        _overlay = true;
        _chaptersOpen = !_chaptersOpen;
        _settingsOpen = false;
      });
    } else if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add) {
      _changeZoom(0.1);
    } else if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _changeZoom(-0.1);
    } else if (key == LogicalKeyboardKey.digit0) {
      setState(() => _zoom = 1);
    } else if (key == LogicalKeyboardKey.slash &&
        HardwareKeyboard.instance.isShiftPressed) {
      setState(() {
        _overlay = true;
        _settingsOpen = true;
        _chaptersOpen = false;
      });
    } else if (key == LogicalKeyboardKey.escape) {
      if (_settingsOpen || _chaptersOpen) {
        setState(() {
          _settingsOpen = false;
          _chaptersOpen = false;
        });
      } else {
        _toggleOverlay();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _setMode(_ReaderMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      if (mode == _ReaderMode.vertical || mode == _ReaderMode.webtoon) {
        _fit = _ReaderFit.width;
      }
      _settingsOpen = false;
      _chaptersOpen = false;
      _overlay = true;
      _finished = false;
    });
    if (_isScrollMode && _pages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToIndex(_index, animate: false);
      });
    }
  }

  void _changeZoom(double delta) =>
      setState(() => _zoom = (_zoom + delta).clamp(0.7, 1.6));

  String get _modeLabel => switch (_mode) {
    _ReaderMode.rtl => 'Páginas · direita → esquerda',
    _ReaderMode.ltr => 'Páginas · esquerda → direita',
    _ReaderMode.doublePage => 'Página dupla',
    _ReaderMode.vertical => 'Rolagem vertical',
    _ReaderMode.webtoon => 'Webtoon',
  };

  Color get _stageColor => switch (_theme) {
    _ReaderTheme.black => Colors.black,
    _ReaderTheme.graphite => const Color(0xFF161B25),
    _ReaderTheme.paper => const Color(0xFFD8D1C3),
  };

  BoxFit get _boxFit => switch (_fit) {
    _ReaderFit.height => BoxFit.contain,
    _ReaderFit.width => BoxFit.fitWidth,
    _ReaderFit.original => BoxFit.none,
  };

  String get _saveStatus {
    if (_saving) return 'Salvando progresso…';
    if (_saveError != null) return 'Falha ao salvar';
    return 'Progresso salvo';
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: true,
    onKeyEvent: _onKey,
    child: Scaffold(
      backgroundColor: _stageColor,
      body: AsyncBody(
        isLoading: _loading,
        error: _error,
        onRetry: _load,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: _stageColor),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.3),
                    radius: 0.84,
                    colors: [
                      Colors.white.withValues(alpha: 0.012),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.5],
                  ),
                ),
              ),
            ),
            _readerCanvas(),
            if (_mode != _ReaderMode.vertical &&
                _mode != _ReaderMode.webtoon) ...[
              Positioned(
                left: 0,
                top: 74,
                bottom: 70,
                width: 96,
                child: _edgeButton(left: true),
              ),
              Positioned(
                right: 0,
                top: 74,
                bottom: 70,
                width: 96,
                child: _edgeButton(left: false),
              ),
            ],
            Align(
              alignment: Alignment.bottomCenter,
              child: LinearProgressIndicator(
                value: _pages.isEmpty ? 0 : (_index + 1) / _pages.length,
                minHeight: 2,
                backgroundColor: Colors.white10,
                color: YomuTokens.accent,
              ),
            ),
            if (_overlay) ...[
              _topbar(),
              _bottomControls(),
              if (_settingsOpen) _settingsPanel(),
              if (_chaptersOpen) _chaptersPanel(),
            ],
            if (_finished) _endPanel(),
          ],
        ),
      ),
    ),
  );

  Widget _readerCanvas() {
    if (_pages.isEmpty) {
      return const Center(
        child: Text('Sem páginas', style: TextStyle(color: Colors.white70)),
      );
    }
    if (_isScrollMode) {
      return NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _onScrollNotification(notification);
          return false;
        },
        child: GestureDetector(
          onTap: _toggleOverlay,
          child: SizedBox.expand(
            key: _scrollViewportKey,
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(80, 34, 80, _overlay ? 90 : 34),
              itemCount: _pages.length,
              cacheExtent: 1600,
              itemBuilder: (context, index) => Center(
                key: _keyForPage(index),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 760 * _zoom),
                  child: _pageImage(index, vertical: true),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final indexes = <int>[_index];
    if (_mode == _ReaderMode.doublePage && _index + 1 < _pages.length) {
      indexes.add(_index + 1);
    }
    // Match the design's single row-reverse: current page on the right and
    // the following page on the left. Do not reverse the children as well.
    final rtlSpread = _mode == _ReaderMode.doublePage && indexes.length > 1;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final width = MediaQuery.sizeOf(context).width;
        if (details.localPosition.dx > width * 0.35 &&
            details.localPosition.dx < width * 0.65) {
          _toggleOverlay();
        }
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          118,
          _overlay ? 74 : 34,
          118,
          _overlay ? 92 : 46,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          textDirection: rtlSpread ? TextDirection.rtl : TextDirection.ltr,
          children: indexes
              .map(
                (index) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Transform.scale(
                      scale: _zoom,
                      child: _pageImage(index),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _pageImage(int index, {bool vertical = false}) {
    final reference = _pages[index];
    return Container(
      margin: EdgeInsets.only(bottom: _mode == _ReaderMode.webtoon ? 0 : 10),
      constraints: vertical ? const BoxConstraints(minHeight: 300) : null,
      decoration: BoxDecoration(
        color: const Color(0xFF151922),
        border: Border.all(color: const Color(0x12FFFFFF)),
        borderRadius: BorderRadius.circular(
          _mode == _ReaderMode.webtoon ? 0 : 5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 38,
            offset: Offset(0, 18),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child:
          widget.pageContentBuilder?.call(context, index, reference) ??
          _ReaderPageImage(
            reference: reference,
            media: widget.media,
            fit: vertical ? BoxFit.fitWidth : _boxFit,
            pageNumber: index + 1,
          ),
    );
  }

  Widget _edgeButton({required bool left}) {
    final movesForward = left
        ? _mode == _ReaderMode.rtl || _mode == _ReaderMode.doublePage
        : _mode != _ReaderMode.rtl && _mode != _ReaderMode.doublePage;
    final label = movesForward ? 'Próxima página' : 'Página anterior';
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: left ? _visualLeft : _visualRight,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: left ? Alignment.centerLeft : Alignment.centerRight,
              end: left ? Alignment.centerRight : Alignment.centerLeft,
              colors: [
                YomuTokens.accent.withValues(alpha: 0.12),
                Colors.transparent,
              ],
            ),
          ),
          child: Center(
            child: YomuIcon(
              left ? YomuIcons.chevronLeft : YomuIcons.chevronRight,
              color: const Color(0xFF677188),
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _topbar() => Positioned(
    left: 0,
    right: 0,
    top: 0,
    child: Container(
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC080A0F), Color(0x99080A0F), Colors.transparent],
          stops: [0, 0.62, 1],
        ),
      ),
      child: Row(
        children: [
          _readerButton(
            tooltip: 'Voltar à página da obra',
            icon: YomuIcons.chevronLeft,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.mangaTitle} · ${_chapter.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF0F2F8),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_modeLabel · $_saveStatus',
                  style: TextStyle(
                    color: _saveError == null
                        ? const Color(0xFF909AAD)
                        : YomuTokens.danger,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          _modePill(),
          const SizedBox(width: 7),
          _readerButton(
            tooltip: 'Abrir capítulos',
            icon: YomuIcons.chapters,
            expanded: _chaptersOpen,
            onPressed: () => setState(() {
              _chaptersOpen = !_chaptersOpen;
              _settingsOpen = false;
            }),
          ),
          const SizedBox(width: 5),
          Tooltip(
            message: 'Esta função ainda não foi implementada.',
            child: _readerButton(
              tooltip: 'Marcador indisponível',
              icon: YomuIcons.bookmark,
              onPressed: null,
            ),
          ),
          const SizedBox(width: 5),
          Tooltip(
            message: 'Esta função ainda não foi implementada.',
            child: _readerButton(
              tooltip: 'Tela cheia indisponível',
              icon: YomuIcons.maximize,
              onPressed: null,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _readerButton({
    required String tooltip,
    required YomuIconData icon,
    required VoidCallback? onPressed,
    bool? expanded,
  }) => Semantics(
    button: true,
    enabled: onPressed != null,
    expanded: expanded,
    label: tooltip,
    child: ExcludeSemantics(
      child: Tooltip(
        message: tooltip,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Opacity(
              opacity: onPressed == null ? 0.45 : 1,
              child: Material(
                color: Colors.white.withValues(alpha: 0.055),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                  side: const BorderSide(color: Colors.white10),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: onPressed,
                  child: SizedBox.square(
                    dimension: 34,
                    child: Center(
                      child: YomuIcon(
                        icon,
                        size: 18,
                        color: const Color(0xFFC3CADA),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  YomuIconData get _modeIcon => switch (_mode) {
    _ReaderMode.rtl => YomuIcons.layoutRtl,
    _ReaderMode.ltr => YomuIcons.layoutLtr,
    _ReaderMode.doublePage => YomuIcons.layoutDouble,
    _ReaderMode.vertical => YomuIcons.layoutVertical,
    _ReaderMode.webtoon => YomuIcons.layoutWebtoon,
  };

  Widget _modePill() => Semantics(
    button: true,
    expanded: _settingsOpen,
    label: 'Modo de leitura: $_modeLabel',
    child: ExcludeSemantics(
      child: SizedBox(
        height: 44,
        child: Center(
          child: Material(
            color: Colors.white.withValues(alpha: 0.07),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Colors.white12),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() {
                _settingsOpen = !_settingsOpen;
                _chaptersOpen = false;
              }),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    YomuIcon(
                      _modeIcon,
                      size: 18,
                      color: const Color(0xFFD6DBE8),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _modeLabel.split(' · ').first,
                      style: const TextStyle(
                        color: Color(0xFFD6DBE8),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 7),
                    const YomuIcon(
                      YomuIcons.chevronDown,
                      size: 14,
                      color: Color(0xFFD6DBE8),
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

  Widget _bottomControls() => Positioned(
    left: 18,
    right: 18,
    bottom: 14,
    child: Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: const Color(0xE60D1017),
        border: Border.all(color: Colors.white10),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 48,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Row(
        children: [
          _readerButton(
            tooltip: 'Página anterior',
            icon: YomuIcons.chevronLeft,
            onPressed: () => _step(-1),
          ),
          const SizedBox(width: 6),
          _readerButton(
            tooltip: 'Próxima página',
            icon: YomuIcons.chevronRight,
            onPressed: () => _step(1),
          ),
          const SizedBox(width: 16),
          Text(
            '${_index + 1}',
            style: const TextStyle(color: Color(0xFFA5AEC0), fontSize: 9.5),
          ),
          Expanded(
            child: Semantics(
              label: 'Ir para página',
              child: Slider(
                value: _pages.isEmpty ? 0 : _index.toDouble(),
                min: 0,
                max: _pages.length <= 1 ? 1 : (_pages.length - 1).toDouble(),
                semanticFormatterCallback: (value) =>
                    'Página ${value.round() + 1} de ${_pages.length}',
                onChanged: _pages.isEmpty || _transitioning
                    ? null
                    : (value) => _setIndex(value.round(), seekScroll: true),
              ),
            ),
          ),
          Text(
            '${_pages.length}',
            style: const TextStyle(color: Color(0xFFA5AEC0), fontSize: 9.5),
          ),
          const SizedBox(width: 18),
          Semantics(
            liveRegion: _saving || _saveError != null,
            label: _saveStatus,
            child: Text(
              _saveStatus,
              style: const TextStyle(color: Color(0xFF9CA6B9), fontSize: 10),
            ),
          ),
          const SizedBox(width: 12),
          _readerButton(
            tooltip: 'Diminuir zoom',
            icon: YomuIcons.zoomOut,
            onPressed: () => _changeZoom(-0.1),
          ),
          SizedBox(
            width: 46,
            child: Text(
              '${(_zoom * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFD9DEEA),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _readerButton(
            tooltip: 'Aumentar zoom',
            icon: YomuIcons.zoomIn,
            onPressed: () => _changeZoom(0.1),
          ),
        ],
      ),
    ),
  );

  Widget _settingsPanel() => Positioned(
    top: 60,
    right: 16,
    width: 342,
    child: Container(
      constraints: const BoxConstraints(maxHeight: 650),
      decoration: BoxDecoration(
        color: const Color(0xFA12161F),
        border: Border.all(color: YomuTokens.borderStrong),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x8C000000),
            blurRadius: 80,
            offset: Offset(0, 28),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _panelHead(
              'Ajustes de leitura',
              () => setState(() => _settingsOpen = false),
            ),
            _settingsSection(
              label: 'MODO',
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 2.75,
                mainAxisSpacing: 7,
                crossAxisSpacing: 7,
                children: [
                  _modeOption(
                    _ReaderMode.rtl,
                    'Direita → esquerda',
                    YomuIcons.layoutRtl,
                  ),
                  _modeOption(
                    _ReaderMode.ltr,
                    'Esquerda → direita',
                    YomuIcons.layoutLtr,
                  ),
                  _modeOption(
                    _ReaderMode.doublePage,
                    'Página dupla',
                    YomuIcons.layoutDouble,
                  ),
                  _modeOption(
                    _ReaderMode.vertical,
                    'Rolagem vertical',
                    YomuIcons.layoutVertical,
                  ),
                  _modeOption(
                    _ReaderMode.webtoon,
                    'Webtoon',
                    YomuIcons.layoutWebtoon,
                  ),
                ],
              ),
            ),
            _settingsSection(label: 'ENCAIXE DA PÁGINA', child: _fitSelector()),
            _settingsSection(label: 'FUNDO', child: _themeSelector()),
            _settingsSection(
              label: 'POR OBRA',
              child: Tooltip(
                message: 'Esta função ainda não foi implementada.',
                child: Opacity(
                  opacity: 0.48,
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Usar nesta obra',
                              style: TextStyle(
                                color: Color(0xFFDCE1ED),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Persistência por obra indisponível.',
                              style: TextStyle(
                                color: Color(0xFF7F899C),
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(value: false, onChanged: null),
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

  Widget _panelHead(String title, VoidCallback close) => Container(
    padding: const EdgeInsets.fromLTRB(15, 11, 9, 11),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: YomuTokens.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: YomuTokens.text,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _readerButton(
          tooltip: 'Fechar',
          icon: YomuIcons.close,
          onPressed: close,
        ),
      ],
    ),
  );

  Widget _settingsSection({required String label, required Widget child}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x0EFFFFFF))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF7F899E),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );

  Widget _modeOption(_ReaderMode mode, String label, YomuIconData icon) {
    final selected = _mode == mode;
    return Semantics(
      selected: selected,
      button: true,
      label: 'Modo $label',
      child: OutlinedButton(
        onPressed: () => _setMode(mode),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.centerLeft,
          backgroundColor: selected
              ? YomuTokens.accent.withValues(alpha: 0.13)
              : const Color(0xFF151A24),
          foregroundColor: selected
              ? const Color(0xFFCDD5FF)
              : YomuTokens.textMuted,
          side: BorderSide(
            color: selected
                ? YomuTokens.accent.withValues(alpha: 0.45)
                : const Color(0xFF2C3444),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
        child: Row(
          children: [
            YomuIcon(
              icon,
              size: 20,
              color: selected ? const Color(0xFFCDD5FF) : YomuTokens.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fitSelector() {
    if (_isScrollMode) {
      return Semantics(
        enabled: false,
        label: 'Encaixe da página: largura fixa nos modos de rolagem',
        child: ExcludeSemantics(
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF0B0E14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Largura fixa na rolagem',
              style: TextStyle(
                color: Color(0xFF8F99AD),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: _ReaderFit.values.map((fit) {
          final selected = _fit == fit;
          final label = switch (fit) {
            _ReaderFit.height => 'Altura',
            _ReaderFit.width => 'Largura',
            _ReaderFit.original => 'Original',
          };
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: 'Encaixe $label',
              child: ExcludeSemantics(
                child: TextButton(
                  onPressed: () => setState(() => _fit = fit),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: EdgeInsets.zero,
                    backgroundColor: selected
                        ? const Color(0xFF29365F)
                        : Colors.transparent,
                    foregroundColor: selected
                        ? const Color(0xFFE4E8FF)
                        : const Color(0xFF8F99AD),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(label),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _themeSelector() => Row(
    children: _ReaderTheme.values.map((theme) {
      final selected = _theme == theme;
      final (label, swatch) = switch (theme) {
        _ReaderTheme.black => ('Preto', Colors.black),
        _ReaderTheme.graphite => ('Grafite', const Color(0xFF161B25)),
        _ReaderTheme.paper => ('Papel', const Color(0xFFD8D1C3)),
      };
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 7),
          child: Semantics(
            selected: selected,
            button: true,
            label: 'Tema $label',
            child: OutlinedButton(
              onPressed: () => setState(() => _theme = theme),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                foregroundColor: YomuTokens.textMuted,
                side: BorderSide(
                  color: selected
                      ? const Color(0xFF7F93E8)
                      : const Color(0xFF313949),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                textStyle: const TextStyle(fontSize: 9.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: swatch,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList(),
  );

  Widget _chaptersPanel() => Positioned(
    top: 60,
    left: 16,
    width: 290,
    child: Container(
      constraints: const BoxConstraints(maxHeight: 620),
      decoration: BoxDecoration(
        color: const Color(0xFA12161F),
        border: Border.all(color: YomuTokens.borderStrong),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x8C000000),
            blurRadius: 80,
            offset: Offset(0, 28),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _panelHead('Capítulos', () => setState(() => _chaptersOpen = false)),
          Flexible(
            child: ListView.builder(
              padding: const EdgeInsets.all(6),
              itemCount: widget.chapters.length,
              itemBuilder: (context, index) {
                final chapter = widget.chapters[index];
                final current = chapter.id == _chapter.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: TextButton.icon(
                    onPressed: () => _openChapter(chapter),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      backgroundColor: current
                          ? YomuTokens.accent.withValues(alpha: 0.15)
                          : Colors.transparent,
                      foregroundColor: current
                          ? const Color(0xFFE2E6FF)
                          : YomuTokens.textMuted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    icon: YomuIcon(
                      chapter.isRead ? YomuIcons.check : YomuIcons.bookOpen,
                      size: 14,
                      color: current
                          ? const Color(0xFFE2E6FF)
                          : YomuTokens.textSubtle,
                    ),
                    label: Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              chapter.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if ((chapter.lastPageRead ?? 0) > 0)
                            Text(
                              'pág ${(chapter.lastPageRead ?? 0) + 1}',
                              style: const TextStyle(
                                color: Color(0xFF788296),
                                fontSize: 9,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _endPanel() => Positioned.fill(
    child: ColoredBox(
      color: const Color(0xEB06080C),
      child: Center(
        child: Container(
          width: 430,
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: YomuTokens.surface,
            border: Border.all(color: YomuTokens.borderStrong),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x8C000000),
                blurRadius: 90,
                offset: Offset(0, 30),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: YomuTokens.success.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: YomuIcon(
                    YomuIcons.check,
                    size: 21,
                    color: YomuTokens.success,
                  ),
                ),
              ),
              const SizedBox(height: 13),
              const Text(
                'Capítulo concluído',
                style: TextStyle(
                  color: YomuTokens.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                _chapter.name,
                style: const TextStyle(
                  color: YomuTokens.textSubtle,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 9,
                runSpacing: 9,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Voltar à obra'),
                  ),
                  FilledButton.icon(
                    onPressed: _hasNextChapter && !_transitioning
                        ? () => _openAdjacentChapter(1)
                        : null,
                    iconAlignment: IconAlignment.end,
                    icon: const YomuIcon(
                      YomuIcons.chevronRight,
                      size: 18,
                      color: Colors.white,
                    ),
                    label: Text(
                      _hasNextChapter ? 'Próximo capítulo' : 'Último capítulo',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

ReadingChapter _chapterWithProgress(
  ReadingChapter chapter,
  ReadingProgressSnapshot progress,
) {
  return ReadingChapter(
    id: chapter.id,
    name: chapter.name,
    chapterNumber: chapter.chapterNumber,
    pageCount: chapter.pageCount,
    readingOrder: chapter.readingOrder,
    scanlator: chapter.scanlator,
    lastPageRead: progress.lastPageRead,
    isRead: chapter.isRead || progress.isRead,
    isDownloaded: chapter.isDownloaded,
    mangaId: chapter.mangaId,
  );
}

String _sanitizedEngineMessage(Object error, {required String fallback}) {
  return error is EngineException ? error.failure.message : fallback;
}

class _ReaderPageImage extends StatefulWidget {
  const _ReaderPageImage({
    required this.reference,
    required this.media,
    required this.fit,
    required this.pageNumber,
  });

  final MediaReference reference;
  final EngineMediaGateway media;
  final BoxFit fit;
  final int pageNumber;

  @override
  State<_ReaderPageImage> createState() => _ReaderPageImageState();
}

class _ReaderPageImageState extends State<_ReaderPageImage> {
  late Future<MediaPayload> _payload;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ReaderPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference ||
        !identical(oldWidget.media, widget.media)) {
      _load();
    }
  }

  void _load() {
    _payload = widget.media.fetch(widget.reference, maxBytes: 40 * 1024 * 1024);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MediaPayload>(
      future: _payload,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 420,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final payload = snapshot.data;
        if (payload == null ||
            payload.statusCode < 200 ||
            payload.statusCode >= 300 ||
            payload.bytes.isEmpty) {
          return SizedBox(
            height: 420,
            child: Center(
              child: Text(
                'Erro ao carregar a página ${widget.pageNumber}',
                style: const TextStyle(color: YomuTokens.danger),
              ),
            ),
          );
        }
        return Image.memory(
          payload.bytes,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => SizedBox(
            height: 420,
            child: Center(
              child: Text(
                'Erro ao carregar a página ${widget.pageNumber}',
                style: const TextStyle(color: YomuTokens.danger),
              ),
            ),
          ),
        );
      },
    );
  }
}
