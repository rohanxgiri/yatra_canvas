import 'package:flutter/material.dart';

/// The shared editorial artwork, with optional detail crops for route stops.
class OnboardingJourneyImage extends StatelessWidget {
  const OnboardingJourneyImage({
    this.aspectRatio = 1,
    this.detailScale = 1,
    this.alignment = Alignment.center,
    super.key,
  });

  final double aspectRatio;
  final double detailScale;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: AspectRatio(
      aspectRatio: aspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) => OverflowBox(
          alignment: alignment,
          maxWidth: constraints.maxWidth * detailScale,
          maxHeight: constraints.maxHeight * detailScale,
          child: Image.asset(
            'lib/assets/home/journey_editorial.png',
            width: constraints.maxWidth * detailScale,
            height: constraints.maxHeight * detailScale,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
      ),
    ),
  );
}
