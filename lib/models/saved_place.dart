import 'place.dart';

enum AssignmentMode {
  auto('AUTO'),
  locked('LOCKED');

  const AssignmentMode(this.value);

  final String value;

  static AssignmentMode fromJson(String? value) {
    if (value == null) return AssignmentMode.auto;
    switch (value.toUpperCase()) {
      case 'LOCKED':
        return AssignmentMode.locked;
      case 'AUTO':
      default:
        return AssignmentMode.auto;
    }
  }

  String toJson() => value;
}

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
    this.assignmentMode = AssignmentMode.auto,
    this.assignedDayId,
    this.notes,
  });

  final String id;
  final String tripId;
  final String placeId;
  final int customOrder;
  final int priority;
  final bool isLocked;
  final bool mustVisit;
  final AssignmentMode assignmentMode;
  final String? assignedDayId;
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
      assignmentMode: AssignmentMode.fromJson(
        json['assignment_mode'] as String?,
      ),
      assignedDayId: json['assigned_day_id'] as String?,
      notes: json['notes'] as String?,
      place: Place.fromJson(json['place'] as Map<String, dynamic>),
    );
  }

  SavedPlace copyWith({
    String? id,
    String? tripId,
    String? placeId,
    int? customOrder,
    int? priority,
    bool? isLocked,
    bool? mustVisit,
    AssignmentMode? assignmentMode,
    String? assignedDayId,
    bool clearAssignedDay = false,
    String? notes,
    Place? place,
  }) {
    return SavedPlace(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      placeId: placeId ?? this.placeId,
      customOrder: customOrder ?? this.customOrder,
      priority: priority ?? this.priority,
      isLocked: isLocked ?? this.isLocked,
      mustVisit: mustVisit ?? this.mustVisit,
      assignmentMode: assignmentMode ?? this.assignmentMode,
      assignedDayId:
          clearAssignedDay ? null : (assignedDayId ?? this.assignedDayId),
      notes: notes ?? this.notes,
      place: place ?? this.place,
    );
  }
}
