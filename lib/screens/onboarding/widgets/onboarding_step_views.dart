import 'package:flutter/material.dart';

import '../../../theme/yc_style.dart';
import 'onboarding_styles.dart';

class DiscoverStepView extends StatelessWidget {
  const DiscoverStepView({super.key});
  @override
  Widget build(BuildContext context) => const _Story(
    title: 'Find somewhere\nworth going.',
    description: 'Discover places and experiences made for your next journey.',
    child: _JourneyImage(),
  );
}

class PersonaliseStepView extends StatelessWidget {
  const PersonaliseStepView({super.key});
  @override
  Widget build(BuildContext context) => _Story(
    title: 'A trip made\naround you.',
    description:
        'Choose your places. We’ll connect them into days that make sense.',
    child: Column(
      children: [
        const _JourneyImage(compact: true),
        const SizedBox(height: 16),
        _PreviewSurface(
          children: [
            Text('YOUR KIND OF JOURNEY', style: YCStyle.caption),
            const SizedBox(height: 14),
            const _PreviewRow(
              icon: Icons.temple_hindu_outlined,
              title: 'Culture & architecture',
              detail: 'Places with a story to tell',
            ),
            const Divider(height: 24),
            const _PreviewRow(
              icon: Icons.restaurant_outlined,
              title: 'Local food',
              detail: 'A little room for new flavours',
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
    title: 'Your trip,\nat your pace.',
    description: 'Start where you arrive. Make room for exploring, and time to take it slow.',
    child: _PreviewSurface(
      children: [
        Text('A FEW DAYS AWAY', style: YCStyle.caption),
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

class _JourneyImage extends StatelessWidget {
  const _JourneyImage({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: AspectRatio(
      aspectRatio: compact ? 2 : 1,
      child: Image.asset(
        'lib/assets/home/journey_editorial.png',
        fit: BoxFit.cover,
        excludeFromSemantics: true,
      ),
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
