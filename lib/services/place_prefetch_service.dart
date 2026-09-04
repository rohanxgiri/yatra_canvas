import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/place.dart';

enum PrefetchStage {
  destinationConfirmed('destination_confirmed'),
  interestsConfirmed('interests_confirmed');

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

  static const Duration _timeout = Duration(seconds: 15);

  /// Fire a non-blocking background prefetch for a city.
  /// This method catches any network/server failure so user flow is never interrupted.
  Future<void> prefetchCity(
    String cityId, {
    required PrefetchStage stage,
    Iterable<PlaceCategory>? categories,
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

    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/places/prefetch'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        developer.log(
          'Prefetch succeeded for city $normalizedCityId (${stage.apiValue})',
          name: 'PlacePrefetchService',
        );
      } else {
        developer.log(
          'Prefetch returned status ${response.statusCode} for city $normalizedCityId',
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

  void close() {
    if (_ownsClient) _client.close();
  }
}
