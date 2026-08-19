import 'package:flutter/material.dart';

import 'screens/onboarding/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const YatraCanvasApp());
}

class YatraCanvasApp extends StatelessWidget {
  const YatraCanvasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YatraCanvas',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) {
        return ColoredBox(
          color: const Color(0xFFE9EDF5),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
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
        );
      },
      home: const SplashScreen(),
    );
  }
}
