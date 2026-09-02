import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/optimized_route.dart';
import '../models/smart_replanning.dart';

class SmartReplanningException implements Exception {
  const SmartReplanningException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'SmartReplanningException: $message';
}

class SmartReplanningService {
  SmartReplanningService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceFirst(RegExp(r'/$'), '');

  static const Duration _requestTimeout = Duration(seconds: 45);

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<TripReplanImpact> getReplanImpact(String tripId) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) {
      throw const SmartReplanningException('Trip ID is required.');
    }
    final response = await _client
        .get(
          Uri.parse(
            '$_baseUrl/trips/${Uri.encodeComponent(normalizedTripId)}/replan-impact',
          ),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw SmartReplanningException(_errorMessage(response));
    }
    try {
      return TripReplanImpact.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (error) {
      throw SmartReplanningException('Failed to parse replan impact.', error);
    }
  }

  Future<TripReplanPreview> getReplanPreview(String tripId) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) {
      throw const SmartReplanningException('Trip ID is required.');
    }
    final response = await _client
        .post(
          Uri.parse(
            '$_baseUrl/trips/${Uri.encodeComponent(normalizedTripId)}/replan-preview',
          ),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw SmartReplanningException(_errorMessage(response));
    }
    try {
      return TripReplanPreview.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (error) {
      throw SmartReplanningException('Failed to parse replan preview.', error);
    }
  }

  Future<OptimizedRoute> applyReplan(String tripId) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) {
      throw const SmartReplanningException('Trip ID is required.');
    }
    final response = await _client
        .post(
          Uri.parse(
            '$_baseUrl/trips/${Uri.encodeComponent(normalizedTripId)}/replan-apply',
          ),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw SmartReplanningException(_errorMessage(response));
    }
    try {
      return OptimizedRoute.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (error) {
      throw SmartReplanningException('Failed to parse applied route.', error);
    }
  }

  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = body['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    } on Object {
      // Fallback below
    }
    return 'Re-planning request failed (${response.statusCode}).';
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
