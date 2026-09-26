import 'package:flutter/material.dart';

import '../../models/yatra_session.dart';
import '../../theme/yc_motion.dart';
import '../../theme/yc_style.dart';
import '../../widgets/yc_scaffold.dart';
import '../../widgets/yatra_brand.dart';
import '../home/home_screen.dart';

/// Honest guest entry retained for legacy navigation references.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  void _continueAsGuest(BuildContext context) {
    YatraSession.instance.enterAsGuest();
    Navigator.of(context).pushAndRemoveUntil(
      YCRoutes.journey<void>(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) => YCScaffold(
    appBar: AppBar(),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(YCStyle.gutter),
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
            'Account sign-in is not available yet. Recent trips and preferences stay in this app session.',
            style: YCStyle.secondary,
          ),
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(YCStyle.gutter),
      child: FilledButton(
        onPressed: () => _continueAsGuest(context),
        child: const Text('Continue as Guest'),
      ),
    ),
  );
}
