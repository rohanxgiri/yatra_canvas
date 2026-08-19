import 'package:flutter/material.dart';

/// YatraCanvas palette: editorial ink, route blue, and a restrained saffron.
class AppColors {
  AppColors._();

  static const Color canvas = Color(0xFFF6F8FC);
  static const Color canvasPeach = Color(0xFFEDF2FF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSoft = Color(0xFFF0F3F8);

  // Legacy token names are retained to keep widgets stable while the visual
  // language moves from teal to YatraCanvas's distinctive route blue.
  static const Color teal = Color(0xFF315EEB);
  static const Color tealDark = Color(0xFF173783);
  static const Color tealLight = Color(0xFFE7EDFF);
  static const Color emerald = Color(0xFF16856F);

  static const Color charcoal = Color(0xFF142033);
  static const Color textSecondary = Color(0xFF5D687B);
  static const Color textTertiary = Color(0xFF8A94A6);

  static const Color border = Color(0xFFE1E6EF);
  static const Color borderStrong = Color(0xFFCDD5E2);
  static const Color marigold = Color(0xFFF4B94F);
  static const Color terracotta = Color(0xFFE86F51);
  static const Color success = Color(0xFF278566);
  static const Color error = Color(0xFFB42318);

  static const LinearGradient canvasGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), canvasPeach],
  );

  static const LinearGradient onboardingGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Colors.white, Colors.white],
  );

  static const LinearGradient tealGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF315EEB), Color(0xFF152D62)],
  );
}
