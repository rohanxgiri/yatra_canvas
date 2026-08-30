import 'place.dart';

class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.tripId,
    required this.placeId,
    required this.customOrder,
    required this.priority,
    required this.isLocked,
    required this.mustVisit,
    required this.place,
    this.notes,
  });

  final String id;
  final String tripId;
  final String placeId;
  final int customOrder;
  final int priority;
  final bool isLocked;
  final bool mustVisit;
  final String? notes;
  final Place place;

  factory SavedPlace.fromJson(Map<String, dynamic> json) {
    return SavedPlace(
      id: json['id'] as String,
      tripId: json['trip_id'] as String,
      placeId: json['place_id'] as String,
      customOrder: json['custom_order'] as int,
      priority: json['priority'] as int? ?? 0,
      isLocked: json['is_locked'] as bool? ?? false,
      mustVisit: json['must_visit'] as bool? ?? false,
      notes: json['notes'] as String?,
      place: Place.fromJson(json['place'] as Map<String, dynamic>),
    );
  }
}
