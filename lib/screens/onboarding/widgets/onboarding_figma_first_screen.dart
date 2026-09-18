import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'onboarding_styles.dart';

/// Responsive implementation of Figma node 73:90 (`onboarding_screen_map`).
///
/// The page layout follows the available viewport. Only the artwork inside
/// [OnboardingMapCard] uses the Figma card as a reference coordinate system.
class OnboardingMapStep extends StatelessWidget {
  const OnboardingMapStep({required this.isActive, super.key});

  final bool isActive;

  static const _headline = 'Beautiful Places\nOne Seamless Experience';
  static const _description =
      'Discover places you love and bring them\n'
      'together in a trip that feels like you';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final viewportHeight = constraints.maxHeight;
        final pagePadding = viewportWidth < 380 ? 20.0 : 24.0;
        final contentWidth = math.min(viewportWidth - pagePadding * 2, 552.0);
        final compact = viewportHeight < 760;
        final typeScale = (viewportWidth / 402).clamp(.90, 1.06);
        final headlineStyle = OnboardingStyle.text(
          28 * typeScale,
          weight: FontWeight.w600,
          height: 34 / 28,
          letterSpacing: -0.34,
          color: const Color(0xFF0E0F12),
        );
        final descriptionStyle = OnboardingStyle.text(
          14 * typeScale,
          height: 20 / 14,
          letterSpacing: -.08,
          color: const Color(0xFF3C3F48),
        );
        final textScaler = MediaQuery.textScalerOf(context);
        final textDirection = Directionality.of(context);
        final headlinePainter = TextPainter(
          text: TextSpan(text: _headline, style: headlineStyle),
          textAlign: TextAlign.center,
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout(maxWidth: contentWidth);
        final descriptionWidth = math.min(contentWidth, 320.0);
        final descriptionPainter = TextPainter(
          text: TextSpan(text: _description, style: descriptionStyle),
          textAlign: TextAlign.center,
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout(maxWidth: descriptionWidth);
        final topPadding = compact ? 4.0 : 8.0;
        final mapToHeadline = compact ? 16.0 : 20.0;
        final headlineToDescription = compact ? 10.0 : 14.0;
        final bottomPadding = compact ? 16.0 : 24.0;
        final reservedHeight =
            topPadding +
            mapToHeadline +
            headlinePainter.height +
            headlineToDescription +
            descriptionPainter.height +
            bottomPadding;
        final heightAwareWidth =
            math.max(240.0, viewportHeight - reservedHeight) * 358 / 500;
        final mapWidth = math.min(contentWidth, heightAwareWidth);

        return CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                pagePadding,
                topPadding,
                pagePadding,
                bottomPadding,
              ),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: SizedBox(
                    width: contentWidth,
                    child: Column(
                      children: [
                        Center(
                          child: SizedBox(
                            width: mapWidth,
                            child: RepaintBoundary(
                              child: AspectRatio(
                                aspectRatio: 358 / 500,
                                child: OnboardingMapCard(isActive: isActive),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: mapToHeadline),
                        Text(
                          _headline,
                          textAlign: TextAlign.center,
                          style: headlineStyle,
                        ),
                        SizedBox(height: headlineToDescription),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Text(
                            _description,
                            textAlign: TextAlign.center,
                            style: descriptionStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The Figma map artwork rendered from bundled node assets.
///
/// The artwork uses the Figma coordinate system and trims only the unused
/// lower cyan field, allowing the hero to sit closer to the reference page
/// margins without stretching its pins or route.
class OnboardingMapCard extends StatefulWidget {
  const OnboardingMapCard({required this.isActive, super.key});

  final bool isActive;

  @override
  State<OnboardingMapCard> createState() => _OnboardingMapCardState();
}

class _OnboardingMapCardState extends State<OnboardingMapCard>
    with TickerProviderStateMixin {
  static const _assetRoot = 'lib/assets/onboarding/figma_map';
  static const _referenceSize = Size(358, 500);

  late final AnimationController _entranceController;
  late final AnimationController _ambientController;
  bool _hasAppeared = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant OnboardingMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion(restart: !oldWidget.isActive && widget.isActive);
  }

  void _syncMotion({bool restart = false}) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (reducedMotion) {
      _entranceController
        ..stop()
        ..value = 1;
      _ambientController.stop();
      _ambientController.value = 0;
      _hasAppeared = true;
      return;
    }

    if (!widget.isActive) {
      _entranceController.stop();
      _ambientController.stop();
      return;
    }

    if (restart || !_hasAppeared) {
      _hasAppeared = true;
      _entranceController.forward(from: 0);
    } else if (!_entranceController.isCompleted &&
        !_entranceController.isAnimating) {
      _entranceController.forward();
    }

    if (!_isWidgetTest && !_ambientController.isAnimating) {
      _ambientController.repeat();
    }
  }

  bool get _isWidgetTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  void dispose() {
    _entranceController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  double _interval(
    double start,
    double end, {
    Curve curve = Curves.easeOutCubic,
  }) {
    final value = ((_entranceController.value - start) / (end - start)).clamp(
      0.0,
      1.0,
    );
    return curve.transform(value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'A Jaipur journey connecting three beautiful places',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sx = constraints.maxWidth / _referenceSize.width;
          final sy = constraints.maxHeight / _referenceSize.height;
          final radius = (28 * sx).clamp(22.0, 28.0);

          Widget softGlow({
            required double left,
            required double top,
            required double width,
            required double height,
            required double blur,
            double rotation = 0,
          }) {
            return Positioned(
              left: left * sx,
              top: top * sy,
              width: width * sx,
              height: height * sy,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: blur * sx,
                  sigmaY: blur * sy,
                ),
                child: Transform.rotate(
                  angle: rotation,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xA6E1FAFE),
                      borderRadius: BorderRadius.all(
                        Radius.elliptical(90, 260),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: ColoredBox(
              color: const Color(0xFF55C6EA),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  softGlow(
                    left: -25,
                    top: -220,
                    width: 43,
                    height: 494,
                    blur: 30,
                    rotation: -.257,
                  ),
                  softGlow(
                    left: 252,
                    top: -176,
                    width: 42,
                    height: 338,
                    blur: 27,
                    rotation: -.257,
                  ),
                  softGlow(
                    left: -76,
                    top: 415,
                    width: 536,
                    height: 95,
                    blur: 46,
                  ),
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      _entranceController,
                      _ambientController,
                    ]),
                    builder: (context, _) {
                      final ambientEnabled = _ambientController.isAnimating;
                      final ambientPhase =
                          _ambientController.value * math.pi * 2;

                      Widget routeNode(
                        Offset offset, {
                        required double revealAt,
                        required double phase,
                      }) {
                        final reveal = _interval(revealAt, revealAt + .18);
                        final pulse = ambientEnabled
                            ? 1 + math.sin(ambientPhase + phase) * .035
                            : 1.0;
                        return Positioned(
                          left: offset.dx * sx,
                          top: offset.dy * sy,
                          width: 25 * sx,
                          height: 25 * sy,
                          child: Opacity(
                            opacity: reveal,
                            child: Transform.scale(
                              scale: (.72 + reveal * .28) * pulse,
                              child: SvgPicture.asset(
                                '$_assetRoot/map_route_node.svg',
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),
                        );
                      }

                      Widget placePin(
                        String name, {
                        required double left,
                        required double top,
                        required double width,
                        required double height,
                        required double revealStart,
                        required double phase,
                      }) {
                        final reveal = _interval(
                          revealStart,
                          revealStart + .24,
                        );
                        final floatY = ambientEnabled
                            ? math.sin(ambientPhase + phase) * 1.4 * sy
                            : 0.0;
                        return Positioned(
                          left: left * sx,
                          top: top * sy,
                          width: width * sx,
                          height: height * sy,
                          child: Opacity(
                            opacity: reveal,
                            child: Transform.translate(
                              offset: Offset(
                                0,
                                (1 - reveal) * 12 * sy + floatY,
                              ),
                              child: Transform.scale(
                                scale: .94 + reveal * .06,
                                alignment: Alignment.bottomCenter,
                                child: Image.asset(
                                  '$_assetRoot/$name',
                                  fit: BoxFit.fill,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      final titleReveal = _interval(0, .20);
                      return Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          Positioned(
                            key: const ValueKey('onboarding-map-route'),
                            left: 14.9 * sx,
                            top: 153.9 * sy,
                            width: 305.4 * sx,
                            height: 339.1 * sy,
                            child: CustomPaint(
                              painter: _AnimatedMapRoutePainter(
                                progress: _interval(
                                  .04,
                                  .90,
                                  curve: Curves.easeInOutCubic,
                                ),
                              ),
                            ),
                          ),
                          routeNode(
                            const Offset(44, 173),
                            revealAt: .05,
                            phase: 0,
                          ),
                          routeNode(
                            const Offset(137, 210),
                            revealAt: .20,
                            phase: .8,
                          ),
                          routeNode(
                            const Offset(7, 361),
                            revealAt: .36,
                            phase: 1.6,
                          ),
                          routeNode(
                            const Offset(154, 439),
                            revealAt: .52,
                            phase: 2.4,
                          ),
                          routeNode(
                            const Offset(306, 407),
                            revealAt: .65,
                            phase: 3.2,
                          ),
                          routeNode(
                            const Offset(273, 276),
                            revealAt: .74,
                            phase: 4.0,
                          ),
                          routeNode(
                            const Offset(297, 147),
                            revealAt: .82,
                            phase: 4.8,
                          ),
                          placePin(
                            'map_albert_hall_pin.png',
                            left: 99,
                            top: 99,
                            width: 102,
                            height: 109,
                            revealStart: .12,
                            phase: 0,
                          ),
                          placePin(
                            'map_jal_mahal_pin.png',
                            left: 245,
                            top: 182,
                            width: 86,
                            height: 91,
                            revealStart: .40,
                            phase: 2.1,
                          ),
                          placePin(
                            'map_hawa_mahal_pin.png',
                            left: 116,
                            top: 323,
                            width: 107,
                            height: 113,
                            revealStart: .68,
                            phase: 4.2,
                          ),
                          Positioned(
                            top: 12 * sy,
                            left: 0,
                            right: 0,
                            child: Opacity(
                              opacity: titleReveal,
                              child: Transform.translate(
                                offset: Offset(0, (1 - titleReveal) * 7 * sy),
                                child: Text(
                                  'Jaipur',
                                  textAlign: TextAlign.center,
                                  style: OnboardingStyle.text(
                                    (34 * sx).clamp(28.0, 38.0),
                                    weight: FontWeight.w600,
                                    height: 41 / 34,
                                    letterSpacing: -.34,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 55 * sy,
                            left: 0,
                            right: 0,
                            child: Opacity(
                              opacity: titleReveal,
                              child: Text(
                                'Planned for better mode',
                                textAlign: TextAlign.center,
                                style: OnboardingStyle.text(
                                  (12 * sx).clamp(10.5, 13.5),
                                  height: 16 / 12,
                                  color: Colors.white.withValues(alpha: .78),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(radius),
                          gradient: const RadialGradient(
                            radius: .92,
                            colors: [
                              Color(0x00E3F6FD),
                              Color(0x00E3F6FD),
                              Color(0xA8E3F6FD),
                            ],
                            stops: [0, .72, 1],
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
      ),
    );
  }
}

class _AnimatedMapRoutePainter extends CustomPainter {
  const _AnimatedMapRoutePainter({required this.progress});

  final double progress;

  static final Path _route = Path()
    ..moveTo(37.0967, 29.1094)
    ..cubicTo(39.4301, 43.7761, 29.0967, 65.6094, 56.5967, 75.6094)
    ..cubicTo(84.0967, 85.6094, 93.5968, 60.6094, 126.097, 67.1094)
    ..cubicTo(158.597, 73.6094, 169.097, 91.6094, 158.097, 118.609)
    ..cubicTo(147.097, 145.609, 111.597, 141.610, 74.5968, 155.110)
    ..cubicTo(37.5968, 168.610, 3.59676, 194.109, 2.09676, 237.109)
    ..cubicTo(.596759, 280.109, 16.5968, 304.610, 45.5968, 305.610)
    ..cubicTo(74.5968, 306.610, 89.0967, 292.610, 126.097, 289.610)
    ..cubicTo(163.097, 286.610, 181.597, 333.110, 217.097, 336.110)
    ..cubicTo(252.597, 339.110, 289.597, 339.610, 302.097, 279.110)
    ..cubicTo(314.597, 218.610, 231.597, 219.110, 229.097, 185.609)
    ..cubicTo(226.597, 152.109, 273.097, 170.004, 273.097, 138.109)
    ..cubicTo(273.097, 123.109, 250.097, 122.844, 227.097, 111.844)
    ..cubicTo(204.097, 100.844, 192.597, 95.1095, 195.597, 54.6095)
    ..cubicTo(198.597, 14.1095, 259.597, -1.39056, 291.097, 2.60944);
  static final ui.PathMetric _routeMetric = _route.computeMetrics().first;
  static final Paint _routePaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || size.isEmpty) return;

    final visibleRoute = _routeMetric.extractPath(
      0,
      _routeMetric.length * progress.clamp(0.0, 1.0),
    );

    canvas
      ..save()
      ..scale(size.width / 305.378, size.height / 339.149)
      ..drawPath(visibleRoute, _routePaint)
      ..restore();
  }

  @override
  bool shouldRepaint(_AnimatedMapRoutePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
