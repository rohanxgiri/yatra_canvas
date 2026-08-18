import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class ProgressHeader extends StatelessWidget {
  const ProgressHeader({
    required this.currentStep,
    required this.totalSteps,
    this.onBack,
    this.onSkip,
    this.skipLabel = 'Skip',
    this.useSafeArea = true,
    super.key,
  }) : assert(totalSteps > 0),
       assert(currentStep > 0);

  final int currentStep;
  final int totalSteps;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;
  final String skipLabel;
  final bool useSafeArea;

  @override
  Widget build(BuildContext context) {
    final normalizedStep = currentStep.clamp(1, totalSteps);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 44,
            child: onBack == null
                ? null
                : IconButton(
                    onPressed: onBack,
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              label: 'Step $normalizedStep of $totalSteps',
              value: '${(normalizedStep / totalSteps * 100).round()} percent',
              child: Row(
                children: List.generate(totalSteps, (index) {
                  final isComplete = index < normalizedStep;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: index == totalSteps - 1 ? 0 : 5,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOut,
                        height: isComplete ? 5 : 3,
                        decoration: BoxDecoration(
                          color: isComplete
                              ? AppColors.teal
                              : AppColors.border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: onSkip == null
                ? null
                : TextButton(
                    onPressed: onSkip,
                    child: Text(skipLabel, style: AppTextStyles.caption),
                  ),
          ),
        ],
      ),
    );

    return useSafeArea ? SafeArea(bottom: false, child: content) : content;
  }
}
