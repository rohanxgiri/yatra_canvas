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
    this.startLocationProvider,
    this.startLocationProviderPlaceId,
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
  String? startLocationProvider;
  String? startLocationProviderPlaceId;
  TimeOfDayValue arrivalTime;
  Set<String> purposes;
  String travelPace;
  String budget;
  Set<String> transportPreferences;

  factory TripDraft.fromJson(Map<String, dynamic> json) {
    final tripId = json['trip_id'] as String?;
    final cityJson = json['city'];
    City? destination;
    if (cityJson is Map<String, dynamic>) {
      destination = City.fromJson(cityJson);
    } else if (json['city_id'] is String) {
      destination = City(
        id: json['city_id'] as String,
        name: '',
        country: 'India',
        latitude: 0,
        longitude: 0,
      );
    }

    final startDateStr = json['start_date'] as String?;
    final endDateStr = json['end_date'] as String?;
    final days = (json['days'] as num?)?.toInt() ?? 2;

    DateTime? startDate;
    DateTime? endDate;
    if (startDateStr != null) {
      startDate = DateTime.tryParse(startDateStr);
    }
    if (endDateStr != null) {
      endDate = DateTime.tryParse(endDateStr);
    } else if (startDate != null) {
      endDate = startDate.add(Duration(days: days - 1));
    }

    final startTypeStr = json['start_location_type'] as String?;
    final startLocationType = startTypeStr != null
        ? TripStartLocationType.values.firstWhere(
            (t) => t.apiValue == startTypeStr,
            orElse: () => TripStartLocationType.arrival,
          )
        : TripStartLocationType.arrival;

    final prefList = (json['preferences'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    const knownPaces = {'relaxed', 'balanced', 'packed'};
    const knownBudgets = {'saver', 'chill', 'boujee'};
    const knownTransports = {
      'walking',
      'public transport',
      'auto / cab',
      'own vehicle',
    };

    String travelPace = 'Balanced';
    String budget = 'Chill';
    final transportPrefs = <String>{};
    final purposes = <String>{};

    for (final pref in prefList) {
      final lower = pref.toLowerCase();
      if (knownPaces.contains(lower)) {
        travelPace = switch (lower) {
          'relaxed' => 'Relaxed',
          'packed' => 'Packed',
          _ => 'Balanced',
        };
      } else if (knownBudgets.contains(lower)) {
        budget = switch (lower) {
          'saver' => 'Saver',
          'boujee' => 'Boujee',
          _ => 'Chill',
        };
      } else if (knownTransports.contains(lower)) {
        transportPrefs.add(
          switch (lower) {
            'walking' => 'Walking',
            'public transport' => 'Public Transport',
            'auto / cab' => 'Auto / Cab',
            'own vehicle' => 'Own Vehicle',
            _ => pref,
          },
        );
      } else {
        purposes.add(pref);
      }
    }

    if (transportPrefs.isEmpty) {
      transportPrefs.addAll(['Walking', 'Auto / Cab']);
    }
    if (purposes.isEmpty) {
      purposes.add('Religious / Spiritual');
    }

    return TripDraft(
      tripId: tripId,
      destination: destination,
      startDate: startDate,
      endDate: endDate,
      durationDays: days,
      arrivalPoint: (json['arrival_place'] as String?) ?? 'Arrival point',
      arrivalLatitude: (json['arrival_latitude'] as num?)?.toDouble(),
      arrivalLongitude: (json['arrival_longitude'] as num?)?.toDouble(),
      startLocationType: startLocationType,
      startLocationName: json['start_location_name'] as String?,
      startLatitude: (json['start_latitude'] as num?)?.toDouble(),
      startLongitude: (json['start_longitude'] as num?)?.toDouble(),
      startLocationProvider: json['start_location_provider'] as String?,
      startLocationProviderPlaceId:
          json['start_location_provider_place_id'] as String?,
      purposes: purposes,
      travelPace: travelPace,
      budget: budget,
      transportPreferences: transportPrefs,
    );
  }
}

class TimeOfDayValue {
  const TimeOfDayValue({required this.hour, required this.minute});

  final int hour;
  final int minute;
}
