import 'package:flutter/material.dart';

import '../theme/yc_style.dart';
import '../screens/home/widgets/home_style.dart';

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
    final step = currentStep.clamp(1, totalSteps);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 24, 4),
      child: Row(
        children: [
          if (onBack != null)
            HomeAction(
              label: 'Back',
              onTap: onBack!,
              child: const Icon(Icons.arrow_back_rounded, color: YCStyle.ink),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your journey', style: YCStyle.caption),
                const SizedBox(height: 8),
                Semantics(
                  label: 'Step $step of $totalSteps',
                  child: Row(
                    children: [
                      for (var i = 0; i < totalSteps; i++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: i == totalSteps - 1 ? 0 : 4,
                            ),
                            child: AnimatedContainer(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              height: 3,
                              decoration: BoxDecoration(
                                color: i < step ? YCStyle.blue : YCStyle.border,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (onSkip != null) ...[
            const SizedBox(width: 12),
            TextButton(onPressed: onSkip, child: Text(skipLabel)),
          ],
        ],
      ),
    );
    return useSafeArea ? SafeArea(bottom: false, child: content) : content;
  }
}
