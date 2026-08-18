import 'package:flutter/material.dart';

/// The YatraCanvas palette: warm paper surfaces with a grounded teal accent.
class AppColors {
  AppColors._();

  static const Color canvas = Color(0xFFFFF9F0);
  static const Color canvasPeach = Color(0xFFFFF1E6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFF8F5EF);

  static const Color teal = Color(0xFF126E69);
  static const Color tealDark = Color(0xFF0B514E);
  static const Color tealLight = Color(0xFFDDEFEA);
  static const Color emerald = Color(0xFF31846F);

  static const Color charcoal = Color(0xFF202A35);
  static const Color textSecondary = Color(0xFF66717E);
  static const Color textTertiary = Color(0xFF8C958F);

  static const Color border = Color(0xFFE5E1D9);
  static const Color borderStrong = Color(0xFFD3CEC4);
  static const Color marigold = Color(0xFFF4B740);
  static const Color terracotta = Color(0xFFD96C4D);
  static const Color success = Color(0xFF4C956C);
  static const Color error = Color(0xFFB42318);

  static const LinearGradient canvasGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [canvas, canvasPeach],
  );

  static const LinearGradient tealGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [emerald, tealDark],
  );
}
