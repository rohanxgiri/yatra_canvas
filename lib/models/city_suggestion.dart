import 'city.dart';

enum CitySuggestionSource { local, geoapify }

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
      providerPlaceId: city.providerPlaceId,
      city: city,
    );
  }

  factory CitySuggestion.fromJson(Map<String, dynamic> json) {
    return CitySuggestion(
      name: json['name'] as String,
      description: json['description'] as String,
      source: CitySuggestionSource.geoapify,
      providerPlaceId: json['provider_place_id'] as String,
    );
  }
}
