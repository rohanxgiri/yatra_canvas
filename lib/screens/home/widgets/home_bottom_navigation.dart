import 'package:flutter/material.dart';

import '../../../widgets/yatra_bottom_navigation.dart';

export '../../../widgets/yatra_bottom_navigation.dart';

/// Compatibility wrapper for callers written before navigation became shared.
@Deprecated('Use YatraBottomNavigation with a state-aware currentIndex.')
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
  Widget build(BuildContext context) => YatraBottomNavigation(
    scale: scale,
    currentIndex: 0,
    onDestinationSelected: (index) {
      switch (index) {
        case 0:
          onHome();
        case 1:
          onDiscover();
        case 2:
          onCreate();
        case 3:
          onFavorites();
        case 4:
          onProfile();
      }
    },
  );
}
