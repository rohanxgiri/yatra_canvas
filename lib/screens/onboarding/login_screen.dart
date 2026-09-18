import 'package:flutter/material.dart';

import '../auth/account_entry_screen.dart';

/// Legacy entry point — now redirects to [AccountEntryScreen].
///
/// Kept to avoid breaking any existing navigation references.
/// Previously served as a guest-only placeholder.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Redirect immediately via WidgetsBinding so the route stack is clean.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AccountEntryScreen()),
      );
    });
    // Blank scaffold during the single-frame redirect.
    return const Scaffold(backgroundColor: Color(0xFFFFFCF5));
  }
}
