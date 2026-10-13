import 'package:flutter/material.dart';

import 'screens/auth/auth_gate.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'models/auth_controller.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YatraCanvasApp());
}

class YatraCanvasApp extends StatelessWidget {
  const YatraCanvasApp({
    this.auth,
    this.requireAuthentication = false,
    super.key,
  });
  final AuthController? auth;
  final bool requireAuthentication;

  @override
  Widget build(BuildContext context) {
    final controller = auth ?? AuthController.instance;
    return MaterialApp(
      title: 'YatraCanvas',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) {
        return ListenableBuilder(
          listenable: controller,
          builder: (context, _) => ColoredBox(
            color: const Color(0xFFE9EDF5),
            child: Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: controller.isAdmin ? double.infinity : 600,
                ),
                decoration: const BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A14294E),
                      blurRadius: 36,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        );
      },
      home: AuthGate(
        auth: controller,
        requireAuthentication: requireAuthentication,
        onboardingBuilder: (_, complete) =>
            OnboardingScreen(auth: controller, onComplete: complete),
      ),
    );
  }
}
