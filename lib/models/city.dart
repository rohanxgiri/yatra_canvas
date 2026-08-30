class City {
  const City({
    this.id,
    required this.name,
    required this.country,
    required this.latitude,
    required this.longitude,
    this.state,
    this.googlePlaceId,
  });

  /// Null only for normalized Google details before `/cities/resolve` saves it.
  final String? id;
  final String name;
  final String? state;
  final String country;
  final double latitude;
  final double longitude;
  final String? googlePlaceId;

  String get locationLabel {
    final parts = <String>[
      if (state != null && state!.isNotEmpty) state!,
      country,
    ];
    return parts.join(', ');
  }

  String get displayName => '$name, $locationLabel';

  factory City.fromJson(Map<String, dynamic> json) {
    return City(
      id: json['id'] as String?,
      name: json['name'] as String,
      state: json['state'] as String?,
      country: json['country'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      googlePlaceId: json['google_place_id'] as String?,
    );
  }

  Map<String, Object?> toResolveJson() {
    return {
      'name': name,
      'state': state,
      'country': country,
      'latitude': latitude,
      'longitude': longitude,
      'google_place_id': googlePlaceId,
    };
  }
}
