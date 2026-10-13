import 'package:flutter/material.dart';

import '../theme/yc_style.dart';

/// Admin-only presentation tokens, derived from the existing traveller palette.
abstract final class AdminTheme {
  static const sidebar = YCStyle.warmCanvas;
  static const primary = YCStyle.blue;
  static const border = YCStyle.border;
  static const radius = 16.0;
  static const gutter = 24.0;
  static const success = Color(0xFF146C43);
  static const warning = Color(0xFF805200);

  static ThemeData of(BuildContext context) {
    final base = YCStyle.theme(context);
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: border),
    );
    final shape = WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: YCStyle.background,
        foregroundColor: YCStyle.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: YCStyle.sectionTitle,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: YCStyle.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(
          borderSide: const BorderSide(color: primary, width: 2),
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: YCStyle.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: base.filledButtonTheme.style?.copyWith(shape: shape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: base.outlinedButtonTheme.style?.copyWith(shape: shape),
      ),
      navigationRailTheme: base.navigationRailTheme.copyWith(
        backgroundColor: sidebar,
        indicatorColor: YCStyle.selected,
        selectedIconTheme: const IconThemeData(color: primary),
        unselectedIconTheme: const IconThemeData(color: YCStyle.muted),
        selectedLabelTextStyle: YCStyle.secondary.copyWith(
          color: primary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: YCStyle.secondary,
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: YCStyle.surface,
        indicatorColor: YCStyle.selected,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
    );
  }
}
