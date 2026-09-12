import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/yc_style.dart';
import '../../widgets/yatra_brand.dart';
import 'onboarding_screen.dart';
import 'welcome_screen.dart';
import 'widgets/onboarding_styles.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({this.openOnboarding = true, super.key});
  final bool openOnboarding;
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, animation, secondaryAnimation) =>
              widget.openOnboarding
              ? const OnboardingScreen()
              : const WelcomeScreen(),
          transitionDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 280),
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: OnboardingStyle.backgroundGradient,
      ),
      child: SafeArea(
        child: SizedBox.expand(
          child: Padding(
            padding: const EdgeInsets.all(YCStyle.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const YatraBrand(compact: true),
                const Spacer(),
                Text(
                  'A little curiosity.\nA world to discover.',
                  style: YCStyle.title,
                ),
                const SizedBox(height: 16),
                Text('Your journey, mapped.', style: YCStyle.secondary),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
