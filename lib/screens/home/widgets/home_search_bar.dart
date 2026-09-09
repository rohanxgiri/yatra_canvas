import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'home_style.dart';
import 'yatra_refractive_glass.dart';

class HomeSearchBar extends StatelessWidget {
  const HomeSearchBar({required this.scale, required this.onSearch, super.key});
  final double scale;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final height = (62 + HomeStyle.extraTextHeight(context, 24)) * scale;
    return SizedBox(
      height: height,
      child: OverflowBox(
        minHeight: math.max(48, height),
        maxHeight: math.max(48, height),
        child: HomeAction(
          label: 'Where do you want to go?',
          onTap: onSearch,
          child: SizedBox(
            height: height,
            child: YatraRefractiveGlass(
              radius: 12 * scale,
              fill: const Color(0x24F4F4F4),
              blur: 2,
              displacement: 1.6,
              child: Row(
                children: [
                  Container(
                    width: 47 * scale,
                    height: 45.291 * scale,
                    margin: EdgeInsets.only(left: 9 * scale),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDDDDD),
                      borderRadius: BorderRadius.circular(6 * scale),
                    ),
                    child: Center(
                      child: HomeIcon('search', width: 24.635 * scale),
                    ),
                  ),
                  SizedBox(width: 26 * scale),
                  Expanded(
                    child: Text(
                      'Where do you want to go?',
                      style: HomeStyle.text(
                        20 * scale,
                        color: const Color(0xFF191C1E),
                      ),
                    ),
                  ),
                  SizedBox(width: 12 * scale),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
