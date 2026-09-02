import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/route_geometry.dart';

class RouteGeometryService {
  RouteGeometryService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceFirst(RegExp(r'/$'), '');

  static const Duration _requestTimeout = Duration(seconds: 30);

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<TripRouteGeometry> getRouteGeometry(
    String tripId, {
    int? dayNumber,
  }) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) {
      throw const RouteGeometryServiceException(
        'A valid trip ID is required to fetch route geometry.',
      );
    }

    final queryParams = <String, String>{};
    if (dayNumber != null) {
      queryParams['day_number'] = dayNumber.toString();
    }

    final uri = Uri.parse(
      '$_baseUrl/trips/${Uri.encodeComponent(normalizedTripId)}/route-geometry',
    ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    final response = await _client.get(uri).timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw RouteGeometryServiceException(_errorMessage(response));
    }

    try {
      return TripRouteGeometry.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on FormatException catch (error) {
      throw RouteGeometryServiceException(
        'The route geometry response was invalid.',
        error,
      );
    } on TypeError catch (error) {
      throw RouteGeometryServiceException(
        'The route geometry response format was unexpected.',
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
      // Fall through to a stable message.
    }
    return 'Failed to load route geometry (${response.statusCode}).';
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class RouteGeometryServiceException implements Exception {
  const RouteGeometryServiceException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
