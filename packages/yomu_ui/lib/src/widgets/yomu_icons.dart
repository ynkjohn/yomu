import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/yomu_tokens.dart';

/// Stroke icon data transcribed from the production design reference
/// (`design_prod/design em producao.html`). Every glyph lives in a 24x24
/// viewBox and renders with a 1.8 stroke, round caps and round joins,
/// exactly like the `.y-icon` CSS class.
class YomuIconData {
  const YomuIconData(
    this.name, {
    this.paths = const <String>[],
    this.circles = const <List<double>>[],
    this.rects = const <List<double>>[],
  });

  final String name;
  final List<String> paths;

  /// Each entry is `[cx, cy, r]`.
  final List<List<double>> circles;

  /// Each entry is `[x, y, width, height, rx]`.
  final List<List<double>> rects;
}

/// Glyphs from the `<symbol id="icon-*">` defs in the reference HTML.
abstract final class YomuIcons {
  static const home = YomuIconData(
    'home',
    paths: ['M3.5 10.5 12 3.8l8.5 6.7', 'M5.5 9.2V20h13V9.2', 'M9.5 20v-6h5v6'],
  );
  static const library = YomuIconData(
    'library',
    paths: [
      'M4.5 4.5h4v15h-4z',
      'M10 4.5h4v15h-4z',
      'm16 5 3.4-1 3.1 14.3-3.4.8z',
    ],
  );
  static const updates = YomuIconData(
    'updates',
    paths: [
      'M12 3.7v2.1M12 18.2v2.1M3.7 12h2.1M18.2 12h2.1',
      'm6.1 6.1 1.5 1.5m8.8 8.8 1.5 1.5m0-11.8-1.5 1.5m-8.8 8.8-1.5 1.5',
    ],
    circles: [
      [12, 12, 3.6],
    ],
  );
  static const history = YomuIconData(
    'history',
    paths: [
      'M4.2 8.2A8.5 8.5 0 1 1 3.6 14',
      'M4.2 3.8v4.4h4.4',
      'M12 7.5V12l3 1.8',
    ],
  );
  static const explore = YomuIconData(
    'explore',
    paths: ['m14.9 9.1-1.8 4-4 1.8 1.8-4z'],
    circles: [
      [12, 12, 8.5],
    ],
  );
  static const maya = YomuIconData(
    'maya',
    paths: [
      'M7.2 5.5h9.6a3 3 0 0 1 3 3v5.8a3 3 0 0 1-3 3H12l-3.8 2.4v-2.4h-1a3 3 0 0 1-3-3V8.5a3 3 0 0 1 3-3Z',
      'M9 11.4h.01M15 11.4h.01',
      'M12 2.8v2.7',
    ],
  );
  static const download = YomuIconData(
    'download',
    paths: ['M12 3.5v11', 'm7.8 10.8 4.2 4.3 4.2-4.3', 'M4.5 19.5h15'],
  );
  static const settings = YomuIconData(
    'settings',
    paths: [
      'M19.2 13.3v-2.6l-2-.6-.7-1.7 1-1.9-1.9-1.9-1.9 1-1.7-.7-.6-2H8.8l-.6 2-1.7.7-1.9-1-1.9 1.9 1 1.9-.7 1.7-2 .6v2.6l2 .6.7 1.7-1 1.9 1.9 1.9 1.9-1 1.7.7.6 2h2.6l.6-2 1.7-.7 1.9 1 1.9-1.9-1-1.9.7-1.7z',
    ],
    circles: [
      [12, 12, 3.1],
    ],
  );
  static const server = YomuIconData(
    'server',
    paths: ['M7 7h.01M7 17h.01M11 7h6M11 17h6'],
    rects: [
      [3.5, 4, 17, 6, 2],
      [3.5, 14, 17, 6, 2],
    ],
  );
  static const backup = YomuIconData(
    'backup',
    paths: [
      'M5 8.3A8 8 0 1 1 4.2 15',
      'M5 3.8v4.5h4.5',
      'M12 8v8m-3-3 3 3 3-3',
    ],
  );
  static const diagnostics = YomuIconData(
    'diagnostics',
    paths: ['M4 12h3l1.5-4 3 9 2.3-6 1.6 3H20'],
    rects: [
      [2.5, 4, 19, 16, 3],
    ],
  );
  static const search = YomuIconData(
    'search',
    paths: ['m16 16 4.2 4.2'],
    circles: [
      [10.8, 10.8, 6.5],
    ],
  );
  static const play = YomuIconData('play', paths: ['m8 5.5 10 6.5-10 6.5z']);
  static const chevronLeft = YomuIconData(
    'chevron-left',
    paths: ['m15 5-7 7 7 7'],
  );
  static const chevronRight = YomuIconData(
    'chevron-right',
    paths: ['m9 5 7 7-7 7'],
  );
  static const chevronDown = YomuIconData(
    'chevron-down',
    paths: ['m5 9 7 7 7-7'],
  );
  static const check = YomuIconData('check', paths: ['m5 12.5 4.4 4.4L19 7.4']);
  static const refresh = YomuIconData(
    'refresh',
    paths: [
      'M19.5 8A8 8 0 0 0 5.3 6.1L3.5 8',
      'M3.5 4v4h4',
      'M4.5 16A8 8 0 0 0 18.7 17.9l1.8-1.9',
      'M20.5 20v-4h-4',
    ],
  );
  static const chapters = YomuIconData(
    'chapters',
    paths: ['M8 5h12M8 12h12M8 19h12', 'M4 5h.01M4 12h.01M4 19h.01'],
  );
  static const layoutRtl = YomuIconData(
    'layout-rtl',
    paths: ['m20 9-3 3 3 3'],
    rects: [
      [5, 4, 11, 16, 1.5],
    ],
  );
  static const layoutLtr = YomuIconData(
    'layout-ltr',
    paths: ['m4 9 3 3-3 3'],
    rects: [
      [8, 4, 11, 16, 1.5],
    ],
  );
  static const layoutDouble = YomuIconData(
    'layout-double',
    paths: [
      'M3.5 5.5A2.5 2.5 0 0 1 6 3h5v16H6a2.5 2.5 0 0 0-2.5 2z',
      'M20.5 5.5A2.5 2.5 0 0 0 18 3h-5v16h5a2.5 2.5 0 0 1 2.5 2z',
    ],
  );
  static const layoutVertical = YomuIconData(
    'layout-vertical',
    rects: [
      [6, 2.5, 12, 6, 1],
      [6, 9, 12, 6, 1],
      [6, 15.5, 12, 6, 1],
    ],
  );
  static const layoutWebtoon = YomuIconData(
    'layout-webtoon',
    paths: ['M7 2.5h10v19H7z', 'M7 8.7h10M7 15.2h10'],
  );
  static const sliders = YomuIconData(
    'sliders',
    paths: ['M4 6h5M15 6h5M4 12h9M17 12h3M4 18h3M11 18h9'],
    circles: [
      [12, 6, 2],
      [15, 12, 2],
      [9, 18, 2],
    ],
  );
  static const maximize = YomuIconData(
    'maximize',
    paths: ['M8.5 3.5h-5v5M15.5 3.5h5v5M8.5 20.5h-5v-5M15.5 20.5h5v-5'],
  );
  static const zoomIn = YomuIconData(
    'zoom-in',
    paths: ['M8 10.5h5M10.5 8v5m4.7 2.2 5 5'],
    circles: [
      [10.5, 10.5, 6.5],
    ],
  );
  static const zoomOut = YomuIconData(
    'zoom-out',
    paths: ['M8 10.5h5m2.2 4.7 5 5'],
    circles: [
      [10.5, 10.5, 6.5],
    ],
  );
  static const bookmark = YomuIconData(
    'bookmark',
    paths: ['M6.5 3.5h11v17L12 17l-5.5 3.5z'],
  );
  static const bookOpen = YomuIconData(
    'book-open',
    paths: [
      'M3.5 5.5A2.5 2.5 0 0 1 6 3h5v16H6a2.5 2.5 0 0 0-2.5 2zM20.5 5.5A2.5 2.5 0 0 0 18 3h-5v16h5a2.5 2.5 0 0 1 2.5 2z',
    ],
  );
  static const more = YomuIconData(
    'more',
    circles: [
      [5, 12, 1],
      [12, 12, 1],
      [19, 12, 1],
    ],
  );
  static const copy = YomuIconData(
    'copy',
    rects: [
      [8, 8, 11, 11, 2],
      [4, 4, 11, 11, 2],
    ],
  );
  static const close = YomuIconData('close', paths: ['m6 6 12 12M18 6 6 18']);
}

/// Renders a [YomuIconData] with the reference stroke style.
class YomuIcon extends StatelessWidget {
  const YomuIcon(
    this.icon, {
    super.key,
    this.size = 18,
    this.color,
    this.semanticLabel,
    this.quarterTurns = 0,
  });

  final YomuIconData icon;
  final double size;
  final Color? color;
  final String? semanticLabel;
  final int quarterTurns;

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ?? IconTheme.of(context).color ?? const Color(0xFFA9B2C4);
    Widget result = CustomPaint(
      size: Size.square(size),
      painter: _YomuIconPainter(icon, resolved),
    );
    if (quarterTurns != 0) {
      result = RotatedBox(quarterTurns: quarterTurns, child: result);
    }
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel == null,
      child: SizedBox(width: size, height: size, child: result),
    );
  }
}

/// Square icon button matching the reference `.icon-button` class:
/// 36x36, radius 11, hairline border, translucent background, hover raise.
class YomuIconButton extends StatefulWidget {
  const YomuIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.color,
    this.size = 36,
    this.iconSize = 18,
    this.selected = false,
    this.quarterTurns = 0,
  });

  final YomuIconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  final double size;
  final double iconSize;
  final bool selected;
  final int quarterTurns;

  @override
  State<YomuIconButton> createState() => _YomuIconButtonState();
}

class _YomuIconButtonState extends State<YomuIconButton> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    const border = Color(0xFF293141);
    const borderStrong = Color(0xFF3C475D);
    const focus = YomuTokens.focus;
    const textMuted = Color(0xFFA9B2C4);
    const text = Color(0xFFF4F6FB);
    final active = enabled && (_hovered || _focused || _pressed);
    final iconColor = widget.color ?? (active ? text : textMuted);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final hitTarget = math.max(widget.size, 44.0);
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        container: true,
        button: true,
        enabled: enabled,
        selected: widget.selected,
        label: widget.tooltip,
        onTap: widget.onTap,
        child: ExcludeSemantics(
          child: SizedBox.square(
            dimension: hitTarget,
            child: Center(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: widget.onTap,
                  onHover: (value) => setState(() => _hovered = value),
                  onFocusChange: (value) => setState(() => _focused = value),
                  onHighlightChanged: (value) =>
                      setState(() => _pressed = value),
                  canRequestFocus: enabled,
                  mouseCursor: enabled
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  borderRadius: BorderRadius.circular(11),
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  child: AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    width: widget.size,
                    height: widget.size,
                    transform: Matrix4.translationValues(
                      0,
                      _hovered && enabled && !reduceMotion ? -1 : 0,
                      0,
                    ),
                    decoration: BoxDecoration(
                      color: _pressed && enabled
                          ? const Color(0xFF293243)
                          : active
                          ? const Color(0xFF222A39)
                          : widget.selected
                          ? const Color(0xFF252C4A)
                          : const Color(0x09FFFFFF),
                      border: Border.all(
                        color: _focused && enabled
                            ? focus
                            : active || widget.selected
                            ? borderStrong
                            : border,
                        width: _focused && enabled ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Opacity(
                      opacity: enabled ? 1 : 0.45,
                      child: Center(
                        child: YomuIcon(
                          widget.icon,
                          size: widget.iconSize,
                          color: iconColor,
                          quarterTurns: widget.quarterTurns,
                        ),
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

class _YomuIconPainter extends CustomPainter {
  _YomuIconPainter(this.icon, this.color);

  final YomuIconData icon;
  final Color color;

  static final Map<String, Path> _cache = <String, Path>{};

  Path _buildPath() {
    return _cache.putIfAbsent(icon.name, () {
      final path = Path();
      for (final d in icon.paths) {
        _SvgPathParser(d).addTo(path);
      }
      for (final c in icon.circles) {
        path.addOval(Rect.fromCircle(center: Offset(c[0], c[1]), radius: c[2]));
      }
      for (final r in icon.rects) {
        path.addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(r[0], r[1], r[2], r[3]),
            Radius.circular(r[4]),
          ),
        );
      }
      return path;
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.save();
    canvas.scale(scale, scale);
    canvas.drawPath(_buildPath(), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _YomuIconPainter oldDelegate) =>
      oldDelegate.icon.name != icon.name || oldDelegate.color != color;
}

/// Minimal SVG path-data parser covering the commands used by the
/// reference glyphs: M/m, L/l, H/h, V/v, A/a and Z/z (rotation-free arcs).
class _SvgPathParser {
  _SvgPathParser(this.data);

  final String data;
  int _i = 0;
  double _x = 0;
  double _y = 0;
  double _startX = 0;
  double _startY = 0;

  void addTo(Path path) {
    String? command;
    while (true) {
      _skipSeparators();
      if (_i >= data.length) break;
      final ch = data[_i];
      if (_isCommand(ch)) {
        command = ch;
        _i++;
      } else if (command == 'M') {
        command = 'L';
      } else if (command == 'm') {
        command = 'l';
      }
      switch (command) {
        case 'M':
          _x = _number();
          _y = _number();
          path.moveTo(_x, _y);
          _startX = _x;
          _startY = _y;
        case 'm':
          _x += _number();
          _y += _number();
          path.moveTo(_x, _y);
          _startX = _x;
          _startY = _y;
        case 'L':
          _x = _number();
          _y = _number();
          path.lineTo(_x, _y);
        case 'l':
          _x += _number();
          _y += _number();
          path.lineTo(_x, _y);
        case 'H':
          _x = _number();
          path.lineTo(_x, _y);
        case 'h':
          _x += _number();
          path.lineTo(_x, _y);
        case 'V':
          _y = _number();
          path.lineTo(_x, _y);
        case 'v':
          _y += _number();
          path.lineTo(_x, _y);
        case 'A':
        case 'a':
          final rx = _number();
          final ry = _number();
          _number(); // x-axis rotation: always 0 in the reference glyphs.
          final largeArc = _number() != 0;
          final sweep = _number() != 0;
          var ex = _number();
          var ey = _number();
          if (command == 'a') {
            ex += _x;
            ey += _y;
          }
          _arcTo(path, rx, ry, largeArc, sweep, ex, ey);
          _x = ex;
          _y = ey;
        case 'Z':
        case 'z':
          path.close();
          _x = _startX;
          _y = _startY;
        default:
          return;
      }
    }
  }

  void _arcTo(
    Path path,
    double rx,
    double ry,
    bool largeArc,
    bool sweep,
    double ex,
    double ey,
  ) {
    if (rx == 0 || ry == 0 || (_x == ex && _y == ey)) {
      path.lineTo(ex, ey);
      return;
    }
    rx = rx.abs();
    ry = ry.abs();
    final dx = (_x - ex) / 2;
    final dy = (_y - ey) / 2;
    final lambda = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry);
    if (lambda > 1) {
      final s = math.sqrt(lambda);
      rx *= s;
      ry *= s;
    }
    final rxSq = rx * rx;
    final rySq = ry * ry;
    var factor =
        (rxSq * rySq - rxSq * dy * dy - rySq * dx * dx) /
        (rxSq * dy * dy + rySq * dx * dx);
    if (factor < 0) factor = 0;
    var root = math.sqrt(factor);
    if (largeArc == sweep) root = -root;
    final cxp = root * rx * dy / ry;
    final cyp = -root * ry * dx / rx;
    final cx = cxp + (_x + ex) / 2;
    final cy = cyp + (_y + ey) / 2;
    final startAngle = math.atan2((dy - cyp) / ry, (dx - cxp) / rx);
    final endAngle = math.atan2((-dy - cyp) / ry, (-dx - cxp) / rx);
    var sweepAngle = endAngle - startAngle;
    if (sweep && sweepAngle < 0) {
      sweepAngle += 2 * math.pi;
    } else if (!sweep && sweepAngle > 0) {
      sweepAngle -= 2 * math.pi;
    }
    path.arcTo(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      startAngle,
      sweepAngle,
      false,
    );
  }

  bool _isCommand(String ch) => 'MmLlHhVvAaZz'.contains(ch);

  void _skipSeparators() {
    while (_i < data.length && (data[_i] == ' ' || data[_i] == ',')) {
      _i++;
    }
  }

  double _number() {
    _skipSeparators();
    final start = _i;
    var seenDot = false;
    if (_i < data.length && (data[_i] == '-' || data[_i] == '+')) _i++;
    while (_i < data.length) {
      final ch = data[_i];
      if (ch == '.') {
        if (seenDot) break;
        seenDot = true;
        _i++;
      } else if (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39) {
        _i++;
      } else {
        break;
      }
    }
    return double.parse(data.substring(start, _i));
  }
}
