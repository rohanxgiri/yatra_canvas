import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/saved_place.dart';

class SavedPlaceService {
  SavedPlaceService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceFirst(RegExp(r'/$'), '');

  static const Duration _requestTimeout = Duration(seconds: 15);

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<List<SavedPlace>> getSavedPlaces(String tripId) async {
    final response = await _client
        .get(_collectionUri(tripId))
        .timeout(_requestTimeout);
    return _decodeList(response);
  }

  Future<SavedPlace> addSavedPlace(
    String tripId,
    String placeId, {
    int? customOrder,
    int priority = 0,
    bool isLocked = false,
    bool mustVisit = false,
    String? notes,
  }) async {
    final response = await _client
        .post(
          _collectionUri(tripId),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'place_id': placeId,
            'custom_order': customOrder,
            'priority': priority,
            'is_locked': isLocked,
            'must_visit': mustVisit,
            'notes': notes,
          }),
        )
        .timeout(_requestTimeout);
    return _decodeOne(response, expectedStatus: 201);
  }

  Future<void> removeSavedPlace(String tripId, String placeId) async {
    final response = await _client
        .delete(_itemUri(tripId, placeId))
        .timeout(_requestTimeout);
    if (response.statusCode != 204) {
      throw SavedPlaceServiceException(
        _errorMessage(response),
        statusCode: response.statusCode,
      );
    }
  }

  Future<SavedPlace> updateNotes(
    String tripId,
    String placeId,
    String? notes,
  ) async {
    final response = await _client
        .patch(
          _itemUri(tripId, placeId),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'notes': notes}),
        )
        .timeout(_requestTimeout);
    return _decodeOne(response);
  }

  Future<SavedPlace> updateSettings(
    String tripId,
    String placeId, {
    required int priority,
    required bool isLocked,
    required bool mustVisit,
    required int customOrder,
    String? notes,
  }) async {
    final response = await _client
        .patch(
          _itemUri(tripId, placeId),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'notes': notes,
            'priority': priority,
            'is_locked': isLocked,
            'must_visit': mustVisit,
            'custom_order': customOrder,
          }),
        )
        .timeout(_requestTimeout);
    return _decodeOne(response);
  }

  Future<List<SavedPlace>> reorderSavedPlaces(
    String tripId,
    List<String> placeIds,
  ) async {
    final encodedTripId = Uri.encodeComponent(_requiredId(tripId, 'trip'));
    final response = await _client
        .patch(
          Uri.parse('$_baseUrl/trips/$encodedTripId/saved-places/reorder'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'places': [
              for (var index = 0; index < placeIds.length; index++)
                {'place_id': placeIds[index], 'custom_order': index + 1},
            ],
          }),
        )
        .timeout(_requestTimeout);
    return _decodeList(response);
  }

  Uri _collectionUri(String tripId) {
    final encodedTripId = Uri.encodeComponent(_requiredId(tripId, 'trip'));
    return Uri.parse('$_baseUrl/trips/$encodedTripId/saved-places');
  }

  Uri _itemUri(String tripId, String placeId) {
    final encodedTripId = Uri.encodeComponent(_requiredId(tripId, 'trip'));
    final encodedPlaceId = Uri.encodeComponent(_requiredId(placeId, 'place'));
    return Uri.parse(
      '$_baseUrl/trips/$encodedTripId/saved-places/$encodedPlaceId',
    );
  }

  String _requiredId(String value, String label) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw SavedPlaceServiceException('$label ID must not be blank.');
    }
    return normalized;
  }

  List<SavedPlace> _decodeList(http.Response response) {
    if (response.statusCode != 200) {
      throw SavedPlaceServiceException(
        _errorMessage(response),
        statusCode: response.statusCode,
      );
    }
    try {
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((item) => SavedPlace.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } on FormatException catch (error) {
      throw SavedPlaceServiceException(
        'Saved places response was invalid.',
        cause: error,
      );
    } on TypeError catch (error) {
      throw SavedPlaceServiceException(
        'Saved places response was invalid.',
        cause: error,
      );
    }
  }

  SavedPlace _decodeOne(http.Response response, {int expectedStatus = 200}) {
    if (response.statusCode != expectedStatus) {
      throw SavedPlaceServiceException(
        _errorMessage(response),
        statusCode: response.statusCode,
      );
    }
    try {
      return SavedPlace.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on FormatException catch (error) {
      throw SavedPlaceServiceException(
        'Saved place response was invalid.',
        cause: error,
      );
    } on TypeError catch (error) {
      throw SavedPlaceServiceException(
        'Saved place response was invalid.',
        cause: error,
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
    return 'Saved place request failed (${response.statusCode}).';
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class SavedPlaceServiceException implements Exception {
  const SavedPlaceServiceException(this.message, {this.cause, this.statusCode});

  final String message;
  final Object? cause;
  final int? statusCode;

  bool get isConflict => statusCode == 409;

  @override
  String toString() => message;
}
