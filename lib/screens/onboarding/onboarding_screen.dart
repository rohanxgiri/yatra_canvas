import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/yatra_session.dart';
import '../../theme/yc_motion.dart';
import '../../widgets/yatra_brand.dart';
import '../home/home_screen.dart';
import '../home/widgets/yatra_refractive_glass.dart';
import '../auth/account_entry_screen.dart';
import 'widgets/onboarding_button.dart';
import 'widgets/onboarding_figma_first_screen.dart';
import 'widgets/onboarding_progress_indicator.dart';
import 'widgets/onboarding_step_views.dart';
import 'widgets/onboarding_styles.dart';

/// The four-screen mobile onboarding experience for YatraCanvas.
/// Introduces travellers to the core value proposition:
/// Discover places -> personalise -> connect the route -> plan your days.
///
/// Finishing or skipping is a one-way guest entry into the product. Traveller
/// account binding remains partial, so onboarding never blocks planning behind
/// account controls that cannot complete yet.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _pageController;
  int _currentPage = 0;

  static const _stepCount = 4;

  Widget _stepAt(int index) => switch (index) {
    0 => const DiscoverStepView(),
    1 => const PersonaliseStepView(),
    2 => OnboardingMapStep(isActive: _currentPage == 2),
    3 => const ItineraryStepView(),
    _ => const SizedBox.shrink(),
  };

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
    YatraSession.instance.enterAsGuest();
    Navigator.of(context).pushAndRemoveUntil(
      YCRoutes.journey<void>(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  void _openAccountOptions() {
    Navigator.of(context).push(
      YCRoutes.standard<void>(builder: (_) => const AccountEntryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: _currentPage == 2
              ? OnboardingStyle.journeyBackgroundGradient
              : OnboardingStyle.backgroundGradient,
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
                        // One stable onboarding shell for every page.
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            20 * scale,
                            10 * scale,
                            16 * scale,
                            6 * scale,
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: YatraBrand(compact: true),
                                ),
                              ),
                              OnboardingSkipButton(
                                label: 'Skip',
                                onTap: _enterApp,
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
                              child: _stepAt(index),
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

                        // Shared glass progress pill and full-width action.
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            20 * scale,
                            8 * scale,
                            20 * scale,
                            18 * scale,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              YatraRefractiveGlass(
                                radius: 16,
                                blur: 5,
                                fill: const Color(0x66FFFFFF),
                                borderColor: const Color(0xB3FFFFFF),
                                shadow: true,
                                shadowColor: const Color(0x0A142C53),
                                shadowBlur: 6,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 7,
                                  ),
                              child: OnboardingProgressIndicator(
                                    currentPage: _currentPage,
                                    pageCount: _stepCount,
                                  ),
                                ),
                              ),
                              if (_currentPage == _stepCount - 1) ...[
                                const SizedBox(height: 4),
                                TextButton(
                                  onPressed: _openAccountOptions,
                                  child: const Text(
                                    'Sign in or save trips to an account',
                                  ),
                                ),
                              ],
                              SizedBox(height: 14 * scale),
                              OnboardingPrimaryButton(
                                label: _currentPage == _stepCount - 1
                                    ? 'Start Planning'
                                    : 'Continue',
                                isProminent: _currentPage == _stepCount - 1,
                                icon: Icons.arrow_forward_rounded,
                                height: 48,
                                backgroundColor: const Color(0xFF235EC6),
                                showShadow: false,
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
