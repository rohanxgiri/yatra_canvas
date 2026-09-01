import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/city.dart';
import '../models/city_suggestion.dart';

class CityService {
  CityService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceFirst(RegExp(r'/$'), '');

  static const Duration _requestTimeout = Duration(seconds: 10);

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<List<City>> searchCities(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) return const [];

    final uri = Uri.parse('$_baseUrl/cities/search')
        .replace(queryParameters: {'query': normalizedQuery});
    final response = await _client.get(uri).timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw CityServiceException(_errorMessage(response));
    }

    try {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((item) => City.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } on FormatException catch (error) {
      throw CityServiceException(
        'The city search response was invalid.',
        error,
      );
    } on TypeError catch (error) {
      throw CityServiceException(
        'The city search response was invalid.',
        error,
      );
    }
  }

  Future<List<CitySuggestion>> autocompleteCities(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 3) return const [];

    final uri = Uri.parse('$_baseUrl/locations/autocomplete').replace(
      queryParameters: {
        'query': normalizedQuery,
        'type': 'city',
        'country_code': 'in',
        'limit': '5',
      },
    );
    final response = await _client.get(uri).timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw CityServiceException(_errorMessage(response));
    }

    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final data = payload['results'] as List<dynamic>;
      return data
          .map((item) => item as Map<String, dynamic>)
          .where((item) => item['result_type'] == 'city')
          .map(CitySuggestion.fromGeoapifyJson)
          .toList(growable: false);
    } on FormatException catch (error) {
      throw CityServiceException(
        'The external city search response was invalid.',
        error,
      );
    } on TypeError catch (error) {
      throw CityServiceException(
        'The external city search response was invalid.',
        error,
      );
    }
  }

  Future<City> getPlaceDetails(String googlePlaceId) async {
    final normalizedPlaceId = googlePlaceId.trim();
    if (normalizedPlaceId.isEmpty) {
      throw const CityServiceException('Google Place ID must not be blank.');
    }

    final encodedPlaceId = Uri.encodeComponent(normalizedPlaceId);
    final uri = Uri.parse('$_baseUrl/cities/place-details/$encodedPlaceId');
    final response = await _client.get(uri).timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw CityServiceException(_errorMessage(response));
    }

    try {
      return City.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } on FormatException catch (error) {
      throw CityServiceException(
        'The city details response was invalid.',
        error,
      );
    } on TypeError catch (error) {
      throw CityServiceException(
        'The city details response was invalid.',
        error,
      );
    }
  }

  Future<City> resolveCity(City city) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/cities/resolve'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(city.toResolveJson()),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw CityServiceException(_errorMessage(response));
    }

    try {
      return City.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } on FormatException catch (error) {
      throw CityServiceException(
        'The city resolve response was invalid.',
        error,
      );
    } on TypeError catch (error) {
      throw CityServiceException(
        'The city resolve response was invalid.',
        error,
      );
    }
  }

  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = body['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    } on Object {
      // Use the stable fallback below when the backend response is not JSON.
    }
    return 'City request failed (${response.statusCode}). Please try again.';
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class CityServiceException implements Exception {
  const CityServiceException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
