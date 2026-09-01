import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/optimized_route.dart';

class RouteOptimizationService {
  RouteOptimizationService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceFirst(RegExp(r'/$'), '');

  static const Duration _requestTimeout = Duration(seconds: 45);

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<OptimizedRoute> optimizeRoute(String tripId) async {
    final normalizedTripId = tripId.trim();
    if (normalizedTripId.isEmpty) {
      throw const RouteOptimizationServiceException(
        'Save the trip before optimizing its route.',
      );
    }
    final response = await _client
        .post(
          Uri.parse(
            '$_baseUrl/trips/${Uri.encodeComponent(normalizedTripId)}/optimize-route',
          ),
        )
        .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw RouteOptimizationServiceException(_errorMessage(response));
    }
    try {
      return OptimizedRoute.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on FormatException catch (error) {
      throw RouteOptimizationServiceException(
        'The optimized route response was invalid.',
        error,
      );
    } on TypeError catch (error) {
      throw RouteOptimizationServiceException(
        'The optimized route response was invalid.',
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
    return 'Route optimization failed (${response.statusCode}).';
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class RouteOptimizationServiceException implements Exception {
  const RouteOptimizationServiceException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
