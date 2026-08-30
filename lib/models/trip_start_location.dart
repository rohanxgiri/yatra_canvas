enum TripStartLocationType { arrival, hotel, currentLocation, custom }

extension TripStartLocationTypeValue on TripStartLocationType {
  String get apiValue => switch (this) {
    TripStartLocationType.arrival => 'arrival',
    TripStartLocationType.hotel => 'hotel',
    TripStartLocationType.currentLocation => 'current_location',
    TripStartLocationType.custom => 'custom',
  };

  String get label => switch (this) {
    TripStartLocationType.arrival => 'Arrival point',
    TripStartLocationType.hotel => 'Hotel',
    TripStartLocationType.currentLocation => 'Current location',
    TripStartLocationType.custom => 'Choose another location',
  };
}

class LocationSuggestion {
  const LocationSuggestion({
    required this.googlePlaceId,
    required this.name,
    required this.description,
  });

  final String googlePlaceId;
  final String name;
  final String description;

  factory LocationSuggestion.fromJson(Map<String, dynamic> json) {
    return LocationSuggestion(
      googlePlaceId: json['google_place_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
    );
  }
}

class LocationDetails {
  const LocationDetails({
    required this.googlePlaceId,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String googlePlaceId;
  final String name;
  final double latitude;
  final double longitude;

  factory LocationDetails.fromJson(Map<String, dynamic> json) {
    return LocationDetails(
      googlePlaceId: json['google_place_id'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

class TripStartLocation {
  const TripStartLocation({
    required this.tripId,
    required this.type,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String tripId;
  final TripStartLocationType type;
  final String name;
  final double latitude;
  final double longitude;

  factory TripStartLocation.fromJson(Map<String, dynamic> json) {
    final value = json['start_location_type'] as String;
    return TripStartLocation(
      tripId: json['trip_id'] as String,
      type: TripStartLocationType.values.firstWhere(
        (type) => type.apiValue == value,
      ),
      name: json['start_location_name'] as String,
      latitude: (json['start_latitude'] as num).toDouble(),
      longitude: (json['start_longitude'] as num).toDouble(),
    );
  }
}
