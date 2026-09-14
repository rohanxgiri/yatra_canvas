import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/popular_destinations.dart';
import '../../models/yatra_session.dart';
import '../../widgets/yatra_bottom_navigation.dart';
import '../account/account_screens.dart';
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
  // Guest favorites are intentionally empty until the traveller chooses one.
  final Set<String> _favorites = {};
  int _selectedDestination = 0;

  void _toggleFavorite(String name) => setState(() {
    if (!_favorites.add(name)) _favorites.remove(name);
  });

  void _openCreateTrip({String? destination}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DestinationSelectionScreen(initialQuery: destination),
      ),
    );
  }

  void _continueTrip() {
    final trips = YatraSession.instance.trips;
    if (trips.isEmpty) {
      _openCreateTrip();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripSummaryScreen(draft: trips.first),
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
        setState(() => _selectedDestination = 3);
      case 4:
        setState(() => _selectedDestination = 4);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: YatraSession.instance,
    builder: (context, _) => PopScope(
      canPop: _selectedDestination == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _selectedDestination = 0);
      },
      child: Scaffold(
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
                      child: switch (_selectedDestination) {
                        0 => KeyedSubtree(
                          key: const ValueKey('home-page'),
                          child: _buildHomePage(padding, s),
                        ),
                        1 => ExplorePage(
                          key: const ValueKey('explore-page'),
                          favorites: _favorites,
                          onFavorite: _toggleFavorite,
                          onOpenTripCreation: _openCreateTrip,
                          onOpenDestination: (name) =>
                              _openCreateTrip(destination: name),
                        ),
                        3 => SavedScreen(
                          favorites: _favorites,
                          onFavorite: _toggleFavorite,
                          embedded: true,
                          onExplore: () => _selectDestination(1),
                        ),
                        _ => ProfileScreen(
                          favorites: _favorites,
                          onFavorite: _toggleFavorite,
                          embedded: true,
                        ),
                      },
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
                              onLightSurface: _selectedDestination >= 3,
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
      ),
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
                    name: YatraSession.instance.name,
                    onProfile: () => _selectDestination(4),
                  ),
                  SizedBox(height: 41 * scale),
                  HomeSearchBar(scale: scale, onSearch: _openCreateTrip),
                  SizedBox(height: 41 * scale),
                  Text(
                    YatraSession.instance.trips.isEmpty
                        ? 'Your next journey'
                        : 'Continue planning',
                    style: HomeStyle.text(24 * scale),
                  ),
                  SizedBox(height: 14 * scale),
                  ContinuePlanningCard(
                    trip: YatraSession.instance.trips.firstOrNull,
                    onContinue: _continueTrip,
                  ),
                  SizedBox(height: 30 * scale),
                  WhereNextCard(onCreateTrip: _openCreateTrip),
                  SizedBox(height: 27 * scale),
                  Text(
                    'Popular Destinations',
                    style: HomeStyle.text(24 * scale),
                  ),
                  SizedBox(height: 14 * scale),
                  for (var i = 0; i < _popularDestinations.length; i += 2) ...[
                    if (i > 0) SizedBox(height: 20 * scale),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: HomeDestinationCard(
                            name: _popularDestinations[i].name,
                            region: _popularDestinations[i].region,
                            image: _popularDestinations[i].image,
                            favorite: _favorites.contains(
                              _popularDestinations[i].name,
                            ),
                            onTap: () => _openCreateTrip(
                              destination: _popularDestinations[i].name,
                            ),
                            onFavorite: () => _toggleFavorite(
                              _popularDestinations[i].name,
                            ),
                          ),
                        ),
                        SizedBox(width: 20 * scale),
                        Expanded(
                          child: HomeDestinationCard(
                            name: _popularDestinations[i + 1].name,
                            region: _popularDestinations[i + 1].region,
                            image: _popularDestinations[i + 1].image,
                            favorite: _favorites.contains(
                              _popularDestinations[i + 1].name,
                            ),
                            onTap: () => _openCreateTrip(
                              destination: _popularDestinations[i + 1].name,
                            ),
                            onFavorite: () => _toggleFavorite(
                              _popularDestinations[i + 1].name,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

const _popularDestinations = popularDestinations;
