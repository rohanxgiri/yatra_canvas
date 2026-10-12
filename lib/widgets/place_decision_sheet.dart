import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/place.dart';
import '../models/recommendation.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'place_image.dart';

/// Read-only place information with an explicit, optional itinerary action.
///
/// This sheet deliberately uses the recommendation's existing image metadata:
/// it never rewrites asset paths, requests a new photo, or saves a place
/// merely because the user opened its details.
class PlaceDecisionSheet extends StatefulWidget {
  const PlaceDecisionSheet({
    required this.recommendation,
    required this.cityName,
    required this.initiallySelected,
    required this.categoryLabel,
    required this.matchDescription,
    required this.meta,
    this.onToggle,
    super.key,
  });

  final Recommendation recommendation;
  final String cityName;
  final bool initiallySelected;
  final String categoryLabel;
  final String matchDescription;
  final String meta;

  /// Returns the authoritative selected state after the existing save/remove
  /// flow completes. Null when no trip exists yet.
  final Future<bool> Function()? onToggle;

  @override
  State<PlaceDecisionSheet> createState() => _PlaceDecisionSheetState();
}

class _PlaceDecisionSheetState extends State<PlaceDecisionSheet> {
  late bool _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initiallySelected;
  }

  Future<void> _toggle() async {
    if (_busy || widget.onToggle == null) return;
    setState(() => _busy = true);
    try {
      final nowSelected = await widget.onToggle!();
      if (mounted) setState(() => _selected = nowSelected);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update your trip. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openExternal(Uri url) async {
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    } on Object {
      // A missing launcher or offline device must not interrupt trip planning.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this link.')),
      );
    }
  }

  String? _clean(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  Uri? _websiteUrl(String? website) {
    final raw = _clean(website);
    if (raw == null) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    return uri;
  }

  String _openingHoursText(Place? details) {
    if (details == null ||
        details.openingHoursStatus == OpeningHoursStatus.unknown) {
      return 'Opening hours unavailable. Check before visiting.';
    }
    if (details.openingHoursStatus == OpeningHoursStatus.closed) {
      return 'Listed as closed. Confirm before planning a visit.';
    }
    final raw = _clean(details.rawOpeningHours);
    if (raw == null) {
      return 'Opening hours are available in the schedule, but no short summary is provided.';
    }
    return details.hoursVerification == 'VERIFIED'
        ? raw
        : '$raw (not independently verified)';
  }

  @override
  Widget build(BuildContext context) {
    final recommendation = widget.recommendation;
    final details = recommendation.placeDetails;
    final description = _clean(details?.description);
    final reason = _clean(recommendation.recommendationReason);
    // An offline availability note isn't an explanation of what makes a
    // destination worth visiting.
    final meaningfulReason = reason != null &&
        !reason.toLowerCase().startsWith('available offline in the ');
    final websiteUrl = _websiteUrl(details?.website);
    final mapUrl = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query':
          '${recommendation.name} ${recommendation.latitude},${recommendation.longitude}',
    });

    return Column(
      key: const ValueKey('place-decision-sheet'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: PlaceImage(
                      placeId: recommendation.id,
                      name: recommendation.name,
                      image: recommendation.image,
                      cityName: widget.cityName,
                      normalizedCategory: recommendation.normalizedCategory,
                      rawCategory: recommendation.category,
                      showAttribution: true,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(recommendation.name, style: AppTextStyles.pageTitle),
                const SizedBox(height: 8),
                Text(
                  '${widget.categoryLabel} · ${widget.cityName}',
                  style: AppTextStyles.bodyMuted,
                ),
                if (recommendation.rating != null ||
                    recommendation.reviewCount > 0 ||
                    recommendation.isHeritage ||
                    recommendation.isPopular ||
                    recommendation.isLocalSpeciality) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (recommendation.rating case final rating?)
                        _FactChip(
                          icon: Icons.star_outline_rounded,
                          label: '${rating.toStringAsFixed(1)} / 5'
                              '${recommendation.reviewCount > 0 ? ' · ${recommendation.reviewCount} reviews' : ''}',
                        ),
                      if (recommendation.isHeritage)
                        const _FactChip(label: 'Heritage', icon: Icons.account_balance_outlined),
                      if (recommendation.isPopular)
                        const _FactChip(label: 'Popular', icon: Icons.explore_outlined),
                      if (recommendation.isLocalSpeciality)
                        const _FactChip(label: 'Local speciality', icon: Icons.place_outlined),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Text('About this place', style: AppTextStyles.sectionTitle),
                const SizedBox(height: 9),
                Text(
                  description ??
                      'A detailed description is not available for this place yet. '
                          'You can review its category and the planning information below.',
                  key: const ValueKey('place-decision-description'),
                  style: description == null
                      ? AppTextStyles.bodyMuted
                      : AppTextStyles.body,
                ),
                if (meaningfulReason) ...[
                  const SizedBox(height: 22),
                  Text('Why it matches your trip', style: AppTextStyles.cardTitle),
                  const SizedBox(height: 8),
                  Text(reason, style: AppTextStyles.bodyMuted),
                ] else if (recommendation.matchedCategories.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text('Why it matches your trip', style: AppTextStyles.cardTitle),
                  const SizedBox(height: 8),
                  Text(widget.matchDescription == reason
                      ? 'Matches your selected trip interests.'
                      : widget.matchDescription, style: AppTextStyles.bodyMuted),
                ],
                const SizedBox(height: 22),
                Text('Before you visit', style: AppTextStyles.cardTitle),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.schedule_outlined, size: 19, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_openingHoursText(details), style: AppTextStyles.bodyMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(widget.meta, style: AppTextStyles.caption),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _openExternal(mapUrl),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('View on map'),
                    ),
                    if (websiteUrl != null)
                      OutlinedButton.icon(
                        onPressed: () => _openExternal(websiteUrl),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Website'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onToggle == null) ...[
                    const Text(
                      'Create a trip first to save this place to your itinerary.',
                      style: AppTextStyles.caption,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('place-decision-action'),
                      onPressed: widget.onToggle == null || _busy ? null : _toggle,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_selected ? Icons.check_circle_outline : Icons.add_circle_outline),
                      label: Text(widget.onToggle == null
                          ? 'Save trip first'
                          : _selected
                              ? 'Remove from itinerary'
                              : 'Add to itinerary'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.tealLight,
      borderRadius: BorderRadius.circular(100),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.tealDark),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(color: AppColors.tealDark),
          ),
        ],
      ),
    ),
  );
}
