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
    this.prominentIndex,
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
  final int? prominentIndex;

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
          destinations: List.generate(items.length, (index) {
            final item = items[index];
            final prominent = prominentIndex == index;
            return NavigationDestination(
              icon: prominent ? _CreateIcon(icon: item.icon) : Icon(item.icon),
              selectedIcon: prominent
                  ? _CreateIcon(icon: item.selectedIcon)
                  : Icon(item.selectedIcon),
              label: item.label,
            );
          }),
        ),
      ),
    );
  }
}

class _CreateIcon extends StatelessWidget {
  const _CreateIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.teal,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29126E69),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 28),
    );
  }
}
