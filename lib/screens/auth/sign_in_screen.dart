import 'package:flutter/material.dart';

import '../../models/yatra_session.dart';
import '../../theme/yc_motion.dart';
import '../../widgets/yc_auth_button.dart';
import '../home/home_screen.dart';
import '../onboarding/widgets/onboarding_button.dart';
import '../onboarding/widgets/onboarding_styles.dart';
import 'sign_up_screen.dart';

/// Sign-in screen — UI only.
///
/// [UI ONLY] No backend authentication is performed.
/// Form validation and field state are implemented but the Sign In button
/// shows a placeholder notice. Wire up to Supabase Auth when ready (ADR-001).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _signIn() {
    // [UI ONLY] No real authentication. Supabase Auth integration is planned.
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter your email and password.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Account sign-in is coming soon. Continue as Guest for now.',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _googleNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Google sign-in is coming soon.'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _goToSignUp() {
    // Replace so back goes to AccountEntryScreen, not between sign-in/up.
    Navigator.of(context).pushReplacement(
      YCRoutes.standard<void>(builder: (_) => const SignUpScreen()),
    );
  }

  void _continueAsGuest() {
    YatraSession.instance.enterAsGuest();
    Navigator.of(context).pushAndRemoveUntil(
      YCRoutes.journey<void>(builder: (_) => const HomeScreen()),
      (route) => false,
    );
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
          decoration: const BoxDecoration(
            gradient: OnboardingStyle.radialGlow,
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final scale = (w / 390).clamp(0.85, 1.15);

                return GestureDetector(
                  // Dismiss keyboard on background tap.
                  onTap: () => FocusScope.of(context).unfocus(),
                  behavior: HitTestBehavior.translucent,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      28 * scale,
                      16 * scale,
                      28 * scale,
                      (bottomPad + 24) * scale,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Back ──────────────────────────────────────────
                        OnboardingCircleBackButton(
                          onTap: () => Navigator.maybePop(context),
                        ),
                        SizedBox(height: 32 * scale),

                        // ── Heading ───────────────────────────────────────
                        Text(
                          'Welcome\nback.',
                          style: OnboardingStyle.text(
                            38 * scale,
                            weight: FontWeight.w300,
                            height: 1.1,
                            color: OnboardingStyle.inkNavy,
                          ),
                        ),
                        SizedBox(height: 10 * scale),
                        Text(
                          'Your journeys are waiting.',
                          style: OnboardingStyle.text(
                            15 * scale,
                            color: OnboardingStyle.mutedSlate,
                            height: 1.5,
                          ),
                        ),
                        SizedBox(height: 36 * scale),

                        // ── Fields ────────────────────────────────────────
                        YCAuthField(
                          label: 'Email',
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                        ),
                        SizedBox(height: 14 * scale),
                        YCAuthField(
                          label: 'Password',
                          controller: _passCtrl,
                          obscureText: _obscurePass,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePass
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: OnboardingStyle.mutedSlate,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscurePass = !_obscurePass),
                          ),
                        ),
                        SizedBox(height: 10 * scale),

                        // ── Forgot password ───────────────────────────────
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () => ScaffoldMessenger.of(context)
                                .showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Password reset is coming soon.',
                                ),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                margin: const EdgeInsets.all(16),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Forgot password?',
                                style: OnboardingStyle.text(
                                  13 * scale,
                                  color: OnboardingStyle.bluePrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 20 * scale),

                        // ── Sign in ───────────────────────────────────────
                        OnboardingPrimaryButton(
                          label: 'Sign In',
                          height: 52 * scale,
                          backgroundColor: const Color(0xFF1A4FC4),
                          showShadow: false,
                          onTap: _signIn,
                        ),
                        SizedBox(height: 28 * scale),

                        // ── OR ────────────────────────────────────────────
                        const YCAuthDivider(),
                        SizedBox(height: 28 * scale),

                        // ── Google ────────────────────────────────────────
                        YCGoogleButton(
                          height: 52 * scale,
                          onTap: _googleNotice,
                        ),
                        SizedBox(height: 24 * scale),

                        // ── Create account link ───────────────────────────
                        Center(
                          child: YCAuthTextLink(
                            prefix: "Don't have an account?",
                            linkText: 'Create account',
                            onTap: _goToSignUp,
                          ),
                        ),
                        SizedBox(height: 16 * scale),

                        // ── Guest ─────────────────────────────────────────
                        Center(
                          child: YCAuthTextLink(
                            prefix: '',
                            linkText: 'Continue as Guest',
                            onTap: _continueAsGuest,
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
      ),
    );
  }
}
