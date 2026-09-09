import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../create_trip/destination_selection_screen.dart';
import 'widgets/continue_planning_card.dart';
import 'widgets/home_background.dart';
import 'widgets/home_bottom_navigation.dart';
import 'widgets/home_destination_card.dart';
import 'widgets/home_header.dart';
import 'widgets/home_search_bar.dart';
import 'widgets/home_style.dart';
import 'widgets/where_next_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scrollController = ScrollController();
  // Presentation-only toggles, retained while this Home is mounted.
  final Set<String> _favorites = {'Jaipur'};

  void _toggleFavorite(String name) => setState(() {
    if (!_favorites.add(name)) _favorites.remove(name);
  });

  void _openCreateTrip() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const DestinationSelectionScreen(),
      ),
    );
  }

  // Retain the existing home placeholder. There is no account trip-list or
  // saved-trip selection on this screen from which to resume a real trip.
  void _showPlaceholder(String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$label is coming in the next phase.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, 700.0);
        final padding = (width * .057143).clamp(20.0, 40.0);
        final contentWidth = width - 2 * padding;
        // Individual design details scale; the screen is not transformed.
        // Cards receive actual available width through LayoutBuilder / Expanded.
        final s = contentWidth / 620;
        return Center(
          child: SizedBox(
            width: width,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: RepaintBoundary(
                    child: FittedBox(
                      fit: BoxFit.fill,
                      child: SizedBox(
                        width: HomeStyle.designWidth,
                        height: HomeStyle.designHeight,
                        child: HomeBackground(scale: 1),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Stack(
                    children: [
                      CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              padding,
                              22 * s,
                              padding,
                              math.max(120, 173 * s),
                            ),
                            sliver: SliverList.list(
                              children: [
                                HomeHeader(
                                  scale: s,
                                  onProfile: () => _showPlaceholder('Profile'),
                                ),
                                SizedBox(height: 41 * s),
                                HomeSearchBar(
                                  scale: s,
                                  onSearch: _openCreateTrip,
                                ),
                                SizedBox(height: 41 * s),
                                Text(
                                  'Continue planning',
                                  style: HomeStyle.text(24 * s),
                                ),
                                SizedBox(height: 14 * s),
                                ContinuePlanningCard(
                                  onContinue: () =>
                                      _showPlaceholder('Trip planning'),
                                ),
                                SizedBox(height: 30 * s),
                                WhereNextCard(onCreateTrip: _openCreateTrip),
                                SizedBox(height: 27 * s),
                                Text(
                                  'Popular Destinations',
                                  style: HomeStyle.text(24 * s),
                                ),
                                SizedBox(height: 14 * s),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: HomeDestinationCard(
                                        name: 'Jaipur',
                                        region: 'Rajisthan',
                                        image: 'jaipur',
                                        favorite: _favorites.contains('Jaipur'),
                                        onTap: _openCreateTrip,
                                        onFavorite: () =>
                                            _toggleFavorite('Jaipur'),
                                      ),
                                    ),
                                    SizedBox(width: 20 * s),
                                    Expanded(
                                      child: HomeDestinationCard(
                                        name: 'Varanasi',
                                        region: 'Uttar Pradesh',
                                        image: 'varanasi',
                                        favorite: _favorites.contains(
                                          'Varanasi',
                                        ),
                                        onTap: _openCreateTrip,
                                        onFavorite: () =>
                                            _toggleFavorite('Varanasi'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 36 * s,
                        child: Center(
                          child: HomeBottomNavigation(
                            scale: s,
                            onHome: () => _scrollController.animateTo(
                              0,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            ),
                            onDiscover: _openCreateTrip,
                            onCreate: _openCreateTrip,
                            onFavorites: () => _showPlaceholder('Favorites'),
                            onProfile: () => _showPlaceholder('Profile'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
