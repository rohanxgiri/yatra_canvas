import 'package:flutter/material.dart';

import 'onboarding_styles.dart';

/// Primary action button for onboarding matching the approved Image 1 visual target.
/// Uses a dark teal pill shape (`#134552`) with white typography and a right arrow.
class OnboardingPrimaryButton extends StatelessWidget {
  const OnboardingPrimaryButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.width,
    this.height = 56,
    this.backgroundColor = OnboardingStyle.darkTeal,
    this.showShadow = true,
    this.isProminent = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final double? width;
  final double height;
  final Color backgroundColor;
  final bool showShadow;
  final bool isProminent;

  @override
  Widget build(BuildContext context) {
    return OnboardingAction(
      label: label,
      onTap: onTap,
      child: Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: showShadow
              ? const [
                  BoxShadow(
                    color: Color(0x22134552),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'HomeInter',
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(icon, color: Colors.white, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}

/// Circular back button matching Image 1: 56x56 white circle with subtle dark-teal border and arrow.
class OnboardingCircleBackButton extends StatelessWidget {
  const OnboardingCircleBackButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OnboardingAction(
      label: 'Go back',
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(
            color: OnboardingStyle.darkTeal.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.arrow_back,
            color: OnboardingStyle.darkTeal,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// Quiet 44pt Skip action for the shared onboarding header.
class OnboardingSkipButton extends StatelessWidget {
  const OnboardingSkipButton({
    required this.label,
    required this.onTap,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OnboardingAction(
      label: label,
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'HomeInter',
                color: Color(0xFF50617B),
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Legacy alias for compatibility
class OnboardingGhostButton extends StatelessWidget {
  const OnboardingGhostButton({
    required this.label,
    required this.onTap,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      OnboardingSkipButton(label: label, onTap: onTap);
}
