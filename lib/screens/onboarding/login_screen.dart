import 'package:flutter/material.dart';

import '../../theme/yc_style.dart';
import '../../widgets/yc_scaffold.dart';
import '../../widgets/yatra_brand.dart';
import 'onboarding_screen.dart';

/// Guest entry until authentication is available.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});
  @override
  Widget build(BuildContext context) => YCScaffold(
    appBar: AppBar(),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const YatraBrand(compact: true),
          const SizedBox(height: 48),
          Text('Start with a little curiosity.', style: YCStyle.title),
          const SizedBox(height: 16),
          Text(
            'Discover destinations and shape your next trip as a guest.',
            style: YCStyle.body,
          ),
          const SizedBox(height: 24),
          Text(
            'Account sign-in is not available yet. Your recent trips and preferences stay in this app session.',
            style: YCStyle.secondary,
          ),
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(24),
      child: FilledButton(
        onPressed: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const OnboardingScreen()),
        ),
        child: const Text('Continue as Guest'),
      ),
    ),
  );
}
