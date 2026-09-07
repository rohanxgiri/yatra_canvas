import 'package:yatra_canvas/models/optimized_route.dart';

class MovedPlace {
  const MovedPlace({
    required this.placeId,
    required this.name,
    required this.fromDay,
    required this.toDay,
    this.fromTime,
    this.toTime,
  });

  final String placeId;
  final String name;
  final int fromDay;
  final int toDay;
  final String? fromTime;
  final String? toTime;

  String get moveDescription {
    final fromTimeStr = fromTime != null
        ? ' at ${_stripSeconds(fromTime!)}'
        : '';
    final toTimeStr = toTime != null ? ' at ${_stripSeconds(toTime!)}' : '';
    if (fromDay == toDay) {
      return 'Rescheduled from$fromTimeStr →$toTimeStr';
    }
    return 'Moved from Day $fromDay$fromTimeStr → Day $toDay$toTimeStr';
  }

  static String _stripSeconds(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length >= 2) {
      return '${parts[0]}:${parts[1]}';
    }
    return timeStr;
  }

  factory MovedPlace.fromJson(Map<String, dynamic> json) {
    return MovedPlace(
      placeId: json['place_id'] as String,
      name: json['name'] as String,
      fromDay: json['from_day'] as int,
      toDay: json['to_day'] as int,
      fromTime: json['from_time'] as String?,
      toTime: json['to_time'] as String?,
    );
  }
}

class TripReplanImpact {
  const TripReplanImpact({
    required this.tripId,
    required this.isStale,
    required this.requiresReplanPreview,
    required this.reasons,
    required this.summary,
  });

  final String tripId;
  final bool isStale;
  final bool requiresReplanPreview;
  final List<String> reasons;
  final String summary;

  factory TripReplanImpact.fromJson(Map<String, dynamic> json) {
    return TripReplanImpact(
      tripId: json['trip_id'] as String,
      isStale: json['is_stale'] as bool,
      requiresReplanPreview: json['requires_replan_preview'] as bool,
      reasons:
          (json['reasons'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      summary: json['summary'] as String? ?? '',
    );
  }
}

class TripReplanPreview {
  const TripReplanPreview({
    required this.tripId,
    required this.isStale,
    required this.summary,
    required this.addedPlaces,
    required this.removedPlaces,
    required this.movedPlaces,
    required this.travelTimeDeltaMinutes,
    required this.proposedItinerary,
    required this.breaks,
    required this.conflicts,
    this.unscheduledPlaces = const [],
  });

  final String tripId;
  final bool isStale;
  final String summary;
  final List<String> addedPlaces;
  final List<String> removedPlaces;
  final List<MovedPlace> movedPlaces;
  final int travelTimeDeltaMinutes;
  final List<OptimizedRoutePlace> proposedItinerary;
  final List<ItineraryBreak> breaks;
  final List<String> conflicts;
  final List<UnscheduledRoutePlace> unscheduledPlaces;

  factory TripReplanPreview.fromJson(Map<String, dynamic> json) {
    final added =
        (json['added_places'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList(growable: false) ??
        const [];
    final removed =
        (json['removed_places'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList(growable: false) ??
        const [];
    final movedJson = json['moved_places'] as List<dynamic>? ?? const [];
    final itinJson = json['proposed_itinerary'] as List<dynamic>? ?? const [];
    final breaksJson = json['breaks'] as List<dynamic>? ?? const [];
    final conflictsJson =
        (json['conflicts'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList(growable: false) ??
        const [];

    return TripReplanPreview(
      tripId: json['trip_id'] as String,
      isStale: json['is_stale'] as bool? ?? true,
      summary: json['summary'] as String? ?? '',
      addedPlaces: added,
      removedPlaces: removed,
      movedPlaces: movedJson
          .map((m) => MovedPlace.fromJson(m as Map<String, dynamic>))
          .toList(growable: false),
      travelTimeDeltaMinutes:
          (json['travel_time_delta_minutes'] as num?)?.toInt() ?? 0,
      proposedItinerary: itinJson
          .map((p) => OptimizedRoutePlace.fromJson(p as Map<String, dynamic>))
          .toList(growable: false),
      breaks: breaksJson
          .map((b) => ItineraryBreak.fromJson(b as Map<String, dynamic>))
          .toList(growable: false),
      conflicts: conflictsJson,
      unscheduledPlaces: (json['unscheduled_places'] as List<dynamic>? ?? [])
          .map((p) => UnscheduledRoutePlace.fromJson(p as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}
