import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_bottom_navigation.dart';
import '../../widgets/section_header.dart';
import '../../widgets/selection_chip.dart';
import '../../widgets/yatra_brand.dart';
import '../create_trip/destination_selection_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _navItems = [
    AppBottomNavigationItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Home',
    ),
    AppBottomNavigationItem(
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore_rounded,
      label: 'Explore',
    ),
    AppBottomNavigationItem(
      icon: Icons.add_rounded,
      selectedIcon: Icons.add_rounded,
      label: 'Create',
    ),
    AppBottomNavigationItem(
      icon: Icons.luggage_outlined,
      selectedIcon: Icons.luggage_rounded,
      label: 'Trips',
    ),
    AppBottomNavigationItem(
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  static const _destinations = <_Destination>[
    _Destination('Ujjain', 'Madhya Pradesh', Icons.temple_hindu_rounded),
    _Destination('Jaipur', 'Rajasthan', Icons.fort_rounded),
    _Destination('Goa', 'Konkan Coast', Icons.beach_access_rounded),
    _Destination('Manali', 'Himachal Pradesh', Icons.landscape_rounded),
    _Destination('Varanasi', 'Uttar Pradesh', Icons.water_rounded),
  ];

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

  void _openCreateTrip() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const DestinationSelectionScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildTopBar()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              sliver: SliverList.list(
                children: [
                  const SectionHeader(title: 'Continue planning'),
                  const SizedBox(height: 14),
                  _ContinueTripCard(
                    onContinue: () => _showPlaceholder('Trip planning'),
                  ),
                  const SizedBox(height: 34),
                  const SectionHeader(title: 'Start a new journey'),
                  const SizedBox(height: 14),
                  _CreateJourneyCard(onTap: _openCreateTrip),
                  const SizedBox(height: 34),
                  const SectionHeader(
                    title: 'Explore by mood',
                    subtitle: 'Find a journey that matches your pace.',
                  ),
                  const SizedBox(height: 14),
                  _MoodScroller(onTap: _showPlaceholder),
                  const SizedBox(height: 34),
                  const SectionHeader(
                    title: 'Popular destinations',
                    subtitle: 'Ideas loved by travellers across India.',
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 224,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _destinations.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (context, index) {
                        final destination = _destinations[index];
                        return _DestinationCard(
                          destination: destination,
                          index: index,
                          onTap: () => _showPlaceholder(destination.name),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 34),
                  const SectionHeader(
                    title: 'Recommended for you',
                    subtitle: 'Picked from the interests you enjoy.',
                  ),
                  const SizedBox(height: 14),
                  _RecommendationList(onTap: _showPlaceholder),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 0,
        items: _navItems,
        prominentIndex: 2,
        onDestinationSelected: (index) {
          if (index == 0) return;
          if (index == 2) {
            _openCreateTrip();
            return;
          }
          _showPlaceholder(_navItems[index].label);
        },
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: YatraBrand(compact: true)),
              IconButton.filledTonal(
                onPressed: () => _showPlaceholder('Search'),
                tooltip: 'Search',
                icon: const Icon(Icons.search_rounded),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'Open profile',
                child: InkWell(
                  onTap: () => _showPlaceholder('Profile'),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: AppColors.tealGradient,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x24315EEB),
                          blurRadius: 12,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'YC',
                      style: AppTextStyles.label.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Text(
            'Good morning, traveller',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.teal,
              fontWeight: FontWeight.w800,
              letterSpacing: .75,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Where will your next\nstory begin?',
            style: AppTextStyles.pageTitle,
          ),
        ],
      ),
    );
  }
}

class _ContinueTripCard extends StatelessWidget {
  const _ContinueTripCard({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 146,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const _TravelArtwork(
                  icon: Icons.temple_hindu_rounded,
                  warm: true,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x990B302F)],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.marigold,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      'PLANNING',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.charcoal,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 15,
                  child: Text(
                    'Ujjain Spiritual Trip',
                    style: AppTextStyles.sectionTitle.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Row(
                  children: [
                    Expanded(
                      child: _TripDetail(
                        icon: Icons.calendar_today_outlined,
                        label: '25 Aug – 26 Aug',
                      ),
                    ),
                    _TripDetail(icon: Icons.schedule_rounded, label: '2 Days'),
                    SizedBox(width: 16),
                    _TripDetail(icon: Icons.place_outlined, label: '8 Places'),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: const LinearProgressIndicator(
                          value: .62,
                          minHeight: 7,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      onPressed: onContinue,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(108, 46),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TripDetail extends StatelessWidget {
  const _TripDetail({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption,
          ),
        ),
      ],
    );
  }
}

class _CreateJourneyCard extends StatelessWidget {
  const _CreateJourneyCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.tealDark,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              right: -18,
              top: -30,
              child: Icon(
                Icons.public_rounded,
                size: 170,
                color: Colors.white.withValues(alpha: .08),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Where to next?',
                          style: AppTextStyles.sectionTitle.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start building your personalized trip.',
                          style: AppTextStyles.body.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: onTap,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.terracotta,
                            minimumSize: const Size(0, 46),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Create Trip'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.near_me_rounded,
                    color: AppColors.marigold,
                    size: 58,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoodScroller extends StatelessWidget {
  const _MoodScroller({required this.onTap});

  final ValueChanged<String> onTap;

  static const moods = <(String, IconData)>[
    ('Spiritual', Icons.temple_hindu_rounded),
    ('Weekend', Icons.weekend_rounded),
    ('Nature', Icons.park_rounded),
    ('Food', Icons.restaurant_rounded),
    ('Heritage', Icons.account_balance_rounded),
    ('Adventure', Icons.hiking_rounded),
    ('Relaxing', Icons.spa_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: moods.length,
        separatorBuilder: (_, _) => const SizedBox(width: 9),
        itemBuilder: (context, index) {
          final mood = moods[index];
          return SelectionChip(
            label: mood.$1,
            icon: mood.$2,
            selected: false,
            onSelected: (_) => onTap(mood.$1),
          );
        },
      ),
    );
  }
}

class _Destination {
  const _Destination(this.name, this.location, this.icon);

  final String name;
  final String location;
  final IconData icon;
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.destination,
    required this.index,
    required this.onTap,
  });

  final _Destination destination;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 178,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TravelArtwork(
                  icon: destination.icon,
                  warm: index.isEven,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(destination.name, style: AppTextStyles.cardTitle),
                    const SizedBox(height: 3),
                    Text(
                      destination.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TravelArtwork extends StatelessWidget {
  const _TravelArtwork({required this.icon, this.warm = false});

  final IconData icon;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: warm
              ? const [Color(0xFFF6C895), Color(0xFFD96C4D)]
              : const [Color(0xFF8DC9BE), Color(0xFF126E69)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -16,
            bottom: -16,
            child: Icon(icon, size: 122, color: Colors.white24),
          ),
          Center(child: Icon(icon, size: 56, color: Colors.white)),
          const Positioned(
            left: 12,
            top: 12,
            child: Icon(Icons.route_rounded, color: Colors.white70, size: 24),
          ),
        ],
      ),
    );
  }
}

class _RecommendationList extends StatelessWidget {
  const _RecommendationList({required this.onTap});

  final ValueChanged<String> onTap;

  static const items = <(String, String, IconData, Color)>[
    (
      'Spiritual Escapes',
      'Quiet temples and meaningful routes',
      Icons.temple_hindu_rounded,
      AppColors.marigold,
    ),
    (
      'Food Trails',
      'Local favourites, one stop at a time',
      Icons.restaurant_rounded,
      AppColors.terracotta,
    ),
    (
      'Weekend Journeys',
      'Easy plans for a refreshing short break',
      Icons.weekend_rounded,
      AppColors.emerald,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items
          .map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: () => onTap(item.$1),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: item.$4.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(item.$3, color: item.$4),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.$1, style: AppTextStyles.cardTitle),
                              const SizedBox(height: 3),
                              Text(item.$2, style: AppTextStyles.caption),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}
