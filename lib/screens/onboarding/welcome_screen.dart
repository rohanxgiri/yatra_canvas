import 'package:flutter/material.dart';

import 'onboarding_screen.dart';

/// Compatibility entry for the unified introduction; preferences belong to trips.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const OnboardingScreen();
}
