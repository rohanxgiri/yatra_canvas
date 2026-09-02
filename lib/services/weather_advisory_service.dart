import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/weather_advisory.dart';

class WeatherAdvisoryService {
  WeatherAdvisoryService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceFirst(RegExp(r'/$'), '');

  static const Duration _requestTimeout = Duration(seconds: 15);

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<TripWeatherAdvisories?> getAdvisories(String tripId) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) return null;

    try {
      final uri = Uri.parse(
        '$_baseUrl/trips/${Uri.encodeComponent(normalizedTripId)}/weather-advisories',
      );
      final response = await _client.get(uri).timeout(_requestTimeout);
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return TripWeatherAdvisories.fromJson(body);
    } catch (_) {
      // Safe degradation: never let weather failure block the trip view
      return null;
    }
  }

  Future<List<PlaceAlternative>> getAlternatives(
    String tripId,
    int dayNumber,
    String condition,
  ) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) return const [];

    try {
      final uri = Uri.parse(
        '$_baseUrl/trips/${Uri.encodeComponent(normalizedTripId)}/weather-alternatives',
      ).replace(
        queryParameters: {
          'day_number': dayNumber.toString(),
          'condition': condition,
        },
      );
      final response = await _client.get(uri).timeout(_requestTimeout);
      if (response.statusCode != 200) return const [];

      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .map((item) => PlaceAlternative.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<DayRearrangePreview?> previewRearrange(
    String tripId,
    int dayNumber,
    String condition, {
    List<String>? alternativePlaceIds,
  }) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) return null;

    try {
      final uri = Uri.parse(
        '$_baseUrl/trips/${Uri.encodeComponent(normalizedTripId)}/rearrange-preview',
      ).replace(queryParameters: {'condition': condition});

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'day_number': dayNumber,
              'alternative_place_ids': alternativePlaceIds ?? [],
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return DayRearrangePreview.fromJson(body);
    } catch (_) {
      return null;
    }
  }

  Future<bool> applyAdjustment(
    String tripId,
    int dayNumber,
    List<String> placeIds,
  ) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty || placeIds.isEmpty) return false;

    try {
      final uri = Uri.parse(
        '$_baseUrl/trips/${Uri.encodeComponent(normalizedTripId)}/apply-itinerary-adjustment',
      );
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'day_number': dayNumber,
              'place_ids': placeIds,
            }),
          )
          .timeout(_requestTimeout);

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> ignoreWeather(String tripId) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) return false;

    try {
      final uri = Uri.parse(
        '$_baseUrl/trips/${Uri.encodeComponent(normalizedTripId)}/ignore-weather',
      );
      final response = await _client.post(uri).timeout(_requestTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
