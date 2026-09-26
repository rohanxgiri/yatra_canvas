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
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: YCStyle.title),
                          const SizedBox(height: 14),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: Text(
                              subtitle,
                              style: YCStyle.body.copyWith(
                                color: YCStyle.muted,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          child,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: const BoxDecoration(
                  color: Color(0xF8FFFFFF),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x14142C53),
                      blurRadius: 24,
                      offset: Offset(0, -8),
                    ),
                  ],
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: PrimaryButton(
                      label: continueLabel,
                      icon: continueIcon,
                      onPressed: continueEnabled ? onContinue : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
