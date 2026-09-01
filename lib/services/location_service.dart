import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/trip_start_location.dart';

class LocationService {
  LocationService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceFirst(RegExp(r'/$'), '');

  static const _timeout = Duration(seconds: 15);
  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<List<LocationSuggestion>> autocomplete(
    String query, {
    required bool hotelOnly,
    double? latitude,
    double? longitude,
  }) async {
    final normalized = query.trim();
    if (normalized.length < 3) return const [];
    final uri = Uri.parse('$_baseUrl/locations/autocomplete').replace(
      queryParameters: {
        'query': normalized,
        'type': 'amenity',
        'country_code': 'in',
        'limit': '5',
        if (latitude != null) 'latitude': '$latitude',
        if (longitude != null) 'longitude': '$longitude',
      },
    );
    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw LocationServiceException(_errorMessage(response));
    }
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final values = payload['results'] as List<dynamic>;
      return values
          .map(
            (item) => LocationSuggestion.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false);
    } on Object catch (error) {
      throw LocationServiceException(
        'Location suggestions were invalid.',
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
      // Fall through.
    }
    return 'Location request failed (${response.statusCode}).';
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class LocationServiceException implements Exception {
  const LocationServiceException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => message;
}
