import 'package:flutter/material.dart';

import '../../models/yatra_session.dart';
import '../../theme/yc_motion.dart';
import '../../widgets/yatra_brand.dart';
import '../../widgets/yc_auth_button.dart';
import '../home/home_screen.dart';
import '../onboarding/widgets/onboarding_button.dart';
import '../onboarding/widgets/onboarding_styles.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

/// The account entry screen shown after onboarding visual pages.
///
/// Presents four paths: Continue with Google, Sign Up, Sign In, or Guest.
///
/// Authentication status:
/// [UI ONLY] — no backend or OAuth flow is executed here.
/// The Google button shows a "coming soon" notice.
/// Guest mode calls [YatraSession.enterAsGuest()] and navigates to [HomeScreen].
/// See ADR-001 for the planned Supabase Auth integration path.
class AccountEntryScreen extends StatelessWidget {
  const AccountEntryScreen({super.key});

  void _continueAsGuest(BuildContext context) {
    YatraSession.instance.enterAsGuest();
    Navigator.of(context).pushAndRemoveUntil(
      YCRoutes.journey<void>(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  void _googleNotice(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Google sign-in is coming soon. Continue as Guest for now.',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _openSignUp(BuildContext context) {
    Navigator.of(context)
        .push(YCRoutes.standard<void>(builder: (_) => const SignUpScreen()));
  }

  void _openSignIn(BuildContext context) {
    Navigator.of(context)
        .push(YCRoutes.standard<void>(builder: (_) => const SignInScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomPad = mq.padding.bottom;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: OnboardingStyle.backgroundGradient,
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: OnboardingStyle.radialGlow),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final scale = (w / 390).clamp(0.85, 1.15);

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    28 * scale,
                    24 * scale,
                    28 * scale,
                    (bottomPad + 24) * scale,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Brand mark ─────────────────────────────────────
                      const YatraBrand(compact: true),
                      SizedBox(height: 48 * scale),

                      // ── Hero heading ────────────────────────────────────
                      Text(
                        'Ready to map\nyour next journey?',
                        style: OnboardingStyle.text(
                          34 * scale,
                          weight: FontWeight.w300,
                          height: 1.15,
                          color: OnboardingStyle.inkNavy,
                        ),
                      ),
                      SizedBox(height: 14 * scale),

                      // ── Supporting copy ─────────────────────────────────
                      Text(
                        'Sign in to keep your trips and preferences '
                        'wherever you travel. Account access is still being '
                        'prepared, so guest planning is available now.',
                        style: OnboardingStyle.text(
                          15 * scale,
                          color: OnboardingStyle.mutedSlate,
                          height: 1.55,
                        ),
                      ),
                      SizedBox(height: 36 * scale),

                      // ── Google ──────────────────────────────────────────
                      YCGoogleButton(
                        height: 52 * scale,
                        onTap: () => _googleNotice(context),
                      ),
                      SizedBox(height: 12 * scale),

                      // ── Sign up ─────────────────────────────────────────
                      OnboardingPrimaryButton(
                        label: 'Create account',
                        height: 52 * scale,
                        backgroundColor: const Color(0xFF1A4FC4),
                        showShadow: false,
                        onTap: () => _openSignUp(context),
                      ),
                      SizedBox(height: 18 * scale),

                      // ── Sign in link ────────────────────────────────────
                      Center(
                        child: YCAuthTextLink(
                          prefix: 'Already have an account?',
                          linkText: 'Sign in',
                          onTap: () => _openSignIn(context),
                        ),
                      ),
                      SizedBox(height: 28 * scale),

                      // ── OR divider ──────────────────────────────────────
                      const YCAuthDivider(),
                      SizedBox(height: 28 * scale),

                      // ── Guest ───────────────────────────────────────────
                      YCGhostButton(
                        label: 'Continue as Guest',
                        height: 52 * scale,
                        icon: Icons.person_outline_rounded,
                        onTap: () => _continueAsGuest(context),
                      ),
                      SizedBox(height: 14 * scale),

                      Center(
                        child: Text(
                          'Trips stay in this app session while you continue as a guest.',
                          textAlign: TextAlign.center,
                          style: OnboardingStyle.text(
                            12 * scale,
                            color: OnboardingStyle.mutedSlate.withValues(
                              alpha: 0.75,
                            ),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
