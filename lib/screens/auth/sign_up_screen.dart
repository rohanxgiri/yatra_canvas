import 'package:flutter/material.dart';

import '../../theme/yc_motion.dart';
import '../../widgets/yc_auth_button.dart';
import '../onboarding/widgets/onboarding_button.dart';
import '../onboarding/widgets/onboarding_styles.dart';
import 'sign_in_screen.dart';

/// Sign-up screen — UI only.
///
/// [UI ONLY] No backend account creation is performed.
/// The Create account button shows a placeholder notice.
/// Wire up to Supabase Auth when ready (ADR-001).
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  void _createAccount() {
    // [UI ONLY] Validation only — no backend or account creation.
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final confirm = _confirmPassCtrl.text;

    String? error;
    if (name.isEmpty) {
      error = 'Please enter your name.';
    } else if (email.isEmpty || !email.contains('@')) {
      error = 'Please enter a valid email address.';
    } else if (pass.length < 8) {
      error = 'Password must be at least 8 characters.';
    } else if (pass != confirm) {
      error = 'Passwords do not match.';
    }

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    // All fields valid but auth backend not yet integrated.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Account creation is coming soon. Continue as Guest for now.',
        ),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _googleNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Google sign-in is coming soon.'),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _goToSignIn() {
    // Replace so back goes to AccountEntryScreen, not between sign-up/in.
    Navigator.of(context).pushReplacement(
      YCRoutes.standard<void>(builder: (_) => const SignInScreen()),
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
                          'Create your\nYatraCanvas\naccount',
                          style: OnboardingStyle.text(
                            36 * scale,
                            weight: FontWeight.w300,
                            height: 1.12,
                            color: OnboardingStyle.inkNavy,
                          ),
                        ),
                        SizedBox(height: 10 * scale),
                        Text(
                          'Your trips and preferences, wherever you go.',
                          style: OnboardingStyle.text(
                            15 * scale,
                            color: OnboardingStyle.mutedSlate,
                            height: 1.5,
                          ),
                        ),
                        SizedBox(height: 32 * scale),

                        // ── Name ──────────────────────────────────────────
                        YCAuthField(
                          label: 'Your name',
                          controller: _nameCtrl,
                          keyboardType: TextInputType.name,
                          autofillHints: const [AutofillHints.name],
                          textInputAction: TextInputAction.next,
                        ),
                        SizedBox(height: 14 * scale),

                        // ── Email ─────────────────────────────────────────
                        YCAuthField(
                          label: 'Email',
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                        ),
                        SizedBox(height: 14 * scale),

                        // ── Password ──────────────────────────────────────
                        YCAuthField(
                          label: 'Password',
                          controller: _passCtrl,
                          obscureText: _obscurePass,
                          autofillHints: const [
                            AutofillHints.newPassword,
                          ],
                          textInputAction: TextInputAction.next,
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
                        SizedBox(height: 14 * scale),

                        // ── Confirm password ──────────────────────────────
                        YCAuthField(
                          label: 'Confirm password',
                          controller: _confirmPassCtrl,
                          obscureText: _obscureConfirm,
                          autofillHints: const [
                            AutofillHints.newPassword,
                          ],
                          textInputAction: TextInputAction.done,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: OnboardingStyle.mutedSlate,
                              size: 20,
                            ),
                            onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm,
                            ),
                          ),
                        ),
                        SizedBox(height: 28 * scale),

                        // ── Create account ────────────────────────────────
                        OnboardingPrimaryButton(
                          label: 'Create account',
                          height: 52 * scale,
                          backgroundColor: const Color(0xFF1A4FC4),
                          showShadow: false,
                          onTap: _createAccount,
                        ),
                        SizedBox(height: 20 * scale),

                        // ── Sign in link ──────────────────────────────────
                        Center(
                          child: YCAuthTextLink(
                            prefix: 'Already have an account?',
                            linkText: 'Sign in',
                            onTap: _goToSignIn,
                          ),
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
