import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'home_style.dart';

/// Original flipped image, layer blur, and three rotated glows from node 18:16.
class HomeBackground extends StatelessWidget {
  const HomeBackground({required this.scale, super.key});
  final double scale;
  @override
  Widget build(BuildContext context) {
    final s = scale;
    return ClipRect(
      child: ColoredBox(
        color: const Color(0xFF151515),
        child: Stack(
          children: [
            Positioned(
              left: -232 * s,
              top: 2 * s,
              width: 1163 * s,
              height: 1463 * s,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 59.5 * s,
                  sigmaY: 59.5 * s,
                ),
                child: Transform.flip(
                  flipY: true,
                  child: Image.asset(
                    '${HomeStyle.assetRoot}home_background.png',
                    fit: BoxFit.fill,
                  ),
                ),
              ),
            ),
            Positioned.fill(child: CustomPaint(painter: _OriginalGlows(s))),
          ],
        ),
      ),
    );
  }
}

class _OriginalGlows extends CustomPainter {
  const _OriginalGlows(this.scale);
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    void glow(
      Offset center,
      Size size,
      double degrees,
      double sigma,
      Color color,
      BlendMode blend,
    ) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(degrees * math.pi / 180);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: size.width,
          height: size.height,
        ),
        Paint()
          ..color = color
          ..blendMode = blend
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma),
      );
      canvas.restore();
    }

    glow(
      const Offset(469.47, -150.87),
      const Size(648.445, 706.748),
      9.96,
      84.75,
      const Color(0x99FDF1C0),
      BlendMode.srcOver,
    );
    glow(
      const Offset(249.71, 153.5),
      const Size(74.31, 551.114),
      38.9,
      60.9,
      const Color(0x40C0C4D4),
      BlendMode.screen,
    );
    glow(
      const Offset(540.56, 59.28),
      const Size(88.117, 297.089),
      38.9,
      69.25,
      const Color(0x40C0C4D4),
      BlendMode.screen,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OriginalGlows oldDelegate) => oldDelegate.scale != scale;
}
