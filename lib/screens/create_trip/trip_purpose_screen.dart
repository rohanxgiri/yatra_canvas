import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/place.dart';
import '../../models/trip_draft.dart';
import '../../services/place_prefetch_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/create_trip_scaffold.dart';
import 'trip_preferences_screen.dart';

class TripPurposeScreen extends StatefulWidget {
  const TripPurposeScreen({
    required this.draft,
    this.tripService,
    this.prefetchService,
    super.key,
  });

  final TripDraft draft;
  final TripService? tripService;
  final PlacePrefetchService? prefetchService;

  @override
  State<TripPurposeScreen> createState() => _TripPurposeScreenState();
}

class _TripPurposeScreenState extends State<TripPurposeScreen> {
  late final Set<String> _selected;

  static const _purposes = <(String, IconData)>[
    ('Religious / Spiritual', Icons.self_improvement_rounded),
    ('Sightseeing', Icons.visibility_outlined),
    ('Culture & Heritage', Icons.account_balance_rounded),
    ('Food Exploration', Icons.restaurant_rounded),
    ('Nature', Icons.park_rounded),
    ('Relaxation', Icons.spa_rounded),
    ('Family Trip', Icons.family_restroom_rounded),
    ('Photography', Icons.photo_camera_outlined),
    ('Shopping', Icons.shopping_bag_outlined),
    ('Mixed Trip', Icons.auto_awesome_mosaic_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _selected = {...widget.draft.purposes};
  }

  void _toggle(String purpose) {
    setState(() {
      if (!_selected.add(purpose)) _selected.remove(purpose);
    });
  }

  void _continue() {
    widget.draft.purposes = {..._selected};
    final cityId = widget.draft.destination?.id;
    if (cityId != null && cityId.isNotEmpty) {
      unawaited(
        (widget.prefetchService ?? PlacePrefetchService.shared).prefetchCity(
          cityId,
          stage: PrefetchStage.interestsConfirmed,
          categories: PlaceCategoryLabel.categoriesForPurposes(_selected),
        ),
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripPreferencesScreen(
          draft: widget.draft,
          tripService: widget.tripService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final city = widget.draft.destination?.name ?? 'Ujjain';
    return CreateTripScaffold(
      step: 4,
      title: 'What brings you\nto $city?',
      subtitle: "We'll prioritize places that match the purpose of this trip.",
      continueEnabled: _selected.isNotEmpty,
      onContinue: _continue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose one or more',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.teal,
              fontWeight: FontWeight.w800,
              letterSpacing: .7,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _purposes
                    .map(
                      (purpose) => SizedBox(
                        width: itemWidth,
                        child: _PurposeCard(
                          label: purpose.$1,
                          icon: purpose.$2,
                          selected: _selected.contains(purpose.$1),
                          onTap: () => _toggle(purpose.$1),
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          if (_selected.contains('Religious / Spiritual')) ...[
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.tealLight,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.teal.withValues(alpha: .2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: AppColors.teal),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "We'll give higher priority to temples, spiritual places "
                      'and relevant cultural experiences.',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.tealDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PurposeCard extends StatelessWidget {
  const _PurposeCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? AppColors.tealLight : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? AppColors.teal : AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.teal),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: AppTextStyles.bodyLarge)),
              const SizedBox(width: 12),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 22,
                color: selected ? AppColors.teal : AppColors.borderStrong,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
