import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/yc_motion.dart';
import '../../widgets/yatra_brand.dart';
import '../home/home_screen.dart';
import 'widgets/onboarding_button.dart';
import 'widgets/onboarding_progress_indicator.dart';
import 'widgets/onboarding_step_views.dart';
import 'widgets/onboarding_styles.dart';

/// The four-screen mobile onboarding experience for YatraCanvas.
/// Introduces travellers to the core value proposition:
/// Discover places -> personalise -> connect the route -> plan your days.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _pageController;
  int _currentPage = 0;

  static const _steps = <Widget>[
    DiscoverStepView(),
    PersonaliseStepView(),
    RouteStepView(),
    ItineraryStepView(),
  ];
  static final _stepCount = _steps.length;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
  }

  void _next() {
    if (_currentPage < _stepCount - 1) {
      _pageController.nextPage(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
      );
    } else {
      _enterApp();
    }
  }

  void _enterApp() {
    Navigator.of(context).pushAndRemoveUntil(
      YCRoutes.journey<void>(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: OnboardingStyle.backgroundGradient,
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: OnboardingStyle.radialGlow),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = math.min(constraints.maxWidth, 600.0);
                final scale = (width / 400).clamp(.82, 1.15);

                return Center(
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        // Top navigation bar with Brand and Skip
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            20 * scale,
                            10 * scale,
                            16 * scale,
                            6 * scale,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: YatraBrand(compact: true),
                                ),
                              ),
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: _currentPage < _stepCount - 1
                                    ? 1.0
                                    : 0.0,
                                child: IgnorePointer(
                                  ignoring: _currentPage >= _stepCount - 1,
                                  child: OnboardingGhostButton(
                                    label: 'Skip',
                                    onTap: _enterApp,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Shared swipe navigation for the complete story.
                        Expanded(
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: _stepCount,
                            onPageChanged: _onPageChanged,
                            itemBuilder: (context, index) => AnimatedBuilder(
                              animation: _pageController,
                              child: _steps[index],
                              builder: (context, child) {
                                if (MediaQuery.disableAnimationsOf(context)) {
                                  return child!;
                                }
                                final page = _pageController.hasClients
                                    ? (_pageController.page ??
                                          _currentPage.toDouble())
                                    : _currentPage.toDouble();
                                final distance = (page - index).abs().clamp(
                                  0.0,
                                  1.0,
                                );
                                return Opacity(
                                  opacity: 1 - distance * .22,
                                  child: Transform.scale(
                                    scale: 1 - distance * .035,
                                    alignment: Alignment.center,
                                    child: child,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // Bottom action area: Progress indicator and Primary CTA
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            24 * scale,
                            8 * scale,
                            24 * scale,
                            18 * scale,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OnboardingProgressIndicator(
                                currentPage: _currentPage,
                                pageCount: _stepCount,
                              ),
                              SizedBox(height: 14 * scale),
                              OnboardingPrimaryButton(
                                label: _currentPage == _stepCount - 1
                                    ? 'Start Planning'
                                    : 'Continue',
                                isProminent: _currentPage == _stepCount - 1,
                                icon: Icons.arrow_forward_rounded,
                                onTap: _next,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
