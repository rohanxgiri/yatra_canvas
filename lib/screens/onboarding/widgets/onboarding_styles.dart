import 'package:flutter/material.dart';

/// Styling tokens and typography for the YatraCanvas onboarding experience.
/// Shares font tokens and visual aesthetics with [HomeStyle] and [ExplorePage].
abstract final class OnboardingStyle {
  static const ink = Color(0xFF141B34);
  static const inkSecondary = Color(0xFF5D687B);
  static const inkMuted = Color(0xFF8A94A6);

  static const bluePrimary = Color(0xFF055EC8);
  static const blueDark = Color(0xFF164779);
  static const blueLight = Color(0xFFEAF1FF);

  static const amber = Color(0xFFFCB61F);
  static const borderSubtle = Color(0x66FFFFFF);

  /// Consistent cream-to-travel-blue gradient matching ExplorePage and Home.
  static const backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFFFFCF5),
      Color(0xFFF6F8FC),
      Color(0xFFD9E8FC),
      Color(0xFF8DBAF6),
      Color(0xFF5798F1),
    ],
    stops: [0, .2, .43, .7, 1],
  );

  /// Warm sunlit glow overlay for depth and calm travel feeling.
  static const radialGlow = RadialGradient(
    center: Alignment(.72, -.88),
    radius: .72,
    colors: [Color(0x66FFF0B8), Color(0x00FFF0B8)],
  );

  /// Typography helper leveraging the bundled HomeInter font.
  static TextStyle text(
    double size, {
    Color color = ink,
    FontWeight weight = FontWeight.w400,
    FontStyle fontStyle = FontStyle.normal,
    double height = 1.25,
    double letterSpacing = 0,
  }) => TextStyle(
    fontFamily: 'HomeInter',
    fontSize: size,
    height: height,
    fontWeight: weight,
    fontStyle: fontStyle,
    color: color,
    letterSpacing: letterSpacing,
    fontVariations: const [FontVariation('opsz', 14)],
  );

  /// Editorial serif italic emphasis using bundled InriaSerif font with serif fallback.
  static TextStyle editorialText(
    double size, {
    Color color = ink,
    FontWeight weight = FontWeight.w700,
    double height = 1.15,
    double letterSpacing = 0,
  }) => TextStyle(
    fontFamily: 'InriaSerif',
    fontFamilyFallback: const ['serif'],
    fontSize: size,
    height: height,
    fontWeight: weight,
    fontStyle: FontStyle.italic,
    color: color,
    letterSpacing: letterSpacing,
  );
}

/// A press-scaled action component following the exact pattern of [HomeAction].
/// Avoids default Material ink/splash blobs and visual tooltips entirely.
class OnboardingAction extends StatefulWidget {
  const OnboardingAction({
    required this.label,
    required this.onTap,
    required this.child,
    this.selected = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool selected;

  @override
  State<OnboardingAction> createState() => _OnboardingActionState();
}

class _OnboardingActionState extends State<OnboardingAction> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    button: true,
    selected: widget.selected,
    onTap: widget.onTap,
    child: FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onFocusChange: (value) {
        if (!value) _setPressed(false);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? .97 : 1,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    ),
  );
}
