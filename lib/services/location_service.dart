import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/trip_start_location.dart';

class LocationService {
  LocationService({http.Client? client, String baseUrl = ApiConfig.baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), '');

  static const _timeout = Duration(seconds: 15);
  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<List<LocationSuggestion>> autocomplete(
    String query, {
    required bool hotelOnly,
  }) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];
    final uri = Uri.parse('$_baseUrl/locations/autocomplete').replace(
      queryParameters: {
        'query': normalized,
        'kind': hotelOnly ? 'hotel' : 'custom',
      },
    );
    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw LocationServiceException(_errorMessage(response));
    }
    try {
      final values = jsonDecode(response.body) as List<dynamic>;
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

  Future<LocationDetails> getDetails(String googlePlaceId) async {
    final encoded = Uri.encodeComponent(googlePlaceId.trim());
    final response = await _client
        .get(Uri.parse('$_baseUrl/locations/place-details/$encoded'))
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw LocationServiceException(_errorMessage(response));
    }
    try {
      return LocationDetails.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on Object catch (error) {
      throw LocationServiceException('Location details were invalid.', error);
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
