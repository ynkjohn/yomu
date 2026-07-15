import 'package:flutter/material.dart';

import '../theme/yomu_tokens.dart';

class YomuScreenHeader extends StatelessWidget {
  const YomuScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        YomuTokens.screenPaddingX,
        YomuTokens.screenHeaderTop,
        YomuTokens.screenPaddingX,
        YomuTokens.screenHeaderBottom,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: YomuTokens.screenDivider)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x0991A5FF), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: YomuTokens.textSubtle,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: YomuTokens.space4),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class YomuScreenScroll extends StatelessWidget {
  const YomuScreenScroll({
    super.key,
    required this.child,
    this.controller,
    this.padding = const EdgeInsets.fromLTRB(
      YomuTokens.screenPaddingX,
      YomuTokens.screenScrollTop,
      YomuTokens.screenPaddingX,
      YomuTokens.screenScrollBottom,
    ),
  });

  final Widget child;
  final ScrollController? controller;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SingleChildScrollView(
        controller: controller,
        padding: padding,
        child: child,
      ),
    );
  }
}

class YomuMetricCard extends StatelessWidget {
  const YomuMetricCard({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: YomuTokens.cardWash,
        border: Border.all(color: YomuTokens.cardBorder),
        borderRadius: BorderRadius.circular(YomuTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: YomuTokens.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(color: YomuTokens.textSubtle, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class YomuProgressBar extends StatelessWidget {
  const YomuProgressBar({super.key, required this.value, this.height = 4});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: YomuTokens.progressTrack),
            AnimatedFractionallySizedBox(
              duration: reduceMotion ? Duration.zero : YomuTokens.durationSlow,
              curve: Curves.easeOutCubic,
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [YomuTokens.accentStrong, YomuTokens.accent],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class YomuSectionCard extends StatelessWidget {
  const YomuSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(YomuTokens.space4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: YomuTokens.surface.withValues(alpha: 0.82),
        border: Border.all(color: YomuTokens.border),
        borderRadius: BorderRadius.circular(YomuTokens.radiusMd),
      ),
      child: child,
    );
  }
}

class YomuSectionLabel extends StatelessWidget {
  const YomuSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: YomuTokens.textSubtle,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}
