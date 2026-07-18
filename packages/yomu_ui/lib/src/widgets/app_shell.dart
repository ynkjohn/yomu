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

enum YomuWindowResizeEdge {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

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
    this.onWindowDrag,
    this.onWindowMinimize,
    this.onWindowToggleMaximize,
    this.onWindowClose,
    this.onWindowResize,
  });

  final List<YomuNavItem> items;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final Widget body;
  final String title;
  final String serverLabel;
  final Color serverColor;
  final VoidCallback? onServerTap;
  final VoidCallback? onWindowDrag;
  final VoidCallback? onWindowMinimize;
  final VoidCallback? onWindowToggleMaximize;
  final VoidCallback? onWindowClose;
  final ValueChanged<YomuWindowResizeEdge>? onWindowResize;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(color: YomuTokens.bg),
              child: Column(
                children: [
                  _WindowTitleBar(
                    title: title,
                    onDrag: onWindowDrag,
                    onMinimize: onWindowMinimize,
                    onToggleMaximize: onWindowToggleMaximize,
                    onClose: onWindowClose,
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 208,
                          decoration: const BoxDecoration(
                            color: YomuTokens.sidebar,
                            border: Border(
                              right: BorderSide(color: Color(0x12FFFFFF)),
                            ),
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
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      18,
                                      12,
                                      18,
                                      14,
                                    ),
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      itemCount: items.length,
                                      itemBuilder: (context, index) {
                                        final item = items[index];
                                        final selected = item.id == selectedId;
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (item.group ==
                                                    YomuNavGroup.system &&
                                                (index == 0 ||
                                                    items[index - 1].group !=
                                                        YomuNavGroup.system))
                                              const Padding(
                                                padding: EdgeInsets.fromLTRB(
                                                  10,
                                                  16,
                                                  10,
                                                  6,
                                                ),
                                                child: Text(
                                                  'SISTEMA',
                                                  style: TextStyle(
                                                    color:
                                                        YomuTokens.textSubtle,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 0.7,
                                                  ),
                                                ),
                                              ),
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 1,
                                              ),
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
                                    margin: const EdgeInsets.fromLTRB(
                                      10,
                                      0,
                                      10,
                                      2,
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      11,
                                      10,
                                      0,
                                    ),
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                          color: Color(0x0FFFFFFF),
                                        ),
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
                                              backgroundColor: Color(
                                                0x335B73DC,
                                              ),
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
                ],
              ),
            ),
          ),
          if (onWindowResize != null)
            _WindowResizeRegions(onResize: onWindowResize!),
        ],
      ),
    );
  }
}

class _WindowResizeRegions extends StatelessWidget {
  const _WindowResizeRegions({required this.onResize});

  static const double _edgeSize = 6;
  static const double _cornerSize = 12;

  final ValueChanged<YomuWindowResizeEdge> onResize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _region(
          edge: YomuWindowResizeEdge.top,
          cursor: SystemMouseCursors.resizeUp,
          left: _cornerSize,
          top: 0,
          right: _cornerSize,
          height: _edgeSize,
        ),
        _region(
          edge: YomuWindowResizeEdge.right,
          cursor: SystemMouseCursors.resizeRight,
          top: _cornerSize,
          right: 0,
          bottom: _cornerSize,
          width: _edgeSize,
        ),
        _region(
          edge: YomuWindowResizeEdge.bottom,
          cursor: SystemMouseCursors.resizeDown,
          left: _cornerSize,
          right: _cornerSize,
          bottom: 0,
          height: _edgeSize,
        ),
        _region(
          edge: YomuWindowResizeEdge.left,
          cursor: SystemMouseCursors.resizeLeft,
          left: 0,
          top: _cornerSize,
          bottom: _cornerSize,
          width: _edgeSize,
        ),
        _region(
          edge: YomuWindowResizeEdge.topLeft,
          cursor: SystemMouseCursors.resizeUpLeft,
          left: 0,
          top: 0,
          width: _cornerSize,
          height: _cornerSize,
        ),
        _region(
          edge: YomuWindowResizeEdge.topRight,
          cursor: SystemMouseCursors.resizeUpRight,
          top: 0,
          right: 0,
          width: _cornerSize,
          height: _cornerSize,
        ),
        _region(
          edge: YomuWindowResizeEdge.bottomRight,
          cursor: SystemMouseCursors.resizeDownRight,
          right: 0,
          bottom: 0,
          width: _cornerSize,
          height: _cornerSize,
        ),
        _region(
          edge: YomuWindowResizeEdge.bottomLeft,
          cursor: SystemMouseCursors.resizeDownLeft,
          left: 0,
          bottom: 0,
          width: _cornerSize,
          height: _cornerSize,
        ),
      ],
    );
  }

  Widget _region({
    required YomuWindowResizeEdge edge,
    required MouseCursor cursor,
    double? left,
    double? top,
    double? right,
    double? bottom,
    double? width,
    double? height,
  }) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        key: ValueKey('yomu-window-resize-${edge.name}'),
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onPanDown: (_) => onResize(edge),
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

class _WindowTitleBar extends StatelessWidget {
  const _WindowTitleBar({
    required this.title,
    required this.onDrag,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
  });

  final String title;
  final VoidCallback? onDrag;
  final VoidCallback? onMinimize;
  final VoidCallback? onToggleMaximize;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('yomu-window-title-bar'),
      height: YomuTokens.windowTitleBarHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Row(
            children: [
              Container(
                width: 208,
                decoration: const BoxDecoration(
                  color: YomuTokens.sidebar,
                  border: Border(right: BorderSide(color: Color(0x12FFFFFF))),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    _WindowControlButton(
                      key: const ValueKey('yomu-window-close'),
                      label: 'Fechar',
                      color: const Color(0xFFFF5F57),
                      onPressed: onClose,
                    ),
                    _WindowControlButton(
                      key: const ValueKey('yomu-window-minimize'),
                      label: 'Minimizar',
                      color: const Color(0xFFFEBC2E),
                      onPressed: onMinimize,
                    ),
                    _WindowControlButton(
                      key: const ValueKey('yomu-window-maximize'),
                      label: 'Maximizar ou restaurar',
                      color: const Color(0xFF28C840),
                      onPressed: onToggleMaximize,
                    ),
                    Expanded(
                      child: _WindowDragRegion(
                        key: const ValueKey('yomu-window-drag-sidebar'),
                        onDrag: onDrag,
                        onDoubleTap: onToggleMaximize,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ColoredBox(
                  color: YomuTokens.bg,
                  child: _WindowDragRegion(
                    key: const ValueKey('yomu-window-drag-main'),
                    onDrag: onDrag,
                    onDoubleTap: onToggleMaximize,
                  ),
                ),
              ),
            ],
          ),
          IgnorePointer(
            child: Center(
              child: Text(
                title,
                key: const ValueKey('yomu-window-title'),
                style: const TextStyle(
                  color: Color(0xFFC9CED9),
                  fontFamily: 'Segoe UI Variable Display',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1,
                  letterSpacing: 0.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowDragRegion extends StatelessWidget {
  const _WindowDragRegion({
    super.key,
    required this.onDrag,
    required this.onDoubleTap,
  });

  final VoidCallback? onDrag;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onPanStart: onDrag == null ? null : (_) => onDrag!(),
      onDoubleTap: onDoubleTap,
      child: const SizedBox.expand(),
    );
  }
}

class _WindowControlButton extends StatefulWidget {
  const _WindowControlButton({
    super.key,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final scale = _pressed
        ? 0.9
        : _hovered
        ? 1.08
        : 1.0;

    return FocusableActionDetector(
      enabled: enabled,
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
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.label,
        onTap: widget.onPressed,
        child: ExcludeSemantics(
          child: Tooltip(
            message: widget.label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onPressed,
              onTapDown: enabled
                  ? (_) => setState(() => _pressed = true)
                  : null,
              onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
              onTapCancel: enabled
                  ? () => setState(() => _pressed = false)
                  : null,
              child: SizedBox(
                width: 20,
                height: YomuTokens.windowTitleBarHeight,
                child: Center(
                  child: AnimatedScale(
                    scale: scale,
                    duration: YomuTokens.durationFast,
                    curve: Curves.easeOutCubic,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: enabled
                            ? widget.color
                            : widget.color.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                        border: _focused
                            ? Border.all(
                                color: const Color(0xCCFFFFFF),
                                width: 1,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
