import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/onboarding_canvas.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import '../../widgets/yatra_brand.dart';
import 'personal_interests_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phone = TextEditingController();
  String _countryCode = '+91';

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _continue() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PersonalInterestsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: OnboardingCanvas(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 34),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(height: 18),
                    const Center(child: YatraBrand()),
                    const SizedBox(height: 28),
                    Center(
                      child: Text(
                        'Welcome back',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.display,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Sign in to keep your journeys close.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 34),
                    Text('Mobile number', style: AppTextStyles.sectionTitle),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 58,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSoft,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _countryCode,
                              borderRadius: BorderRadius.circular(16),
                              icon: const Icon(Icons.expand_more_rounded),
                              items: const ['+91', '+1', '+44']
                                  .map(
                                    (code) => DropdownMenuItem(
                                      value: code,
                                      child: Text(code, style: AppTextStyles.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) setState(() => _countryCode = value);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.telephoneNumberNational],
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) {
                              if (_phone.text.length >= 7) _continue();
                            },
                            decoration: const InputDecoration(
                              hintText: 'Phone number',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    PrimaryButton(
                      label: 'Continue with Phone',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: _phone.text.length >= 7 ? _continue : null,
                    ),
                    const SizedBox(height: 26),
                    const _DividerLabel(label: 'or continue with'),
                    const SizedBox(height: 20),
                    SecondaryButton(
                      label: 'Continue with Google',
                      icon: Icons.g_mobiledata_rounded,
                      onPressed: _continue,
                    ),
                    const SizedBox(height: 12),
                    SecondaryButton(
                      label: 'Continue with Apple',
                      icon: Icons.apple,
                      onPressed: _continue,
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: TextButton.icon(
                        onPressed: _continue,
                        icon: const Icon(Icons.person_outline_rounded),
                        label: const Text('Continue as Guest'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        'You can create an account later from your profile.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Divider()),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(label, style: AppTextStyles.caption),
      ),
      const Expanded(child: Divider()),
    ],
  );
}
