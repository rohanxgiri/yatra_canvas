import 'package:flutter/material.dart';

import 'home_style.dart';
import 'yatra_refractive_glass.dart';

/// Controlled state: the home owns session-only favorites, never backend data.
class YatraFavoriteButton extends StatelessWidget {
  const YatraFavoriteButton({
    required this.name,
    required this.selected,
    required this.onTap,
    this.diameter = 35,
    super.key,
  });
  final String name;
  final bool selected;
  final VoidCallback onTap;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final size = diameter.clamp(32.0, 38.0);
    return SizedBox(
      width: 48,
      height: 48,
      child: HomeAction(
        label: 'Favorite $name',
        onTap: onTap,
        toggled: selected,
        child: Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: size,
            height: size,
            child: YatraRefractiveGlass(
              radius: size / 2,
              blur: 1.2,
              displacement: 2.8,
              fill: selected ? const Color(0x20FFE8E2) : const Color(0x18FFFFFF),
              borderColor: const Color(0xA6FFFFFF),
              child: Center(
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 140),
                  child: HomeIcon(
                    selected ? 'favorite_filled' : 'favorite_outline',
                    key: ValueKey(selected),
                    width: (size * .52).clamp(16.0, 19.0),
                    height: (size * .52).clamp(16.0, 19.0) * .88,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
