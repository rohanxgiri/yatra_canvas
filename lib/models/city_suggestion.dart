import 'city.dart';

enum CitySuggestionSource { local, geoapify, google }

class CitySuggestion {
  const CitySuggestion({
    required this.name,
    required this.description,
    required this.source,
    required this.providerPlaceId,
    this.city,
  });

  final String name;
  final String description;
  final CitySuggestionSource source;
  final String? providerPlaceId;
  final City? city;

  bool get isExternal => source != CitySuggestionSource.local;

  String? get attribution => switch (source) {
    CitySuggestionSource.geoapify => 'Geoapify • OpenStreetMap',
    CitySuggestionSource.google => 'Google Maps',
    CitySuggestionSource.local => null,
  };

  String get subtitle {
    final prefix = '$name,';
    if (description.toLowerCase().startsWith(prefix.toLowerCase())) {
      return description.substring(prefix.length).trim();
    }
    return description;
  }

  String get normalizedLocation =>
      description.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  factory CitySuggestion.local(City city) {
    return CitySuggestion(
      name: city.name,
      description: city.displayName,
      source: CitySuggestionSource.local,
      providerPlaceId: city.googlePlaceId,
      city: city,
    );
  }

  factory CitySuggestion.fromGeoapifyJson(Map<String, dynamic> json) {
    final resultType = json['result_type'] as String?;
    if (resultType != 'city') {
      throw const FormatException('Location result is not a city.');
    }
    final name = (json['city'] as String?)?.trim();
    final state = (json['state'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      throw const FormatException('City result is missing its name.');
    }
    final city = City(
      name: name,
      state: state == null || state.isEmpty ? null : state,
      country: 'India',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
    return CitySuggestion(
      name: city.name,
      description: city.displayName,
      source: CitySuggestionSource.geoapify,
      providerPlaceId: json['provider_place_id'] as String,
      city: city,
    );
  }

  factory CitySuggestion.fromGoogleJson(Map<String, dynamic> json) {
    return CitySuggestion(
      name: json['name'] as String,
      description: json['description'] as String,
      source: CitySuggestionSource.google,
      providerPlaceId: json['google_place_id'] as String,
    );
  }
}
