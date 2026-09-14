import 'package:flutter/material.dart';

import '../../../theme/yc_style.dart';
import 'onboarding_journey_image.dart';
import 'onboarding_styles.dart';

// Normalized map anchors keep the cards and road in the same coordinate space.
const _stops = [Offset(.23, .42), Offset(.74, .61), Offset(.30, .88)];

/// An illustrative journey, rendered locally without map tiles or location data.
class OnboardingRoutePreview extends StatelessWidget {
  const OnboardingRoutePreview({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label:
        'Illustrated journey: stop 1, Palace; stop 2, Café, highlighted; '
        'stop 3, riverside ghats. One route connects all three places.',
    child: ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            // Let labels grow with accessibility text settings, independently
            // of the image crops, while preserving the map composition.
            final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
            final height = width * 1.16 + (textScale - 1) * 80;
            final markerSize = (width * .08).clamp(26.0, 32.0);
            return SizedBox(
              height: height,
              child: CustomPaint(
                painter: const _RouteMapPainter(),
                child: Stack(
                  children: [
                    for (var index = 0; index < _stops.length; index++)
                      Positioned(
                        left:
                            width *
                            (_stops[index].dx - (index == 1 ? .17 : .145)),
                        bottom:
                            height * (1 - _stops[index].dy) +
                            markerSize / 2 +
                            6,
                        width: width * (index == 1 ? .34 : .29),
                        child: _StopCard(index: index),
                      ),
                    for (var index = 0; index < _stops.length; index++)
                      Positioned(
                        left: width * _stops[index].dx - markerSize / 2,
                        top: height * _stops[index].dy - markerSize / 2,
                        child: Container(
                          width: markerSize,
                          height: markerSize,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: OnboardingStyle.bluePrimary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Text(
                            '${index + 1}',
                            // The illustration has one complete semantic label.
                            textScaler: TextScaler.noScaling,
                            style: YCStyle.secondary.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _StopCard extends StatelessWidget {
  const _StopCard({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final selected = index == 1;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: selected ? OnboardingStyle.bluePrimary : Colors.white,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OnboardingJourneyImage(
            detailScale: 3,
            alignment: [
              const Alignment(-.35, -.85),
              const Alignment(-1, .35),
              const Alignment(1, -.05),
            ][index],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Text(
              ['Palace', 'Café', 'Ghats'][index],
              textAlign: TextAlign.center,
              style: YCStyle.caption.copyWith(
                color: selected ? OnboardingStyle.bluePrimary : YCStyle.ink,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteMapPainter extends CustomPainter {
  const _RouteMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Geometry is proportional to the available illustration bounds, not a
    // phone-sized artboard. The blue route follows the same road underneath it.
    Offset point(double x, double y) => Offset(x * size.width, y * size.height);
    final fill = Paint();
    canvas.drawRect(Offset.zero & size, fill..color = YCStyle.background);

    final river = Path()
      ..moveTo(size.width * .91, 0)
      ..cubicTo(
        size.width * .77,
        size.height * .3,
        size.width * 1.13,
        size.height * .48,
        size.width * .91,
        size.height * .75,
      )
      ..quadraticBezierTo(
        size.width * .80,
        size.height * .94,
        size.width * .97,
        size.height,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(river, fill..color = YCStyle.border);

    for (final block in [
      const Rect.fromLTWH(.04, .05, .31, .22),
      const Rect.fromLTWH(.40, .05, .34, .21),
      const Rect.fromLTWH(.04, .46, .31, .19),
      const Rect.fromLTWH(.53, .69, .12, .12),
      const Rect.fromLTWH(.04, .94, .56, .12),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            block.left * size.width,
            block.top * size.height,
            block.width * size.width,
            block.height * size.height,
          ),
          const Radius.circular(18),
        ),
        fill..color = OnboardingStyle.blueLight,
      );
    }
    // Small planted courtyards borrow the artwork's warm, quiet accent.
    for (final park in [const Offset(.10, .74), const Offset(.57, .15)]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: point(park.dx, park.dy),
          width: size.width * .13,
          height: size.height * .09,
        ),
        fill..color = OnboardingStyle.amber.withValues(alpha: .12),
      );
    }

    final road = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final streets = [
      Path()
        ..moveTo(0, size.height * .42)
        ..lineTo(size.width, size.height * .42),
      Path()
        ..moveTo(size.width * .46, 0)
        ..lineTo(size.width * .46, size.height),
      Path()
        ..moveTo(0, size.height * .88)
        ..lineTo(size.width, size.height * .88),
      Path()
        ..moveTo(size.width * .74, size.height * .22)
        ..lineTo(size.width * .74, size.height),
      Path()
        ..moveTo(0, size.height * .70)
        ..lineTo(size.width * .46, size.height * .70),
    ];
    for (final street in streets) {
      canvas.drawPath(street, road);
    }

    final route = Path()
      ..moveTo(size.width * _stops[0].dx, size.height * _stops[0].dy)
      ..lineTo(size.width * .42, size.height * .42)
      ..quadraticBezierTo(
        size.width * .46,
        size.height * .42,
        size.width * .46,
        size.height * .46,
      )
      ..lineTo(size.width * .46, size.height * .57)
      ..quadraticBezierTo(
        size.width * .46,
        size.height * .61,
        size.width * .50,
        size.height * .61,
      )
      ..lineTo(size.width * .70, size.height * .61)
      ..quadraticBezierTo(
        size.width * .74,
        size.height * .61,
        size.width * .74,
        size.height * .65,
      )
      ..lineTo(size.width * .74, size.height * .84)
      ..quadraticBezierTo(
        size.width * .74,
        size.height * .88,
        size.width * .70,
        size.height * .88,
      )
      ..lineTo(size.width * _stops[2].dx, size.height * _stops[2].dy);
    canvas.drawPath(route, road..strokeWidth = 10);
    canvas.drawPath(
      route,
      road
        ..color = OnboardingStyle.bluePrimary
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(_RouteMapPainter oldDelegate) => false;
}
