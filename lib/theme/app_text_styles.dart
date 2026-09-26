import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography tokens used across YatraCanvas.
class AppTextStyles {
  AppTextStyles._();

  static const TextStyle display = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.charcoal,
    fontSize: 40,
    height: 1.06,
    fontWeight: FontWeight.w400,
    letterSpacing: -1.15,
  );

  static const TextStyle pageTitle = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.charcoal,
    fontSize: 34,
    height: 1.1,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.9,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.charcoal,
    fontSize: 22,
    height: 1.18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.45,
  );

  static const TextStyle cardTitle = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.charcoal,
    fontSize: 18,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.25,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.charcoal,
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle body = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.charcoal,
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodyMuted = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.textSecondary,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle label = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.charcoal,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.05,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.textSecondary,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle button = TextStyle(
    fontFamily: 'HomeInter',
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.05,
  );
}
