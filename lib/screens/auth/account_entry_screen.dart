import 'package:flutter/material.dart';

import '../../models/auth_controller.dart';
import 'auth_gate.dart';

/// Compatibility entry point. All account navigation uses the same role gate.
class AccountEntryScreen extends StatelessWidget {
  const AccountEntryScreen({this.auth, super.key});
  final AuthController? auth;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account (optional)')),
    body: AuthGate(
      auth: auth ?? AuthController.instance,
      requireAuthentication: true,
    ),
  );
}
