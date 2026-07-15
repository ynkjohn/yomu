import 'package:flutter/material.dart';
import 'package:yomu_ui/yomu_ui.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    this.message = 'Esta função ainda não foi implementada.',
    this.phase,
  });

  final String title;
  final String message;
  final String? phase;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YomuScreenHeader(title: title),
        Expanded(
          child: Center(
            child: Container(
              width: 460,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: YomuTokens.surface.withValues(alpha: 0.82),
                border: Border.all(color: YomuTokens.border),
                borderRadius: BorderRadius.circular(YomuTokens.radiusLg),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: YomuTokens.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: YomuIcon(
                        YomuIcons.sliders,
                        color: YomuTokens.accent,
                        size: 21,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: YomuTokens.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (phase != null) ...[
                    const SizedBox(height: 7),
                    Text(
                      phase!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: YomuTokens.textSubtle,
                        fontSize: 11.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
