import 'package:flutter/material.dart';

import '../theme/yomu_tokens.dart';
import 'yomu_icons.dart';

/// Standard loading, empty, and error presentation for desktop screens.
class AsyncBody extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.isLoading,
    this.error,
    this.isEmpty = false,
    this.emptyMessage = 'Nada por aqui ainda.',
    this.onRetry,
    required this.child,
  });

  final bool isLoading;
  final String? error;
  final bool isEmpty;
  final String emptyMessage;
  final VoidCallback? onRetry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const _StatePanel(
        icon: YomuIcons.updates,
        title: 'Preparando conteúdo',
        message: 'Só um instante enquanto o Yomu organiza esta tela.',
        loading: true,
      );
    }
    if (error != null) {
      return _StatePanel(
        icon: YomuIcons.close,
        iconColor: YomuTokens.danger,
        title: 'Algo não saiu como esperado',
        message: error!,
        action: onRetry == null
            ? null
            : FilledButton(
                onPressed: onRetry,
                child: const Text('Tentar de novo'),
              ),
      );
    }
    if (isEmpty) {
      return _StatePanel(
        icon: YomuIcons.library,
        title: 'Nada por aqui ainda',
        message: emptyMessage,
      );
    }
    return child;
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.iconColor = YomuTokens.accent,
    this.loading = false,
    this.action,
  });

  final YomuIconData icon;
  final String title;
  final String message;
  final Color iconColor;
  final bool loading;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: loading,
      label: loading ? '$title. $message' : null,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          margin: const EdgeInsets.all(YomuTokens.space5),
          padding: const EdgeInsets.all(YomuTokens.space5),
          decoration: BoxDecoration(
            color: YomuTokens.surface.withValues(alpha: 0.86),
            border: Border.all(color: YomuTokens.border),
            borderRadius: BorderRadius.circular(YomuTokens.radiusLg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(YomuTokens.radiusMd),
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(15),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: 'Carregando conteúdo',
                        ),
                      )
                    : Center(child: YomuIcon(icon, color: iconColor, size: 24)),
              ),
              const SizedBox(height: YomuTokens.space4),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: YomuTokens.space2),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: YomuTokens.textSubtle,
                  height: 1.5,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: YomuTokens.space4),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
