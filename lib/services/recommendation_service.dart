import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/place.dart';
import '../models/recommendation.dart';
import 'request_correlation.dart';

enum RecommendationRefreshState {
  idle,
  queued,
  refreshing,
  refreshFailed;

  bool get isActive => this == queued || this == refreshing;

  static RecommendationRefreshState fromHeader(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'queued':
        return queued;
      case 'refreshing':
        return refreshing;
      case 'failed':
      case 'refresh_failed':
      case 'unavailable':
        return refreshFailed;
      default:
        return idle;
    }
  }
}

class RecommendationService {
  RecommendationService({
    http.Client? client,
    String? baseUrl,
    String? requestId,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _requestId = RequestCorrelation.resolve(requestId),
       _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceFirst(
         RegExp(r'/$'),
         '',
       );

  static const Duration _requestTimeout = Duration(seconds: 45);

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
  final String _requestId;
  String? _nextCursor;
  RecommendationRefreshState _lastRefreshState =
      RecommendationRefreshState.idle;
  Set<String> _lastStaleCategories = const {};

  String? get nextCursor => _nextCursor;
  RecommendationRefreshState get lastRefreshState => _lastRefreshState;
  Set<String> get lastStaleCategories => _lastStaleCategories;

  Future<List<Recommendation>> getRecommendations(
    String cityId,
    Iterable<PlaceCategory> categories, {
    int limit = 30,
    String? tripId,
    Iterable<String>? purposes,
    Iterable<String>? interests,
    PlaceCategory? categoryFilter,
    String? cursor,
  }) async {
    final normalizedCityId = cityId.trim();
    final uniqueCategories = categories.toSet().toList(growable: false);
    if (normalizedCityId.isEmpty) {
      throw const RecommendationServiceException('Select a saved city first.');
    }
    if (uniqueCategories.isEmpty && categoryFilter == null) {
      throw const RecommendationServiceException(
        'Select at least one interest.',
      );
    }

    final encodedCityId = Uri.encodeComponent(normalizedCityId);
    final payload = <String, dynamic>{
      'categories': (uniqueCategories.isEmpty && categoryFilter != null)
          ? [categoryFilter.apiValue]
          : uniqueCategories
                .map((category) => category.apiValue)
                .toList(growable: false),
      'limit': limit,
    };
    if (tripId != null && tripId.isNotEmpty) {
      payload['trip_id'] = tripId;
    }
    if (purposes != null && purposes.isNotEmpty) {
      payload['purposes'] = purposes.toList(growable: false);
    }
    if (interests != null && interests.isNotEmpty) {
      payload['interests'] = interests.toList(growable: false);
    }
    if (categoryFilter != null) {
      payload['category_filter'] = categoryFilter.apiValue;
    }
    if (cursor != null && cursor.isNotEmpty) {
      payload['cursor'] = cursor;
    }

    final response = await _client
        .post(
          Uri.parse('$_baseUrl/cities/$encodedCityId/recommendations'),
          headers: {
            'Content-Type': 'application/json',
            'X-Request-ID': _requestId,
          },
          body: jsonEncode(payload),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw RecommendationServiceException(_errorMessage(response));
    }
    _nextCursor = response.headers['x-next-cursor'];
    _lastRefreshState = RecommendationRefreshState.fromHeader(
      response.headers['x-refresh-state'],
    );
    _lastStaleCategories = (response.headers['x-stale-categories'] ?? '')
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

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
