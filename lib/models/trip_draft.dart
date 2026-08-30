import 'city.dart';
import 'trip_start_location.dart';

class DestinationOption {
  const DestinationOption({
    required this.name,
    required this.region,
    this.country = 'India',
    this.tags = const [],
  });

  final String name;
  final String region;
  final String country;
  final List<String> tags;

  String get locationLabel => region.isEmpty ? country : '$region, $country';
}

class TripDraft {
  TripDraft({
    this.tripId,
    this.destination,
    DateTime? startDate,
    DateTime? endDate,
    this.datesFlexible = false,
    this.durationDays = 2,
    this.arrivalMethod = 'Train',
    this.arrivalPoint = 'Ujjain Railway Station',
    this.arrivalLatitude,
    this.arrivalLongitude,
    this.startLocationType = TripStartLocationType.arrival,
    this.startLocationName,
    this.startLatitude,
    this.startLongitude,
    TimeOfDayValue? arrivalTime,
    Set<String>? purposes,
    this.travelPace = 'Balanced',
    this.budget = 'Chill',
    Set<String>? transportPreferences,
  }) : startDate = startDate ?? DateTime(2026, 8, 25),
       endDate = endDate ?? DateTime(2026, 8, 26),
       arrivalTime = arrivalTime ?? const TimeOfDayValue(hour: 8, minute: 30),
       purposes = purposes ?? {'Religious / Spiritual'},
       transportPreferences = transportPreferences ?? {'Walking', 'Auto / Cab'};

  String? tripId;
  City? destination;
  DateTime startDate;
  DateTime endDate;
  bool datesFlexible;
  int durationDays;
  String arrivalMethod;
  String arrivalPoint;
  double? arrivalLatitude;
  double? arrivalLongitude;
  TripStartLocationType startLocationType;
  String? startLocationName;
  double? startLatitude;
  double? startLongitude;
  TimeOfDayValue arrivalTime;
  Set<String> purposes;
  String travelPace;
  String budget;
  Set<String> transportPreferences;
}

class TimeOfDayValue {
  const TimeOfDayValue({required this.hour, required this.minute});

  final int hour;
  final int minute;
}
