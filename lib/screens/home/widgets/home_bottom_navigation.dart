import 'package:flutter/material.dart';

import 'home_style.dart';
import 'yatra_refractive_glass.dart';

class HomeBottomNavigation extends StatelessWidget {
  const HomeBottomNavigation({
    required this.scale,
    required this.onHome,
    required this.onDiscover,
    required this.onCreate,
    required this.onFavorites,
    required this.onProfile,
    super.key,
  });
  final double scale;
  final VoidCallback onHome, onDiscover, onCreate, onFavorites, onProfile;

  @override
  Widget build(BuildContext context) {
    final width = (500 * scale).clamp(280.0, 500.0);
    final height = (width * .198).clamp(64.0, 99.0);
    final iconScale = (width / 500).clamp(.7, 1.0);
    return SizedBox(
      width: width,
      height: height,
      child: YatraRefractiveGlass(
        radius: height / 2,
        blur: 2.2,
        displacement: 3,
        shadow: true,
        fill: const Color(0x20D9E8FF),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(
                child: YatraNavItem(
                  label: 'Home',
                  onTap: onHome,
                  selected: true,
                  child: SizedBox(
                    width: height - 8,
                    height: height - 8,
                    child: YatraRefractiveGlass(
                      radius: height / 2,
                      blur: .8,
                      displacement: 1.2,
                      fill: const Color(0x18FFFFFF),
                      borderColor: const Color(0xB3FFFFFF),
                      child: Center(
                        child: HomeIcon(
                          'home',
                          width: 29.5 * iconScale,
                          height: 31.5 * iconScale,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: YatraNavItem(
                  label: 'Discover',
                  onTap: onDiscover,
                  child: HomeIcon('discover', width: 50 * iconScale),
                ),
              ),
              Expanded(
                child: YatraNavItem(
                  label: 'Create Trip',
                  onTap: onCreate,
                  child: SizedBox(
                    width: 55 * iconScale,
                    height: 55 * iconScale,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        HomeIcon('create_circle', width: 47.33 * iconScale),
                        HomeIcon(
                          'create_vertical',
                          width: 1.5 * iconScale,
                          height: 19.83 * iconScale,
                        ),
                        HomeIcon(
                          'create_horizontal',
                          width: 19.83 * iconScale,
                          height: 1.5 * iconScale,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: YatraNavItem(
                  label: 'Saved',
                  onTap: onFavorites,
                  child: HomeIcon('favorites', width: 44 * iconScale),
                ),
              ),
              Expanded(
                child: YatraNavItem(
                  label: 'Profile',
                  onTap: onProfile,
                  child: HomeIcon('profile', width: 40 * iconScale),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class YatraNavItem extends StatelessWidget {
  const YatraNavItem({
    required this.label,
    required this.onTap,
    required this.child,
    this.selected = false,
    super.key,
  });
  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool selected;
  @override
  Widget build(BuildContext context) =>
      HomeAction(label: label, onTap: onTap, selected: selected, child: child);
}
