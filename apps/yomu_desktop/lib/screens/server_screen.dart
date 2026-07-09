import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

class ServerScreen extends StatelessWidget {
  const ServerScreen({
    super.key,
    required this.status,
    required this.yomuPort,
    required this.managedRootDir,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onHealthCheck,
    this.aboutVersion,
    this.busy = false,
  });

  final SuwayomiStatus status;
  final int yomuPort;
  final String managedRootDir;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onHealthCheck;
  final String? aboutVersion;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final running = status.state == SuwayomiProcessState.running;
    final starting = status.state == SuwayomiProcessState.starting ||
        status.state == SuwayomiProcessState.stopping;

    return ListView(
      padding: const EdgeInsets.all(YomuTokens.space5),
      children: [
        Text(
          'Motor Suwayomi',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: YomuTokens.space2),
        const Text(
          'Loopback only. Não exposto na LAN. Isolado do %LOCALAPPDATA%\\Tachidesk.',
          style: TextStyle(color: YomuTokens.textMuted),
        ),
        const SizedBox(height: YomuTokens.space4),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(YomuTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusPill(
                      label: status.state.name,
                      color: _color(status.state),
                    ),
                    if (busy) ...[
                      const SizedBox(width: 12),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: YomuTokens.space3),
                _kv('URL', status.baseUrl ?? 'http://127.0.0.1:$kYomuSuwayomiPort'),
                _kv('Versão pinada', status.version ?? '—'),
                if (aboutVersion != null) _kv('About runtime', aboutVersion!),
                _kv('PID', status.pid?.toString() ?? '—'),
                _kv('Data root', managedRootDir),
                if (status.lastHealthCheck != null)
                  _kv('Último health', status.lastHealthCheck!.toLocal().toString()),
                if (status.message != null) ...[
                  const SizedBox(height: YomuTokens.space2),
                  SelectableText(
                    status.message!,
                    style: TextStyle(
                      color: status.state == SuwayomiProcessState.crashed ||
                              status.state == SuwayomiProcessState.unhealthy
                          ? YomuTokens.danger
                          : YomuTokens.warning,
                    ),
                  ),
                ],
                const SizedBox(height: YomuTokens.space3),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: (running || starting || busy) ? null : onStart,
                      child: const Text('Iniciar'),
                    ),
                    OutlinedButton(
                      onPressed: (!running && !starting) || busy ? null : onStop,
                      child: const Text('Parar'),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : onRestart,
                      child: const Text('Reiniciar'),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : onHealthCheck,
                      child: const Text('Health check'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text: status.baseUrl ??
                                'http://127.0.0.1:$kYomuSuwayomiPort',
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('URL copiada')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copiar URL'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: YomuTokens.space3),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(YomuTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Yomu HTTP (loopback — dev stub)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: YomuTokens.space2),
                Text('Health/PWA stub: http://127.0.0.1:$yomuPort/'),
                const SizedBox(height: YomuTokens.space2),
                const Text(
                  'Por padrão o Yomu Server escuta só em 127.0.0.1 (sem LAN). '
                  'A PWA stub não é release. Antes de PWA real na rede: '
                  'opt-in LAN explícito, token/pareamento por dispositivo e CORS restrito. '
                  'Suwayomi nunca é exposto na LAN (só 127.0.0.1:14567).',
                  style: TextStyle(color: YomuTokens.textMuted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Color _color(SuwayomiProcessState s) => switch (s) {
        SuwayomiProcessState.running => YomuTokens.success,
        SuwayomiProcessState.starting ||
        SuwayomiProcessState.stopping =>
          YomuTokens.warning,
        SuwayomiProcessState.unhealthy ||
        SuwayomiProcessState.crashed =>
          YomuTokens.danger,
        SuwayomiProcessState.stopped => YomuTokens.textMuted,
      };

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: const TextStyle(color: YomuTokens.textMuted)),
          ),
          Expanded(child: SelectableText(v)),
        ],
      ),
    );
  }
}
