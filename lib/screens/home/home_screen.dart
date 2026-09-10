import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/yatra_bottom_navigation.dart';
import '../create_trip/destination_selection_screen.dart';
import '../explore/explore_page.dart';
import 'widgets/continue_planning_card.dart';
import 'widgets/home_background.dart';
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
  int _selectedDestination = 0;

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

  void _selectDestination(int index) {
    switch (index) {
      case 0:
        if (_selectedDestination != 0) {
          setState(() => _selectedDestination = 0);
        } else {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      case 1:
        if (_selectedDestination != 1) {
          setState(() => _selectedDestination = 1);
        }
      case 2:
        _openCreateTrip();
      case 3:
        _showPlaceholder('Favorites');
      case 4:
        _showPlaceholder('Profile');
    }
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
                Positioned.fill(
                  child: _selectedDestination == 0
                      ? KeyedSubtree(
                          key: const ValueKey('home-page'),
                          child: _buildHomePage(padding, s),
                        )
                      : ExplorePage(
                          key: const ValueKey('explore-page'),
                          favorites: _favorites,
                          onFavorite: _toggleFavorite,
                          onOpenTripCreation: _openCreateTrip,
                        ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 36 * s),
                      child: Center(
                        child: YatraBottomNavigation(
                          scale: s,
                          currentIndex: _selectedDestination,
                          onDestinationSelected: _selectDestination,
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
    ),
  );

  Widget _buildHomePage(double padding, double scale) => Stack(
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
        child: CustomScrollView(
          key: const ValueKey('home-scroll'),
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                padding,
                22 * scale,
                padding,
                math.max(120, 173 * scale),
              ),
              sliver: SliverList.list(
                children: [
                  HomeHeader(
                    scale: scale,
                    onProfile: () => _showPlaceholder('Profile'),
                  ),
                  SizedBox(height: 41 * scale),
                  HomeSearchBar(scale: scale, onSearch: _openCreateTrip),
                  SizedBox(height: 41 * scale),
                  Text('Continue planning', style: HomeStyle.text(24 * scale)),
                  SizedBox(height: 14 * scale),
                  ContinuePlanningCard(
                    onContinue: () => _showPlaceholder('Trip planning'),
                  ),
                  SizedBox(height: 30 * scale),
                  WhereNextCard(onCreateTrip: _openCreateTrip),
                  SizedBox(height: 27 * scale),
                  Text(
                    'Popular Destinations',
                    style: HomeStyle.text(24 * scale),
                  ),
                  SizedBox(height: 14 * scale),
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
                          onFavorite: () => _toggleFavorite('Jaipur'),
                        ),
                      ),
                      SizedBox(width: 20 * scale),
                      Expanded(
                        child: HomeDestinationCard(
                          name: 'Varanasi',
                          region: 'Uttar Pradesh',
                          image: 'varanasi',
                          favorite: _favorites.contains('Varanasi'),
                          onTap: _openCreateTrip,
                          onFavorite: () => _toggleFavorite('Varanasi'),
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
    ],
  );
}
