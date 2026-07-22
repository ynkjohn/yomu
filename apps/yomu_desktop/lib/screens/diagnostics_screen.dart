import 'package:flutter/material.dart';
import 'package:yomu_core/yomu_core.dart';
import 'package:yomu_ui/yomu_ui.dart';

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({
    super.key,
    required this.readiness,
    required this.diagnostics,
    required this.yomuPort,
    required this.lanEnabled,
    required this.onRetry,
    required this.onStop,
    required this.onRestart,
    required this.onRefresh,
    this.busy = false,
  });

  final EngineReadinessSnapshot readiness;
  final EngineDiagnosticsSnapshot? diagnostics;
  final int? yomuPort;
  final bool lanEnabled;
  final VoidCallback onRetry;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onRefresh;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final details = diagnostics;
    final ownership = details?.ownership ?? EngineOwnershipStatus.none;
    final owned = ownership == EngineOwnershipStatus.owned;
    final retryAllowed =
        ownership != EngineOwnershipStatus.foreign &&
        ownership != EngineOwnershipStatus.inconclusive;
    final statusColor = _readinessColor(readiness.state);

    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 20, 28, 10),
            child: Text(
              'Diagnóstico',
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
                constraints: const BoxConstraints(maxWidth: 1040),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = <Widget>[
                      _StatusCard(
                        readiness: readiness,
                        statusColor: statusColor,
                        busy: busy,
                        owned: owned,
                        retryAllowed: retryAllowed,
                        onRetry: onRetry,
                        onStop: onStop,
                        onRestart: onRestart,
                        onRefresh: onRefresh,
                      ),
                      _TechnicalCard(
                        diagnostics: details,
                        yomuPort: yomuPort,
                        lanEnabled: lanEnabled,
                      ),
                    ];
                    if (constraints.maxWidth < 820) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          cards.first,
                          const SizedBox(height: 16),
                          cards.last,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: cards.first),
                        const SizedBox(width: 16),
                        Expanded(flex: 6, child: cards.last),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.readiness,
    required this.statusColor,
    required this.busy,
    required this.owned,
    required this.retryAllowed,
    required this.onRetry,
    required this.onStop,
    required this.onRestart,
    required this.onRefresh,
  });

  final EngineReadinessSnapshot readiness;
  final Color statusColor;
  final bool busy;
  final bool owned;
  final bool retryAllowed;
  final VoidCallback onRetry;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return YomuSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Motor interno',
                  style: TextStyle(
                    color: YomuTokens.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              StatusPill(
                label: _readinessLabel(readiness.state),
                color: statusColor,
              ),
              if (busy) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            readiness.failure?.message ??
                'Os recursos de leitura estão disponíveis.',
            style: TextStyle(
              color: readiness.failure == null
                  ? YomuTokens.textMuted
                  : statusColor,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          if (readiness.attempt > 0) ...[
            const SizedBox(height: 8),
            _detail('Tentativa de recuperação', '${readiness.attempt}'),
          ],
          if (readiness.nextRetryAt != null)
            _detail(
              'Próxima tentativa',
              readiness.nextRetryAt!.toLocal().toString(),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: busy || readiness.isReady || !retryAllowed
                    ? null
                    : onRetry,
                child: const Text('Tentar novamente'),
              ),
              OutlinedButton(
                onPressed: busy || !owned ? null : onStop,
                child: const Text('Parar motor'),
              ),
              OutlinedButton(
                onPressed: busy || !owned ? null : onRestart,
                child: const Text('Reiniciar motor'),
              ),
              OutlinedButton(
                onPressed: busy ? null : onRefresh,
                child: const Text('Atualizar diagnóstico'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Parar ou reiniciar só é permitido quando o processo pertence ao '
            'Yomu e a ownership foi confirmada.',
            style: TextStyle(
              color: YomuTokens.textSubtle,
              fontSize: 10.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _TechnicalCard extends StatelessWidget {
  const _TechnicalCard({
    required this.diagnostics,
    required this.yomuPort,
    required this.lanEnabled,
  });

  final EngineDiagnosticsSnapshot? diagnostics;
  final int? yomuPort;
  final bool lanEnabled;

  @override
  Widget build(BuildContext context) {
    final details = diagnostics;
    final runtime = [
      details?.runtimeName,
      details?.runtimeVersion,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' ');
    final host = details?.host;
    final port = details?.port;
    final endpoint = host == null || port == null ? '—' : '$host:$port';

    return YomuSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detalhes técnicos',
            style: TextStyle(
              color: YomuTokens.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          _detail('Implementação', details?.engineName ?? 'Suwayomi'),
          _detail('Versão', details?.engineVersion ?? '—'),
          _detail('Protocolo', details?.protocolVersion ?? '—'),
          _detail(
            'Compatibilidade',
            _compatibilityLabel(details?.compatibility),
          ),
          _detail('Ownership', _ownershipLabel(details?.ownership)),
          _detail('PID', details?.processId?.toString() ?? '—'),
          _detail('Porta interna', endpoint),
          _detail('Java/JRE', runtime.isEmpty ? '—' : runtime),
          _detail('JAR', details?.artifactPath ?? '—'),
          _detail('Pasta de dados', details?.dataRoot ?? '—'),
          _detail(
            'Último health check',
            details?.lastHealthCheck?.toLocal().toString() ?? '—',
          ),
          _detail(
            'Yomu Core',
            yomuPort == null
                ? 'indisponível'
                : '${lanEnabled ? 'LAN' : 'local'} · porta $yomuPort',
          ),
          const SizedBox(height: 10),
          const YomuSectionLabel('Capacidades'),
          const SizedBox(height: 7),
          if (details == null || details.capabilities.isEmpty)
            const Text(
              'Ainda não verificadas.',
              style: TextStyle(color: YomuTokens.textMuted),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final capability in details.capabilities)
                  Chip(label: Text(capability)),
              ],
            ),
        ],
      ),
    );
  }
}

Widget _detail(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 142,
          child: Text(
            label,
            style: const TextStyle(color: YomuTokens.textSubtle, fontSize: 12),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(color: YomuTokens.text, fontSize: 12.5),
          ),
        ),
      ],
    ),
  );
}

String _readinessLabel(EngineReadinessState state) => switch (state) {
  EngineReadinessState.initializing => 'inicializando',
  EngineReadinessState.starting => 'iniciando',
  EngineReadinessState.ready => 'disponível',
  EngineReadinessState.temporarilyUnavailable => 'indisponível',
  EngineReadinessState.recovering => 'recuperando',
  EngineReadinessState.actionRequired => 'ação necessária',
  EngineReadinessState.shuttingDown => 'encerrando',
};

Color _readinessColor(EngineReadinessState state) => switch (state) {
  EngineReadinessState.ready => YomuTokens.success,
  EngineReadinessState.initializing ||
  EngineReadinessState.starting ||
  EngineReadinessState.recovering ||
  EngineReadinessState.shuttingDown => YomuTokens.warning,
  EngineReadinessState.temporarilyUnavailable ||
  EngineReadinessState.actionRequired => YomuTokens.danger,
};

String _compatibilityLabel(EngineCompatibilityStatus? status) =>
    switch (status) {
      EngineCompatibilityStatus.compatible => 'compatível',
      EngineCompatibilityStatus.incompatible => 'incompatível',
      EngineCompatibilityStatus.unknown || null => 'não verificada',
    };

String _ownershipLabel(EngineOwnershipStatus? status) => switch (status) {
  EngineOwnershipStatus.owned => 'processo owned pelo Yomu',
  EngineOwnershipStatus.foreign => 'processo estrangeiro',
  EngineOwnershipStatus.inconclusive => 'inconclusiva',
  EngineOwnershipStatus.none || null => 'nenhum processo',
};
