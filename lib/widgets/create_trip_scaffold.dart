import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'primary_button.dart';
import 'progress_header.dart';

class CreateTripScaffold extends StatelessWidget {
  const CreateTripScaffold({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.onContinue,
    this.continueLabel = 'Continue',
    this.continueIcon = Icons.arrow_forward_rounded,
    this.continueEnabled = true,
    this.onBack,
    super.key,
  });

  final int step;
  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback? onContinue;
  final String continueLabel;
  final IconData? continueIcon;
  final bool continueEnabled;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            ProgressHeader(
              currentStep: step,
              totalSteps: 5,
              useSafeArea: false,
              onBack: onBack ?? () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.display),
                    const SizedBox(height: 14),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 30),
                    child,
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              decoration: const BoxDecoration(
                color: AppColors.canvas,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: PrimaryButton(
                label: continueLabel,
                icon: continueIcon,
                onPressed: continueEnabled ? onContinue : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
