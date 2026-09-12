import 'package:flutter/material.dart';

import '../screens/home/widgets/home_style.dart';

/// Tokens extrapolated from the approved Home (18:16) and Explore (30:54).
/// Applied locally to planning screens; the approved screens keep their theme.
abstract final class YCStyle {
  static const ink = HomeStyle.ink;
  static const blue = Color(0xFF055EC8);
  static const muted = Color(0xFF526077);
  static const background = Color(0xFFF6F8FC);
  static const border = Color(0xFFD7E2EF);
  static const selected = Color(0xFFE7F0FF);
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const gutter = 24.0;
  static const section = 32.0;
  static const cardRadius = 18.0;
  static const sheetRadius = 28.0;
  static const controlHeight = 52.0;

  static const canvas = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFCF5), Color(0xFFF2F7FF), Color(0xFFDCEBFF)],
    stops: [0, .38, 1],
  );

  static TextStyle get title => HomeStyle.text(
    32,
    color: ink,
    weight: FontWeight.w300,
  ).copyWith(height: 1.16);
  static TextStyle get sectionTitle =>
      HomeStyle.text(20, color: ink, weight: FontWeight.w500);
  static TextStyle get body =>
      HomeStyle.text(16, color: ink).copyWith(height: 1.45);
  static TextStyle get secondary => body.copyWith(color: muted, fontSize: 14);
  static TextStyle get caption => secondary.copyWith(fontSize: 12);

  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    final scheme = base.colorScheme.copyWith(
      primary: blue,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: ink,
    );
    ButtonStyle button({bool primary = false}) => ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, controlHeight)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      textStyle: WidgetStatePropertyAll(
        body.copyWith(fontWeight: FontWeight.w500),
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => primary
            ? states.contains(WidgetState.disabled)
                  ? const Color(0xFFDDE5EF)
                  : states.contains(WidgetState.pressed)
                  ? const Color(0xFF064C9F)
                  : blue
            : Colors.transparent,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? muted
            : primary
            ? Colors.white
            : blue,
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? blue.withValues(alpha: .16)
            : states.contains(WidgetState.pressed)
            ? blue.withValues(alpha: .08)
            : Colors.transparent,
      ),
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      textTheme: base.textTheme.apply(
        fontFamily: 'HomeInter',
        bodyColor: ink,
        displayColor: ink,
      ),
      filledButtonTheme: FilledButtonThemeData(style: button(primary: true)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: button().copyWith(
          side: const WidgetStatePropertyAll(BorderSide(color: border)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: button()),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: blue,
        linearTrackColor: selected,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(sheetRadius),
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(sheetRadius)),
        ),
      ),
    );
  }
}

class YCCanvas extends StatelessWidget {
  const YCCanvas({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(gradient: YCStyle.canvas),
    child: child,
  );
}
