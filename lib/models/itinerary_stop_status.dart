import 'optimized_route.dart';

enum ItineraryStopStatus {
  planned,
  completed,
  missed,
  skipped;

  String toApiString() {
    switch (this) {
      case ItineraryStopStatus.planned:
        return 'PLANNED';
      case ItineraryStopStatus.completed:
        return 'COMPLETED';
      case ItineraryStopStatus.missed:
        return 'MISSED';
      case ItineraryStopStatus.skipped:
        return 'SKIPPED';
    }
  }

  static ItineraryStopStatus fromString(String value) {
    switch (value.toUpperCase().trim()) {
      case 'COMPLETED':
        return ItineraryStopStatus.completed;
      case 'MISSED':
        return ItineraryStopStatus.missed;
      case 'SKIPPED':
        return ItineraryStopStatus.skipped;
      case 'PLANNED':
      default:
        return ItineraryStopStatus.planned;
    }
  }
}

class MoveItineraryPlaceResponse {
  const MoveItineraryPlaceResponse({
    required this.success,
    this.reason,
    required this.tripId,
    required this.placeId,
    this.sourceDayNumber,
    this.targetDayNumber,
    this.sourceItinerary = const [],
    this.targetItinerary = const [],
    this.updatedItinerary,
  });

  final bool success;
  final String? reason;
  final String tripId;
  final String placeId;
  final int? sourceDayNumber;
  final int? targetDayNumber;
  final List<OptimizedRoutePlace> sourceItinerary;
  final List<OptimizedRoutePlace> targetItinerary;
  final OptimizedRoute? updatedItinerary;

  factory MoveItineraryPlaceResponse.fromJson(Map<String, dynamic> json) {
    final srcJson = json['source_itinerary'] as List<dynamic>? ?? [];
    final tgtJson = json['target_itinerary'] as List<dynamic>? ?? [];
    final updJson = json['updated_itinerary'] as Map<String, dynamic>?;

    return MoveItineraryPlaceResponse(
      success: json['success'] as bool? ?? false,
      reason: json['reason'] as String?,
      tripId: json['trip_id'] as String? ?? '',
      placeId: json['place_id'] as String? ?? '',
      sourceDayNumber: (json['source_day_number'] as num?)?.toInt(),
      targetDayNumber: (json['target_day_number'] as num?)?.toInt(),
      sourceItinerary: srcJson
          .map((e) => OptimizedRoutePlace.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      targetItinerary: tgtJson
          .map((e) => OptimizedRoutePlace.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      updatedItinerary:
          updJson != null ? OptimizedRoute.fromJson(updJson) : null,
    );
  }
}
