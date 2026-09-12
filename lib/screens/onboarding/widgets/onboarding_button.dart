import 'package:flutter/material.dart';

import '../../home/widgets/home_style.dart';
import '../../../theme/yc_style.dart';

class OnboardingPrimaryButton extends StatelessWidget {
  const OnboardingPrimaryButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.width,
    this.isProminent = false,
    super.key,
  });
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final double? width;
  final bool isProminent;
  @override
  Widget build(BuildContext context) => Theme(
    data: YCStyle.theme(context),
    child: SizedBox(
      width: width ?? double.infinity,
      child: FilledButton(
        onPressed: onTap,
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          children: [
            Text(label, textAlign: TextAlign.center),
            if (icon != null) Icon(icon, size: 20),
          ],
        ),
      ),
    ),
  );
}

class OnboardingGhostButton extends StatelessWidget {
  const OnboardingGhostButton({
    required this.label,
    required this.onTap,
    super.key,
  });
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => HomeAction(
    label: label,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(label, style: YCStyle.secondary),
    ),
  );
}
