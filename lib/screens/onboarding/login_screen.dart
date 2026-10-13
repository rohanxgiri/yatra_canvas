import 'package:flutter/material.dart';

import '../../models/auth_controller.dart';
import '../auth/auth_gate.dart';

/// Compatibility entry point for the original onboarding login route.
class LoginScreen extends StatelessWidget {
  const LoginScreen({this.auth, super.key});
  final AuthController? auth;
  @override
  Widget build(BuildContext context) => AuthGate(
    auth: auth ?? AuthController.instance,
    requireAuthentication: true,
  );
}
