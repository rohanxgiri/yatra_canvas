class WeatherAdvisory {
  const WeatherAdvisory({
    required this.id,
    required this.dayNumber,
    required this.condition,
    required this.severity,
    required this.summary,
    this.affectedStart,
    this.affectedEnd,
    this.affectedPlaceIds = const [],
    this.affectedPlaceNames = const [],
    this.actions = const [],
  });

  final String id;
  final int dayNumber;
  final String condition;
  final String severity;
  final String summary;
  final DateTime? affectedStart;
  final DateTime? affectedEnd;
  final List<String> affectedPlaceIds;
  final List<String> affectedPlaceNames;
  final List<String> actions;

  factory WeatherAdvisory.fromJson(Map<String, dynamic> json) {
    return WeatherAdvisory(
      id: json['id'] as String,
      dayNumber: json['day_number'] as int,
      condition: json['condition'] as String,
      severity: json['severity'] as String,
      summary: json['summary'] as String,
      affectedStart: json['affected_start'] != null
          ? DateTime.tryParse(json['affected_start'] as String)
          : null,
      affectedEnd: json['affected_end'] != null
          ? DateTime.tryParse(json['affected_end'] as String)
          : null,
      affectedPlaceIds: (json['affected_place_ids'] as List<dynamic>? ?? [])
          .map((id) => id.toString())
          .toList(),
      affectedPlaceNames:
          (json['affected_place_names'] as List<dynamic>? ?? [])
              .map((name) => name.toString())
              .toList(),
      actions: (json['actions'] as List<dynamic>? ?? [])
          .map((a) => a.toString())
          .toList(),
    );
  }
}

class TripWeatherAdvisories {
  const TripWeatherAdvisories({
    required this.tripId,
    required this.status,
    this.advisories = const [],
  });

  final String tripId;
  final String status;
  final List<WeatherAdvisory> advisories;

  factory TripWeatherAdvisories.fromJson(Map<String, dynamic> json) {
    final rawAdvisories = json['advisories'] as List<dynamic>? ?? [];
    return TripWeatherAdvisories(
      tripId: json['trip_id'] as String,
      status: json['status'] as String? ?? 'ok',
      advisories: rawAdvisories
          .map((a) => WeatherAdvisory.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PlaceAlternative {
  const PlaceAlternative({
    required this.placeId,
    required this.name,
    required this.category,
    required this.reason,
    required this.environment,
  });

  final String placeId;
  final String name;
  final String category;
  final String reason;
  final String environment;

  factory PlaceAlternative.fromJson(Map<String, dynamic> json) {
    return PlaceAlternative(
      placeId: json['place_id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      reason: json['reason'] as String,
      environment: json['environment'] as String? ?? 'indoor',
    );
  }
}

class ProposedStop {
  const ProposedStop({
    required this.placeId,
    required this.name,
    required this.visitOrder,
    this.timeWindow,
    this.isAlternative = false,
    this.environment = 'unknown',
  });

  final String placeId;
  final String name;
  final int visitOrder;
  final String? timeWindow;
  final bool isAlternative;
  final String environment;

  factory ProposedStop.fromJson(Map<String, dynamic> json) {
    return ProposedStop(
      placeId: json['place_id'] as String,
      name: json['name'] as String,
      visitOrder: json['visit_order'] as int,
      timeWindow: json['time_window'] as String?,
      isAlternative: json['is_alternative'] as bool? ?? false,
      environment: json['environment'] as String? ?? 'unknown',
    );
  }
}

class DayRearrangePreview {
  const DayRearrangePreview({
    required this.tripId,
    required this.dayNumber,
    required this.explanation,
    this.originalPlaces = const [],
    this.proposedPlaces = const [],
  });

  final String tripId;
  final int dayNumber;
  final String explanation;
  final List<ProposedStop> originalPlaces;
  final List<ProposedStop> proposedPlaces;

  factory DayRearrangePreview.fromJson(Map<String, dynamic> json) {
    final rawOriginal = json['original_places'] as List<dynamic>? ?? [];
    final rawProposed = json['proposed_places'] as List<dynamic>? ?? [];
    return DayRearrangePreview(
      tripId: json['trip_id'] as String,
      dayNumber: json['day_number'] as int,
      explanation: json['explanation'] as String? ?? '',
      originalPlaces: rawOriginal
          .map((p) => ProposedStop.fromJson(p as Map<String, dynamic>))
          .toList(),
      proposedPlaces: rawProposed
          .map((p) => ProposedStop.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}
