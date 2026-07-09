import 'package:flutter/material.dart';

import '../theme/yomu_tokens.dart';

/// Standard loading / empty / error shell for provisional screens.
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
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(YomuTokens.space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: YomuTokens.danger, size: 40),
              const SizedBox(height: YomuTokens.space3),
              Text(error!, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: YomuTokens.space3),
                FilledButton(onPressed: onRetry, child: const Text('Tentar de novo')),
              ],
            ],
          ),
        ),
      );
    }
    if (isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: const TextStyle(color: YomuTokens.textMuted),
        ),
      );
    }
    return child;
  }
}
