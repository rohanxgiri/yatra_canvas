import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../models/trip_draft.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/create_trip_scaffold.dart';
import '../../widgets/search_field.dart';
import 'select_dates_screen.dart';

class DestinationSelectionScreen extends StatefulWidget {
  const DestinationSelectionScreen({this.draft, super.key});

  final TripDraft? draft;

  @override
  State<DestinationSelectionScreen> createState() =>
      _DestinationSelectionScreenState();
}

class _DestinationSelectionScreenState
    extends State<DestinationSelectionScreen> {
  late final TripDraft _draft;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _draft = widget.draft ?? TripDraft();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DestinationOption> get _filteredDestinations {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return MockData.destinations;
    return MockData.destinations
        .where((destination) {
          return destination.name.toLowerCase().contains(query) ||
              destination.region.toLowerCase().contains(query) ||
              destination.tags.any((tag) => tag.toLowerCase().contains(query));
        })
        .toList(growable: false);
  }

  void _select(DestinationOption destination) {
    FocusScope.of(context).unfocus();
    setState(() => _draft.destination = destination);
  }

  void _continue() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SelectDatesScreen(draft: _draft)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _filteredDestinations;
    return CreateTripScaffold(
      step: 1,
      title: 'Where are you\ngoing?',
      subtitle: 'Search for the city or destination you want to explore.',
      continueEnabled: _draft.destination != null,
      onContinue: _continue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchField(
            controller: _searchController,
            hintText: 'Search destinations',
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 26),
          if (_query.isEmpty) ...[
            const _SectionLabel('Recent searches'),
            const SizedBox(height: 10),
            _RecentDestination(
              destination: MockData.destinations.first,
              onTap: () => _select(MockData.destinations.first),
            ),
            const SizedBox(height: 28),
          ],
          _SectionLabel(_query.isEmpty ? 'Popular destinations' : 'Results'),
          const SizedBox(height: 10),
          if (destinations.isEmpty)
            const _NoResults()
          else
            ...destinations.map(
              (destination) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DestinationResult(
                  destination: destination,
                  selected: _draft.destination == destination,
                  onTap: () => _select(destination),
                ),
              ),
            ),
          if (_draft.destination case final destination?) ...[
            const SizedBox(height: 20),
            _DestinationPreview(destination: destination),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: AppTextStyles.sectionTitle);
  }
}

class _RecentDestination extends StatelessWidget {
  const _RecentDestination({required this.destination, required this.onTap});

  final DestinationOption destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: onTap,
      avatar: const Icon(Icons.history_rounded, size: 18),
      label: Text('${destination.name}, ${destination.region}'),
    );
  }
}

class _DestinationResult extends StatelessWidget {
  const _DestinationResult({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final DestinationOption destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.tealLight : AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.teal : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected ? AppColors.teal : AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  _iconFor(destination.name),
                  color: selected ? Colors.white : AppColors.teal,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(destination.name, style: AppTextStyles.cardTitle),
                    const SizedBox(height: 3),
                    Text(destination.region, style: AppTextStyles.bodyMuted),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: selected
                    ? const Icon(
                        Icons.check_circle_rounded,
                        key: ValueKey('selected'),
                        color: AppColors.teal,
                      )
                    : const Icon(
                        Icons.chevron_right_rounded,
                        key: ValueKey('unselected'),
                        color: AppColors.textTertiary,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(String name) {
    return switch (name) {
      'Goa' => Icons.beach_access_rounded,
      'Manali' => Icons.landscape_rounded,
      'Mumbai' => Icons.apartment_rounded,
      _ => Icons.location_city_rounded,
    };
  }
}

class _DestinationPreview extends StatelessWidget {
  const _DestinationPreview({required this.destination});

  final DestinationOption destination;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.tealGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -8,
            bottom: -14,
            child: Icon(
              Icons.route_rounded,
              size: 94,
              color: Colors.white.withValues(alpha: .10),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SELECTED DESTINATION',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.marigold,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                destination.name,
                style: AppTextStyles.pageTitle.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 5),
              Text(
                destination.locationLabel,
                style: AppTextStyles.body.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Text(
                destination.tags.join('  •  '),
                style: AppTextStyles.label.copyWith(color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.travel_explore_rounded, color: AppColors.textTertiary),
          SizedBox(height: 8),
          Text('No local destinations match that search.'),
        ],
      ),
    );
  }
}
