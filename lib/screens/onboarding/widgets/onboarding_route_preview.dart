import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'onboarding_styles.dart';

class _JaipurStop {
  const _JaipurStop({
    required this.name,
    required this.imageAsset,
    required this.cardLeft, // normalized [0, 1]
    required this.cardTop, // normalized [0, 1]
    required this.cardWidth, // normalized [0, 1]
    required this.cardHeightRatio, // height / width
    required this.waypoint, // normalized [0, 1]
    required this.badgeLeft, // normalized [0, 1]
    required this.badgeTop, // normalized [0, 1]
    required this.number,
    this.beakXRatio = 0.5,
  });

  final String name;
  final String imageAsset;
  final double cardLeft;
  final double cardTop;
  final double cardWidth;
  final double cardHeightRatio;
  final Offset waypoint;
  final double badgeLeft;
  final double badgeTop;
  final int number;
  final double beakXRatio;
}

// Stops repositioned for spacious, airy composition (more breathing room between elements)
const _stops = <_JaipurStop>[
  _JaipurStop(
    name: 'Amber Fort',
    imageAsset: 'lib/assets/home/amber_fort.png',
    cardLeft: 0.04,          // More left breathing room
    cardTop: 0.16,           // Higher up = more vertical space
    cardWidth: 0.22,         // Slightly smaller for lightness
    cardHeightRatio: 0.88,
    waypoint: Offset(0.16, 0.36),
    badgeLeft: 0.05,
    badgeTop: 0.28,
    number: 1,
    beakXRatio: 0.46,
  ),
  _JaipurStop(
    name: 'City Palace',
    imageAsset: 'lib/assets/home/city_palace.png',
    cardLeft: 0.70,          // Further right for spread
    cardTop: 0.18,           // Also higher
    cardWidth: 0.23,
    cardHeightRatio: 0.88,
    waypoint: Offset(0.80, 0.38),
    badgeLeft: 0.72,
    badgeTop: 0.30,
    number: 2,
    beakXRatio: 0.44,
  ),
  _JaipurStop(
    name: 'Hawa Mahal',
    imageAsset: 'lib/assets/home/hawa_mahal.png',
    cardLeft: 0.34,
    cardTop: 0.46,           // Lower center for triangular spread
    cardWidth: 0.32,
    cardHeightRatio: 0.86,
    waypoint: Offset(0.50, 0.68),
    badgeLeft: 0.50,
    badgeTop: 0.73,
    number: 3,
    beakXRatio: 0.50,
  ),
];

/// Redesigned illustrative route preview matching the approved Image 1 visual target.
/// Features in-card "Explore Jaipur" header, stylized aqua Jaipur map canvas,
/// speech-bubble photo-pins, dark teal circular numbered waypoints (1, 2, 3),
/// attached capsule labels, and smooth flowing white route.
class OnboardingRoutePreview extends StatefulWidget {
  const OnboardingRoutePreview({super.key});

  @override
  State<OnboardingRoutePreview> createState() => _OnboardingRoutePreviewState();
}

class _OnboardingRoutePreviewState extends State<OnboardingRoutePreview>
    with TickerProviderStateMixin {
  int _selectedIndex = 2; // Default selected stop: Hawa Mahal (center hero)

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
      precacheImage(const AssetImage('lib/assets/home/amber_fort.png'), context);
      precacheImage(const AssetImage('lib/assets/home/city_palace.png'), context);
      precacheImage(const AssetImage('lib/assets/home/hawa_mahal.png'), context);
      precacheImage(const AssetImage('lib/assets/home/jaipur_aqua_map.png'), context);
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
          'Explore Jaipur journey map: stop 1, Amber Fort; stop 2, City Palace; '
          'stop 3, Hawa Mahal. A flowing white route connects all destinations.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
          final scale = (width / 360).clamp(0.85, 1.25);
          final height = (width * 1.22 + (textScale - 1) * 40).clamp(340.0, 580.0);

          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x18055EC8),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Layer 1: Soft sky-blue gradient base (light, airy, premium)
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFDDF4FC), // near-white sky top
                          Color(0xFFAEE5F7), // soft sky blue mid
                          Color(0xFF7DD4F0), // gentle cyan lower
                          Color(0xFF5DC8EA), // subtle teal bottom
                        ],
                        stops: [0.0, 0.35, 0.70, 1.0],
                      ),
                    ),
                  ),

                  // Layer 2: Frosted map texture — very subtle, dreamy, atmospheric
                  Opacity(
                    opacity: 0.14, // reduced from 0.44: map is a whisper, not a detail
                    child: Image.asset(
                      'lib/assets/home/jaipur_aqua_map.png',
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    ),
                  ),

                  // Layer 2b: Frosted glass veil over map for dreamy blur effect
                  ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(color: Colors.white.withValues(alpha: 0.18)),
                    ),
                  ),

                  // Layer 3: Ambient Glow & Flowing Route
                  AnimatedBuilder(
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
                        painter: _RouteAndGlowPainter(
                          routeProgress: routeProgress,
                          ambientShift: ambientShift,
                        ),
                      );
                    },
                  ),

                  // Layer 4: In-Card Header ("Explore Jaipur" + "Places connect stories")
                  Positioned(
                    top: 15 * scale,
                    left: 0,
                    right: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Explore ',
                                style: TextStyle(
                                  fontFamily: 'HomeInter',
                                  fontSize: 25 * scale,
                                  fontWeight: FontWeight.w800,
                                  color: OnboardingStyle.inkNavy,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              TextSpan(
                                text: 'Jaipur',
                                style: TextStyle(
                                  fontFamily: 'HomeInter',
                                  fontSize: 25 * scale,
                                  fontWeight: FontWeight.w800,
                                  color: OnboardingStyle.oceanBlue,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 2 * scale),
                        Text(
                          'Places connect stories',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'HomeInter',
                            fontSize: 12.5 * scale,
                            fontWeight: FontWeight.w500,
                            color: OnboardingStyle.mutedSlate.withValues(alpha: 0.9),
                            letterSpacing: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Layer 5: Photo Pins, Waypoints & Badges
                  AnimatedBuilder(
                    animation: _routeProgressAnimation,
                    builder: (context, _) {
                      final routeProgress = reducedMotion
                          ? 1.0
                          : _routeProgressAnimation.value;

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Pin 1 (Amber Fort, top-left)
                          _buildPhotoPin(
                            index: 0,
                            width: width,
                            height: height,
                            scale: scale,
                            routeProgress: routeProgress,
                            reducedMotion: reducedMotion,
                          ),

                          // Pin 2 (City Palace, middle-right)
                          _buildPhotoPin(
                            index: 1,
                            width: width,
                            height: height,
                            scale: scale,
                            routeProgress: routeProgress,
                            reducedMotion: reducedMotion,
                          ),

                          // Pin 3 (Hawa Mahal, bottom-center)
                          _buildPhotoPin(
                            index: 2,
                            width: width,
                            height: height,
                            scale: scale,
                            routeProgress: routeProgress,
                            reducedMotion: reducedMotion,
                          ),

                          // Waypoint Badges 1, 2, 3
                          for (var i = 0; i < _stops.length; i++)
                            _buildWaypointBadge(
                              index: i,
                              width: width,
                              height: height,
                              scale: scale,
                              routeProgress: routeProgress,
                              reducedMotion: reducedMotion,
                            ),

                          // Destination Pills for 1, 2, 3
                          for (var i = 0; i < _stops.length; i++)
                            _buildPillLabel(
                              index: i,
                              width: width,
                              height: height,
                              scale: scale,
                              routeProgress: routeProgress,
                              reducedMotion: reducedMotion,
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPhotoPin({
    required int index,
    required double width,
    required double height,
    required double scale,
    required double routeProgress,
    required bool reducedMotion,
  }) {
    final stop = _stops[index];
    final isSelected = _selectedIndex == index;
    final cardW = width * stop.cardWidth;
    final beakHeight = 8.0 * scale;
    final cardH = cardW * stop.cardHeightRatio + beakHeight;

    // Sequential pin reveal
    final revealThreshold = [0.0, 0.35, 0.70][index];
    final pinVisible = reducedMotion || routeProgress >= revealThreshold;
    final pinOpacity = reducedMotion
        ? 1.0
        : ((routeProgress - revealThreshold) / 0.20).clamp(0.0, 1.0);

    return Positioned(
      left: width * stop.cardLeft,
      top: height * stop.cardTop,
      width: cardW,
      height: cardH,
      child: AnimatedOpacity(
        duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 260),
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
              duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: CustomPaint(
                painter: _SpeechBubbleShadowAndBorderPainter(
                  beakHeight: beakHeight,
                  beakWidth: 15.0 * scale,
                  beakXRatio: stop.beakXRatio,
                  radius: 19.0 * scale,
                  isSelected: isSelected,
                ),
                child: ClipPath(
                  clipper: _SpeechBubbleClipper(
                    beakHeight: beakHeight,
                    beakWidth: 15.0 * scale,
                    beakXRatio: stop.beakXRatio,
                    radius: 19.0 * scale,
                  ),
                  child: Image.asset(
                    stop.imageAsset,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaypointBadge({
    required int index,
    required double width,
    required double height,
    required double scale,
    required double routeProgress,
    required bool reducedMotion,
  }) {
    final stop = _stops[index];
    final isSelected = _selectedIndex == index;
    final size = (isSelected ? 26.0 : 24.0) * scale;

    final revealThreshold = [0.05, 0.40, 0.75][index];
    final visible = reducedMotion || routeProgress >= revealThreshold;
    final opacity = reducedMotion
        ? 1.0
        : ((routeProgress - revealThreshold) / 0.15).clamp(0.0, 1.0);

    return Positioned(
      left: width * stop.waypoint.dx - size / 2,
      top: height * stop.waypoint.dy - size / 2,
      width: size,
      height: size,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 220),
          opacity: visible ? opacity : 0.0,
          child: AnimatedScale(
            scale: isSelected ? 1.08 : 1.0,
            duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Softer dark-teal with slight transparency for frosted feel
                color: OnboardingStyle.darkTealMarker.withValues(alpha: 0.88),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.90),
                  width: 2.0 * scale,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.60),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                  const BoxShadow(
                    color: Color(0x20000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '${stop.number}',
                  style: TextStyle(
                    fontFamily: 'HomeInter',
                    color: Colors.white,
                    fontSize: 12.5 * scale,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPillLabel({
    required int index,
    required double width,
    required double height,
    required double scale,
    required double routeProgress,
    required bool reducedMotion,
  }) {
    final stop = _stops[index];
    final isSelected = _selectedIndex == index;

    final revealThreshold = [0.10, 0.45, 0.80][index];
    final visible = reducedMotion || routeProgress >= revealThreshold;
    final opacity = reducedMotion
        ? 1.0
        : ((routeProgress - revealThreshold) / 0.15).clamp(0.0, 1.0);

    // Placement geometry guaranteed within card boundaries
    final bool isCentered = (index == 2);
    final double? left;
    final double? right;
    final Alignment alignment;

    if (isCentered) {
      // Hawa Mahal is centered horizontally below its marker
      left = 0;
      right = 0;
      alignment = Alignment.topCenter;
    } else if (index == 1) {
      // City Palace sits on the right side of the card
      left = null;
      right = 10.0 * scale;
      alignment = Alignment.topRight;
    } else {
      // Amber Fort sits on the left side of the card
      left = (width * stop.badgeLeft).clamp(8.0, width - 110.0 * scale);
      right = null;
      alignment = Alignment.topLeft;
    }

    final double top = (height * stop.badgeTop).clamp(8.0, height - 38.0 * scale);

    return Positioned(
      left: left,
      right: right,
      top: top,
      child: Align(
        alignment: alignment,
        child: AnimatedOpacity(
          duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 250),
          opacity: visible ? opacity : 0.0,
          child: GestureDetector(
            onTap: () => _onSelectStop(index),
            behavior: HitTestBehavior.opaque,
            // Frosted-glass pill label matching reference image
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20 * scale),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: (isCentered ? 16 : 12) * scale,
                    vertical: (isCentered ? 6 : 5) * scale,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: isSelected ? 0.88 : 0.72),
                    borderRadius: BorderRadius.circular(20 * scale),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.70),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isSelected
                            ? const Color(0x1A000000)
                            : const Color(0x0F000000),
                        blurRadius: isSelected ? 12 : 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    stop.name,
                    style: TextStyle(
                      fontFamily: 'HomeInter',
                      color: OnboardingStyle.inkNavy.withValues(
                        alpha: isSelected ? 0.92 : 0.80,
                      ),
                      fontWeight: FontWeight.w600,
                      fontSize: (isCentered ? 12.0 : 11.0) * scale,
                      letterSpacing: 0.1,
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

/// Custom Clipper for continuous rounded rectangle with a downward-pointing triangular beak.
class _SpeechBubbleClipper extends CustomClipper<Path> {
  const _SpeechBubbleClipper({
    required this.beakHeight,
    required this.beakWidth,
    required this.beakXRatio,
    required this.radius,
  });

  final double beakHeight;
  final double beakWidth;
  final double beakXRatio;
  final double radius;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height - beakHeight;
    final beakCenter = w * beakXRatio;
    final beakLeft = beakCenter - beakWidth / 2;
    final beakRight = beakCenter + beakWidth / 2;

    final path = Path()
      ..moveTo(radius, 0)
      ..lineTo(w - radius, 0)
      ..arcToPoint(Offset(w, radius), radius: Radius.circular(radius))
      ..lineTo(w, h - radius)
      ..arcToPoint(Offset(w - radius, h), radius: Radius.circular(radius))
      ..lineTo(beakRight, h)
      ..lineTo(beakCenter, size.height)
      ..lineTo(beakLeft, h)
      ..lineTo(radius, h)
      ..arcToPoint(Offset(0, h - radius), radius: Radius.circular(radius))
      ..lineTo(0, radius)
      ..arcToPoint(Offset(radius, 0), radius: Radius.circular(radius))
      ..close();

    return path;
  }

  @override
  bool shouldReclip(_SpeechBubbleClipper oldClipper) =>
      oldClipper.beakHeight != beakHeight ||
      oldClipper.beakWidth != beakWidth ||
      oldClipper.beakXRatio != beakXRatio ||
      oldClipper.radius != radius;
}

/// Custom Painter that renders the drop shadow and the crisp white frame around the speech bubble.
class _SpeechBubbleShadowAndBorderPainter extends CustomPainter {
  const _SpeechBubbleShadowAndBorderPainter({
    required this.beakHeight,
    required this.beakWidth,
    required this.beakXRatio,
    required this.radius,
    required this.isSelected,
  });

  final double beakHeight;
  final double beakWidth;
  final double beakXRatio;
  final double radius;
  final bool isSelected;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height - beakHeight;
    final beakCenter = w * beakXRatio;
    final beakLeft = beakCenter - beakWidth / 2;
    final beakRight = beakCenter + beakWidth / 2;

    final path = Path()
      ..moveTo(radius, 0)
      ..lineTo(w - radius, 0)
      ..arcToPoint(Offset(w, radius), radius: Radius.circular(radius))
      ..lineTo(w, h - radius)
      ..arcToPoint(Offset(w - radius, h), radius: Radius.circular(radius))
      ..lineTo(beakRight, h)
      ..lineTo(beakCenter, size.height)
      ..lineTo(beakLeft, h)
      ..lineTo(radius, h)
      ..arcToPoint(Offset(0, h - radius), radius: Radius.circular(radius))
      ..lineTo(0, radius)
      ..arcToPoint(Offset(radius, 0), radius: Radius.circular(radius))
      ..close();

    // 1. Drop shadow
    canvas.drawShadow(
      path,
      Colors.black.withValues(alpha: isSelected ? 0.45 : 0.30),
      isSelected ? 10.0 : 6.0,
      true,
    );

    // 2. Crisp white frame border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 3.5 : 3.0
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(_SpeechBubbleShadowAndBorderPainter oldDelegate) =>
      oldDelegate.isSelected != isSelected;
}

/// Custom painter for the organic diffuse ambient highlights and luminous white route.
class _RouteAndGlowPainter extends CustomPainter {
  const _RouteAndGlowPainter({
    required this.routeProgress,
    required this.ambientShift,
  });

  final double routeProgress;
  final double ambientShift;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Top-center bloom: dreamy white radial glow like the reference
    final bloomCenter = Offset(
      w * (0.50 + 0.02 * ambientShift),
      h * (0.10 - 0.01 * ambientShift),
    );
    final bloomPaint = Paint()
      ..shader = ui.Gradient.radial(
        bloomCenter,
        w * 0.85,
        [
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.20),
          Colors.white.withValues(alpha: 0.0),
        ],
        [0.0, 0.45, 1.0],
      );
    canvas.drawRect(Offset.zero & size, bloomPaint);

    // 2. Soft secondary glow lower-right for depth
    final h2Center = Offset(
      w * (0.82 - 0.02 * ambientShift),
      h * (0.70 - 0.015 * ambientShift),
    );
    final h2Paint = Paint()
      ..shader = ui.Gradient.radial(
        h2Center,
        w * 0.55,
        [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.0),
        ],
        [0.0, 1.0],
      );
    canvas.drawRect(Offset.zero & size, h2Paint);

    // 3. Elegant flowing route — thin, translucent, premium
    // Route follows the new spacious stop positions
    final pStart = Offset(w * 0.02, h * 0.36);
    final p1 = Offset(w * 0.16, h * 0.36); // Amber Fort waypoint
    final p2 = Offset(w * 0.80, h * 0.38); // City Palace waypoint
    final pDescend = Offset(w * 0.88, h * 0.52); // Flows down off right
    final pHawa = Offset(w * 0.50, h * 0.68);  // Hawa Mahal waypoint
    final pTail = Offset(w * 0.20, h * 0.78); // Trails off lower-left

    final fullRoute = Path()
      ..moveTo(pStart.dx, pStart.dy)
      // soft entry into stop 1
      ..quadraticBezierTo(w * 0.09, h * 0.36, p1.dx, p1.dy)
      // graceful arc through open sky to stop 2
      ..cubicTo(w * 0.30, h * 0.30, w * 0.58, h * 0.28, p2.dx, p2.dy)
      // flowing descent toward hawa mahal
      ..cubicTo(pDescend.dx, pDescend.dy, w * 0.72, h * 0.60, pHawa.dx, pHawa.dy)
      // soft tail trailing lower-left
      ..cubicTo(w * 0.38, h * 0.78, w * 0.28, h * 0.80, pTail.dx, pTail.dy);

    if (routeProgress <= 0.001) return;

    // Truncate path for progressive reveal animation
    final animatedPath = Path();
    for (final metric in fullRoute.computeMetrics()) {
      final targetLength = metric.length * routeProgress.clamp(0.0, 1.0);
      animatedPath.addPath(metric.extractPath(0, targetLength), Offset.zero);
    }

    // Wide diffuse outer bloom around route
    final outerBloom = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(animatedPath, outerBloom);

    // Mid glow halo
    final glowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(animatedPath, glowPaint);

    // Core elegant thin route line
    final routePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(animatedPath, routePaint);
  }

  @override
  bool shouldRepaint(_RouteAndGlowPainter oldDelegate) =>
      oldDelegate.routeProgress != routeProgress ||
      oldDelegate.ambientShift != ambientShift;
}
