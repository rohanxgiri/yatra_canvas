import 'package:flutter/material.dart';

import '../theme/yc_style.dart';
import 'primary_button.dart';
import 'progress_header.dart';

class CreateTripScaffold extends StatelessWidget {
  const CreateTripScaffold({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.onContinue,
    this.continueLabel = 'Continue',
    this.continueIcon = Icons.arrow_forward_rounded,
    this.continueEnabled = true,
    this.onBack,
    super.key,
  });
  final int step;
  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback? onContinue;
  final String continueLabel;
  final IconData? continueIcon;
  final bool continueEnabled;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Theme(
    data: YCStyle.theme(context),
    child: Scaffold(
      resizeToAvoidBottomInset: true,
      body: YCCanvas(
        child: SafeArea(
          child: Column(
            children: [
              ProgressHeader(
                currentStep: step,
                totalSteps: 5,
                useSafeArea: false,
                onBack: onBack ?? () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title.replaceAll('\n', ' '), style: YCStyle.title),
                      const SizedBox(height: 12),
                      Text(
                        subtitle,
                        style: YCStyle.body.copyWith(color: YCStyle.muted),
                      ),
                      const SizedBox(height: 28),
                      child,
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                decoration: const BoxDecoration(
                  color: Color(0xF7F6F9FF),
                  border: Border(top: BorderSide(color: YCStyle.border)),
                ),
                child: PrimaryButton(
                  label: continueLabel,
                  icon: continueIcon,
                  onPressed: continueEnabled ? onContinue : null,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
