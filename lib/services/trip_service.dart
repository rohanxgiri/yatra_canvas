import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/created_trip.dart';
import '../models/trip_day.dart';
import '../models/trip_draft.dart';
import '../models/trip_start_location.dart';

class TripService {
  TripService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceFirst(RegExp(r'/$'), '');

  static const _timeout = Duration(seconds: 15);
  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;

  Future<CreatedTrip> createTrip(TripDraft draft) async {
    final cityId = draft.destination?.id?.trim();
    if (cityId == null || cityId.isEmpty) {
      throw const TripServiceException(
        'Choose and confirm a destination before creating the trip.',
      );
    }

    late http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl/trips'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'city_id': cityId,
              'start_date': _dateValue(draft.startDate),
              'end_date': _dateValue(draft.endDate),
              'days': draft.durationDays,
              'arrival_place': draft.arrivalPoint,
              'arrival_latitude': draft.arrivalLatitude,
              'arrival_longitude': draft.arrivalLongitude,
              'start_location_type': draft.startLocationType.apiValue,
              'start_location_name': draft.startLocationName,
              'start_latitude': draft.startLatitude,
              'start_longitude': draft.startLongitude,
              'start_location_provider': draft.startLocationProvider,
              'start_location_provider_place_id':
                  draft.startLocationProviderPlaceId,
              'purposes': draft.purposes.toList()..sort(),
              'preferences': <String>[
                draft.travelPace,
                draft.budget,
                ...(draft.transportPreferences.toList()..sort()),
              ],
            }),
          )
          .timeout(_timeout);
    } on TimeoutException catch (error) {
      throw TripServiceException(
        'Trip creation took too long. Check your connection and try again.',
        error,
      );
    } on http.ClientException catch (error) {
      throw TripServiceException(
        'Could not reach YatraCanvas. Check your connection and try again.',
        error,
      );
    }

    if (response.statusCode != 201) {
      throw TripServiceException(_createErrorMessage(response));
    }
    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw const FormatException('Trip response must be an object.');
      }
      return CreatedTrip.fromJson(body);
    } on Object catch (error) {
      throw TripServiceException(
        'YatraCanvas returned an invalid trip response. Please try again.',
        error,
      );
    }
  }

  Future<TripDraft> getTrip(String tripId) async {
    final encodedTripId = Uri.encodeComponent(tripId.trim());
    late http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$_baseUrl/trips/$encodedTripId'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(_timeout);
    } on TimeoutException catch (error) {
      throw TripServiceException(
        'Loading trip took too long. Check your connection and try again.',
        error,
      );
    } on http.ClientException catch (error) {
      throw TripServiceException(
        'Could not reach YatraCanvas. Check your connection and try again.',
        error,
      );
    }

    if (response.statusCode != 200) {
      throw TripServiceException(_tripErrorMessage(response, 'load'));
    }

    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw const FormatException('Trip response must be an object.');
      }
      return TripDraft.fromJson(body);
    } on Object catch (error) {
      throw TripServiceException(
        'YatraCanvas returned an invalid trip representation.',
        error,
      );
    }
  }

  Future<TripDraft> updateTrip(String tripId, TripDraft draft) async {
    final encodedTripId = Uri.encodeComponent(tripId.trim());
    final cityId = draft.destination?.id?.trim();

    final payload = <String, dynamic>{
      if (cityId != null && cityId.isNotEmpty) 'city_id': cityId,
      'start_date': _dateValue(draft.startDate),
      'end_date': _dateValue(draft.endDate),
      'days': draft.durationDays,
      'arrival_place': draft.arrivalPoint,
      'arrival_latitude': draft.arrivalLatitude,
      'arrival_longitude': draft.arrivalLongitude,
      'start_location_type': draft.startLocationType.apiValue,
      'start_location_name': draft.startLocationName,
      'start_latitude': draft.startLatitude,
      'start_longitude': draft.startLongitude,
      'start_location_provider': draft.startLocationProvider,
      'start_location_provider_place_id': draft.startLocationProviderPlaceId,
      'purposes': draft.purposes.toList()..sort(),
      'preferences': <String>[
        draft.travelPace,
        draft.budget,
        ...(draft.transportPreferences.toList()..sort()),
      ],
    };

    late http.Response response;
    try {
      response = await _client
          .patch(
            Uri.parse('$_baseUrl/trips/$encodedTripId'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
    } on TimeoutException catch (error) {
      throw TripServiceException(
        'Updating trip took too long. Check your connection and try again.',
        error,
      );
    } on http.ClientException catch (error) {
      throw TripServiceException(
        'Could not reach YatraCanvas. Check your connection and try again.',
        error,
      );
    }

    if (response.statusCode != 200) {
      throw TripServiceException(_tripErrorMessage(response, 'update'));
    }

    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw const FormatException('Trip response must be an object.');
      }
      return TripDraft.fromJson(body);
    } on Object catch (error) {
      throw TripServiceException(
        'YatraCanvas returned an invalid updated trip response.',
        error,
      );
    }
  }

  Future<TripStartLocation> updateStartLocation(
    String tripId, {
    required TripStartLocationType type,
    String? name,
    double? latitude,
    double? longitude,
    String? provider,
    String? providerPlaceId,
  }) async {
    final encodedTripId = Uri.encodeComponent(tripId.trim());
    final response = await _client
        .patch(
          Uri.parse('$_baseUrl/trips/$encodedTripId/start-location'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'start_location_type': type.apiValue,
            'start_location_name': name,
            'start_latitude': latitude,
            'start_longitude': longitude,
            'start_location_provider': provider,
            'start_location_provider_place_id': providerPlaceId,
          }),
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw TripServiceException(_errorMessage(response));
    }
    try {
      return TripStartLocation.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on Object catch (error) {
      throw TripServiceException('Trip start location was invalid.', error);
    }
  }

  Future<List<TripDay>> getTripDays(String tripId) async {
    final encodedTripId = Uri.encodeComponent(tripId.trim());
    late http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$_baseUrl/trips/$encodedTripId/days'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(_timeout);
    } on TimeoutException catch (error) {
      throw TripServiceException(
        'Loading trip days took too long. Check your connection and try again.',
        error,
      );
    } on http.ClientException catch (error) {
      throw TripServiceException(
        'Could not reach YatraCanvas. Check your connection and try again.',
        error,
      );
    }

    if (response.statusCode != 200) {
      throw TripServiceException(_tripErrorMessage(response, 'load days for'));
    }

    try {
      final body = jsonDecode(response.body);
      if (body is! List) {
        throw const FormatException('Trip days response must be a list.');
      }
      return body
          .map((item) => TripDay.fromJson(item as Map<String, dynamic>))
          .toList();
    } on Object catch (error) {
      throw TripServiceException(
        'YatraCanvas returned an invalid trip days list.',
        error,
      );
    }
  }

  Future<TripDay> updateTripDay(
    String tripId,
    int dayNumber, {
    DayType? dayType,
    String? startTime,
    String? endTime,
  }) async {
    final encodedTripId = Uri.encodeComponent(tripId.trim());
    final payload = <String, dynamic>{
      'day_type': ?dayType?.apiValue,
      'start_time': ?startTime,
      'end_time': ?endTime,
    };

    late http.Response response;
    try {
      response = await _client
          .patch(
            Uri.parse('$_baseUrl/trips/$encodedTripId/days/$dayNumber'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
    } on TimeoutException catch (error) {
      throw TripServiceException(
        'Updating trip day took too long. Check your connection and try again.',
        error,
      );
    } on http.ClientException catch (error) {
      throw TripServiceException(
        'Could not reach YatraCanvas. Check your connection and try again.',
        error,
      );
    }

    if (response.statusCode != 200) {
      throw TripServiceException(_tripErrorMessage(response, 'update day on'));
    }

    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw const FormatException('Trip day response must be an object.');
      }
      return TripDay.fromJson(body);
    } on Object catch (error) {
      throw TripServiceException(
        'YatraCanvas returned an invalid updated trip day.',
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
      // Fall through.
    }
    return 'Could not save the trip start (${response.statusCode}).';
  }

  String _createErrorMessage(http.Response response) {
    return _tripErrorMessage(response, 'create');
  }

  String _tripErrorMessage(http.Response response, String action) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = body['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map<String, dynamic>) {
          final message = first['msg'];
          if (message is String && message.isNotEmpty) {
            return message.replaceFirst('Value error, ', '');
          }
        }
      }
    } on Object {
      // Fall through to a status-specific safe message.
    }
    if (response.statusCode == 404) {
      return 'Trip not found.';
    }
    if (response.statusCode == 422) {
      return 'Check the trip details and try again.';
    }
    return 'Could not $action the trip (${response.statusCode}).';
  }

  static String _dateValue(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class TripServiceException implements Exception {
  const TripServiceException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => message;
}
