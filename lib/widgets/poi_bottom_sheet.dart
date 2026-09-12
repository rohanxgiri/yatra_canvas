import '../theme/yc_style.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/itinerary_stop_status.dart';
import '../models/optimized_route.dart';
import '../models/place.dart';
import '../models/saved_place.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A polished map-layer POI detail sheet.
///
/// All data is passed in by the caller from already-loaded state — no extra
/// network calls are made inside this widget.
class PoiBottomSheet extends StatefulWidget {
  const PoiBottomSheet({
    required this.savedPlace,
    this.routeStop,
    this.availableDays = const [],
    this.isStartLocation = false,
    this.visitDate,
    this.onStatusChange,
    this.onMoveToDay,
    super.key,
  });

  /// The full saved-place record (contains Place with opening-hours data).
  final SavedPlace savedPlace;

  /// Scheduled stop info from the optimized route. Null when not yet scheduled.
  ///
  /// [OptimizedRoutePlace.travelTimeMinutes] and
  /// [OptimizedRoutePlace.distanceFromPrevious] describe the leg arriving
  /// **at** this stop (i.e. from the previous stop). They are displayed as
  /// "From previous stop" travel info.
  final OptimizedRoutePlace? routeStop;

  /// Valid target days for "Move to Another Day" (excludes current day + REST days).
  final List<int> availableDays;

  /// True when the marker is the trip start location rather than a saved place.
  final bool isStartLocation;

  /// The actual calendar date of this stop's trip day.
  ///
  /// When provided, opening-hours evaluation uses the correct weekday.
  /// When null and status is KNOWN, opening-hours open/closed claim is omitted
  /// and "Opening hours unavailable" is shown instead of a potentially wrong
  /// day-of-week guess.
  final DateTime? visitDate;

  /// Called when the user updates the stop status (complete / missed / skipped).
  final Future<void> Function(ItineraryStopStatus status)? onStatusChange;

  /// Called when the user picks a target day in the "Move" flow.
  final Future<void> Function(int targetDay)? onMoveToDay;

  @override
  State<PoiBottomSheet> createState() => _PoiBottomSheetState();
}

class _PoiBottomSheetState extends State<PoiBottomSheet> {
  bool _isBusy = false;

  // ── helpers ─────────────────────────────────────────────────────────────────

  Place get _place => widget.savedPlace.place;

  ItineraryStopStatus get _status {
    final stop = widget.routeStop;
    if (stop == null) return ItineraryStopStatus.planned;
    return ItineraryStopStatus.fromString(stop.status);
  }

  /// Derives a human-readable opening-hours string for this stop's arrival time.
  ///
  /// Rules:
  /// - UNKNOWN → null → caller renders "Opening hours unavailable".
  /// - CLOSED  → 'Closed'  (not "Permanently closed" — we don't have that info).
  /// - KNOWN, no visitDate → null → cannot determine correct day → show unavailable.
  /// - KNOWN, visitDate available, no arrival time → null.
  /// - KNOWN, visitDate + arrival time → derive "Open until HH:mm" or
  ///   "Closed" / "Closed at scheduled time".
  String? get _openingHoursLabel {
    if (_place.openingHoursStatus == OpeningHoursStatus.unknown) return null;

    if (_place.openingHoursStatus == OpeningHoursStatus.closed) {
      // CLOSED means no open hours stored — not confirmed permanently out-of-business.
      return 'Closed';
    }

    // KNOWN — need both a calendar date and an arrival time to safely evaluate.
    final date = widget.visitDate;
    if (date == null) {
      // Without the actual date we cannot safely pick the correct weekday.
      return null;
    }

    final arrivalStr = widget.routeStop?.plannedArrivalTime;
    if (arrivalStr == null) return null;

    final parts = arrivalStr.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]) ?? -1;
    final minute = int.tryParse(parts[1]) ?? -1;
    if (hour < 0 || minute < 0) return null;

    // Build a DateTime on the correct calendar date but with the visit hour/min.
    final atArrival = DateTime(date.year, date.month, date.day, hour, minute);
    final intervals = _place.getIntervalsForDay(atArrival);

    if (intervals.isEmpty) return 'Closed at scheduled time';

    // Check all intervals — correctly handles split hours (e.g. 09-12, 14-22).
    for (final interval in intervals) {
      if (interval.containsTime(hour, minute)) {
        final closeStr = _stripSeconds(interval.close);
        // Format as 12h for readability: "Open until 5:00 PM"
        return 'Open until ${_format12h(closeStr)}';
      }
    }
    return 'Closed at scheduled time';
  }

  static String _stripSeconds(String t) {
    final p = t.split(':');
    return p.length >= 2 ? '${p[0]}:${p[1]}' : t;
  }

  /// Converts a 24h "HH:mm" string to 12h "H:MM AM/PM" format.
  static String _format12h(String hhmm) {
    final p = hhmm.split(':');
    if (p.length < 2) return hhmm;
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    final period = h < 12 ? 'AM' : 'PM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final mm = m.toString().padLeft(2, '0');
    return '$h12:$mm $period';
  }

  /// Formats a distance in km as a compact string.
  static String _formatDistance(double km) {
    if (km < 1.0) {
      return '${(km * 1000).round()} m';
    }
    return '${km.toStringAsFixed(1)} km';
  }

  // ── actions ─────────────────────────────────────────────────────────────────

  Future<void> _updateStatus(ItineraryStopStatus status) async {
    if (_isBusy || widget.onStatusChange == null) return;
    setState(() => _isBusy = true);
    try {
      await widget.onStatusChange!(status);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _isBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update status. Try again.')),
        );
      }
    }
  }

  Future<void> _launchGoogleMaps({required bool directions}) async {
    final lat = _place.latitude;
    final lng = _place.longitude;
    final name = _place.name;

    // Use Uri constructor so all query parameter values are correctly encoded,
    // handling spaces, &, apostrophes, and non-ASCII characters in place names.
    final Uri uri;
    if (directions) {
      uri = Uri.https(
        'www.google.com',
        '/maps/dir/',
        {
          'api': '1',
          'destination': '$lat,$lng',
          'destination_place_id': '', // empty — we don't have a GPlaces ID
        }..removeWhere((k, v) => v.isEmpty),
      );
    } else {
      // "More details" — include name so Google Maps shows the correct POI.
      uri = Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': '$name $lat,$lng',
      });
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')),
        );
      }
    }
  }

  Future<void> _showMoveDayPicker() async {
    if (widget.availableDays.isEmpty || widget.onMoveToDay == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other days available to move this place to.'),
        ),
      );
      return;
    }

    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MoveDayPicker(
        availableDays: widget.availableDays,
        placeName: _place.name,
      ),
    );

    if (picked == null || !mounted) return;
    if (_isBusy) return;

    setState(() => _isBusy = true);
    try {
      await widget.onMoveToDay!(picked);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _isBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("This place doesn't fit into that day. Try another."),
          ),
        );
      }
    }
  }

  // ── build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => Theme(
    data: YCStyle.theme(context),
    child: Builder(builder: _buildSheet),
  );

  Widget _buildSheet(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Center(
                child: Container(
                  key: const Key('poi_drag_handle'),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildInfoRows(),
                    if (!widget.isStartLocation) ...[
                      const SizedBox(height: 16),
                      _buildStatusBadge(),
                      const SizedBox(height: 20),
                      _buildActions(),
                    ] else
                      const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final stop = widget.routeStop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category chip
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.tealLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.place_rounded,
                    size: 12,
                    color: AppColors.teal,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _place.category,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (stop != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Day ${stop.dayNumber} · Stop ${stop.visitOrder}',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        // Place name
        Text(_place.name, style: AppTextStyles.sectionTitle),
      ],
    );
  }

  Widget _buildInfoRows() {
    final stop = widget.routeStop;
    final rows = <Widget>[];

    // Scheduled time window
    if (stop?.formattedTimeWindow != null) {
      rows.add(
        _InfoRow(
          key: const Key('poi_schedule_row'),
          icon: Icons.schedule_rounded,
          label: stop!.formattedTimeWindow!,
          color: AppColors.teal,
        ),
      );
    }

    // Visit duration
    if (stop != null) {
      rows.add(
        _InfoRow(
          key: const Key('poi_duration_row'),
          icon: Icons.timer_outlined,
          label: '${stop.visitDurationMinutes} min visit',
        ),
      );
    }

    // ── Travel info: from PREVIOUS stop → this stop ──────────────────────────
    // travelTimeMinutes and distanceFromPrevious on the current stop describe
    // the arriving leg. We omit this row for:
    //   - the first stop in a day (visitOrder == 1, no previous stop)
    //   - when both values are zero (no data)
    if (stop != null &&
        stop.visitOrder > 1 &&
        (stop.travelTimeMinutes > 0 || stop.distanceFromPrevious > 0)) {
      final timePart = stop.travelTimeMinutes > 0
          ? '${stop.travelTimeMinutes} min'
          : null;
      final distPart = stop.distanceFromPrevious > 0
          ? _formatDistance(stop.distanceFromPrevious)
          : null;
      final travelLabel = [timePart, distPart].whereType<String>().join(' · ');

      if (travelLabel.isNotEmpty) {
        rows.add(
          _InfoRow(
            key: const Key('poi_travel_row'),
            icon: Icons.directions_car_outlined,
            label: 'From previous stop · $travelLabel',
          ),
        );
      }
    }

    // Opening hours
    final ohLabel = _openingHoursLabel;
    if (_place.openingHoursStatus == OpeningHoursStatus.unknown ||
        (_place.openingHoursStatus == OpeningHoursStatus.known &&
            ohLabel == null)) {
      // UNKNOWN or KNOWN-without-date: cannot safely claim open/closed
      rows.add(
        _InfoRow(
          key: const Key('poi_opening_hours_row'),
          icon: Icons.access_time_rounded,
          label: 'Opening hours unavailable',
          color: AppColors.textTertiary,
        ),
      );
    } else if (_place.openingHoursStatus == OpeningHoursStatus.closed) {
      rows.add(
        _InfoRow(
          key: const Key('poi_opening_hours_row'),
          icon: Icons.access_time_rounded,
          label: 'Closed',
          color: AppColors.error,
        ),
      );
    } else if (ohLabel != null) {
      final isOpen = ohLabel.startsWith('Open until');
      rows.add(
        _InfoRow(
          key: const Key('poi_opening_hours_row'),
          icon: Icons.access_time_rounded,
          label: ohLabel,
          color: isOpen ? AppColors.success : AppColors.error,
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows.expand((w) => [w, const SizedBox(height: 10)]).toList()
        ..removeLast(),
    );
  }

  Widget _buildStatusBadge() {
    final (label, bg, fg) = switch (_status) {
      ItineraryStopStatus.planned => (
        'Planned',
        AppColors.surfaceSoft,
        AppColors.textSecondary,
      ),
      ItineraryStopStatus.completed => (
        'Visited',
        const Color(0xFFE6F5F0),
        AppColors.success,
      ),
      ItineraryStopStatus.missed => (
        'Missed',
        const Color(0xFFFFF4E5),
        const Color(0xFFB45309),
      ),
      ItineraryStopStatus.skipped => (
        'Skipped',
        AppColors.surfaceSoft,
        AppColors.textTertiary,
      ),
    };

    return Row(
      children: [
        Container(
          key: const Key('poi_status_badge'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    if (_isBusy) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary status action
        _buildPrimaryAction(),
        const SizedBox(height: 10),
        // Directions + More details
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('poi_directions_button'),
                onPressed: () => _launchGoogleMaps(directions: true),
                icon: const Icon(Icons.directions_outlined, size: 18),
                label: const Text('Directions'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.teal,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('poi_more_details_button'),
                onPressed: () => _launchGoogleMaps(directions: false),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('More details'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPrimaryAction() {
    switch (_status) {
      case ItineraryStopStatus.planned:
        return _StatusActionMenu(
          onMarkVisited: () => _updateStatus(ItineraryStopStatus.completed),
          onCouldntVisit: () => _updateStatus(ItineraryStopStatus.missed),
          onSkip: () => _updateStatus(ItineraryStopStatus.skipped),
          onMove: _showMoveDayPicker,
        );

      case ItineraryStopStatus.missed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              key: const Key('poi_move_day_button'),
              onPressed: _showMoveDayPicker,
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
              label: const Text('Move to Another Day'),
              style: FilledButton.styleFrom(
                backgroundColor: YCStyle.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('poi_skip_button'),
              onPressed: () => _updateStatus(ItineraryStopStatus.skipped),
              child: const Text('Skip'),
            ),
          ],
        );

      case ItineraryStopStatus.skipped:
      case ItineraryStopStatus.completed:
        return const SizedBox.shrink();
    }
  }
}

// ── _StatusActionMenu ──────────────────────────────────────────────────────────

class _StatusActionMenu extends StatelessWidget {
  const _StatusActionMenu({
    required this.onMarkVisited,
    required this.onCouldntVisit,
    required this.onSkip,
    required this.onMove,
  });

  final VoidCallback onMarkVisited;
  final VoidCallback onCouldntVisit;
  final VoidCallback onSkip;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('poi_mark_visited_button'),
          onPressed: onMarkVisited,
          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: const Text('Mark Visited'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('poi_couldnt_visit_button'),
                onPressed: onCouldntVisit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB45309),
                  side: const BorderSide(color: Color(0xFFB45309)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text("Couldn't Visit"),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const Key('poi_skip_button'),
                onPressed: onSkip,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text('Skip'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('poi_move_day_button'),
          onPressed: onMove,
          icon: const Icon(Icons.calendar_today_rounded, size: 18),
          label: const Text('Move to Another Day'),
        ),
      ],
    );
  }
}

// ── _MoveDayPicker ─────────────────────────────────────────────────────────────

class _MoveDayPicker extends StatelessWidget {
  const _MoveDayPicker({required this.availableDays, required this.placeName});

  final List<int> availableDays;
  final String placeName;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('poi_move_day_picker'),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Move to another day', style: AppTextStyles.cardTitle),
                const SizedBox(height: 4),
                Text(
                  placeName,
                  style: AppTextStyles.bodyMuted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                ...availableDays.map(
                  (day) => InkWell(
                    key: Key('poi_move_day_option_$day'),
                    onTap: () => Navigator.of(context).pop(day),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.tealLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$day',
                              style: AppTextStyles.label.copyWith(
                                color: AppColors.teal,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('Day $day', style: AppTextStyles.label),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── _InfoRow ───────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.textSecondary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: effectiveColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMuted.copyWith(color: effectiveColor),
          ),
        ),
      ],
    );
  }
}
