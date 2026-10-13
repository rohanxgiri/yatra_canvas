import 'package:flutter/material.dart';

import 'onboarding_screen.dart';
import '../../models/auth_controller.dart';

/// Compatibility entry for the unified introduction; preferences belong to trips.
class PersonalInterestsScreen extends StatelessWidget {
  const PersonalInterestsScreen({this.auth, super.key});
  final AuthController? auth;
  @override
  Widget build(BuildContext context) => OnboardingScreen(auth: auth);
}
