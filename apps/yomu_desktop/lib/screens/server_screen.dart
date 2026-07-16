import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_suwayomi/yomu_suwayomi.dart';
import 'package:yomu_ui/yomu_ui.dart';

class PairedSessionRow {
  const PairedSessionRow({
    required this.sessionId,
    required this.deviceName,
    required this.createdAt,
    this.lastSeenAt,
  });

  final String sessionId;
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
  final Future<void> Function(String sessionId)? onRevokeSession;
  final Future<void> Function()? onRevokeAllSessions;
  final String? aboutVersion;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final running = status.state == SuwayomiProcessState.running;
    final starting =
        status.state == SuwayomiProcessState.starting ||
        status.state == SuwayomiProcessState.stopping;

    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 10),
            child: Text(
              'Servidor e Motor',
              style: const TextStyle(
                color: YomuTokens.text,
                fontSize: 23,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.46,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 6, 28, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: YomuSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Servidor do iPhone · ${lanEnabled ? 'ativo' : 'local'}',
                                    style: const TextStyle(
                                      color: YomuTokens.text,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Semantics(
                                  container: true,
                                  label: 'Permitir acesso na LAN (Wi-Fi)',
                                  value: busy
                                      ? '${lanEnabled ? 'Ativado' : 'Desativado'}. Alteração em andamento'
                                      : lanEnabled
                                      ? 'Ativado'
                                      : 'Desativado',
                                  toggled: lanEnabled,
                                  enabled: !busy,
                                  liveRegion: busy,
                                  onTap: busy
                                      ? null
                                      : () => onToggleLan(!lanEnabled),
                                  child: ExcludeSemantics(
                                    child: Switch(
                                      value: lanEnabled,
                                      onChanged: busy ? null : onToggleLan,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            ExcludeSemantics(
                              child: Text(
                                lanEnabled
                                    ? 'Permitir acesso na LAN (Wi-Fi) · ativado'
                                    : 'Permitir acesso na LAN (Wi-Fi) · desativado',
                                style: const TextStyle(
                                  color: YomuTokens.textSubtle,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: YomuTokens.surface2,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 76,
                                    height: 76,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: YomuTokens.bg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: YomuTokens.border,
                                      ),
                                    ),
                                    child: Text(
                                      pairingCode == null
                                          ? 'QR\nindisponível'
                                          : 'Código: $pairingCode',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: pairingCode == null
                                            ? YomuTokens.textSubtle
                                            : YomuTokens.accent,
                                        fontFamily: 'Consolas',
                                        fontSize: pairingCode == null ? 10 : 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _lanUrls(context),
                                        const SizedBox(height: 4),
                                        Text(
                                          lanEnabled
                                              ? 'mesma rede Wi-Fi · API autenticada por pareamento'
                                              : 'LAN desativada · somente este computador',
                                          style: const TextStyle(
                                            color: YomuTokens.textSubtle,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        pairingCode == null
                                            ? FilledButton(
                                                onPressed: lanEnabled && !busy
                                                    ? onStartPairing
                                                    : null,
                                                child: const Text(
                                                  'Gerar código de pareamento',
                                                ),
                                              )
                                            : OutlinedButton(
                                                onPressed: onCancelPairing,
                                                child: Text(
                                                  pairingExpiresAt == null
                                                      ? 'Cancelar código'
                                                      : 'Cancelar · expira ${pairingExpiresAt!.toLocal()}',
                                                ),
                                              ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            _kv(
                              'Yomu HTTP',
                              lanEnabled
                                  ? '0.0.0.0:$yomuPort'
                                  : '127.0.0.1:$yomuPort',
                            ),
                            _kv('Sessões pareadas', '$sessionCount'),
                            const SizedBox(height: 8),
                            const YomuSectionLabel('Dispositivos conectados'),
                            const SizedBox(height: 6),
                            if (sessions.isEmpty)
                              const Text(
                                'Nenhum dispositivo pareado.',
                                style: TextStyle(color: YomuTokens.textMuted),
                              )
                            else
                              ...sessions.map(
                                (session) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text(session.deviceName),
                                  subtitle: Text(
                                    'ultimo acesso: ${session.lastSeenAt?.toLocal() ?? session.createdAt.toLocal()}',
                                    style: const TextStyle(
                                      color: YomuTokens.textSubtle,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                  trailing: onRevokeSession == null
                                      ? null
                                      : TextButton(
                                          onPressed: busy
                                              ? null
                                              : () async {
                                                  await onRevokeSession!(
                                                    session.sessionId,
                                                  );
                                                },
                                          child: const Text('Revogar'),
                                        ),
                                ),
                              ),
                            if (sessions.isNotEmpty &&
                                onRevokeAllSessions != null)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () async {
                                        await onRevokeAllSessions!();
                                      },
                                child: const Text('Revogar todas as sessões'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 5,
                      child: YomuSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Motor de extensões · ${status.state.name}',
                                    style: const TextStyle(
                                      color: YomuTokens.text,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                StatusPill(
                                  label: status.state.name,
                                  color: _color(status.state),
                                ),
                                if (busy) ...[
                                  const SizedBox(width: 8),
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 14),
                            _kv(
                              'Serviço',
                              status.version ?? 'Suwayomi gerenciado',
                            ),
                            if (aboutVersion != null)
                              _kv('Runtime', aboutVersion!),
                            _kv(
                              'Porta (somente loopback)',
                              '127.0.0.1:$kYomuSuwayomiPort',
                            ),
                            _kv('PID', status.pid?.toString() ?? '—'),
                            _kv('Pasta de dados', managedRootDir),
                            _kv('Java/JRE', 'OpenJDK 21 gerenciado'),
                            if (status.message != null) ...[
                              const SizedBox(height: 8),
                              SelectableText(
                                status.message!,
                                style: TextStyle(
                                  color: running
                                      ? YomuTokens.success
                                      : YomuTokens.warning,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton(
                                  onPressed: (running || starting || busy)
                                      ? null
                                      : onStart,
                                  child: const Text('Iniciar'),
                                ),
                                OutlinedButton(
                                  onPressed: (!running && !starting) || busy
                                      ? null
                                      : onStop,
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
                            const SizedBox(height: 12),
                            const Text(
                              'O motor executa as extensões e nunca é exposto na rede — só o Yomu fala com ele.',
                              style: TextStyle(
                                color: YomuTokens.textSubtle,
                                fontSize: 10.5,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _color(SuwayomiProcessState s) => switch (s) {
    SuwayomiProcessState.running => YomuTokens.success,
    SuwayomiProcessState.starting ||
    SuwayomiProcessState.stopping => YomuTokens.warning,
    SuwayomiProcessState.unhealthy ||
    SuwayomiProcessState.crashed => YomuTokens.danger,
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
            child: Text(
              k,
              style: const TextStyle(
                color: YomuTokens.textSubtle,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: const TextStyle(color: YomuTokens.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lanUrls(BuildContext context) {
    final urls = lanEnabled
        ? lanAddresses
              .map((address) => 'http://$address:$yomuPort/')
              .toList(growable: false)
        : <String>['http://127.0.0.1:$yomuPort/'];
    if (urls.isEmpty) {
      return const Text(
        'Não foi possível listar endereços LAN. Confira a conexão deste PC.',
        style: TextStyle(color: YomuTokens.warning, fontSize: 11.5),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final url in urls)
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  url,
                  style: const TextStyle(
                    color: YomuTokens.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              YomuIconButton(
                tooltip: 'Copiar $url',
                icon: YomuIcons.copy,
                iconSize: 16,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('URL copiada')));
                },
              ),
            ],
          ),
      ],
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
