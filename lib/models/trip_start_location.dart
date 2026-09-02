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
    required this.provider,
    required this.providerPlaceId,
    required this.name,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    required this.countryCode,
    required this.resultType,
    this.city,
    this.state,
  });

  final String provider;
  final String providerPlaceId;
  final String name;
  final String formattedAddress;
  final double latitude;
  final double longitude;
  final String? city;
  final String? state;
  final String countryCode;
  final String resultType;

  factory LocationSuggestion.fromJson(Map<String, dynamic> json) {
    return LocationSuggestion(
      provider: json['provider'] as String,
      providerPlaceId: json['provider_place_id'] as String,
      name: json['name'] as String,
      formattedAddress: json['formatted_address'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      city: json['city'] as String?,
      state: json['state'] as String?,
      countryCode: json['country_code'] as String,
      resultType: json['result_type'] as String,
    );
  }
}

class LocationDetails {
  const LocationDetails({
    required this.providerPlaceId,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String providerPlaceId;
  final String name;
  final double latitude;
  final double longitude;

  factory LocationDetails.fromJson(Map<String, dynamic> json) {
    return LocationDetails(
      providerPlaceId: json['provider_place_id'] as String? ?? json['google_place_id'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'provider_place_id': providerPlaceId,
    };
  }
}

class TripStartLocation {
  const TripStartLocation({
    required this.tripId,
    required this.type,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.provider,
    this.providerPlaceId,
  });

  final String tripId;
  final TripStartLocationType type;
  final String name;
  final double latitude;
  final double longitude;
  final String? provider;
  final String? providerPlaceId;

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
      provider: json['start_location_provider'] as String?,
      providerPlaceId: json['start_location_provider_place_id'] as String?,
    );
  }
}
