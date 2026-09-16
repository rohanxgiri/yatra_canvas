import 'package:flutter/material.dart';

import 'onboarding_styles.dart';

/// Progress indicator matching Image 1 approved visual target.
/// Renders naked indicators without an outer card container.
/// Active screen expands into an elongated teal pill; inactive screens stay as compact subtle dots.
class OnboardingProgressIndicator extends StatelessWidget {
  const OnboardingProgressIndicator({
    required this.currentPage,
    this.pageCount = 4,
    super.key,
  });

  final int currentPage;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Page ${currentPage + 1} of $pageCount',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(pageCount, (index) {
          final isActive = index == currentPage;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3.5),
            width: isActive ? 22 : 6.5,
            height: 6.5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3.5),
              color: isActive
                  ? OnboardingStyle.activeDotTeal
                  : OnboardingStyle.inactiveDotGrey,
            ),
          );
        }),
      ),
    );
  }
}
