import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'local_first_client.dart';

import '../config/api_config.dart';
import '../models/city.dart';
import '../models/city_suggestion.dart';

class CityService {
  CityService({http.Client? client, String? baseUrl})
    : _client = client ?? LocalFirstClient(),
      _ownsClient = client == null,
      _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceFirst(RegExp(r'/$'), '');

  static const Duration _requestTimeout = Duration(seconds: 10);
  // Destination search is the first remote read after launch. Render Free can
  // take about a minute to start; existing results remain selectable meanwhile.
  static const Duration _searchTimeout = Duration(seconds: 65);

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<List<City>> searchCities(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) return const [];

    final uri = Uri.parse('$_baseUrl/cities/search')
        .replace(queryParameters: {'query': normalizedQuery});
    final response = await _search(uri);

    if (response.statusCode != 200) {
      throw CityServiceException(_errorMessage(response));
    }

    try {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((item) => City.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } on FormatException catch (error) {
      throw CityServiceException(
        'The city search response was invalid.',
        error,
      );
    } on TypeError catch (error) {
      throw CityServiceException(
        'The city search response was invalid.',
        error,
      );
    }
  }

  Future<List<CitySuggestion>> autocompleteCities(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 3) return const [];

    final uri = Uri.parse('$_baseUrl/cities/autocomplete')
        .replace(queryParameters: {'query': normalizedQuery});
    final response = await _search(uri, timeout: _requestTimeout);

    if (response.statusCode != 200) {
      throw CityServiceException(_errorMessage(response));
    }

    try {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((item) => item as Map<String, dynamic>)
          .map(CitySuggestion.fromJson)
          .toList(growable: false);
    } on FormatException catch (error) {
      throw CityServiceException(
        'The external city search response was invalid.',
        error,
      );
    } on TypeError catch (error) {
      throw CityServiceException(
        'The external city search response was invalid.',
        error,
      );
    }
  }

  Future<City> getPlaceDetails(String googlePlaceId) async {
    final normalizedPlaceId = googlePlaceId.trim();
    if (normalizedPlaceId.isEmpty) {
      throw const CityServiceException('Google Place ID must not be blank.');
    }

    final encodedPlaceId = Uri.encodeComponent(normalizedPlaceId);
    final uri = Uri.parse('$_baseUrl/cities/place-details/$encodedPlaceId');
    final response = await _client.get(uri).timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw CityServiceException(_errorMessage(response));
    }

    try {
      return City.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } on FormatException catch (error) {
      throw CityServiceException(
        'The city details response was invalid.',
        error,
      );
    } on TypeError catch (error) {
      throw CityServiceException(
        'The city details response was invalid.',
        error,
      );
    }
  }

  Future<City> resolveCity(City city) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/cities/resolve'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(city.toResolveJson()),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw CityServiceException(_errorMessage(response));
    }

    try {
      return City.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } on FormatException catch (error) {
      throw CityServiceException(
        'The city resolve response was invalid.',
        error,
      );
    } on TypeError catch (error) {
      throw CityServiceException(
        'The city resolve response was invalid.',
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
      // Use the stable fallback below when the backend response is not JSON.
    }
    return 'City request failed (${response.statusCode}). Please try again.';
  }

  Future<http.Response> _search(Uri uri, {Duration? timeout}) async {
    final abort = Completer<void>();
    try {
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      );
      return await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(timeout ?? _searchTimeout);
    } on TimeoutException catch (error) {
      throw CityServiceException(
        'The server is taking longer to respond. Please retry shortly; prepared cities remain available offline.',
        error,
      );
    } on http.ClientException catch (error) {
      throw CityServiceException(
        'Could not load city suggestions. Check your connection and retry.',
        error,
      );
    } finally {
      // Cancel pending network I/O and prevent a late automatic retry after the
      // caller's timeout. Local pack reads finish independently of transport.
      if (!abort.isCompleted) abort.complete();
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class CityServiceException implements Exception {
  const CityServiceException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
