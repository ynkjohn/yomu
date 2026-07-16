import 'package:flutter/material.dart';
import 'package:yomu_ai/yomu_ai.dart';
import 'package:yomu_storage/yomu_storage.dart';
import 'package:yomu_ui/yomu_ui.dart';

import '../services/maya_provider_controller.dart';

class MayaScreen extends StatefulWidget {
  const MayaScreen({
    super.key,
    required this.service,
    required this.engineReady,
    this.providerController,
    this.unavailableReason,
    this.onOpenManga,
  });

  final MayaService? service;
  final bool engineReady;
  final MayaProviderController? providerController;
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
  bool get _available => _maya != null;

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
    if (!widget.engineReady) {
      setState(() {
        _error = 'Inicie o motor local antes de confirmar uma ação da Maya.';
      });
      return;
    }
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

  Future<void> _configureProvider() async {
    final controller = widget.providerController;
    if (controller == null || _busy) return;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _MayaProviderDialog(controller: controller),
    );
    if (mounted) {
      setState(() {
        if (changed == true) _error = null;
      });
    }
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
                providerController: widget.providerController,
                onConfigureProvider: widget.providerController == null || _busy
                    ? null
                    : _configureProvider,
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
    if (messages.isEmpty) {
      final cloudReady =
          widget.providerController?.status ==
          MayaProviderControllerStatus.cloudReady;
      return Center(
        child: Text(
          cloudReady
              ? 'Pergunte à Maya ou peça uma ação sobre a biblioteca.'
              : 'Diga “ajuda”, “biblioteca” ou configure um provider.',
          style: const TextStyle(color: YomuTokens.textMuted, fontSize: 13.5),
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
                      canConfirm: widget.engineReady,
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
    required this.providerController,
    required this.onConfigureProvider,
    required this.onClearHistory,
  });

  final bool engineReady;
  final int messageCount;
  final MayaProviderController? providerController;
  final VoidCallback? onConfigureProvider;
  final VoidCallback? onClearHistory;

  @override
  Widget build(BuildContext context) {
    final provider = _mayaProviderPresentation(providerController);
    return Padding(
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
                Text(
                  provider.cloudConfigured
                      ? 'IA por provider · ações só após confirmação'
                      : 'assistente local · ações só após confirmação',
                  style: const TextStyle(
                    color: YomuTokens.textSubtle,
                    fontSize: 10.5,
                  ),
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
                    _ContextChip(
                      label: provider.label,
                      dot: true,
                      dotColor: provider.color,
                    ),
                    const Tooltip(
                      message: 'Esta função ainda não foi implementada.',
                      child: _ContextChip(
                        label: 'Perfil de gosto',
                        disabled: true,
                      ),
                    ),
                    YomuIconButton(
                      tooltip: 'Configurar IA da Maya',
                      icon: YomuIcons.settings,
                      color: YomuTokens.textMuted,
                      onTap: onConfigureProvider,
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
}

({String label, Color color, bool cloudConfigured}) _mayaProviderPresentation(
  MayaProviderController? controller,
) {
  if (controller == null) {
    return (
      label: 'IA · indisponível',
      color: YomuTokens.textSubtle,
      cloudConfigured: false,
    );
  }
  final settings = controller.settings;
  final providerId = settings?.providerId;
  final provider = _mayaProviderLabel(providerId);
  return switch (controller.status) {
    MayaProviderControllerStatus.unset => (
      label: 'IA · não configurada',
      color: YomuTokens.textSubtle,
      cloudConfigured: false,
    ),
    MayaProviderControllerStatus.local => (
      label: 'Maya · local',
      color: YomuTokens.success,
      cloudConfigured: false,
    ),
    MayaProviderControllerStatus.disabled => (
      label: '$provider · desativada',
      color: YomuTokens.warning,
      cloudConfigured: true,
    ),
    MayaProviderControllerStatus.cloudReady => (
      label: '$provider · ${settings?.modelId ?? 'modelo pendente'}',
      color: YomuTokens.success,
      cloudConfigured: true,
    ),
    MayaProviderControllerStatus.missingCredential => (
      label: '$provider · chave ausente',
      color: YomuTokens.warning,
      cloudConfigured: true,
    ),
    MayaProviderControllerStatus.credentialUnavailable => (
      label: '$provider · cofre indisponível',
      color: YomuTokens.danger,
      cloudConfigured: true,
    ),
    MayaProviderControllerStatus.consentRequired => (
      label: '$provider · novo consentimento',
      color: YomuTokens.warning,
      cloudConfigured: true,
    ),
    MayaProviderControllerStatus.unsupportedProvider ||
    MayaProviderControllerStatus.adapterUnavailable => (
      label: '$provider · fallback local',
      color: YomuTokens.warning,
      cloudConfigured: true,
    ),
    MayaProviderControllerStatus.closed => (
      label: 'IA · encerrada',
      color: YomuTokens.textSubtle,
      cloudConfigured: false,
    ),
  };
}

String _mayaProviderLabel(String? providerId) => switch (providerId) {
  'openai' => 'OpenAI',
  'anthropic' => 'Anthropic',
  'gemini' => 'Gemini',
  'ollama' => 'Ollama local',
  null => 'Provider',
  _ => providerId,
};

const List<(String, String)> _mayaProviderChoices = <(String, String)>[
  ('openai', 'OpenAI'),
  ('anthropic', 'Anthropic'),
  ('gemini', 'Google Gemini'),
  ('ollama', 'Ollama local'),
];

class _MayaProviderDialog extends StatefulWidget {
  const _MayaProviderDialog({required this.controller});

  final MayaProviderController controller;

  @override
  State<_MayaProviderDialog> createState() => _MayaProviderDialogState();
}

class _MayaProviderDialogState extends State<_MayaProviderDialog> {
  late String _providerId;
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  late bool _shareRecentHistory;
  late bool _shareLibraryContext;
  late bool _cloudConsent;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.settings;
    final persistedProvider = settings?.providerId;
    _providerId = kSupportedMayaProviderIds.contains(persistedProvider)
        ? persistedProvider!
        : 'openai';
    _modelController = TextEditingController(text: settings?.modelId ?? '');
    _apiKeyController = TextEditingController();
    _shareRecentHistory = settings?.shareRecentHistory ?? false;
    _shareLibraryContext = settings?.shareLibraryContext ?? false;
    _cloudConsent =
        settings?.mode == MayaProviderMode.cloud &&
        settings?.isEnabled == true &&
        settings?.consentVersion == kCurrentMayaProviderConsentVersion;
  }

  @override
  void dispose() {
    _apiKeyController.clear();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _saveCloud() async {
    if (_saving) return;
    final model = _modelController.text.trim();
    if (model.isEmpty) {
      setState(() => _error = 'Informe o ID exato do modelo.');
      return;
    }
    if (!_cloudConsent) {
      setState(() {
        _error = 'Confirme o envio da mensagem atual antes de ativar a IA.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final apiKey = _apiKeyController.text;
    try {
      await widget.controller.saveCloud(
        providerId: _providerId,
        modelPolicy: MayaProviderModelPolicy.explicit,
        modelId: model,
        apiKey: apiKey.trim().isEmpty ? null : apiKey,
        shareRecentHistory: _shareRecentHistory,
        shareLibraryContext: _shareLibraryContext,
      );
      _apiKeyController.clear();
      if (mounted) Navigator.of(context).pop(true);
    } on MayaProviderControllerException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Não foi possível salvar a configuração da Maya.';
        });
      }
    }
  }

  Future<void> _saveLocal() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.saveLocal();
      _apiKeyController.clear();
      if (mounted) Navigator.of(context).pop(true);
    } on MayaProviderControllerException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Não foi possível ativar o modo local.';
        });
      }
    }
  }

  Future<void> _removeProvider() async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar credenciais cloud da Maya?'),
        content: const Text(
          'As requisições serão canceladas e todas as credenciais cloud da '
          'Maya (OpenAI, Anthropic e Gemini) serão removidas do Windows '
          'Credential Manager antes de ativar o modo local. O histórico '
          'continuará disponível.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: YomuTokens.danger),
            child: const Text('Remover com segurança'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.removeProvider(
        resetToUnset: widget.controller.settings == null,
      );
      _apiKeyController.clear();
      if (mounted) Navigator.of(context).pop(true);
    } on MayaProviderControllerException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Não foi possível remover o provider com segurança.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOllama = _providerId == 'ollama';
    return AlertDialog(
      title: const Text('IA da Maya'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'A Maya continua segura e local por padrão. Ao ativar cloud, '
                'somente a mensagem atual é obrigatória; histórico e '
                'biblioteca exigem consentimentos separados.',
                style: TextStyle(
                  color: YomuTokens.textMuted,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              const _MayaFieldLabel('Provider'),
              const SizedBox(height: 7),
              DropdownButtonFormField<String>(
                value: _providerId,
                isExpanded: true,
                decoration: const InputDecoration(
                  hintText: 'Selecione o provider',
                ),
                items: [
                  for (final choice in _mayaProviderChoices)
                    DropdownMenuItem<String>(
                      value: choice.$1,
                      child: Text(choice.$2),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null || value == _providerId) return;
                        setState(() {
                          _providerId = value;
                          _modelController.clear();
                          _apiKeyController.clear();
                          _cloudConsent = false;
                          _error = null;
                        });
                      },
              ),
              const SizedBox(height: 15),
              const _MayaFieldLabel('Modelo'),
              const SizedBox(height: 7),
              TextField(
                controller: _modelController,
                enabled: !_saving,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: isOllama
                      ? 'Nome exato do modelo instalado no Ollama'
                      : 'ID exato do modelo do provider',
                  helperText: isOllama
                      ? 'Ollama permanece em 127.0.0.1:11434.'
                      : 'O Yomu não escolhe modelo ou custo automaticamente.',
                ),
              ),
              if (!isOllama) ...[
                const SizedBox(height: 15),
                const _MayaFieldLabel('API key'),
                const SizedBox(height: 7),
                TextField(
                  controller: _apiKeyController,
                  enabled: !_saving,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableInteractiveSelection: false,
                  keyboardType: TextInputType.visiblePassword,
                  autofillHints: const <String>[],
                  decoration: const InputDecoration(
                    hintText: 'Cole uma nova chave',
                    helperText:
                        'Nunca é exibida ou salva no SQLite. Deixe vazio para '
                        'manter a credencial já configurada.',
                  ),
                ),
              ],
              const SizedBox(height: 18),
              CheckboxListTile(
                value: _cloudConsent,
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _cloudConsent = value ?? false;
                        _error = null;
                      }),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Autorizo enviar a mensagem atual a este provider',
                  style: TextStyle(fontSize: 12.5),
                ),
                subtitle: const Text(
                  'Obrigatório para cada ativação cloud.',
                  style: TextStyle(color: YomuTokens.textSubtle, fontSize: 11),
                ),
              ),
              CheckboxListTile(
                value: _shareRecentHistory,
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _shareRecentHistory = value ?? false;
                      }),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Compartilhar histórico recente',
                  style: TextStyle(fontSize: 12.5),
                ),
                subtitle: const Text(
                  'No máximo 12 mensagens, dentro de um orçamento limitado.',
                  style: TextStyle(color: YomuTokens.textSubtle, fontSize: 11),
                ),
              ),
              CheckboxListTile(
                value: _shareLibraryContext,
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _shareLibraryContext = value ?? false;
                      }),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Compartilhar contexto da biblioteca',
                  style: TextStyle(fontSize: 12.5),
                ),
                subtitle: const Text(
                  'Snapshot transitório e limitado; o banco Suwayomi não é '
                  'copiado para o SQLite Yomu.',
                  style: TextStyle(color: YomuTokens.textSubtle, fontSize: 11),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: YomuTokens.danger,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _removeProvider,
          style: TextButton.styleFrom(foregroundColor: YomuTokens.danger),
          child: const Text('Limpar credenciais cloud'),
        ),
        TextButton(
          onPressed: _saving ? null : _saveLocal,
          child: const Text('Usar modo local'),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _saveCloud,
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Salvar e ativar'),
        ),
      ],
    );
  }
}

class _MayaFieldLabel extends StatelessWidget {
  const _MayaFieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: YomuTokens.text,
      fontSize: 12,
      fontWeight: FontWeight.w700,
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
