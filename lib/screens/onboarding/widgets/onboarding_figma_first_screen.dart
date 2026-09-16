import 'package:flutter/material.dart';

/// The first onboarding screen faithfully reproducing Figma node 73:90
/// ("iPhone 17 - 1 / Typography Polish").
class OnboardingFigmaFirstScreen extends StatelessWidget {
  const OnboardingFigmaFirstScreen({
    required this.onContinue,
    this.currentPage = 0,
    this.pageCount = 5,
    super.key,
  });

  final VoidCallback onContinue;
  final int currentPage;
  final int pageCount;

  static const Color screenBackground = Color(0xFFF0EDDE);
  static const Color ink = Color(0xFF141B34);
  static const Color secondaryText = Color(0xFF555F7A);
  static const Color primaryBlue = Color(0xFF2F5ABB);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        // Proportional design scaling based on 402px Figma canvas width
        final scale = (screenWidth / 402.0).clamp(0.80, 1.25);
        final horizontalMargin = 24.0 * scale;

        // Card takes proportional vertical space (~58% of available viewport)
        // With reasonable min/max bounds so it looks great on any screen
        final availableCardHeight = (screenHeight * 0.58).clamp(320.0, 560.0);
        final cardWidth = screenWidth - (horizontalMargin * 2);

        return ColoredBox(
          color: screenBackground,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
              child: Column(
                children: [
                  SizedBox(height: 8 * scale),

                  // 1. Large rounded visual/map card
                  SizedBox(
                    width: cardWidth,
                    height: availableCardHeight,
                    child: FigmaJaipurMapCard(
                      width: cardWidth,
                      height: availableCardHeight,
                    ),
                  ),

                  const Spacer(flex: 2),

                  // 2. Pagination indicator directly beneath the visual card
                  FigmaOnboardingPagination(
                    currentPage: currentPage,
                    pageCount: pageCount,
                  ),

                  const Spacer(flex: 3),

                  // 3. Main headline (2 lines, centered)
                  Text(
                    'Beautiful Places\nOne Seamless Experience',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'HomeInter',
                      fontSize: (23.0 * scale).clamp(20.0, 27.0),
                      fontWeight: FontWeight.w700,
                      height: 1.22,
                      letterSpacing: -0.4,
                      color: ink,
                    ),
                  ),

                  SizedBox(height: 10 * scale),

                  // 4. Supporting description (2 lines, centered)
                  Text(
                    'Discover places you love and bring them\ntogether in a trip that feels like you',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'HomeInter',
                      fontSize: (13.5 * scale).clamp(12.0, 15.0),
                      fontWeight: FontWeight.w400,
                      height: 1.45,
                      letterSpacing: -0.1,
                      color: secondaryText,
                    ),
                  ),

                  const Spacer(flex: 4),

                  // 5. Large blue rounded Continue CTA button
                  SizedBox(
                    width: double.infinity,
                    height: (50.0 * scale).clamp(48.0, 56.0),
                    child: ElevatedButton(
                      onPressed: onContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28 * scale),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Continue',
                            style: TextStyle(
                              fontFamily: 'HomeInter',
                              fontSize: (16.0 * scale).clamp(15.0, 18.0),
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8 * scale),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: (19.0 * scale).clamp(17.0, 22.0),
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 16 * scale),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The upper rounded illustration card featuring the cyan gradient atmosphere,
/// diffused top glow, title, 3 speech-bubble pins, and continuous journey route.
class FigmaJaipurMapCard extends StatelessWidget {
  const FigmaJaipurMapCard({
    required this.width,
    required this.height,
    super.key,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Relative coordinates derived from Figma 354x548 card measurements:
    // Pin 1: Albert Hall (top-left)
    final p1Left = width * 0.14;
    final p1Top = height * 0.15;
    final p1W = width * 0.38;
    final p1H = height * 0.20;

    // Pin 2: Jal Mahal (mid-right)
    final p2Left = width * 0.52;
    final p2Top = height * 0.26;
    final p2W = width * 0.34;
    final p2H = height * 0.21;

    // Pin 3: Hawa Mahal (bottom-center)
    final p3Left = width * 0.28;
    final p3Top = height * 0.54;
    final p3W = width * 0.35;
    final p3H = height * 0.23;

    return ClipRRect(
      borderRadius: BorderRadius.circular(38),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // A. Sky-blue / cyan gradient background
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF76C8EE),
                  Color(0xFF55B5E6),
                  Color(0xFF67BFEA),
                ],
              ),
            ),
          ),

          // B. Diffused soft top glow bloom behind title
          Positioned(
            top: -height * 0.15,
            left: 0,
            right: 0,
            height: height * 0.55,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.3),
                  radius: 0.85,
                  colors: [
                    Colors.white.withValues(alpha: 0.52),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          // C. Custom route line and waypoint nodes
          CustomPaint(
            size: Size(width, height),
            painter: const FigmaRoutePainter(),
          ),

          // D. Jaipur title and subtitle
          Positioned(
            top: height * 0.065,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Jaipur',
                  style: TextStyle(
                    fontFamily: 'HomeInter',
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Planned for better mode',
                  style: TextStyle(
                    fontFamily: 'HomeInter',
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),

          // E. Speech bubble destination pin 1 (Albert Hall / Palace)
          Positioned(
            left: p1Left,
            top: p1Top,
            width: p1W,
            height: p1H,
            child: const FigmaSpeechBubblePin(
              imageAsset: 'lib/assets/onboarding/jaipur_albert_hall.png',
            ),
          ),

          // F. Speech bubble destination pin 2 (Jal Mahal)
          Positioned(
            left: p2Left,
            top: p2Top,
            width: p2W,
            height: p2H,
            child: const FigmaSpeechBubblePin(
              imageAsset: 'lib/assets/onboarding/jaipur_jal_mahal.png',
            ),
          ),

          // G. Speech bubble destination pin 3 (Hawa Mahal)
          Positioned(
            left: p3Left,
            top: p3Top,
            width: p3W,
            height: p3H,
            child: const FigmaSpeechBubblePin(
              imageAsset: 'lib/assets/onboarding/jaipur_hawa_mahal.png',
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter rendering the continuous flowing white travel route line
/// and luminous waypoint nodes matching the Figma composition.
class FigmaRoutePainter extends CustomPainter {
  const FigmaRoutePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Measured waypoint nodes from Figma 354x548 reference:
    // Node 1: Left edge
    final n1 = Offset(w * 0.04, h * 0.50);
    // Node 2: Top left
    final n2 = Offset(w * 0.17, h * 0.28);
    // Node 3: Below Pin 1 beak
    final n3 = Offset(w * 0.33, h * 0.35);
    // Node 4: Top right
    final n4 = Offset(w * 0.88, h * 0.24);
    // Node 5: Below Pin 2 beak
    final n5 = Offset(w * 0.69, h * 0.47);
    // Node 6: Below Pin 3 beak
    final n6 = Offset(w * 0.45, h * 0.77);
    // Node 7: Bottom right
    final n7 = Offset(w * 0.88, h * 0.70);

    // Continuous flowing journey loop path
    final routePath = Path()
      ..moveTo(n1.dx, n1.dy)
      // Curve up to Node 2
      ..cubicTo(w * 0.05, h * 0.36, w * 0.11, h * 0.28, n2.dx, n2.dy)
      // Curve down-right to Pin 1 waypoint (Node 3)
      ..cubicTo(w * 0.22, h * 0.28, w * 0.26, h * 0.35, n3.dx, n3.dy)
      // Arc up and right to Node 4
      ..cubicTo(w * 0.42, h * 0.35, w * 0.62, h * 0.18, n4.dx, n4.dy)
      // Curve down-left to Pin 2 waypoint (Node 5)
      ..cubicTo(w * 0.90, h * 0.32, w * 0.80, h * 0.42, n5.dx, n5.dy)
      // S-curve down and across to Pin 3 waypoint (Node 6)
      ..cubicTo(w * 0.60, h * 0.52, w * 0.55, h * 0.66, n6.dx, n6.dy)
      // Curve right to Node 7
      ..cubicTo(w * 0.55, h * 0.82, w * 0.78, h * 0.82, n7.dx, n7.dy)
      // Loop around bottom-left back up towards Node 1
      ..cubicTo(w * 0.92, h * 0.62, w * 0.76, h * 0.92, w * 0.42, h * 0.90)
      ..cubicTo(w * 0.16, h * 0.88, w * 0.02, h * 0.70, n1.dx, n1.dy);

    // 1. Soft outer diffuse glow
    final glowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(routePath, glowPaint);

    // 2. Mid halo
    final haloPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(routePath, haloPaint);

    // 3. Crisp luminous white core line
    final corePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(routePath, corePaint);

    // Draw luminous waypoint nodes
    final nodes = [n1, n2, n3, n4, n5, n6, n7];
    for (final node in nodes) {
      // Outer soft glowing ring
      canvas.drawCircle(
        node,
        10.5,
        Paint()..color = Colors.white.withValues(alpha: 0.38),
      );
      // Mid halo
      canvas.drawCircle(
        node,
        7.0,
        Paint()..color = Colors.white.withValues(alpha: 0.70),
      );
      // Solid white core
      canvas.drawCircle(
        node,
        5.0,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A speech bubble destination pin matching the Figma design:
/// white rounded border with a bottom-center anchor beak pointing to a waypoint.
class FigmaSpeechBubblePin extends StatelessWidget {
  const FigmaSpeechBubblePin({
    required this.imageAsset,
    super.key,
  });

  final String imageAsset;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _SpeechBubbleBorderPainter(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(3.5, 3.5, 3.5, 11.5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            imageAsset,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const ColoredBox(
              color: Color(0xFFE2E8F0),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for the speech bubble border and anchor beak.
class _SpeechBubbleBorderPainter extends CustomPainter {
  const _SpeechBubbleBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const beakHeight = 8.0;
    const beakHalfWidth = 7.0;
    final bodyHeight = h - beakHeight;
    const radius = 15.0;

    final path = Path()
      // Top left
      ..moveTo(radius, 0)
      ..lineTo(w - radius, 0)
      ..arcToPoint(Offset(w, radius), radius: const Radius.circular(radius))
      // Right side
      ..lineTo(w, bodyHeight - radius)
      ..arcToPoint(Offset(w - radius, bodyHeight), radius: const Radius.circular(radius))
      // Bottom side to beak
      ..lineTo(w / 2 + beakHalfWidth, bodyHeight)
      ..lineTo(w / 2, h)
      ..lineTo(w / 2 - beakHalfWidth, bodyHeight)
      ..lineTo(radius, bodyHeight)
      // Left side
      ..arcToPoint(Offset(0, bodyHeight - radius), radius: const Radius.circular(radius))
      ..lineTo(0, radius)
      ..arcToPoint(const Offset(radius, 0), radius: const Radius.circular(radius))
      ..close();

    // Subtle soft drop shadow for card depth
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.15), 3.0, false);

    // Fill white background for the border
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Reusable 5-dot pagination indicator matching Figma node 73:90.
/// Capsule background with active elongated pill and inactive circle dots.
class FigmaOnboardingPagination extends StatelessWidget {
  const FigmaOnboardingPagination({
    this.currentPage = 0,
    this.pageCount = 5,
    super.key,
  });

  final int currentPage;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E0D4).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(pageCount, (index) {
          final isActive = index == currentPage;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: isActive ? 20.0 : 6.5,
            height: 6.5,
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF2F5ABB)
                  : const Color(0xFF90B4ED),
              borderRadius: BorderRadius.circular(3.5),
            ),
          );
        }),
      ),
    );
  }
}
