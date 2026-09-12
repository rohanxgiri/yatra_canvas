import 'package:flutter/material.dart';

import 'onboarding_styles.dart';

/// Refined progress indicator matching YatraCanvas's calm glass aesthetic.
/// Active screen expands into an elongated pill; inactive screens stay as compact dots.
class OnboardingProgressIndicator extends StatelessWidget {
  const OnboardingProgressIndicator({
    required this.currentPage,
    this.pageCount = 3,
    super.key,
  });

  final int currentPage;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x40FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x80FFFFFF), width: .8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F14294E),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(pageCount, (index) {
          final isActive = index == currentPage;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isActive ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: isActive
                  ? OnboardingStyle.bluePrimary
                  : OnboardingStyle.bluePrimary.withValues(alpha: .22),
            ),
          );
        }),
      ),
    );
  }
}
