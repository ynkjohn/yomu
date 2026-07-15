import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/yomu_tokens.dart';
import 'yomu_icons.dart';

class YomuNavItem {
  const YomuNavItem({
    required this.id,
    required this.label,
    required this.icon,
    this.group = YomuNavGroup.main,
    this.badge,
  });

  final String id;
  final String label;
  final YomuIconData icon;
  final YomuNavGroup group;
  final String? badge;
}

enum YomuNavGroup { main, system }

/// Desktop shell with a compact production sidebar and persistent status rail.
class YomuAppShell extends StatelessWidget {
  const YomuAppShell({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelect,
    required this.body,
    this.title = 'Yomu',
    this.serverLabel = 'Yomu Core ativo · :8787',
    this.serverColor = YomuTokens.success,
    this.onServerTap,
  });

  final List<YomuNavItem> items;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final Widget body;
  final String title;
  final String serverLabel;
  final Color serverColor;
  final VoidCallback? onServerTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(color: YomuTokens.bg),
        child: Row(
          children: [
            Container(
              width: 208,
              decoration: const BoxDecoration(
                color: YomuTokens.sidebar,
                border: Border(right: BorderSide(color: Color(0x12FFFFFF))),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 92,
                    bottom: 70,
                    child: Container(
                      width: 1,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Color(0x5791A5FF),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(22, 16, 18, 14),
                        child: Row(
                          children: [
                            _WindowDot(Color(0xFFFF5F57)),
                            SizedBox(width: 7),
                            _WindowDot(Color(0xFFFEBC2E)),
                            SizedBox(width: 7),
                            _WindowDot(Color(0xFF28C840)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 2, 18, 14),
                        child: Row(
                          children: [
                            _YomuMark(),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: YomuTokens.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final selected = item.id == selectedId;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (item.group == YomuNavGroup.system &&
                                    (index == 0 ||
                                        items[index - 1].group !=
                                            YomuNavGroup.system))
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(10, 16, 10, 6),
                                    child: Text(
                                      'SISTEMA',
                                      style: TextStyle(
                                        color: YomuTokens.textSubtle,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.7,
                                      ),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 1),
                                  child: _NavItemButton(
                                    item: item,
                                    selected: selected,
                                    onTap: () => onSelect(item.id),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.fromLTRB(10, 0, 10, 2),
                        padding: const EdgeInsets.fromLTRB(10, 11, 10, 0),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Color(0x0FFFFFFF)),
                          ),
                        ),
                        child: Column(
                          children: [
                            _ServerStatusButton(
                              label: serverLabel,
                              color: serverColor,
                              onTap: onServerTap,
                            ),
                            const SizedBox(height: 8),
                            const Row(
                              children: [
                                CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Color(0x335B73DC),
                                  child: Text(
                                    'YL',
                                    style: TextStyle(
                                      color: Color(0xFFC7D2FF),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      height: 1,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    'Perfil local',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Color(0xFF8D96A8),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _ServerStatusButton extends StatefulWidget {
  const _ServerStatusButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  State<_ServerStatusButton> createState() => _ServerStatusButtonState();
}

class _ServerStatusButtonState extends State<_ServerStatusButton> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Yomu server status');
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return FocusableActionDetector(
      key: const ValueKey('yomu-server-status-focus'),
      enabled: enabled,
      focusNode: _focusNode,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: Semantics(
        button: enabled,
        enabled: enabled,
        label: enabled ? 'Abrir Servidor. ${widget.label}' : widget.label,
        onTap: widget.onTap,
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : YomuTokens.durationFast,
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: _hovered
                    ? YomuTokens.accent.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(YomuTokens.radiusSm),
                border: _focused
                    ? Border.all(color: YomuTokens.focus, width: 1.5)
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8D96A8),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItemButton extends StatefulWidget {
  const _NavItemButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final YomuNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItemButton> createState() => _NavItemButtonState();
}

class _NavItemButtonState extends State<_NavItemButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final selected = widget.selected;
    final isMain = item.group == YomuNavGroup.main;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final animationDuration = reduceMotion
        ? Duration.zero
        : YomuTokens.durationFast;
    final labelColor = _hovered
        ? const Color(0xFFDCE2FF)
        : selected
        ? YomuTokens.text
        : YomuTokens.textMuted;
    final iconColor = _hovered
        ? const Color(0xFFDCE2FF)
        : selected
        ? YomuTokens.accent
        : YomuTokens.textSubtle;
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Stack(
            children: [
              AnimatedContainer(
                duration: animationDuration,
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(_hovered ? 2 : 0, 0, 0),
                constraints: const BoxConstraints(minHeight: 44),
                padding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: isMain ? 7 : 6,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? YomuTokens.accent.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(YomuTokens.radiusSm),
                  border: _focused
                      ? Border.all(color: YomuTokens.focus, width: 1.5)
                      : null,
                ),
                child: Row(
                  children: [
                    AnimatedScale(
                      scale: _hovered ? 1.06 : 1,
                      duration: animationDuration,
                      curve: Curves.easeOutCubic,
                      child: YomuIcon(item.icon, size: 18, color: iconColor),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: labelColor,
                          fontSize: isMain ? 13 : 12.5,
                          fontWeight: isMain
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (item.badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: YomuTokens.accent.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          item.badge!,
                          style: const TextStyle(
                            color: Color(0xFFC7D2FF),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: AnimatedContainer(
                      duration: reduceMotion
                          ? Duration.zero
                          : YomuTokens.durationMedium,
                      curve: Curves.easeOutCubic,
                      width: 2,
                      height: 18,
                      decoration: BoxDecoration(
                        color: YomuTokens.accent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YomuMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: YomuTokens.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x14FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x47283C91),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            width: 12,
            height: 34,
            left: -6,
            top: -6,
            child: Transform.rotate(
              angle: 0.488692,
              child: const ColoredBox(color: Color(0x2EFFFFFF)),
            ),
          ),
          const Center(
            child: Text(
              'Y',
              style: TextStyle(
                color: YomuTokens.accent,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowDot extends StatelessWidget {
  const _WindowDot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
