import 'package:flutter/material.dart';

import '../../../models/weather_advisory.dart';
import '../../../services/weather_advisory_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';

class WeatherAdvisoryCard extends StatefulWidget {
  const WeatherAdvisoryCard({
    required this.tripId,
    required this.advisory,
    required this.weatherService,
    required this.onDismiss,
    required this.onApplied,
    super.key,
  });

  final String tripId;
  final WeatherAdvisory advisory;
  final WeatherAdvisoryService weatherService;
  final VoidCallback onDismiss;
  final VoidCallback onApplied;

  @override
  State<WeatherAdvisoryCard> createState() => _WeatherAdvisoryCardState();
}

class _WeatherAdvisoryCardState extends State<WeatherAdvisoryCard> {
  bool _isLoadingAction = false;

  IconData _getConditionIcon(String condition) {
    switch (condition.toLowerCase()) {
      case 'very_hot':
      case 'hot':
        return Icons.wb_sunny_rounded;
      case 'heavy_rain':
        return Icons.water_drop_rounded;
      case 'storm':
        return Icons.thunderstorm_rounded;
      case 'very_cold':
      case 'cold':
        return Icons.ac_unit_rounded;
      case 'high_wind':
        return Icons.air_rounded;
      default:
        return Icons.cloud_rounded;
    }
  }

  Color _getBadgeColor(String severity) {
    if (severity.toLowerCase() == 'warning') {
      return Colors.deepOrange;
    }
    return AppColors.teal;
  }

  Future<void> _showAlternatives() async {
    setState(() => _isLoadingAction = true);
    final alternatives = await widget.weatherService.getAlternatives(
      widget.tripId,
      widget.advisory.dayNumber,
      widget.advisory.condition,
    );
    if (!mounted) return;
    setState(() => _isLoadingAction = false);

    if (alternatives.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No indoor alternatives found for this city.'),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.roofing_rounded, color: AppColors.teal),
                  const SizedBox(width: 8),
                  Text(
                    'Weather-Friendly Alternatives',
                    style: AppTextStyles.sectionTitle,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Sheltered indoor attractions matching your interests for Day ${widget.advisory.dayNumber}:',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: 16),
              for (final alt in alternatives) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.museum_outlined,
                        color: AppColors.teal,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alt.name,
                              style: AppTextStyles.body.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              alt.category,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.teal,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              alt.reason,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRearrangePreview() async {
    setState(() => _isLoadingAction = true);
    final preview = await widget.weatherService.previewRearrange(
      widget.tripId,
      widget.advisory.dayNumber,
      widget.advisory.condition,
    );
    if (!mounted) return;
    setState(() => _isLoadingAction = false);

    if (preview == null || preview.proposedPlaces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not generate schedule preview.'),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.tune_rounded, color: AppColors.teal),
            const SizedBox(width: 8),
            const Expanded(child: Text('Suggested Adjustment')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview.explanation,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Proposed schedule for Day ${preview.dayNumber}:',
                style: AppTextStyles.label.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              for (final stop in preview.proposedPlaces) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        stop.environment == 'indoor'
                            ? Icons.roofing_rounded
                            : Icons.wb_sunny_outlined,
                        size: 18,
                        color: AppColors.teal,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          stop.name,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (stop.timeWindow != null)
                        Text(
                          stop.timeWindow!,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.teal,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep original plan'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final placeIds = preview.proposedPlaces.map((p) => p.placeId).toList();
              final success = await widget.weatherService.applyAdjustment(
                widget.tripId,
                preview.dayNumber,
                placeIds,
              );
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Itinerary schedule updated successfully!'),
                  ),
                );
                widget.onApplied();
              }
            },
            child: const Text('Apply changes'),
          ),
        ],
      ),
    );
  }

  Future<void> _ignoreWeather() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ignore Weather Suggestions?'),
        content: const Text(
          'Weather suggestions will be suppressed for this trip. You can continue planning without weather advisories.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ignore for this trip'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.weatherService.ignoreWeather(widget.tripId);
      widget.onDismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final conditionIcon = _getConditionIcon(widget.advisory.condition);
    final badgeColor = _getBadgeColor(widget.advisory.severity);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: badgeColor.withValues(alpha: .3)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: .15),
                  shape: BoxShape.circle,
                ),
                child: Icon(conditionIcon, color: badgeColor, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weather Advisory · Day ${widget.advisory.dayNumber}',
                      style: AppTextStyles.label.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.advisory.summary,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.charcoal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Default path: Continue as planned
              FilledButton.tonal(
                onPressed: widget.onDismiss,
                child: const Text('Continue as planned'),
              ),
              OutlinedButton.icon(
                onPressed: _isLoadingAction ? null : _showAlternatives,
                icon: const Icon(Icons.roofing_rounded, size: 16),
                label: const Text('Suggest alternatives'),
              ),
              OutlinedButton.icon(
                onPressed: _isLoadingAction ? null : _showRearrangePreview,
                icon: const Icon(Icons.swap_vert_rounded, size: 16),
                label: const Text('Rearrange this day'),
              ),
              TextButton(
                onPressed: _isLoadingAction ? null : _ignoreWeather,
                child: Text(
                  'Ignore for this trip',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
