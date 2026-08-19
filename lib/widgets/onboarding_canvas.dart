import 'package:flutter/material.dart';

/// A quiet, pure-white surface shared by every first-run screen.
class OnboardingCanvas extends StatelessWidget {
  const OnboardingCanvas({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: Colors.white, child: child);
  }
}
