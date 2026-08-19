import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/onboarding_canvas.dart';
import '../../widgets/secondary_button.dart';
import '../../widgets/yatra_brand.dart';
import 'personal_interests_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  void _continue(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PersonalInterestsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OnboardingCanvas(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 22),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 34,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Back',
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(height: 26),
                      const Center(child: YatraBrand()),
                      const SizedBox(height: 42),
                      Text(
                        'Keep every journey\nin one place.',
                        style: AppTextStyles.display,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Save your plans and pick up wherever the road takes you.',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 36),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .76),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white),
                        ),
                        child: Column(
                          children: [
                            SecondaryButton(
                              label: 'Continue with Google',
                              icon: Icons.g_mobiledata_rounded,
                              onPressed: () => _continue(context),
                            ),
                            const SizedBox(height: 12),
                            SecondaryButton(
                              label: 'Continue with Email',
                              icon: Icons.mail_outline_rounded,
                              onPressed: () => _continue(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Center(
                        child: TextButton(
                          onPressed: () => _continue(context),
                          child: const Text.rich(
                            TextSpan(
                              text: 'Already have an account? ',
                              children: [
                                TextSpan(
                                  text: 'Sign in',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: TextButton(
                          onPressed: () => _continue(context),
                          child: const Text('Skip for now'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
