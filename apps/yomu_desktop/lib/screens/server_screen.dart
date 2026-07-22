import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    required this.yomuPort,
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
    this.busy = false,
  });

  final int yomuPort;
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
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 20, 28, 10),
            child: Text(
              'Servidor',
              style: TextStyle(
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
                constraints: const BoxConstraints(maxWidth: 760),
                child: YomuSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Acesso pelo iPhone · ${lanEnabled ? 'ativo' : 'local'}',
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
                            onTap: busy ? null : () => onToggleLan(!lanEnabled),
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
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: YomuTokens.surface2,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 76,
                              height: 76,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: YomuTokens.bg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: YomuTokens.border),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _lanUrls(context),
                                  const SizedBox(height: 5),
                                  Text(
                                    lanEnabled
                                        ? 'mesma rede Wi-Fi · acesso autenticado por pareamento'
                                        : 'LAN desativada · somente este computador',
                                    style: const TextStyle(
                                      color: YomuTokens.textSubtle,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                  const SizedBox(height: 9),
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
                                          onPressed: busy
                                              ? null
                                              : onCancelPairing,
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
                      const SizedBox(height: 16),
                      _kv(
                        'Endereço',
                        lanEnabled ? 'rede local' : 'somente local',
                      ),
                      _kv('Porta do Yomu', '$yomuPort'),
                      _kv('Sessões pareadas', '$sessionCount'),
                      const SizedBox(height: 9),
                      const YomuSectionLabel('Dispositivos e sessões'),
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
                              'último acesso: ${session.lastSeenAt?.toLocal() ?? session.createdAt.toLocal()}',
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
                      if (sessions.isNotEmpty && onRevokeAllSessions != null)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async => onRevokeAllSessions!(),
                          child: const Text('Revogar todas as sessões'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                color: YomuTokens.textSubtle,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
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

/// Best-effort LAN IPv4 addresses (Wi-Fi/Ethernet).
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
