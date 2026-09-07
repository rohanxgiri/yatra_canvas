import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/models/saved_place.dart';
import 'package:yatra_canvas/services/saved_place_service.dart';

void main() {
  group('AssignmentMode and SavedPlace models', () {
    test('AssignmentMode serializes and deserializes correctly', () {
      expect(AssignmentMode.auto.toJson(), 'AUTO');
      expect(AssignmentMode.locked.toJson(), 'LOCKED');
      expect(AssignmentMode.fromJson('AUTO'), AssignmentMode.auto);
      expect(AssignmentMode.fromJson('auto'), AssignmentMode.auto);
      expect(AssignmentMode.fromJson('LOCKED'), AssignmentMode.locked);
      expect(AssignmentMode.fromJson('locked'), AssignmentMode.locked);
      expect(AssignmentMode.fromJson(null), AssignmentMode.auto);
      expect(AssignmentMode.fromJson('INVALID'), AssignmentMode.auto);
    });

    test('SavedPlace parses assignment fields and defaults to AUTO', () {
      final defaultJson = _mockSavedPlaceJson();
      final defaultPlace = SavedPlace.fromJson(defaultJson);
      expect(defaultPlace.assignmentMode, AssignmentMode.auto);
      expect(defaultPlace.assignedDayId, isNull);

      final lockedJson = _mockSavedPlaceJson(
        assignmentMode: 'LOCKED',
        assignedDayId: 'day-uuid-123',
      );
      final lockedPlace = SavedPlace.fromJson(lockedJson);
      expect(lockedPlace.assignmentMode, AssignmentMode.locked);
      expect(lockedPlace.assignedDayId, 'day-uuid-123');
    });

    test('SavedPlace copyWith updates and clears assignment fields', () {
      final place = SavedPlace.fromJson(
        _mockSavedPlaceJson(
          assignmentMode: 'LOCKED',
          assignedDayId: 'day-uuid-1',
        ),
      );
      expect(place.assignmentMode, AssignmentMode.locked);
      expect(place.assignedDayId, 'day-uuid-1');

      final switched = place.copyWith(
        assignmentMode: AssignmentMode.auto,
        clearAssignedDay: true,
      );
      expect(switched.assignmentMode, AssignmentMode.auto);
      expect(switched.assignedDayId, isNull);

      final reassigned = switched.copyWith(
        assignmentMode: AssignmentMode.locked,
        assignedDayId: 'day-uuid-2',
      );
      expect(reassigned.assignmentMode, AssignmentMode.locked);
      expect(reassigned.assignedDayId, 'day-uuid-2');
    });
  });

  group('SavedPlaceService assignment APIs', () {
    test('updateAssignment sends LOCKED with assignedDayId', () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        expect(request.method, 'PATCH');
        expect(request.url.path, '/trips/trip-1/saved-places/place-1');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body, {
          'assignment_mode': 'LOCKED',
          'assigned_day_id': 'day-uuid-1',
        });
        return http.Response(
          jsonEncode(
            _mockSavedPlaceJson(
              assignmentMode: 'LOCKED',
              assignedDayId: 'day-uuid-1',
            ),
          ),
          200,
        );
      });

      final service = SavedPlaceService(
        client: client,
        baseUrl: 'http://api.test',
      );
      final result = await service.updateAssignment(
        'trip-1',
        'place-1',
        assignmentMode: AssignmentMode.locked,
        assignedDayId: 'day-uuid-1',
      );

      expect(capturedRequest, isNotNull);
      expect(result.assignmentMode, AssignmentMode.locked);
      expect(result.assignedDayId, 'day-uuid-1');
    });

    test('updateAssignment sends AUTO with null assignedDayId', () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        expect(request.method, 'PATCH');
        expect(request.url.path, '/trips/trip-1/saved-places/place-1');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body, {'assignment_mode': 'AUTO', 'assigned_day_id': null});
        return http.Response(
          jsonEncode(
            _mockSavedPlaceJson(assignmentMode: 'AUTO', assignedDayId: null),
          ),
          200,
        );
      });

      final service = SavedPlaceService(
        client: client,
        baseUrl: 'http://api.test',
      );
      final result = await service.updateAssignment(
        'trip-1',
        'place-1',
        assignmentMode: AssignmentMode.auto,
      );

      expect(capturedRequest, isNotNull);
      expect(result.assignmentMode, AssignmentMode.auto);
      expect(result.assignedDayId, isNull);
    });

    test('addSavedPlace supports assignmentMode and assignedDayId', () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        expect(request.method, 'POST');
        expect(request.url.path, '/trips/trip-1/saved-places');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['assignment_mode'], 'LOCKED');
        expect(body['assigned_day_id'], 'day-uuid-3');
        return http.Response(
          jsonEncode(
            _mockSavedPlaceJson(
              assignmentMode: 'LOCKED',
              assignedDayId: 'day-uuid-3',
            ),
          ),
          201,
        );
      });

      final service = SavedPlaceService(
        client: client,
        baseUrl: 'http://api.test',
      );
      final result = await service.addSavedPlace(
        'trip-1',
        'place-1',
        assignmentMode: AssignmentMode.locked,
        assignedDayId: 'day-uuid-3',
      );

      expect(capturedRequest, isNotNull);
      expect(result.assignmentMode, AssignmentMode.locked);
      expect(result.assignedDayId, 'day-uuid-3');
    });
  });
}

Map<String, Object?> _mockSavedPlaceJson({
  String id = 'saved-1',
  String tripId = 'trip-1',
  String placeId = 'place-1',
  int customOrder = 1,
  int priority = 0,
  bool isLocked = false,
  bool mustVisit = false,
  String? assignmentMode,
  String? assignedDayId,
  String? notes,
}) {
  return {
    'id': id,
    'trip_id': tripId,
    'place_id': placeId,
    'custom_order': customOrder,
    'priority': priority,
    'is_locked': isLocked,
    'must_visit': mustVisit,
    'assignment_mode': ?assignmentMode,
    'assigned_day_id': ?assignedDayId,
    'notes': notes,
    'place': {
      'id': placeId,
      'city_id': 'city-1',
      'name': 'Hawa Mahal',
      'category': 'tourism',
      'latitude': 26.92,
      'longitude': 75.82,
      'rating': 4.7,
      'review_count': 1000,
      'is_popular': true,
      'is_heritage': true,
      'is_local_speciality': false,
      'last_fetched_at': null,
    },
  };
}
