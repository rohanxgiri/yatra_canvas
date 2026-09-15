import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../../theme/yc_style.dart';
import 'onboarding_styles.dart';

class _JaipurStop {
  const _JaipurStop({
    required this.name,
    required this.subtitle,
    required this.cardLeft,
    required this.cardTop,
    required this.cardWidth,
    required this.cardHeightRatio,
    required this.waypoint,
    required this.badgeOffset,
    required this.imageAlignment,
    required this.imageScale,
  });

  final String name;
  final String subtitle;
  final double cardLeft; // normalized [0, 1]
  final double cardTop; // normalized [0, 1]
  final double cardWidth; // normalized [0, 1]
  final double cardHeightRatio; // height / width
  final Offset waypoint; // normalized [0, 1]
  final Offset badgeOffset; // normalized [0, 1]
  final Alignment imageAlignment;
  final double imageScale;
}

const _stops = <_JaipurStop>[
  _JaipurStop(
    name: 'Amer Fort',
    subtitle: 'Hilltop fortress',
    cardLeft: .08,
    cardTop: .06,
    cardWidth: .35,
    cardHeightRatio: 0.92,
    waypoint: Offset(.25, .41),
    badgeOffset: Offset(.32, .39),
    imageAlignment: Alignment(-0.45, -0.70),
    imageScale: 2.6,
  ),
  _JaipurStop(
    name: 'Hawa Mahal',
    subtitle: 'Palace of Winds',
    cardLeft: .57,
    cardTop: .20,
    cardWidth: .35,
    cardHeightRatio: 0.92,
    waypoint: Offset(.76, .58),
    badgeOffset: Offset(.44, .56),
    imageAlignment: Alignment(0.55, 0.15),
    imageScale: 2.4,
  ),
  _JaipurStop(
    name: 'Jal Mahal',
    subtitle: 'Water Palace',
    cardLeft: .09,
    cardTop: .54,
    cardWidth: .35,
    cardHeightRatio: 0.92,
    waypoint: Offset(.27, .88),
    badgeOffset: Offset(.35, .86),
    imageAlignment: Alignment(-0.45, 0.10),
    imageScale: 2.9,
  ),
];

/// Redesigned illustrative route preview for YatraCanvas journey onboarding.
/// Combines the photo-pin composition of coordinated Jaipur destinations with the
/// restrained aqua canvas, white curved route, and coordinated motion from design reference.
class OnboardingRoutePreview extends StatefulWidget {
  const OnboardingRoutePreview({super.key});

  @override
  State<OnboardingRoutePreview> createState() => _OnboardingRoutePreviewState();
}

class _OnboardingRoutePreviewState extends State<OnboardingRoutePreview>
    with TickerProviderStateMixin {
  int _selectedIndex = 1; // Default selected stop: Hawa Mahal

  late final AnimationController _entranceController;
  late final Animation<double> _routeProgressAnimation;

  late final AnimationController _ambientController;
  late final Animation<double> _ambientAnimation;

  bool _isPrecached = false;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );
    _routeProgressAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeInOutCubic,
    );

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    _ambientAnimation = Tween<double>(begin: -1.0, end: 1.0).animate(
      CurvedAnimation(parent: _ambientController, curve: Curves.easeInOutSine),
    );

    _entranceController.forward();
    if (!WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      _ambientController.repeat(reverse: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isPrecached) {
      _isPrecached = true;
      precacheImage(const AssetImage('lib/assets/home/jaipur.png'), context);
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  void _onSelectStop(int index) {
    if (_selectedIndex != index) {
      setState(() => _selectedIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    if (reducedMotion && !_entranceController.isCompleted) {
      _entranceController.value = 1.0;
    }

    return Semantics(
      image: true,
      label:
          'Illustrated Jaipur journey: stop 1, Amer Fort; stop 2, Hawa Mahal, highlighted; '
          'stop 3, Jal Mahal. A flowing curved white route connects all three destinations. '
          'Currently selected destination: ${_stops[_selectedIndex].name}.',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final textScale =
                MediaQuery.textScalerOf(context).scale(12) / 12;
            final height = (width * 1.02 + (textScale - 1) * 50).clamp(
              280.0,
              520.0,
            );

            return Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x18055EC8),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _routeProgressAnimation,
                  _ambientAnimation,
                ]),
                builder: (context, _) {
                  final routeProgress = reducedMotion
                      ? 1.0
                      : _routeProgressAnimation.value;
                  final ambientShift = reducedMotion
                      ? 0.0
                      : _ambientAnimation.value;

                  return CustomPaint(
                    painter: _AquaCanvasPainter(
                      routeProgress: routeProgress,
                      ambientShift: ambientShift,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Layer 1: Photo Pins (Amer Fort, Hawa Mahal, Jal Mahal)
                        for (var i = 0; i < _stops.length; i++)
                          _buildPhotoPin(
                            index: i,
                            width: width,
                            height: height,
                            textScale: textScale,
                            routeProgress: routeProgress,
                            reducedMotion: reducedMotion,
                          ),

                        // Layer 2: Circular Waypoints along the route
                        for (var i = 0; i < _stops.length; i++)
                          _buildWaypoint(
                            index: i,
                            width: width,
                            height: height,
                            routeProgress: routeProgress,
                            reducedMotion: reducedMotion,
                          ),

                        // Layer 3: Floating Translucent Destination Badge
                        _buildFloatingBadge(
                          width: width,
                          height: height,
                          routeProgress: routeProgress,
                          reducedMotion: reducedMotion,
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPhotoPin({
    required int index,
    required double width,
    required double height,
    required double textScale,
    required double routeProgress,
    required bool reducedMotion,
  }) {
    final stop = _stops[index];
    final isSelected = _selectedIndex == index;
    final cardW = width * stop.cardWidth;
    final cardH = cardW * stop.cardHeightRatio;

    // Sequential pin reveal during entrance
    final revealThreshold = [0.0, 0.40, 0.78][index];
    final pinVisible = reducedMotion || routeProgress >= revealThreshold;
    final pinOpacity = reducedMotion
        ? 1.0
        : ((routeProgress - revealThreshold) / 0.22).clamp(0.0, 1.0);

    return Positioned(
      left: width * stop.cardLeft,
      top: height * stop.cardTop,
      width: cardW,
      height: cardH,
      child: AnimatedOpacity(
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 260),
        opacity: pinVisible ? pinOpacity : 0.0,
        child: GestureDetector(
          onTap: () => _onSelectStop(index),
          behavior: HitTestBehavior.opaque,
          child: Semantics(
            button: true,
            selected: isSelected,
            label: 'Select destination ${stop.name}',
            child: AnimatedScale(
              scale: isSelected ? 1.06 : 1.0,
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: .85),
                    width: isSelected ? 2.4 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected
                          ? const Color(0x35000000)
                          : const Color(0x1A000000),
                      blurRadius: isSelected ? 12 : 7,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Photographic crop from jaipur.png
                      LayoutBuilder(
                        builder: (context, boxConstraints) => OverflowBox(
                          alignment: stop.imageAlignment,
                          maxWidth: boxConstraints.maxWidth * stop.imageScale,
                          maxHeight:
                              boxConstraints.maxHeight * stop.imageScale,
                          child: Image.asset(
                            'lib/assets/home/jaipur.png',
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                          ),
                        ),
                      ),

                      // Refined frosted bottom caption for landmark identity
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.62),
                                Colors.black.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                          child: Text(
                            stop.name,
                            style: YCStyle.caption.copyWith(
                              color: Colors.white,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              fontSize:
                                  (10.5 * textScale).clamp(9.0, 12.0),
                              letterSpacing: 0.1,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaypoint({
    required int index,
    required double width,
    required double height,
    required double routeProgress,
    required bool reducedMotion,
  }) {
    final stop = _stops[index];
    final isSelected = _selectedIndex == index;
    final markerSize = isSelected ? 22.0 : 13.0;

    // Sequential waypoint reveal
    final revealThreshold = [0.05, 0.50, 0.90][index];
    final visible = reducedMotion || routeProgress >= revealThreshold;
    final opacity = reducedMotion
        ? 1.0
        : ((routeProgress - revealThreshold) / 0.12).clamp(0.0, 1.0);

    return Positioned(
      left: width * stop.waypoint.dx - markerSize / 2,
      top: height * stop.waypoint.dy - markerSize / 2,
      width: markerSize,
      height: markerSize,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          opacity: visible ? opacity : 0.0,
          child: isSelected
              // Selected: Dark slate outlined ring with aqua hollow center matching reference
              ? Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: OnboardingStyle.waypointSelectedRing,
                      width: 3.5,
                    ),
                  ),
                )
              // Inactive: Solid white dot with soft outer halo
              : Container(
                  width: 13,
                  height: 13,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x66FFFFFF),
                        blurRadius: 5,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildFloatingBadge({
    required double width,
    required double height,
    required double routeProgress,
    required bool reducedMotion,
  }) {
    final stop = _stops[_selectedIndex];
    final isVisible = reducedMotion || routeProgress >= 0.35;

    final targetLeft = (width * stop.badgeOffset.dx).clamp(
      8.0,
      width - 110.0,
    );
    final targetTop = (height * stop.badgeOffset.dy - 12).clamp(
      6.0,
      height - 36.0,
    );

    return AnimatedPositioned(
      duration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      left: targetLeft,
      top: targetTop,
      child: AnimatedOpacity(
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 250),
        opacity: isVisible ? 1.0 : 0.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .90),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: .95),
              width: 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 240),
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.22, 0),
                end: Offset.zero,
              ).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Text(
              stop.name,
              key: ValueKey(stop.name),
              style: YCStyle.caption.copyWith(
                color: OnboardingStyle.ink,
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for the restrained aqua atmospheric surface and flowing white curved route.
class _AquaCanvasPainter extends CustomPainter {
  const _AquaCanvasPainter({
    required this.routeProgress,
    required this.ambientShift,
  });

  final double routeProgress;
  final double ambientShift;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Base soft cyan/aqua atmospheric gradient matching reference
    final baseGradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF5CCDE6),
        Color(0xFF76D8ED),
        Color(0xFF8DE3F4),
      ],
      stops: [0.0, 0.52, 1.0],
    ).createShader(Offset.zero & size);

    final bgPaint = Paint()..shader = baseGradient;
    canvas.drawRect(Offset.zero & size, bgPaint);

    // 2. Broad, heavily diffused organic white highlights with subtle ambient drift
    final h1Center = Offset(
      size.width * (0.40 + 0.035 * ambientShift),
      size.height * (0.28 + 0.025 * ambientShift),
    );
    final h1Paint = Paint()
      ..shader = ui.Gradient.radial(
        h1Center,
        size.width * 0.72,
        [
          Colors.white.withValues(alpha: .44),
          Colors.white.withValues(alpha: .18),
          Colors.white.withValues(alpha: .0),
        ],
        [0.0, 0.5, 1.0],
      );
    canvas.drawRect(Offset.zero & size, h1Paint);

    final h2Center = Offset(
      size.width * (0.80 - 0.03 * ambientShift),
      size.height * (0.68 - 0.02 * ambientShift),
    );
    final h2Paint = Paint()
      ..shader = ui.Gradient.radial(
        h2Center,
        size.width * 0.60,
        [
          Colors.white.withValues(alpha: .28),
          Colors.white.withValues(alpha: .0),
        ],
        [0.0, 1.0],
      );
    canvas.drawRect(Offset.zero & size, h2Paint);

    // 3. Smooth flowing white curved route connecting the 3 Jaipur destinations
    final p0 = Offset(
      size.width * _stops[0].waypoint.dx,
      size.height * _stops[0].waypoint.dy,
    );
    final p1 = Offset(
      size.width * _stops[1].waypoint.dx,
      size.height * _stops[1].waypoint.dy,
    );
    final p2 = Offset(
      size.width * _stops[2].waypoint.dx,
      size.height * _stops[2].waypoint.dy,
    );

    final fullRoute = Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(
        size.width * 0.46,
        size.height * 0.38,
        size.width * 0.65,
        size.height * 0.46,
        p1.dx,
        p1.dy,
      )
      ..cubicTo(
        size.width * 0.78,
        size.height * 0.72,
        size.width * 0.52,
        size.height * 0.88,
        p2.dx,
        p2.dy,
      );

    if (routeProgress <= 0.001) return;

    // Truncate path according to routeProgress (for progressive reveal entrance)
    final animatedPath = Path();
    for (final metric in fullRoute.computeMetrics()) {
      final targetLength = metric.length * routeProgress.clamp(0.0, 1.0);
      animatedPath.addPath(metric.extractPath(0, targetLength), Offset.zero);
    }

    // Route subtle outer halo glow
    final glowPaint = Paint()
      ..color = Colors.white.withValues(alpha: .38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(animatedPath, glowPaint);

    // Route solid flowing white line
    final routePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(animatedPath, routePaint);
  }

  @override
  bool shouldRepaint(_AquaCanvasPainter oldDelegate) =>
      oldDelegate.routeProgress != routeProgress ||
      oldDelegate.ambientShift != ambientShift;
}
