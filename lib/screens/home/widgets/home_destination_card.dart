import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'home_style.dart';
import 'yatra_favorite_button.dart';

class HomeDestinationCard extends StatelessWidget {
  const HomeDestinationCard({
    required this.name,
    required this.region,
    required this.image,
    required this.onTap,
    required this.onFavorite,
    this.favorite = false,
    super.key,
  });
  final String name;
  final String region;
  final String image;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final bool favorite;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final s = constraints.maxWidth / 300;
      final extra = HomeStyle.extraTextHeight(context, 58) * s;
      final favoriteInset = (constraints.maxWidth * .07).clamp(10.0, 14.0);
      double textHeight(String text, double fontSize, double maxWidth) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: HomeStyle.text(fontSize)),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: maxWidth);
        final height = painter.height;
        painter.dispose();
        return height;
      }

      final captionHeight =
          textHeight(name, 32 * s, constraints.maxWidth - 26 * s) +
          textHeight(region, 16 * s, constraints.maxWidth - 41.26 * s);
      final height = math.max(
        234 * s + extra,
        favoriteInset + 48 + 10 + captionHeight + 9 * s,
      );
      return SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18 * s),
          child: Stack(
            fit: StackFit.expand,
            children: [
              HomeAction(
                label: '$name, $region',
                onTap: onTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      left: -9 * s,
                      top: -8 * s,
                      width: 332 * s,
                      height: height + 15 * s,
                      child: Image.asset(
                        '${HomeStyle.assetRoot}$image.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      bottom: -10 * s,
                      width: 310 * s,
                      height: 113 * s + extra,
                      child: const Opacity(
                        opacity: .6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x33FFFFFF), Color(0xFF252525)],
                              stops: [0, .7096],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16 * s,
                      right: 10 * s,
                      bottom: 9 * s,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: HomeStyle.text(32 * s, color: Colors.white),
                          ),
                          Row(
                            children: [
                              SizedBox(width: 2 * s),
                              SizedBox(
                                width: 10.26 * s,
                                height: 10.26 * s,
                                child: Stack(
                                  children: [
                                    Positioned(
                                      left: .61 * s,
                                      top: -.11 * s,
                                      child: HomeIcon(
                                        'location_outline',
                                        width: 8.7 * s,
                                        height: 10.4 * s,
                                      ),
                                    ),
                                    Positioned(
                                      left: 3.4 * s,
                                      top: 2.5 * s,
                                      child: HomeIcon(
                                        'location_center',
                                        width: 3.6 * s,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 3 * s),
                              Expanded(
                                child: Text(
                                  region,
                                  style: HomeStyle.text(
                                    16 * s,
                                    color: Colors.white,
                                    weight: FontWeight.w300,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: favoriteInset,
                top: favoriteInset,
                width: 48,
                height: 48,
                child: YatraFavoriteButton(
                  name: name,
                  selected: favorite,
                  onTap: onFavorite,
                  diameter: (constraints.maxWidth * .28).clamp(44.0, 48.0),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
