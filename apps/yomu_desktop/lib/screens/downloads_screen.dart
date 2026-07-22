import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_ui/yomu_ui.dart';

class _DownloadsSkeleton extends StatefulWidget {
  const _DownloadsSkeleton();

  @override
  State<_DownloadsSkeleton> createState() => _DownloadsSkeletonState();
}

class _DownloadsSkeletonState extends State<_DownloadsSkeleton>
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
            child: Column(
              children: [
                Row(
                  children: [
                    for (var index = 0; index < 4; index++) ...[
                      const Expanded(child: _DownloadSkeletonBlock(height: 59)),
                      if (index != 3) const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                const _DownloadSkeletonBlock(height: 68),
                const SizedBox(height: 7),
                const _DownloadSkeletonBlock(height: 68),
                const SizedBox(height: 7),
                const _DownloadSkeletonBlock(height: 68),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadSkeletonBlock extends StatelessWidget {
  const _DownloadSkeletonBlock({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFF171C27),
      borderRadius: BorderRadius.circular(13),
    ),
  );
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({
    super.key,
    required this.downloads,
    required this.engineReady,
  });

  final DownloadsGateway? downloads;
  final bool engineReady;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  bool _loading = false;
  String? _error;
  DownloadsSnapshot? _status;
  Timer? _poll;
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    if (widget.engineReady) {
      _load();
      _poll = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _load(silent: true),
      );
    }
  }

  @override
  void didUpdateWidget(covariant DownloadsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.engineReady && !oldWidget.engineReady) {
      _load();
      _poll?.cancel();
      _poll = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _load(silent: true),
      );
    } else if (!widget.engineReady && oldWidget.engineReady) {
      _poll?.cancel();
      _poll = null;
      _loadGeneration++;
      _loadBusy = false;
      _loading = false;
      _actionBusy = false;
      _error = null;
      _status = null;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  int _loadGeneration = 0;
  bool _loadBusy = false;

  Future<void> _load({bool silent = false}) async {
    final downloads = widget.downloads;
    if (downloads == null || !widget.engineReady) return;
    if (_loadBusy && silent) return;
    final generation = ++_loadGeneration;
    _loadBusy = true;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final st = await downloads.getStatus();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _status = st;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (!silent) {
          _error = _sanitizedEngineMessage(
            e,
            fallback: 'Não foi possível carregar os downloads.',
          );
        }
        _loading = false;
      });
    } finally {
      if (generation == _loadGeneration) {
        _loadBusy = false;
      }
    }
  }

  Future<void> _run(Future<void> Function() op, String label) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await op();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(label)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _sanitizedEngineMessage(
              e,
              fallback: 'Não foi possível concluir esta ação.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _confirmClear() async {
    final downloads = widget.downloads;
    if (downloads == null || _actionBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar downloads?'),
        content: const Text(
          'Todos os itens da fila de downloads serão removidos. '
          'Os capítulos já concluídos não serão inventados nem recriados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Limpar fila'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(downloads.clear, 'Fila limpa');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.engineReady) {
      return const AsyncBody(
        isLoading: false,
        isEmpty: true,
        emptyMessage: 'Os recursos de leitura estão indisponíveis.',
        child: SizedBox.shrink(),
      );
    }

    final st = _status;
    final queue = st?.queue ?? const <EngineDownloadItem>[];
    final running = st?.managerState == DownloadManagerState.running;
    final activeCount = st?.activeCount ?? 0;
    final actionsEnabled = widget.downloads != null && !_actionBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YomuScreenHeader(
          title: 'Downloads',
          subtitle: 'Leitura offline gerenciada pelo motor local',
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              running
                  ? _pillButton(
                      label: 'Pausar tudo',
                      onTap: actionsEnabled
                          ? () => _run(() async {
                              await widget.downloads!.pause();
                            }, 'Downloader pausado')
                          : null,
                    )
                  : _pillButton(
                      label: 'Retomar tudo',
                      accent: true,
                      onTap: actionsEnabled
                          ? () => _run(
                              widget.downloads!.resume,
                              'Downloader iniciado',
                            )
                          : null,
                    ),
              _pillButton(
                label: 'Limpar fila',
                onTap: actionsEnabled && queue.isNotEmpty
                    ? _confirmClear
                    : null,
              ),
            ],
          ),
        ),
        if (_loading && _status == null)
          const Expanded(child: _DownloadsSkeleton())
        else
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 18, 28, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: YomuTokens.danger.withValues(alpha: 0.1),
                          border: Border.all(
                            color: YomuTokens.danger.withValues(alpha: 0.35),
                          ),
                          borderRadius: BorderRadius.circular(
                            YomuTokens.radiusMd,
                          ),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: YomuTokens.danger,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      _metricCard(
                        '$activeCount baixando',
                        running ? 'fila em execução' : 'fila pausada',
                      ),
                      const SizedBox(width: 8),
                      _metricCard('${queue.length} na fila', 'capítulos'),
                      const SizedBox(width: 8),
                      _metricCard('Indisponível', 'armazenados offline'),
                      const SizedBox(width: 8),
                      _metricCard('Indisponível', 'livres no disco'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 4, bottom: 8),
                                child: YomuSectionLabel('Fila'),
                              ),
                              if (queue.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 44,
                                    horizontal: 20,
                                  ),
                                  decoration: BoxDecoration(
                                    color: YomuTokens.surface.withValues(
                                      alpha: 0.82,
                                    ),
                                    border: Border.all(
                                      color: YomuTokens.border,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      YomuTokens.radiusMd,
                                    ),
                                  ),
                                  child: const Column(
                                    children: [
                                      Text(
                                        'Nada por aqui ainda',
                                        style: TextStyle(
                                          color: YomuTokens.text,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Enfileire capítulos na página da obra.',
                                        style: TextStyle(
                                          color: YomuTokens.textSubtle,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                for (final item in queue) ...[
                                  _queueCard(item),
                                  const SizedBox(height: 7),
                                ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      _storagePanel(),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _pillButton({
    required String label,
    VoidCallback? onTap,
    bool accent = false,
  }) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: accent ? YomuTokens.accentStrong : YomuTokens.surface2,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: accent
                  ? null
                  : Border.all(color: const Color(0x1AFFFFFF)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
                color: accent ? Colors.white : YomuTokens.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricCard(String value, String caption) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0x06FFFFFF),
          border: Border.all(color: const Color(0x0FFFFFFF)),
          borderRadius: BorderRadius.circular(YomuTokens.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: YomuTokens.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              caption,
              style: const TextStyle(
                color: YomuTokens.textSubtle,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _queueCard(EngineDownloadItem item) {
    final title = item.mangaTitle ?? 'Obra';
    final ch = item.chapterName ?? 'Capítulo';
    final prog = item.progress;
    final isError = item.state == DownloadItemState.failed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isError
            ? YomuTokens.danger.withValues(alpha: 0.08)
            : YomuTokens.surface.withValues(alpha: 0.82),
        border: Border.all(
          color: isError
              ? YomuTokens.danger.withValues(alpha: 0.3)
              : YomuTokens.border,
        ),
        borderRadius: BorderRadius.circular(YomuTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$title · $ch',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: YomuTokens.text,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                [
                  if (prog != null) '${(prog * 100).toStringAsFixed(0)}%',
                  _downloadStateLabel(item.state),
                ].join(' · '),
                style: TextStyle(
                  fontSize: 11,
                  color: isError ? YomuTokens.danger : YomuTokens.textSubtle,
                  fontWeight: isError ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              if (item.chapterId != null) ...[
                const SizedBox(width: 8),
                YomuIconButton(
                  tooltip: 'Remover da fila',
                  icon: YomuIcons.close,
                  size: 32,
                  iconSize: 14,
                  color: YomuTokens.textSubtle,
                  onTap: () => _run(
                    () => widget.downloads!.dequeueChapters([item.chapterId!]),
                    'Removido da fila',
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 4,
              child: LinearProgressIndicator(
                value: prog ?? 0,
                backgroundColor: const Color(0xFF29303E),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  YomuTokens.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _storagePanel() {
    return Container(
      width: 260,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF12151E),
        border: Border.all(color: const Color(0x0FFFFFFF)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const YomuSectionLabel('Armazenamento'),
          const SizedBox(height: 10),
          const Text(
            'Indisponível',
            style: TextStyle(
              color: YomuTokens.text,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Métricas de armazenamento offline ainda não foram implementadas.',
            style: TextStyle(color: YomuTokens.textSubtle, fontSize: 11),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: const SizedBox(
              height: 5,
              child: ColoredBox(color: Color(0xFF232937)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Remover lidos automaticamente',
                  style: TextStyle(color: YomuTokens.textMuted, fontSize: 12),
                ),
              ),
              Tooltip(
                message: 'Indisponível — sem backend nesta fase',
                child: Opacity(
                  opacity: 0.5,
                  child: Container(
                    width: 38,
                    height: 22,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A3140),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: YomuTokens.textSubtle,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _downloadStateLabel(DownloadItemState state) => switch (state) {
  DownloadItemState.queued => 'na fila',
  DownloadItemState.downloading => 'baixando',
  DownloadItemState.completed => 'concluído',
  DownloadItemState.failed => 'falhou',
};

String _sanitizedEngineMessage(Object error, {required String fallback}) {
  return error is EngineException ? error.failure.message : fallback;
}
