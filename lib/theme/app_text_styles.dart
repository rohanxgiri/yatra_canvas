import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography tokens used across YatraCanvas.
class AppTextStyles {
  AppTextStyles._();

  static const TextStyle display = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.charcoal,
    fontSize: 34,
    height: 1.08,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.4,
  );

  static const TextStyle pageTitle = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.charcoal,
    fontSize: 32,
    height: 1.12,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.3,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.charcoal,
    fontSize: 21,
    height: 1.22,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.45,
  );

  static const TextStyle cardTitle = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.charcoal,
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.15,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.charcoal,
    fontSize: 16,
    height: 1.55,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle body = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.charcoal,
    fontSize: 14,
    height: 1.55,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodyMuted = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.textSecondary,
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle label = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.charcoal,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: 'HomeInter',
    color: AppColors.textSecondary,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle button = TextStyle(
    fontFamily: 'HomeInter',
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.05,
  );
}
