import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'home_style.dart';
import 'yatra_refractive_glass.dart';

class WhereNextCard extends StatelessWidget {
  const WhereNextCard({required this.onCreateTrip, super.key});
  final VoidCallback onCreateTrip;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final s = constraints.maxWidth / 620;
      final extra = HomeStyle.extraTextHeight(context, 96) * s;
      final buttonHeight = (48 + HomeStyle.extraTextHeight(context, 19)) * s;
      final hitHeight = math.max(48.0, buttonHeight);
      return SizedBox(
        height: 252 * s + extra,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18 * s),
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0x12DBDBDB)),
              ),
              Positioned(
                left: 5 * s,
                bottom: -32 * s,
                child: HomeIcon('mountains', width: 636 * s, height: 168 * s),
              ),
              Positioned(
                left: 372.5 * s,
                bottom: 80 * s,
                child: HomeIcon('route', width: 190.5 * s, height: 119.005 * s),
              ),
              Positioned(
                left: 353 * s,
                bottom: 78 * s,
                child: HomeIcon('route_pin', width: 29 * s, height: 31 * s),
              ),
              Positioned(
                left: 551 * s,
                bottom: 196 * s,
                child: HomeIcon('route_pin', width: 29 * s, height: 31 * s),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18 * s),
                      border: Border.all(
                        color: const Color(0x80FFFFFF),
                        width: .7 * s,
                      ),
                    ),
                    child: CustomPaint(painter: _OriginalInsetShadow(s)),
                  ),
                ),
              ),
              Positioned(
                left: 15 * s,
                top: 29 * s,
                right: 100 * s,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Where next?', style: HomeStyle.text(38 * s)),
                    SizedBox(height: 8 * s),
                    Text(
                      'Start building your personalized trip',
                      style: HomeStyle.text(
                        16 * s,
                        color: const Color(0xFF191C1E),
                        weight: FontWeight.w300,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 18 * s,
                bottom: 30 * s - (hitHeight - buttonHeight) / 2,
                width: (131 + HomeStyle.extraTextHeight(context, 85)) * s,
                height: hitHeight,
                child: HomeAction(
                  label: 'Create Trip',
                  onTap: onCreateTrip,
                  child: SizedBox(
                    height: buttonHeight,
                    child: YatraRefractiveGlass(
                      radius: 74 * s,
                      fill: const Color(0x33E7E7E7),
                      borderColor: const Color(0xFFFCB61F),
                      borderWidth: s,
                      // Preserve the approved amber outline without a white rim.
                      highlight: false,
                      blur: 1,
                      displacement: 1.2,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          HomeIcon('plus', width: 24 * s),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Create Trip',
                                style: HomeStyle.text(
                                  16 * s,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 8 * s),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Figma inset shadow: (0, 4), blur 14.4, spread 1, #DADADA at 25%.
class _OriginalInsetShadow extends CustomPainter {
  const _OriginalInsetShadow(this.scale);
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(bounds, Radius.circular(18 * scale));
    canvas.save();
    canvas.clipRRect(outer);
    final hole = RRect.fromRectAndRadius(
      bounds.deflate(scale).shift(Offset(0, 4 * scale)),
      Radius.circular(17 * scale),
    );
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds.inflate(60 * scale))
      ..addRRect(hole);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x40DADADA)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 7.2 * scale),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OriginalInsetShadow oldDelegate) =>
      oldDelegate.scale != scale;
}
