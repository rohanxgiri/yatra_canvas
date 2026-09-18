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

  static const aquaBase = Color(0xFF67D2EA);
  static const aquaLight = Color(0xFF8CE3F4);
  static const aquaDeep = Color(0xFF52C4DE);
  static const waypointSelectedRing = Color(0xFF2C3E50);

  // Design tokens aligned with Image 1 approved visual target
  static const darkTeal = Color(0xFF134552);
  static const darkTealMarker = Color(0xFF154C5B);
  static const oceanBlue = Color(0xFF0284C7);
  static const inkNavy = Color(0xFF0F2537);
  static const mutedSlate = Color(0xFF5A7A8E);
  static const activeDotTeal = Color(0xFF1F8A98);
  static const inactiveDotGrey = Color(0xFFD1E6EC);
  static const skipPillBg = Color(0xFFF0F9FB);
  static const skipPillBorder = Color(0xFFD3EEF4);
  static const skipTextTeal = Color(0xFF1B6B7C);

  static const cardGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFE2F7FB),
      Color(0xFF6ED8ED),
      Color(0xFF50CBE5),
    ],
    stops: [0.0, 0.55, 1.0],
  );

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

  /// Airy off-white screen background for the redesigned journey onboarding screen.
  static const journeyBackgroundGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [
      Color(0xFFFDF9E7),
      Color(0xFFFAF9F2),
      Color(0xFFF5F7FA),
    ],
    stops: [0, .42, 1],
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
