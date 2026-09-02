class OptimizedRoutePlace {
  const OptimizedRoutePlace({
    required this.placeId,
    required this.name,
    required this.dayNumber,
    required this.visitOrder,
    required this.distanceFromPrevious,
    required this.travelTimeMinutes,
    this.plannedArrivalTime,
    this.plannedDepartureTime,
    this.visitDurationMinutes = 60,
    this.isOpeningHoursKnown = false,
  });

  final String placeId;
  final String name;
  final int dayNumber;
  final int visitOrder;
  final double distanceFromPrevious;
  final int travelTimeMinutes;
  final String? plannedArrivalTime;
  final String? plannedDepartureTime;
  final int visitDurationMinutes;
  final bool isOpeningHoursKnown;

  String? get formattedTimeWindow {
    if (plannedArrivalTime == null || plannedDepartureTime == null) {
      return null;
    }
    final arrival = _stripSeconds(plannedArrivalTime!);
    final departure = _stripSeconds(plannedDepartureTime!);
    return '$arrival – $departure';
  }

  static String _stripSeconds(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length >= 2) {
      return '${parts[0]}:${parts[1]}';
    }
    return timeStr;
  }

  factory OptimizedRoutePlace.fromJson(Map<String, dynamic> json) {
    return OptimizedRoutePlace(
      placeId: json['place_id'] as String,
      name: json['name'] as String,
      dayNumber: json['day_number'] as int,
      visitOrder: json['visit_order'] as int,
      distanceFromPrevious: (json['distance_from_previous'] as num).toDouble(),
      travelTimeMinutes: json['travel_time_minutes'] as int,
      plannedArrivalTime: json['planned_arrival_time'] as String?,
      plannedDepartureTime: json['planned_departure_time'] as String?,
      visitDurationMinutes: (json['visit_duration_minutes'] as num?)?.toInt() ?? 60,
      isOpeningHoursKnown: json['is_opening_hours_known'] as bool? ?? false,
    );
  }
}

class ItineraryBreak {
  const ItineraryBreak({
    required this.dayNumber,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.label,
  });

  final int dayNumber;
  final String startTime;
  final String endTime;
  final int durationMinutes;
  final String label;

  String get formattedTimeWindow {
    final start = OptimizedRoutePlace._stripSeconds(startTime);
    final end = OptimizedRoutePlace._stripSeconds(endTime);
    return '$start – $end';
  }

  factory ItineraryBreak.fromJson(Map<String, dynamic> json) {
    return ItineraryBreak(
      dayNumber: json['day_number'] as int,
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      durationMinutes: (json['duration_minutes'] as num).toInt(),
      label: json['label'] as String? ?? 'Midday Break',
    );
  }
}

class OptimizedRoute {
  const OptimizedRoute({
    required this.tripId,
    required this.places,
    required this.totalDistance,
    required this.totalTravelTimeMinutes,
    this.breaks = const [],
    this.conflicts = const [],
  });

  final String tripId;
  final List<OptimizedRoutePlace> places;
  final double totalDistance;
  final int totalTravelTimeMinutes;
  final List<ItineraryBreak> breaks;
  final List<String> conflicts;

  factory OptimizedRoute.fromJson(Map<String, dynamic> json) {
    final places = json['optimized_places'] as List<dynamic>;
    final breaksJson = json['breaks'] as List<dynamic>? ?? [];
    final conflictsJson = json['conflicts'] as List<dynamic>? ?? [];

    return OptimizedRoute(
      tripId: json['trip_id'] as String,
      places: places
          .map(
            (item) =>
                OptimizedRoutePlace.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      totalDistance: (json['total_distance'] as num).toDouble(),
      totalTravelTimeMinutes: json['total_travel_time_minutes'] as int,
      breaks: breaksJson
          .map((item) => ItineraryBreak.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      conflicts: conflictsJson.map((e) => e.toString()).toList(growable: false),
    );
  }
}
