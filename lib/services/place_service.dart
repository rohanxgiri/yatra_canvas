import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/place.dart';

class PlaceService {
  PlaceService({http.Client? client, String baseUrl = ApiConfig.baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), '');

  static const Duration _requestTimeout = Duration(seconds: 15);

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<List<Place>> discoverPlaces(
    String cityId,
    PlaceCategory category,
  ) async {
    final normalizedCityId = cityId.trim();
    if (normalizedCityId.isEmpty) {
      throw const PlaceServiceException('Select a saved city first.');
    }

    final encodedCityId = Uri.encodeComponent(normalizedCityId);
    final uri = Uri.parse('$_baseUrl/cities/$encodedCityId/discover-places')
        .replace(queryParameters: {'category': category.apiValue});
    final response = await _client.get(uri).timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw PlaceServiceException(_errorMessage(response));
    }

    try {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((item) => Place.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } on FormatException catch (error) {
      throw PlaceServiceException(
        'The nearby places response was invalid.',
        error,
      );
    } on TypeError catch (error) {
      throw PlaceServiceException(
        'The nearby places response was invalid.',
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
    return 'Place discovery failed (${response.statusCode}). Please try again.';
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class PlaceServiceException implements Exception {
  const PlaceServiceException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
