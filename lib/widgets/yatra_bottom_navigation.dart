import 'package:flutter/material.dart';

import '../screens/home/widgets/home_style.dart';
import '../screens/home/widgets/yatra_refractive_glass.dart';

/// The one floating navigation surface shared by Home and Explore.
///
/// Only destinations backed by a page should update [currentIndex]. The shell
/// may use the remaining destinations for actions without moving selection.
class YatraBottomNavigation extends StatelessWidget {
  const YatraBottomNavigation({
    required this.scale,
    required this.currentIndex,
    required this.onDestinationSelected,
    super.key,
  }) : assert(currentIndex >= 0 && currentIndex < itemCount);

  static const itemCount = 5;

  final double scale;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _items = <_YatraNavigationDestination>[
    _YatraNavigationDestination(label: 'Home', asset: 'home'),
    _YatraNavigationDestination(label: 'Explore', asset: 'discover'),
    _YatraNavigationDestination(label: 'Create Trip', asset: 'create'),
    _YatraNavigationDestination(label: 'Saved', asset: 'favorites'),
    _YatraNavigationDestination(label: 'Profile', asset: 'profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final width = (500 * scale).clamp(280.0, 500.0);
    final height = (width * .198).clamp(64.0, 99.0);
    final iconScale = (width / 500).clamp(.7, 1.0);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slotWidth = constraints.maxWidth / itemCount;
              final indicatorSize = constraints.maxHeight;
              final indicatorLeft =
                  slotWidth * currentIndex + (slotWidth - indicatorSize) / 2;
              return Stack(
                children: [
                  AnimatedPositioned(
                    key: const ValueKey('yatra-nav-selection'),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    left: indicatorLeft,
                    top: (constraints.maxHeight - indicatorSize) / 2,
                    width: indicatorSize,
                    height: indicatorSize,
                    child: YatraRefractiveGlass(
                      radius: indicatorSize / 2,
                      blur: .8,
                      displacement: 1.2,
                      fill: const Color(0x18FFFFFF),
                      borderColor: const Color(0xB3FFFFFF),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Row(
                    children: List.generate(_items.length, (index) {
                      final item = _items[index];
                      return Expanded(
                        child: YatraNavItem(
                          label: item.label,
                          selected: currentIndex == index,
                          onTap: () => onDestinationSelected(index),
                          child: _NavigationGlyph(
                            asset: item.asset,
                            iconScale: iconScale,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
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

class _YatraNavigationDestination {
  const _YatraNavigationDestination({required this.label, required this.asset});

  final String label;
  final String asset;
}

class _NavigationGlyph extends StatelessWidget {
  const _NavigationGlyph({required this.asset, required this.iconScale});

  final String asset;
  final double iconScale;

  @override
  Widget build(BuildContext context) {
    switch (asset) {
      case 'home':
        return HomeIcon(
          'home',
          width: 29.5 * iconScale,
          height: 31.5 * iconScale,
        );
      case 'discover':
        return HomeIcon('discover', width: 50 * iconScale);
      case 'create':
        return SizedBox(
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
        );
      case 'favorites':
        return HomeIcon('favorites', width: 44 * iconScale);
      case 'profile':
        return HomeIcon('profile', width: 40 * iconScale);
    }
    throw StateError('Unknown navigation glyph: $asset');
  }
}
