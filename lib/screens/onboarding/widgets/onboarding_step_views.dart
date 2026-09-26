import 'package:flutter/material.dart';

import '../../../theme/yc_style.dart';
import 'onboarding_journey_image.dart';
import 'onboarding_styles.dart';

class DiscoverStepView extends StatelessWidget {
  const DiscoverStepView({super.key});
  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          height:
              (constraints.maxWidth / .72).clamp(360, 520) +
              ((textScale - 1).clamp(0, 1) * 550),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const OnboardingJourneyImage(
                  aspectRatio: .72,
                  detailScale: 1.08,
                  alignment: Alignment.centerRight,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x08000000), Color(0xD9141B34)],
                      stops: [.28, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .86),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          'YOUR JOURNEY, THOUGHTFULLY MADE',
                          style: YCStyle.caption.copyWith(
                            color: YCStyle.ink,
                            letterSpacing: .8,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Find the place\nthat stays with you.',
                        style: YCStyle.display.copyWith(
                          color: Colors.white,
                          fontSize: 38,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Begin with a city. Shape every day around what you love.',
                        style: YCStyle.body.copyWith(
                          color: Colors.white.withValues(alpha: .86),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PersonaliseStepView extends StatelessWidget {
  const PersonaliseStepView({super.key});
  @override
  Widget build(BuildContext context) => _Story(
    title: 'More of what\nyou travel for.',
    description:
        'Tell us what draws you in. We’ll shape the journey around you.',
    child: Column(
      children: [
        const _DestinationCollage(),
        const SizedBox(height: 16),
        _PreviewSurface(
          children: [
            Text('YOUR TRAVEL SIGNALS', style: YCStyle.caption),
            const SizedBox(height: 14),
            const _PreviewRow(
              icon: Icons.temple_hindu_outlined,
              title: 'Heritage & local stories',
              detail: 'The places that give a city its character',
            ),
            const Divider(height: 24),
            const _PreviewRow(
              icon: Icons.restaurant_outlined,
              title: 'Food worth a detour',
              detail: 'Markets, cafés and regional favourites',
            ),
          ],
        ),
      ],
    ),
  );
}

class ItineraryStepView extends StatelessWidget {
  const ItineraryStepView({super.key});
  @override
  Widget build(BuildContext context) => _Story(
    title: 'A plan with\nroom to breathe.',
    description: 'Arrive, explore and pause. A useful plan that still moves at your pace.',
    child: _PreviewSurface(
      children: [
        Text('THREE MOMENTS, ONE EASY FLOW', style: YCStyle.caption),
        const SizedBox(height: 20),
        const _PreviewRow(
          icon: Icons.train_outlined,
          title: 'Arrive & settle in',
          detail: 'Begin from your station, airport or stay',
        ),
        const Padding(
          padding: EdgeInsets.only(left: 23),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(height: 24, child: VerticalDivider()),
          ),
        ),
        const _PreviewRow(
          icon: Icons.route_outlined,
          title: 'Explore your way',
          detail: 'Nearby places, in a thoughtful order',
        ),
        const Padding(
          padding: EdgeInsets.only(left: 23),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(height: 24, child: VerticalDivider()),
          ),
        ),
        const _PreviewRow(
          icon: Icons.wb_sunny_outlined,
          title: 'Take a rest day',
          detail: 'Keep a day intentionally unplanned',
        ),
        const SizedBox(height: 22),
        Text(
          'Adjust your days as your plans change.',
          style: YCStyle.secondary,
        ),
      ],
    ),
  );
}

class _DestinationCollage extends StatelessWidget {
  const _DestinationCollage();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 214,
    child: Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 28,
          right: 86,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'lib/assets/home/jaipur.png',
              fit: BoxFit.cover,
              cacheWidth: 720,
              excludeFromSemantics: true,
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 54,
          width: 126,
          height: 160,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white, width: 4),
              image: const DecorationImage(
                image: ResizeImage(
                  AssetImage('lib/assets/home/varanasi.png'),
                  width: 480,
                ),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        Positioned(
          left: 18,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: YCStyle.ink,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              'Heritage  •  Food  •  Slow days',
              style: YCStyle.caption.copyWith(color: Colors.white),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Story extends StatelessWidget {
  const _Story({
    required this.title,
    required this.description,
    required this.child,
  });
  final String title;
  final String description;
  final Widget child;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: OnboardingStyle.text(
            34,
            weight: FontWeight.w300,
            height: 1.16,
          ),
        ),
        const SizedBox(height: 14),
        Text(description, style: YCStyle.body.copyWith(color: YCStyle.muted)),
        const SizedBox(height: 28),
        child,
      ],
    ),
  );
}

class _PreviewSurface extends StatelessWidget {
  const _PreviewSurface({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xEFFFFFFF),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 48, child: Icon(icon, color: YCStyle.blue, size: 24)),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: YCStyle.body.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(detail, style: YCStyle.secondary),
          ],
        ),
      ),
    ],
  );
}
