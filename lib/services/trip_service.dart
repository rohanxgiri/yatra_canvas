import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/trip_start_location.dart';

class TripService {
  TripService({http.Client? client, String baseUrl = ApiConfig.baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), '');

  static const _timeout = Duration(seconds: 15);
  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<TripStartLocation> updateStartLocation(
    String tripId, {
    required TripStartLocationType type,
    String? name,
    double? latitude,
    double? longitude,
    String? provider,
    String? providerPlaceId,
  }) async {
    final encodedTripId = Uri.encodeComponent(tripId.trim());
    final response = await _client
        .patch(
          Uri.parse('$_baseUrl/trips/$encodedTripId/start-location'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'start_location_type': type.apiValue,
            'start_location_name': name,
            'start_latitude': latitude,
            'start_longitude': longitude,
            'start_location_provider': provider,
            'start_location_provider_place_id': providerPlaceId,
          }),
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw TripServiceException(_errorMessage(response));
    }
    try {
      return TripStartLocation.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on Object catch (error) {
      throw TripServiceException('Trip start location was invalid.', error);
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
    return 'Could not save the trip start (${response.statusCode}).';
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class TripServiceException implements Exception {
  const TripServiceException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => message;
}
