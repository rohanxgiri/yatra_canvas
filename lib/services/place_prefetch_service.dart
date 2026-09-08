import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/place.dart';

enum PrefetchStage {
  destinationConfirmed('destination_confirmed'),
  datesConfirmed('dates_confirmed'),
  interestsConfirmed('interests_confirmed'),
  startLocationConfirmed('start_location_confirmed');

  const PrefetchStage(this.apiValue);
  final String apiValue;
}

class PlacePrefetchService {
  PlacePrefetchService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
  final Map<String, Future<void>> _inFlight = {};

  static final PlacePrefetchService shared = PlacePrefetchService();

  static const Duration _timeout = Duration(seconds: 15);

  /// Fire a non-blocking background prefetch for a city.
  /// This method catches any network/server failure so user flow is never interrupted.
  Future<void> prefetchCity(
    String cityId, {
    required PrefetchStage stage,
    Iterable<PlaceCategory>? categories,
    DateTime? startDate,
    DateTime? endDate,
    double? startLatitude,
    double? startLongitude,
  }) async {
    final normalizedCityId = cityId.trim();
    if (normalizedCityId.isEmpty) return;

    final payload = <String, dynamic>{
      'city_id': normalizedCityId,
      'stage': stage.apiValue,
    };
    if (categories != null && categories.isNotEmpty) {
      payload['categories'] = categories
          .toSet()
          .map((c) => c.apiValue)
          .toList(growable: false);
    }
    if (startDate != null) payload['start_date'] = _dateValue(startDate);
    if (endDate != null) payload['end_date'] = _dateValue(endDate);
    if (startLatitude != null) payload['start_latitude'] = startLatitude;
    if (startLongitude != null) payload['start_longitude'] = startLongitude;

    final categoryKey =
        categories?.toSet().map((category) => category.apiValue).toList() ??
        <String>[];
    categoryKey.sort();
    final requestKey =
        '$normalizedCityId:${stage.apiValue}:${categoryKey.join(',')}:'
        '${payload['start_date'] ?? ''}:${payload['end_date'] ?? ''}:'
        '${startLatitude ?? ''}:${startLongitude ?? ''}';
    final existing = _inFlight[requestKey];
    if (existing != null) {
      developer.log(
        '[PREFETCH] reused $requestKey',
        name: 'PlacePrefetchService',
      );
      return existing;
    }

    final request = _send(payload, normalizedCityId, stage);
    _inFlight[requestKey] = request;
    try {
      await request;
    } finally {
      if (identical(_inFlight[requestKey], request)) {
        _inFlight.remove(requestKey);
      }
    }
  }

  Future<void> _send(
    Map<String, dynamic> payload,
    String cityId,
    PrefetchStage stage,
  ) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/places/prefetch'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 202) {
        developer.log(
          '[PREFETCH] accepted city=$cityId stage=${stage.apiValue}',
          name: 'PlacePrefetchService',
        );
      } else {
        developer.log(
          '[PREFETCH] status=${response.statusCode} city=$cityId',
          name: 'PlacePrefetchService',
        );
      }
    } on Object catch (error) {
      // Fire-and-forget: background prefetch failure must never block trip creation.
      developer.log(
        'Prefetch ignored transient failure: $error',
        name: 'PlacePrefetchService',
      );
    }
  }

  String _dateValue(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  void close() {
    if (_ownsClient) _client.close();
  }
}
