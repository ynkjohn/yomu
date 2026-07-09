import 'package:flutter/material.dart';
import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_ui/yomu_ui.dart';

/// Minimal Maya chat — offline heuristic + ActionProposal confirm cards.
class MayaScreen extends StatefulWidget {
  const MayaScreen({
    super.key,
    required this.service,
    required this.engineReady,
    this.onOpenManga,
  });

  final MayaService? service;
  final bool engineReady;
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

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final maya = _maya;
    final text = _controller.text.trim();
    if (maya == null || text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _controller.clear();
    try {
      await maya.sendUserMessage(text);
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) {
      setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  Future<void> _confirm(ActionProposal p) async {
    final maya = _maya;
    if (maya == null || _busy) return;
    setState(() => _busy = true);
    try {
      final done = await maya.confirmProposal(p.id);
      if (done.kind == MayaActionKind.openManga &&
          done.status == ActionProposalStatus.executed) {
        final id = done.payload['mangaId'];
        final title = '${done.payload['title'] ?? ''}';
        final mangaId = id is int ? id : int.tryParse('$id');
        if (mangaId != null) {
          widget.onOpenManga?.call(mangaId, title);
        }
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _reject(ActionProposal p) async {
    final maya = _maya;
    if (maya == null) return;
    await maya.rejectProposal(p.id);
    if (mounted) setState(() {});
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.engineReady || _maya == null) {
      return const AsyncBody(
        isLoading: false,
        error: null,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(YomuTokens.space5),
            child: Text(
              'Inicie o Suwayomi para a Maya consultar a biblioteca.\n'
              'Maya roda em modo local (sem API externa) e só executa ações após você confirmar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: YomuTokens.textMuted),
            ),
          ),
        ),
      );
    }

    final maya = _maya!;
    final messages = maya.messages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            YomuTokens.space5,
            YomuTokens.space4,
            YomuTokens.space5,
            YomuTokens.space2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Maya',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await maya.clearHistory();
                        if (mounted) setState(() {});
                      },
                child: const Text('Limpar'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: YomuTokens.space5),
          child: Text(
            'Assistente local. Ações mutáveis viram propostas — confirme para executar.',
            style: TextStyle(color: YomuTokens.textMuted),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(YomuTokens.space3),
            child: Text(_error!, style: const TextStyle(color: YomuTokens.danger)),
          ),
        Expanded(
          child: messages.isEmpty
              ? const Center(
                  child: Text(
                    'Diga “ajuda”, “biblioteca” ou “continuar”.',
                    style: TextStyle(color: YomuTokens.textMuted),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(YomuTokens.space4),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    final proposals = maya.proposalsFor(m);
                    final isUser = m.role == MayaRole.user;
                    return Align(
                      alignment:
                          isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                        ),
                        child: Card(
                          color: isUser
                              ? YomuTokens.accent.withValues(alpha: 0.18)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(YomuTokens.space3),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isUser ? 'Você' : 'Maya',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isUser
                                        ? YomuTokens.accent
                                        : YomuTokens.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SelectableText(m.text),
                                for (final p in proposals) ...[
                                  const SizedBox(height: 10),
                                  _ProposalCard(
                                    proposal: p,
                                    busy: _busy,
                                    onConfirm: () => _confirm(p),
                                    onReject: () => _reject(p),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(YomuTokens.space3),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_busy,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Mensagem para a Maya…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _send,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enviar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.busy,
    required this.onConfirm,
    required this.onReject,
  });

  final ActionProposal proposal;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final pending = proposal.status == ActionProposalStatus.pending;
    final color = switch (proposal.status) {
      ActionProposalStatus.pending => YomuTokens.warning,
      ActionProposalStatus.executed => YomuTokens.success,
      ActionProposalStatus.failed => YomuTokens.danger,
      ActionProposalStatus.rejected => YomuTokens.textMuted,
      ActionProposalStatus.confirmed => YomuTokens.accent,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(label: proposal.status.name, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  proposal.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            proposal.description,
            style: const TextStyle(color: YomuTokens.textMuted, fontSize: 13),
          ),
          if (proposal.error != null) ...[
            const SizedBox(height: 4),
            Text(
              proposal.error!,
              style: const TextStyle(color: YomuTokens.danger, fontSize: 12),
            ),
          ],
          if (pending) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: busy ? null : onConfirm,
                  child: const Text('Confirmar'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : onReject,
                  child: const Text('Recusar'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
