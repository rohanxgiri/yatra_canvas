import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../screens/onboarding/widgets/onboarding_styles.dart';

// ─────────────────────────────────────────────────────────────────────────────
// YCGoogleButton
// ─────────────────────────────────────────────────────────────────────────────

/// Continue with Google button.
///
/// Renders a glass surface with the Google "G" icon drawn via [CustomPaint]
/// (no external SVG dependency) and the YatraCanvas typography.
///
/// [PARTIAL] UI only. Does not call any Google OAuth flow.
/// Wire up [onTap] to a real provider SDK when Supabase Auth is implemented.
class YCGoogleButton extends StatelessWidget {
  const YCGoogleButton({required this.onTap, this.height = 52, super.key});

  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return OnboardingAction(
      label: 'Continue with Google',
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(height / 2),
                border: Border.all(
                  color: const Color(0xFFD7E2EF),
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CustomPaint(painter: _GoogleGPainter()),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontFamily: 'HomeInter',
                      color: Color(0xFF1A1A2E),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.05,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the Google 'G' logo using the official four-colour arc geometry.
class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy);
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // ── Stroke colours ────────────────────────────────────────────────────
    const blue = Color(0xFF4285F4);
    const red = Color(0xFFEA4335);
    const yellow = Color(0xFFFBBC05);
    const green = Color(0xFF34A853);

    final sw = r * 0.38;
    final outerR = r - sw / 2;
    final outerRect = Rect.fromCircle(
      center: Offset(cx, cy),
      radius: outerR,
    );

    // Sweep helper (degrees → radians, 0° = 3 o'clock)
    double deg(double d) => d * math.pi / 180;

    void arc(Color c, double startDeg, double sweepDeg) {
      canvas.drawArc(
        outerRect,
        deg(startDeg),
        deg(sweepDeg),
        false,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.butt,
      );
    }

    // Blue: right side (~-15° to 90°)
    arc(blue, -15, 105);
    // Green: bottom (~90° to 195°)
    arc(green, 90, 105);
    // Yellow: left/bottom (~195° to 270°)
    arc(yellow, 195, 75);
    // Red: top (~270° to 345°)
    arc(red, 270, 75);

    // White horizontal bar (the horizontal part of the G)
    final barY = cy;
    final barLeft = cx + outerR * math.cos(deg(-15)) - sw * 0.1;
    final barRight = cx + r * 0.62;
    canvas.drawLine(
      Offset(barLeft, barY),
      Offset(barRight, barY),
      Paint()
        ..color = blue
        ..strokeWidth = sw * 0.88
        ..strokeCap = StrokeCap.round,
    );

    // Cover the gap at -15° with a blue cap
    canvas.drawArc(
      rect,
      deg(-15) - 0.01,
      0.01,
      false,
      Paint()
        ..color = blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw,
    );
  }

  @override
  bool shouldRepaint(_GoogleGPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// YCGhostButton
// ─────────────────────────────────────────────────────────────────────────────

/// Outlined, low-emphasis button for the "Continue as Guest" action.
/// Visually secondary to the primary blue or Google actions.
class YCGhostButton extends StatelessWidget {
  const YCGhostButton({
    required this.label,
    required this.onTap,
    this.height = 52,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final double height;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OnboardingAction(
      label: label,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(
            color: const Color(0xFFB8CCE8),
            width: 1.2,
          ),
          color: Colors.white.withValues(alpha: 0.35),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: OnboardingStyle.mutedSlate, size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'HomeInter',
                color: OnboardingStyle.mutedSlate,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// YCAuthDivider
// ─────────────────────────────────────────────────────────────────────────────

/// A horizontal "OR" divider matching the auth screen palette.
class YCAuthDivider extends StatelessWidget {
  const YCAuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFCDD8E8);
    return Row(
      children: [
        const Expanded(child: Divider(color: color, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'OR',
            style: TextStyle(
              fontFamily: 'HomeInter',
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const Expanded(child: Divider(color: color, thickness: 1)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// YCAuthField
// ─────────────────────────────────────────────────────────────────────────────

/// Rounded input field styled to match the YatraCanvas auth screens.
class YCAuthField extends StatelessWidget {
  const YCAuthField({
    required this.label,
    this.controller,
    this.obscureText = false,
    this.textInputAction = TextInputAction.next,
    this.keyboardType,
    this.suffixIcon,
    this.autofillHints,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputAction textInputAction;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      style: const TextStyle(
        fontFamily: 'HomeInter',
        fontSize: 16,
        color: Color(0xFF141B34),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontFamily: 'HomeInter',
          color: Color(0xFF7A8FA6),
          fontSize: 14,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.80),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD7E2EF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD7E2EF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: OnboardingStyle.bluePrimary,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// YCAuthTextLink
// ─────────────────────────────────────────────────────────────────────────────

/// An inline text link styled for auth screens. Renders a normal `TextSpan`
/// prefix + a tappable `WidgetSpan` with underline.
class YCAuthTextLink extends StatelessWidget {
  const YCAuthTextLink({
    required this.prefix,
    required this.linkText,
    required this.onTap,
    super.key,
  });

  final String prefix;
  final String linkText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      fontFamily: 'HomeInter',
      color: Color(0xFF7A8FA6),
      fontSize: 14,
      fontWeight: FontWeight.w400,
    );
    const linkStyle = TextStyle(
      fontFamily: 'HomeInter',
      color: OnboardingStyle.bluePrimary,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.underline,
      decorationColor: OnboardingStyle.bluePrimary,
    );
    return Text.rich(
      TextSpan(
        text: prefix.isEmpty ? '' : '$prefix ',
        style: baseStyle,
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: onTap,
              child: Text(linkText, style: linkStyle),
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
