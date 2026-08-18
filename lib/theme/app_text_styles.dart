import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography tokens used across YatraCanvas.
class AppTextStyles {
  AppTextStyles._();

  static const TextStyle display = TextStyle(
    color: AppColors.charcoal,
    fontSize: 36,
    height: 1.16,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.1,
  );

  static const TextStyle pageTitle = TextStyle(
    color: AppColors.charcoal,
    fontSize: 30,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
  );

  static const TextStyle sectionTitle = TextStyle(
    color: AppColors.charcoal,
    fontSize: 22,
    height: 1.27,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.35,
  );

  static const TextStyle cardTitle = TextStyle(
    color: AppColors.charcoal,
    fontSize: 17,
    height: 1.35,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle bodyLarge = TextStyle(
    color: AppColors.charcoal,
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle body = TextStyle(
    color: AppColors.charcoal,
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodyMuted = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle label = TextStyle(
    color: AppColors.charcoal,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.05,
  );

  static const TextStyle caption = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle button = TextStyle(
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
  );
}
