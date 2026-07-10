import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

class PairedSessionRow {
  const PairedSessionRow({
    required this.token,
    required this.deviceName,
    required this.createdAt,
    this.lastSeenAt,
  });

  final String token;
  final String deviceName;
  final DateTime createdAt;
  final DateTime? lastSeenAt;
}

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
    required this.lanEnabled,
    required this.onToggleLan,
    required this.pairingCode,
    required this.pairingExpiresAt,
    required this.onStartPairing,
    required this.onCancelPairing,
    required this.lanAddresses,
    required this.sessionCount,
    this.sessions = const [],
    this.onRevokeSession,
    this.onRevokeAllSessions,
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
  final bool lanEnabled;
  final ValueChanged<bool> onToggleLan;
  final String? pairingCode;
  final DateTime? pairingExpiresAt;
  final VoidCallback onStartPairing;
  final VoidCallback onCancelPairing;
  final List<String> lanAddresses;
  final int sessionCount;
  final List<PairedSessionRow> sessions;
  final ValueChanged<String>? onRevokeSession;
  final VoidCallback? onRevokeAllSessions;
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
          'Sempre em 127.0.0.1:14567 (nunca na LAN). Isolado do AppData Tachidesk.',
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
                  'Acesso iPhone (PWA mínima)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: YomuTokens.space2),
                const Text(
                  'O iPhone fala só com o Yomu Core (nunca com a porta do Suwayomi). '
                  'LAN exige opt-in explícito + código de pareamento.',
                  style: TextStyle(color: YomuTokens.textMuted),
                ),
                const SizedBox(height: YomuTokens.space3),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Permitir acesso na LAN (Wi‑Fi)'),
                  subtitle: Text(
                    lanEnabled
                        ? 'Yomu escuta em 0.0.0.0:$yomuPort (API autenticada)'
                        : 'Yomu só em 127.0.0.1:$yomuPort (sem iPhone na rede)',
                  ),
                  value: lanEnabled,
                  onChanged: busy ? null : onToggleLan,
                ),
                _kv('Yomu HTTP', lanEnabled ? '0.0.0.0:$yomuPort' : '127.0.0.1:$yomuPort'),
                _kv('Sessões pareadas', '$sessionCount'),
                if (sessions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Dispositivos pareados',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  ...sessions.map(
                    (s) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(s.deviceName),
                      subtitle: Text(
                        'desde ${s.createdAt.toLocal()}'
                        '${s.lastSeenAt != null ? ' · visto ${s.lastSeenAt!.toLocal()}' : ''}',
                        style: const TextStyle(
                          color: YomuTokens.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      trailing: onRevokeSession == null
                          ? null
                          : TextButton(
                              onPressed: busy
                                  ? null
                                  : () => onRevokeSession!(s.token),
                              child: const Text('Revogar'),
                            ),
                    ),
                  ),
                  if (onRevokeAllSessions != null)
                    TextButton(
                      onPressed: busy ? null : onRevokeAllSessions,
                      child: const Text('Revogar todas as sessões'),
                    ),
                ],
                if (lanEnabled) ...[
                  const SizedBox(height: 8),
                  const Text('URLs na rede local:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  if (lanAddresses.isEmpty)
                    const Text(
                      'Não foi possível listar IPs. Confira o Wi‑Fi do PC.',
                      style: TextStyle(color: YomuTokens.warning),
                    )
                  else
                    ...lanAddresses.map(
                      (ip) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Expanded(child: SelectableText('http://$ip:$yomuPort/')),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: 'http://$ip:$yomuPort/'),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('URL copiada')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (pairingCode == null)
                    FilledButton(
                      onPressed: onStartPairing,
                      child: const Text('Gerar código de pareamento'),
                    )
                  else ...[
                    Text(
                      'Código: $pairingCode',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    if (pairingExpiresAt != null)
                      Text(
                        'Expira: ${pairingExpiresAt!.toLocal()}',
                        style: const TextStyle(color: YomuTokens.textMuted),
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'No iPhone: abra a URL acima → digite o código → use a biblioteca.',
                      style: TextStyle(color: YomuTokens.textMuted),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: onCancelPairing,
                      child: const Text('Cancelar código'),
                    ),
                  ],
                ],
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
            width: 140,
            child: Text(k, style: const TextStyle(color: YomuTokens.textMuted)),
          ),
          Expanded(child: SelectableText(v)),
        ],
      ),
    );
  }
}

/// Best-effort LAN IPv4 addresses (Wi‑Fi/Ethernet).
Future<List<String>> listLanIpv4Addresses() async {
  final out = <String>[];
  try {
    final ifaces = await NetworkInterface.list(
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    for (final iface in ifaces) {
      for (final addr in iface.addresses) {
        if (addr.isLoopback) continue;
        final ip = addr.address;
        if (ip.startsWith('127.')) continue;
        out.add(ip);
      }
    }
  } catch (_) {}
  return out.toSet().toList()..sort();
}
