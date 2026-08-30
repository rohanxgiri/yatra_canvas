import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/city.dart';

class CityService {
  CityService({http.Client? client, String baseUrl = ApiConfig.baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), '');

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

  Future<City> resolveCity(City city) async {
    if (city.googlePlaceId == null || city.googlePlaceId!.trim().isEmpty) {
      throw const CityServiceException(
        'This city is missing its Google Place ID and cannot be resolved.',
      );
    }

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
