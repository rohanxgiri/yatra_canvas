import 'city.dart';

enum CitySuggestionSource { local, google }

class CitySuggestion {
  const CitySuggestion({
    required this.name,
    required this.description,
    required this.source,
    required this.googlePlaceId,
    this.city,
  });

  final String name;
  final String description;
  final CitySuggestionSource source;
  final String? googlePlaceId;
  final City? city;

  bool get isExternal => source == CitySuggestionSource.google;

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
      googlePlaceId: city.googlePlaceId,
      city: city,
    );
  }

  factory CitySuggestion.fromGoogleJson(Map<String, dynamic> json) {
    return CitySuggestion(
      name: json['name'] as String,
      description: json['description'] as String,
      source: CitySuggestionSource.google,
      googlePlaceId: json['google_place_id'] as String,
    );
  }
}
