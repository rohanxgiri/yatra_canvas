enum DayType {
  fullDay('FULL_DAY'),
  halfDay('HALF_DAY'),
  rest('REST'),
  travel('TRAVEL');

  const DayType(this.apiValue);
  final String apiValue;

  static DayType fromJson(String value) {
    switch (value.toUpperCase().trim()) {
      case 'FULL_DAY':
        return DayType.fullDay;
      case 'HALF_DAY':
        return DayType.halfDay;
      case 'REST':
        return DayType.rest;
      case 'TRAVEL':
        return DayType.travel;
      default:
        return DayType.fullDay;
    }
  }

  String get label {
    switch (this) {
      case DayType.fullDay:
        return 'Full Day';
      case DayType.halfDay:
        return 'Half Day';
      case DayType.rest:
        return 'Rest Day';
      case DayType.travel:
        return 'Travel Day';
    }
  }
}

class TripDay {
  const TripDay({
    required this.id,
    required this.tripId,
    required this.dayNumber,
    required this.date,
    required this.dayType,
    this.startTime,
    this.endTime,
  });

  final String id;
  final String tripId;
  final int dayNumber;
  final DateTime date;
  final DayType dayType;
  final String? startTime;
  final String? endTime;

  factory TripDay.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final tripId = json['trip_id'] as String?;
    final dayNumber = (json['day_number'] as num?)?.toInt();
    final dateStr = json['date'] as String?;
    final dayTypeStr = json['day_type'] as String? ?? 'FULL_DAY';
    final startTime = json['start_time'] as String?;
    final endTime = json['end_time'] as String?;

    if (id == null || tripId == null || dayNumber == null || dateStr == null) {
      throw const FormatException('Missing required fields in TripDay JSON.');
    }

    return TripDay(
      id: id,
      tripId: tripId,
      dayNumber: dayNumber,
      date: DateTime.parse(dateStr),
      dayType: DayType.fromJson(dayTypeStr),
      startTime: startTime,
      endTime: endTime,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'trip_id': tripId,
    'day_number': dayNumber,
    'date':
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    'day_type': dayType.apiValue,
    if (startTime != null) 'start_time': startTime,
    if (endTime != null) 'end_time': endTime,
  };
}
