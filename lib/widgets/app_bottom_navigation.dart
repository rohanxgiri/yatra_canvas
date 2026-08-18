import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppBottomNavigationItem {
  const AppBottomNavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    required this.currentIndex,
    required this.onDestinationSelected,
    this.items = defaultItems,
    super.key,
  }) : assert(items.length >= 2),
       assert(currentIndex >= 0 && currentIndex < items.length);

  static const List<AppBottomNavigationItem> defaultItems = [
    AppBottomNavigationItem(
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore_rounded,
      label: 'Discover',
    ),
    AppBottomNavigationItem(
      icon: Icons.luggage_outlined,
      selectedIcon: Icons.luggage_rounded,
      label: 'Trips',
    ),
    AppBottomNavigationItem(
      icon: Icons.route_outlined,
      selectedIcon: Icons.route_rounded,
      label: 'Canvas',
    ),
    AppBottomNavigationItem(
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AppBottomNavigationItem> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: items
              .map(
                (item) => NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: item.label,
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}
