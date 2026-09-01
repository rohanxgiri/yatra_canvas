import 'package:flutter/material.dart';

import '../../models/trip_draft.dart';
import '../../services/trip_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/create_trip_scaffold.dart';
import '../../widgets/selection_chip.dart';
import '../place_discovery/place_discovery_screen.dart';

class TripPreferencesScreen extends StatefulWidget {
  const TripPreferencesScreen({
    required this.draft,
    this.tripService,
    super.key,
  });

  final TripDraft draft;
  final TripService? tripService;

  @override
  State<TripPreferencesScreen> createState() => _TripPreferencesScreenState();
}

class _TripPreferencesScreenState extends State<TripPreferencesScreen> {
  late String _pace;
  late String _budget;
  late final Set<String> _transport;
  late final TripService _tripService;
  late final bool _ownsTripService;
  bool _isCreating = false;
  String? _creationError;

  static const _paces = <(String, String, IconData)>[
    ('Relaxed', 'Fewer places, more time at each stop', Icons.spa_outlined),
    (
      'Balanced',
      'A comfortable mix of exploring and breaks',
      Icons.balance_rounded,
    ),
    ('Packed', 'See as much as possible', Icons.bolt_rounded),
  ];

  static const _budgets = <(String, IconData)>[
    ('Saver', Icons.savings_outlined),
    ('Chill', Icons.account_balance_wallet_outlined),
    ('Boujee', Icons.workspace_premium_outlined),
  ];

  static const _transports = <(String, IconData)>[
    ('Walking', Icons.directions_walk_rounded),
    ('Public Transport', Icons.directions_bus_outlined),
    ('Auto / Cab', Icons.local_taxi_outlined),
    ('Own Vehicle', Icons.directions_car_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _pace = widget.draft.travelPace;
    _budget = widget.draft.budget;
    _transport = {...widget.draft.transportPreferences};
    _ownsTripService = widget.tripService == null;
    _tripService = widget.tripService ?? TripService();
  }

  @override
  void dispose() {
    if (_ownsTripService) _tripService.close();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_isCreating) return;
    widget.draft
      ..travelPace = _pace
      ..budget = _budget
      ..transportPreferences = {..._transport};
    setState(() {
      _isCreating = true;
      _creationError = null;
    });
    try {
      final tripId = widget.draft.tripId?.trim();
      final String effectiveTripId;
      if (tripId != null && tripId.isNotEmpty) {
        final updated = await _tripService.updateTrip(tripId, widget.draft);
        effectiveTripId = updated.tripId ?? tripId;
      } else {
        final created = await _tripService.createTrip(widget.draft);
        effectiveTripId = created.tripId;
        widget.draft.tripId = effectiveTripId;
      }
      if (!mounted) return;
      final city = widget.draft.destination;
      if (city == null) {
        throw const TripServiceException(
          'Choose and confirm a destination before creating the trip.',
        );
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              PlaceDiscoveryScreen(city: city, tripId: effectiveTripId),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _creationError = error is TripServiceException
            ? error.message
            : 'Could not save the trip. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing =
        widget.draft.tripId != null && widget.draft.tripId!.isNotEmpty;
    return CreateTripScaffold(
      step: 5,
      title: 'How do you like\nto travel?',
      subtitle:
          'Tell us what feels right and we will tune the flow and pace of the trip.',
      continueLabel: _isCreating
          ? (isEditing ? 'Saving Trip…' : 'Creating Trip…')
          : (isEditing ? 'Save & Discover Places' : 'Find Places For Me'),
      continueIcon: Icons.auto_awesome_rounded,
      continueEnabled: !_isCreating,
      onContinue: _finish,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Travel pace'),
          const SizedBox(height: 12),
          ..._paces.map(
            (pace) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PaceCard(
                label: pace.$1,
                description: pace.$2,
                icon: pace.$3,
                selected: _pace == pace.$1,
                onTap: () => setState(() => _pace = pace.$1),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Budget'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 20) / 3;
              return Row(
                children: _budgets
                    .map((budget) {
                      return Padding(
                        padding: EdgeInsets.only(
                          right: budget == _budgets.last ? 0 : 10,
                        ),
                        child: SizedBox(
                          width: width,
                          child: _BudgetCard(
                            label: budget.$1,
                            icon: budget.$2,
                            selected: _budget == budget.$1,
                            onTap: () => setState(() => _budget = budget.$1),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              );
            },
          ),
          const SizedBox(height: 28),
          const _SectionTitle('Getting around'),
          const SizedBox(height: 6),
          Text('Choose all that work for you.', style: AppTextStyles.bodyMuted),
          const SizedBox(height: 12),
          Wrap(
            spacing: 9,
            runSpacing: 10,
            children: _transports
                .map(
                  (transport) => SelectionChip(
                    label: transport.$1,
                    icon: transport.$2,
                    selected: _transport.contains(transport.$1),
                    onSelected: (_) {
                      setState(() {
                        if (!_transport.add(transport.$1)) {
                          _transport.remove(transport.$1);
                        }
                      });
                    },
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 30),
          _TripSummary(draft: widget.draft, pace: _pace, budget: _budget),
          if (_isCreating) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
          ],
          if (_creationError case final error?) ...[
            const SizedBox(height: 14),
            _TripCreationError(message: error),
          ],
        ],
      ),
    );
  }
}

class _TripCreationError extends StatelessWidget {
  const _TripCreationError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: AppTextStyles.bodyMuted)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: AppTextStyles.sectionTitle);
  }
}

class _PaceCard extends StatelessWidget {
  const _PaceCard({
    required this.label,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.tealLight : AppColors.surface,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: selected ? AppColors.teal : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected ? AppColors.teal : AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: selected ? Colors.white : AppColors.teal,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTextStyles.cardTitle),
                    const SizedBox(height: 4),
                    Text(description, style: AppTextStyles.bodyMuted),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.teal : AppColors.borderStrong,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
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
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 15),
        decoration: BoxDecoration(
          color: selected ? AppColors.tealLight : AppColors.surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? AppColors.teal : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? AppColors.teal : AppColors.textSecondary,
            ),
            const SizedBox(height: 8),
            FittedBox(child: Text(label, style: AppTextStyles.label)),
          ],
        ),
      ),
    );
  }
}

class _TripSummary extends StatelessWidget {
  const _TripSummary({
    required this.draft,
    required this.pace,
    required this.budget,
  });

  final TripDraft draft;
  final String pace;
  final String budget;

  @override
  Widget build(BuildContext context) {
    final destination = draft.destination?.name ?? 'Ujjain';
    final purposes = draft.purposes.join(', ');
    final rows = <(IconData, String)>[
      (
        Icons.calendar_today_outlined,
        '${draft.startDate.day}–${draft.endDate.day} Aug  •  ${draft.durationDays} Days',
      ),
      (Icons.train_rounded, draft.arrivalMethod),
      (Icons.flag_outlined, 'START: ${draft.arrivalPoint}'),
      (Icons.auto_awesome_outlined, purposes),
      (Icons.tune_rounded, '$pace pace  •  $budget budget'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.tealDark,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR TRIP AT A GLANCE',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.marigold,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            destination,
            style: AppTextStyles.pageTitle.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 18),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(row.$1, color: Colors.white70, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      row.$2,
                      style: AppTextStyles.body.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
