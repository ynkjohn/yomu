import 'package:flutter/material.dart';
import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_ui/yomu_ui.dart';

class MayaScreen extends StatefulWidget {
  const MayaScreen({
    super.key,
    required this.service,
    required this.engineReady,
    this.unavailableReason,
    this.onOpenManga,
  });

  final MayaService? service;
  final bool engineReady;
  final String? unavailableReason;
  final void Function(int mangaId, String title)? onOpenManga;

  @override
  State<MayaScreen> createState() => _MayaScreenState();
}

class _MayaScreenState extends State<MayaScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;
  String? _error;

  MayaService? get _maya => widget.service;
  bool get _available => widget.engineReady && _maya != null;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final maya = _maya;
    final text = _controller.text.trim();
    if (!_available || maya == null || text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _controller.clear();
    try {
      await maya.sendUserMessage(text);
    } catch (_) {
      _error = 'Não foi possível salvar a mensagem da Maya.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _scrollToEnd();
  }

  Future<void> _confirm(ActionProposal proposal) async {
    final maya = _maya;
    if (!_available || maya == null || _busy) return;
    setState(() => _busy = true);
    try {
      final done = await maya.confirmProposal(proposal.id);
      if (done.kind == MayaActionKind.openManga &&
          done.status == ActionProposalStatus.executed) {
        final rawId = done.payload['mangaId'];
        final mangaId = rawId is int ? rawId : int.tryParse('$rawId');
        if (mangaId != null) {
          widget.onOpenManga?.call(mangaId, '${done.payload['title'] ?? ''}');
        }
      }
    } catch (_) {
      _error =
          'Não foi possível concluir a ação da Maya. '
          'O estado persistido foi preservado.';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _reject(ActionProposal proposal) async {
    final maya = _maya;
    if (maya == null || _busy) return;
    setState(() => _busy = true);
    try {
      await maya.rejectProposal(proposal.id);
    } catch (_) {
      _error = 'Não foi possível registrar o cancelamento da proposta.';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _clearHistory() async {
    final maya = _maya;
    if (maya == null || _busy || maya.messages.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar histórico?'),
        content: const Text(
          'As mensagens e propostas salvas da Maya serão removidas. '
          'Essa ação não altera a biblioteca.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Limpar histórico'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await maya.clearHistory();
    } catch (_) {
      _error = 'Não foi possível limpar o histórico da Maya.';
    }
    if (mounted) setState(() => _busy = false);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : YomuTokens.durationMedium,
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = _maya?.messages ?? const <MayaMessage>[];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            children: [
              _MayaHeader(
                engineReady: widget.engineReady,
                messageCount: messages.length,
                onClearHistory: messages.isEmpty || _busy
                    ? null
                    : _clearHistory,
              ),
              if (_error != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(28, 0, 28, 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: YomuTokens.danger.withValues(alpha: 0.1),
                    border: Border.all(
                      color: YomuTokens.danger.withValues(alpha: 0.35),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const YomuIcon(
                        YomuIcons.close,
                        size: 14,
                        color: YomuTokens.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: YomuTokens.danger,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: _conversation(messages),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: _MayaComposer(
                  controller: _controller,
                  enabled: _available && !_busy,
                  busy: _busy,
                  onSend: _send,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 300, child: _MayaMemoryPanel()),
      ],
    );
  }

  Widget _conversation(List<MayaMessage> messages) {
    if (_maya == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _MayaUnavailable(reason: widget.unavailableReason),
        ),
      );
    }
    if (!_available && messages.isEmpty) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(28), child: _MayaUnavailable()),
      );
    }
    if (messages.isEmpty) {
      return const Center(
        child: Text(
          'Diga “ajuda”, “biblioteca” ou “continuar”.',
          style: TextStyle(color: YomuTokens.textMuted, fontSize: 13.5),
        ),
      );
    }
    final maya = _maya!;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final proposals = maya.proposalsFor(message);
        final isUser = message.role == MayaRole.user;
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isUser ? 470 : 560),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  _MessageBubble(message: message),
                  for (final proposal in proposals) ...[
                    const SizedBox(height: 10),
                    _ProposalCard(
                      proposal: proposal,
                      busy: _busy,
                      canConfirm: _available,
                      onConfirm: () => _confirm(proposal),
                      onReject: () => _reject(proposal),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MayaHeader extends StatelessWidget {
  const _MayaHeader({
    required this.engineReady,
    required this.messageCount,
    required this.onClearHistory,
  });

  final bool engineReady;
  final int messageCount;
  final VoidCallback? onClearHistory;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _MayaFace(size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Maya',
                style: TextStyle(
                  color: YomuTokens.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const Text(
                'assistente local · ações só após confirmação',
                style: TextStyle(color: YomuTokens.textSubtle, fontSize: 10.5),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _ContextChip(
                    label: engineReady
                        ? 'Biblioteca · conectada'
                        : 'Biblioteca · offline',
                    dot: true,
                    dotColor: engineReady
                        ? YomuTokens.success
                        : YomuTokens.danger,
                  ),
                  _ContextChip(label: 'Histórico · $messageCount mensagens'),
                  const Tooltip(
                    message: 'Esta função ainda não foi implementada.',
                    child: _ContextChip(
                      label: 'Perfil de gosto',
                      disabled: true,
                    ),
                  ),
                  YomuIconButton(
                    tooltip: 'Limpar histórico da Maya',
                    icon: YomuIcons.close,
                    color: YomuTokens.danger,
                    onTap: onClearHistory,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ContextChip extends StatelessWidget {
  const _ContextChip({
    required this.label,
    this.dot = false,
    this.dotColor = YomuTokens.success,
    this.disabled = false,
  });

  final String label;
  final bool dot;
  final Color dotColor;
  final bool disabled;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: disabled ? 0.5 : 1,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF171C27),
        border: Border.all(color: const Color(0x14FFFFFF)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: const TextStyle(
              color: YomuTokens.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final MayaMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.role == MayaRole.user;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: user ? YomuTokens.accent : const Color(0xFF171C27),
        border: user ? null : Border.all(color: const Color(0x12FFFFFF)),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(user ? 16 : 5),
          bottomRight: Radius.circular(user ? 5 : 16),
        ),
      ),
      child: SelectableText(
        message.text,
        style: TextStyle(
          color: user ? Colors.white : const Color(0xFFE0E2E9),
          fontSize: 13.5,
          height: 1.55,
        ),
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.busy,
    required this.canConfirm,
    required this.onConfirm,
    required this.onReject,
  });

  final ActionProposal proposal;
  final bool busy;
  final bool canConfirm;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final pending = proposal.status == ActionProposalStatus.pending;
    if (proposal.status == ActionProposalStatus.rejected) {
      return const Text(
        'Proposta ignorada — nada foi alterado.',
        style: TextStyle(color: YomuTokens.textSubtle, fontSize: 12),
      );
    }
    if (proposal.status == ActionProposalStatus.executed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: YomuTokens.success.withValues(alpha: 0.08),
          border: Border.all(color: YomuTokens.success.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const YomuIcon(YomuIcons.check, size: 15, color: Color(0xFF9DD8B4)),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Ação aplicada — ${proposal.title}',
                style: const TextStyle(
                  color: Color(0xFF9DD8B4),
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (proposal.status == ActionProposalStatus.confirmed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFF141923),
          border: Border.all(color: const Color(0x66C8B7F4)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'Confirmação registrada, mas o resultado não foi verificado. '
          'A ação não será repetida automaticamente.',
          style: TextStyle(
            color: YomuTokens.textMuted,
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
      );
    }
    final color = proposal.status == ActionProposalStatus.failed
        ? YomuTokens.danger
        : const Color(0xFFC8B7F4);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF141923),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pending
                ? 'PROPOSTA DE AÇÃO · AGUARDANDO VOCÊ'
                : proposal.status.name.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            proposal.title,
            style: const TextStyle(
              color: YomuTokens.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            proposal.description,
            style: const TextStyle(
              color: YomuTokens.textMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          if (proposal.error != null) ...[
            const SizedBox(height: 6),
            Text(
              proposal.error!,
              style: const TextStyle(color: YomuTokens.danger, fontSize: 12),
            ),
          ],
          if (pending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: busy ? null : onReject,
                  child: const Text('Ignorar'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy || !canConfirm ? null : onConfirm,
                  child: const Text('Confirmar ação'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MayaComposer extends StatelessWidget {
  const _MayaComposer({
    required this.controller,
    required this.enabled,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
    child: Container(
      height: 52,
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF191E2A),
        border: Border.all(color: const Color(0x1AFFFFFF)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              style: const TextStyle(color: YomuTokens.text, fontSize: 13.5),
              decoration: InputDecoration.collapsed(
                hintText: enabled
                    ? 'Pergunte à Maya…'
                    : 'Inicie o motor para conversar…',
                hintStyle: const TextStyle(color: YomuTokens.textSubtle),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          Semantics(
            button: true,
            enabled: enabled,
            label: busy ? 'Enviando mensagem' : 'Enviar mensagem',
            liveRegion: busy,
            child: SizedBox.square(
              dimension: 44,
              child: Center(
                child: InkWell(
                  excludeFromSemantics: true,
                  onTap: enabled ? onSend : null,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: enabled
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF9765D5), Color(0xFF536CD6)],
                            )
                          : null,
                      color: enabled ? null : const Color(0xFF292F3D),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const YomuIcon(
                            YomuIcons.chevronDown,
                            size: 17,
                            color: Colors.white,
                            quarterTurns: 2,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MayaMemoryPanel extends StatelessWidget {
  const _MayaMemoryPanel();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
    decoration: const BoxDecoration(
      color: Color(0xFF0C111A),
      border: Border(left: BorderSide(color: Color(0x12FFFFFF))),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Memória da Maya',
          style: TextStyle(
            color: YomuTokens.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Memória detalhada ainda não implementada.',
          style: TextStyle(
            color: YomuTokens.textSubtle,
            fontSize: 11,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF141923),
            border: Border.all(color: const Color(0x0FFFFFFF)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Esta função ainda não foi implementada.',
            style: TextStyle(
              color: YomuTokens.textMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Tooltip(
          message: 'Esta função ainda não foi implementada.',
          child: OutlinedButton(
            onPressed: null,
            style: OutlinedButton.styleFrom(
              disabledForegroundColor: YomuTokens.danger,
              side: BorderSide(color: YomuTokens.danger.withValues(alpha: 0.3)),
            ),
            child: const Text('Apagar toda a memória'),
          ),
        ),
      ],
    ),
  );
}

class _MayaUnavailable extends StatelessWidget {
  const _MayaUnavailable({this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const _MayaFace(size: 56),
      const SizedBox(height: 14),
      Text(
        reason == null
            ? 'Maya temporariamente indisponível'
            : 'Histórico da Maya indisponível',
        style: const TextStyle(
          color: YomuTokens.text,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        reason ??
            'Inicie o Suwayomi para a Maya consultar a biblioteca.\n'
                'As ações só são executadas depois da sua confirmação.',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: YomuTokens.textMuted,
          fontSize: 13.5,
          height: 1.55,
        ),
      ),
    ],
  );
}

class _MayaFace extends StatelessWidget {
  const _MayaFace({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF9C65D4), Color(0xFF536CD6)],
      ),
    ),
    alignment: Alignment.center,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size >= 36 ? 4 : 3,
          height: size >= 36 ? 7 : 6,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        SizedBox(width: size >= 36 ? 4 : 3),
        Container(
          width: size >= 36 ? 4 : 3,
          height: size >= 36 ? 7 : 6,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ],
    ),
  );
}
