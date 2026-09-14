import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/trip_draft.dart';
import 'home_style.dart';
import 'yatra_refractive_glass.dart';

/// Image-led planning card using the actual saved session trip when available.
class ContinuePlanningCard extends StatelessWidget {
  const ContinuePlanningCard({required this.onContinue, this.trip, super.key});
  final VoidCallback onContinue;
  final TripDraft? trip;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final s = constraints.maxWidth / 620;
      final city = trip?.destination?.name;
      final image = switch (city?.toLowerCase()) {
        'jaipur' => 'jaipur',
        'varanasi' => 'varanasi',
        null || 'ujjain' => 'ujjain',
        _ => 'journey_editorial',
      };
      final spiritual =
          trip?.purposes.contains('Religious / Spiritual') ?? false;
      final title = city == null
          ? 'Somewhere\nworth going.'
          : '$city\n${spiritual ? 'Spiritual Trip' : 'Your travel plan'}';
      final localizations = MaterialLocalizations.of(context);
      final formatDate = trip?.startDate.year == trip?.endDate.year
          ? localizations.formatShortMonthDay
          : localizations.formatShortDate;
      final dates = trip == null
          ? 'Choose a place. Make it your own.'
          : '${formatDate(trip!.startDate)} – ${formatDate(trip!.endDate)}';
      final action = SizedBox(
        width: math.max(92, 141 * s),
        child: HomeAction(
          label: trip == null ? 'Plan your first trip' : 'Continue planning',
          onTap: onContinue,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              child: YatraRefractiveGlass(
                radius: 25,
                blur: 3,
                fill: const Color(0x33D9D9D9),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12 * s,
                    vertical: 14 * s,
                  ),
                  child: Center(
                    child: Text(
                      trip == null ? 'PLAN A TRIP' : 'CONTINUE',
                      textAlign: TextAlign.center,
                      style: HomeStyle.text(
                        math.max(11, 16 * s),
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (trip != null) ...[
                HomeIcon('calendar', width: math.max(13, 18 * s)),
                SizedBox(width: 6 * s),
              ],
              Expanded(
                child: Text(
                  dates,
                  style: HomeStyle.text(
                    math.max(11, 16 * s),
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          if (trip != null) ...[
            SizedBox(height: 10 * s),
            // This is setup completeness, not an invented itinerary percentage.
            Semantics(
              label: 'Trip setup complete',
              value: '${(_setupProgress * 100).round()} percent',
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _setupProgress,
                    minHeight: math.max(4, 7 * s),
                    color: const Color(0xFFFF6246),
                    backgroundColor: const Color(0xD9FFFFFF),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;
      return ClipRRect(
        borderRadius: BorderRadius.circular(18 * s),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                '${HomeStyle.assetRoot}$image.png',
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x00141B34),
                      Color(0xA6141B34),
                    ],
                    stops: [0, .62, 1],
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: 341 * s),
              child: Padding(
                padding: EdgeInsets.fromLTRB(26 * s, 26 * s, 16 * s, 14 * s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 26 * s,
                        vertical: 10 * s,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.all(Radius.circular(30)),
                      ),
                      child: Text(
                        trip == null ? 'EXPLORE' : 'PLANNING',
                        style: HomeStyle.text(math.max(10, 16 * s)),
                      ),
                    ),
                    SizedBox(height: 24 * s),
                    Text(
                      title,
                      style: HomeStyle.text(64 * s, color: Colors.white),
                    ),
                    SizedBox(height: 16 * s),
                    if (largeText)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          details,
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: action,
                          ),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: details),
                          SizedBox(width: 18 * s),
                          action,
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  double get _setupProgress {
    final draft = trip;
    if (draft == null) return 0;
    final completed = [
      draft.destination != null,
      !draft.endDate.isBefore(draft.startDate) && draft.durationDays > 0,
      draft.startLatitude != null && draft.startLongitude != null,
      draft.purposes.isNotEmpty,
    ].where((ready) => ready).length;
    return completed / 4;
  }
}
