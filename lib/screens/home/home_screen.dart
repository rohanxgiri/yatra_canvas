import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/section_header.dart';
import '../../widgets/yatra_brand.dart';
import '../create_trip/destination_selection_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
                ],
              ),
            ),
          ],
        ),
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
              FilledButton.tonalIcon(
                onPressed: _openCreateTrip,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create'),
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
