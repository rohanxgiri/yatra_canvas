import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Clipped native backdrop blur, shared across renderers.
/// Custom shader filters remapped unrelated backdrop content on Android.
class YatraRefractiveGlass extends StatelessWidget {
  const YatraRefractiveGlass({
    required this.child,
    this.radius = 24,
    this.fill = const Color(0x18FFFFFF),
    this.borderColor = const Color(0x80FFFFFF),
    this.borderWidth = .65,
    this.blur = 2,
    this.displacement = 2.4,
    this.shadow = false,
    this.highlight = true,
    super.key,
  });

  final Widget child;
  // Displacement remains a compatibility argument; native blur does not warp UVs.
  final double radius, borderWidth, blur, displacement;
  final Color fill, borderColor;
  final bool shadow, highlight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final rounded = BorderRadius.circular(radius);
      final reduced = MediaQuery.highContrastOf(context);
      final filter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: rounded,
          boxShadow: shadow
              ? const [
                  BoxShadow(
                    color: Color(0x0D142C53),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: rounded,
          child: BackdropFilter(
            filter: filter,
            child: ColoredBox(
              color: reduced ? const Color(0xB3DCE7F4) : fill,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: rounded,
                  gradient: highlight
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0x16FFFFFF),
                            Color(0x02FFFFFF),
                            Color(0x08142C53),
                          ],
                          stops: [0, .45, 1],
                        )
                      : null,
                  border: Border.all(color: borderColor, width: borderWidth),
                ),
                child: CustomPaint(
                  foregroundPainter: highlight ? _GlassEdge(radius) : null,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Narrow inner optical rim, not a glow or a second opaque surface.
class _GlassEdge extends CustomPainter {
  const _GlassEdge(this.radius);
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        Radius.circular((radius - 1.3).clamp(0, 100)),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x30FFFFFF), Color(0x00FFFFFF), Color(0x14142C53)],
          stops: [0, .45, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassEdge oldDelegate) => radius != oldDelegate.radius;
}
