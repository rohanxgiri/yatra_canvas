import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'home_style.dart';
import 'yatra_refractive_glass.dart';

class ContinuePlanningCard extends StatelessWidget {
  const ContinuePlanningCard({required this.onContinue, super.key});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final s = constraints.maxWidth / 620;
      final titleStyle = HomeStyle.text(64 * s, color: Colors.white);
      final titlePainter = TextPainter(
        text: TextSpan(text: 'Ujjain\nSpritual Trip', style: titleStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth - 38 * s);
      final extra =
          math.max(0.0, titlePainter.height - 154 * s) +
          HomeStyle.extraTextHeight(context, 36) * s;
      titlePainter.dispose();
      final buttonWidth = (141 + HomeStyle.extraTextHeight(context, 84)) * s;
      final buttonHeight = (50 + HomeStyle.extraTextHeight(context, 19)) * s;
      final hitHeight = math.max(48.0, buttonHeight);
      return SizedBox(
        height: 341 * s + extra,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18 * s),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The Figma node export includes its original fill crop.
              Image.asset(
                '${HomeStyle.assetRoot}ujjain.png',
                fit: BoxFit.cover,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 93 * s,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      // Preserve Figma's gray/alpha interpolation instead of
                      // letting a transparent endpoint lose its RGB in Skia.
                      colors: [
                        Color(0x00919191),
                        Color(0x40777777),
                        Color(0x805E5E5E),
                        Color(0xBF444444),
                        Color(0xFF2B2B2B),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 26 * s,
                top: 27 * s,
                child: Container(
                  width: 134 * s,
                  height: (37 + HomeStyle.extraTextHeight(context, 19)) * s,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(42 * s),
                  ),
                  child: Text('PLANNING', style: HomeStyle.text(16 * s)),
                ),
              ),
              Positioned(
                left: 26 * s,
                right: 12 * s,
                top: (94 + HomeStyle.extraTextHeight(context, 19)) * s,
                child: Text('Ujjain\nSpritual Trip', style: titleStyle),
              ),
              Positioned(
                left: 32 * s,
                bottom: 49 * s,
                child: Row(
                  children: [
                    HomeIcon('calendar', width: 17 * s),
                    SizedBox(width: 6 * s),
                    Text(
                      '25 Aug - 28 Aug',
                      style: HomeStyle.text(14 * s, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 26 * s,
                bottom: 32 * s,
                width: 561 * s - buttonWidth,
                height: 7 * s,
                child: Semantics(
                  label: 'Trip planning progress',
                  value: '72%',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24 * s),
                    child: const ColoredBox(
                      color: Color(0xFFDFDFDF),
                      child: FractionallySizedBox(
                        widthFactor: 302 / 420,
                        alignment: Alignment.centerLeft,
                        child: ColoredBox(color: Color(0xFFFF5533)),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 15 * s,
                bottom: 14 * s - (hitHeight - buttonHeight) / 2,
                width: buttonWidth,
                height: hitHeight,
                child: HomeAction(
                  label: 'Continue planning',
                  onTap: onContinue,
                  child: SizedBox(
                    width: buttonWidth,
                    height: buttonHeight,
                    child: YatraRefractiveGlass(
                      radius: buttonHeight / 2,
                      blur: 1.8,
                      fill: const Color(0x24D9D9D9),
                      child: Center(
                        child: Text(
                          'CONTINUE',
                          style: HomeStyle.text(16 * s, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
