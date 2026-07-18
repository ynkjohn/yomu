import 'package:flutter/material.dart';
import 'package:yomu_core/yomu_core.dart';

class EngineMediaImage extends StatefulWidget {
  const EngineMediaImage({
    super.key,
    required this.reference,
    required this.media,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.maxBytes = 8 * 1024 * 1024,
  });

  final MediaReference? reference;
  final EngineMediaGateway? media;
  final Widget fallback;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final int maxBytes;

  @override
  State<EngineMediaImage> createState() => _EngineMediaImageState();
}

class _EngineMediaImageState extends State<EngineMediaImage> {
  Future<MediaPayload>? _payload;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant EngineMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference ||
        !identical(oldWidget.media, widget.media) ||
        oldWidget.maxBytes != widget.maxBytes) {
      _resolve();
    }
  }

  void _resolve() {
    final reference = widget.reference;
    final media = widget.media;
    _payload = reference == null || media == null || widget.maxBytes <= 0
        ? null
        : media.fetch(reference, maxBytes: widget.maxBytes);
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    if (payload == null) return widget.fallback;
    return FutureBuilder<MediaPayload>(
      future: payload,
      builder: (context, snapshot) {
        final value = snapshot.data;
        if (value == null ||
            value.statusCode < 200 ||
            value.statusCode >= 300 ||
            value.bytes.isEmpty) {
          return widget.fallback;
        }
        Widget image = Image.memory(
          value.bytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => widget.fallback,
        );
        final radius = widget.borderRadius;
        if (radius != null) {
          image = ClipRRect(borderRadius: radius, child: image);
        }
        return image;
      },
    );
  }
}
