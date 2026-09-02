import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/place.dart';
import '../models/recommendation.dart';

class RecommendationService {
  RecommendationService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceFirst(RegExp(r'/$'), '');

  static const Duration _requestTimeout = Duration(seconds: 45);

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<List<Recommendation>> getRecommendations(
    String cityId,
    Iterable<PlaceCategory> categories, {
    int limit = 30,
    String? tripId,
  }) async {
    final normalizedCityId = cityId.trim();
    final uniqueCategories = categories.toSet().toList(growable: false);
    if (normalizedCityId.isEmpty) {
      throw const RecommendationServiceException('Select a saved city first.');
    }
    if (uniqueCategories.isEmpty) {
      throw const RecommendationServiceException(
        'Select at least one interest.',
      );
    }

    final encodedCityId = Uri.encodeComponent(normalizedCityId);
    final payload = <String, dynamic>{
      'categories': uniqueCategories
          .map((category) => category.apiValue)
          .toList(growable: false),
      'limit': limit,
    };
    if (tripId != null && tripId.isNotEmpty) {
      payload['trip_id'] = tripId;
    }

    final response = await _client
        .post(
          Uri.parse('$_baseUrl/cities/$encodedCityId/recommendations'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw RecommendationServiceException(_errorMessage(response));
    }

    try {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((item) => Recommendation.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } on FormatException catch (error) {
      throw RecommendationServiceException(
        'The recommendations response was invalid.',
        error,
      );
    } on TypeError catch (error) {
      throw RecommendationServiceException(
        'The recommendations response was invalid.',
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
      // Fall through to a stable user-facing message.
    }
    return 'Recommendations failed (${response.statusCode}). Please try again.';
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class RecommendationServiceException implements Exception {
  const RecommendationServiceException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
