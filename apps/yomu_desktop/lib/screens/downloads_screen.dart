import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({
    super.key,
    required this.api,
    required this.engineReady,
  });

  final SuwayomiApi? api;
  final bool engineReady;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  bool _loading = false;
  String? _error;
  DownloadStatusInfo? _status;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (widget.engineReady) {
      _load();
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _load(silent: true));
    }
  }

  @override
  void didUpdateWidget(covariant DownloadsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.engineReady && !oldWidget.engineReady) {
      _load();
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _load(silent: true));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final api = widget.api;
    if (api == null || !widget.engineReady) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final st = await api.getDownloadStatus();
      if (!mounted) return;
      setState(() {
        _status = st;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() op, String label) async {
    try {
      await op();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(label)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.engineReady) {
      return const AsyncBody(
        isLoading: false,
        isEmpty: true,
        emptyMessage: 'Inicie o Suwayomi para gerenciar downloads.',
        child: SizedBox.shrink(),
      );
    }

    final st = _status;
    final queue = st?.queue ?? const <DownloadQueueItem>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(YomuTokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Downloads',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Fila do Suwayomi (estado: ${st?.state ?? "—"}). '
                'Enfileire capítulos na página da obra.',
                style: const TextStyle(color: YomuTokens.textMuted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _run(
                      () => widget.api!.startDownloader(),
                      'Downloader iniciado',
                    ),
                    child: const Text('Iniciar fila'),
                  ),
                  OutlinedButton(
                    onPressed: () => _run(
                      () => widget.api!.stopDownloader(),
                      'Downloader parado',
                    ),
                    child: const Text('Pausar'),
                  ),
                  OutlinedButton(
                    onPressed: () => _run(
                      () => widget.api!.clearDownloader(),
                      'Fila limpa',
                    ),
                    child: const Text('Limpar fila'),
                  ),
                  OutlinedButton(
                    onPressed: _loading ? null : () => _load(),
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
            isEmpty: queue.isEmpty && !_loading,
            emptyMessage: 'Fila vazia.',
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: queue.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = queue[i];
                final title = item.manga?.title ?? 'Manga';
                final ch = item.chapter?.name ?? 'capítulo';
                final prog = item.progress;
                return ListTile(
                  title: Text(title),
                  subtitle: Text(
                    [
                      ch,
                      item.state,
                      if (prog != null) '${(prog * 100).toStringAsFixed(0)}%',
                      if (item.chapter != null) 'chId=${item.chapter!.id}',
                    ].join(' · '),
                  ),
                  trailing: item.chapter == null
                      ? null
                      : IconButton(
                          tooltip: 'Remover da fila',
                          icon: const Icon(Icons.close),
                          onPressed: () => _run(
                            () => widget.api!.dequeueChapterDownloads(
                              [item.chapter!.id],
                            ),
                            'Removido da fila',
                          ),
                        ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
