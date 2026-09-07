import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/models/itinerary_stop_status.dart';
import 'package:yatra_canvas/models/optimized_route.dart';
import 'package:yatra_canvas/services/smart_replanning_service.dart';

void main() {
  group('ItineraryStopStatus enum tests', () {
    test('converts enum to API string', () {
      expect(ItineraryStopStatus.planned.toApiString(), 'PLANNED');
      expect(ItineraryStopStatus.completed.toApiString(), 'COMPLETED');
      expect(ItineraryStopStatus.missed.toApiString(), 'MISSED');
      expect(ItineraryStopStatus.skipped.toApiString(), 'SKIPPED');
    });

    test('parses API string to enum', () {
      expect(ItineraryStopStatus.fromString('PLANNED'), ItineraryStopStatus.planned);
      expect(ItineraryStopStatus.fromString('COMPLETED'), ItineraryStopStatus.completed);
      expect(ItineraryStopStatus.fromString('MISSED'), ItineraryStopStatus.missed);
      expect(ItineraryStopStatus.fromString('SKIPPED'), ItineraryStopStatus.skipped);
      expect(ItineraryStopStatus.fromString('unknown'), ItineraryStopStatus.planned);
    });
  });

  group('OptimizedRoutePlace status tests', () {
    test('defaults status to PLANNED when omitted in json', () {
      final json = {
        'place_id': 'pid-1',
        'name': 'Test Place',
        'day_number': 1,
        'visit_order': 1,
        'distance_from_previous': 1.5,
        'travel_time_minutes': 10,
      };
      final place = OptimizedRoutePlace.fromJson(json);
      expect(place.id, isNull);
      expect(place.status, 'PLANNED');
      expect(place.isPlanned, isTrue);
      expect(place.isCompleted, isFalse);
      expect(place.isMissed, isFalse);
      expect(place.isSkipped, isFalse);
    });

    test('parses id and explicit status in json', () {
      final json = {
        'id': 'stop-uuid-1',
        'place_id': 'pid-1',
        'name': 'City Palace',
        'day_number': 2,
        'visit_order': 3,
        'distance_from_previous': 2.0,
        'travel_time_minutes': 15,
        'status': 'COMPLETED',
      };
      final place = OptimizedRoutePlace.fromJson(json);
      expect(place.id, 'stop-uuid-1');
      expect(place.status, 'COMPLETED');
      expect(place.isCompleted, isTrue);
      expect(place.isPlanned, isFalse);
    });
  });

  group('MoveItineraryPlaceResponse tests', () {
    test('parses successful move response', () {
      final json = {
        'success': true,
        'reason': null,
        'trip_id': 'trip-1',
        'place_id': 'place-c',
        'source_day_number': 1,
        'target_day_number': 2,
        'source_itinerary': [
          {
            'place_id': 'place-a',
            'name': 'Place A',
            'day_number': 1,
            'visit_order': 1,
            'distance_from_previous': 0.0,
            'travel_time_minutes': 0,
            'status': 'COMPLETED',
          }
        ],
        'target_itinerary': [
          {
            'place_id': 'place-c',
            'name': 'Place C',
            'day_number': 2,
            'visit_order': 1,
            'distance_from_previous': 3.5,
            'travel_time_minutes': 20,
            'status': 'PLANNED',
          }
        ],
      };
      final resp = MoveItineraryPlaceResponse.fromJson(json);
      expect(resp.success, isTrue);
      expect(resp.reason, isNull);
      expect(resp.sourceDayNumber, 1);
      expect(resp.targetDayNumber, 2);
      expect(resp.sourceItinerary.length, 1);
      expect(resp.sourceItinerary.first.name, 'Place A');
      expect(resp.targetItinerary.length, 1);
      expect(resp.targetItinerary.first.name, 'Place C');
    });

    test('parses infeasible move failure response', () {
      final json = {
        'success': false,
        'reason': 'TARGET_DAY_INFEASIBLE',
        'trip_id': 'trip-1',
        'place_id': 'place-c',
        'source_day_number': 1,
        'target_day_number': 2,
        'source_itinerary': [],
        'target_itinerary': [],
      };
      final resp = MoveItineraryPlaceResponse.fromJson(json);
      expect(resp.success, isFalse);
      expect(resp.reason, 'TARGET_DAY_INFEASIBLE');
    });
  });

  group('SmartReplanningService live itinerary API tests', () {
    test('updateStopStatus calls patch and deserializes result', () async {
      final client = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/trips/trip-123/itinerary/stops/stop-456');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['status'], 'COMPLETED');
        return http.Response(
          jsonEncode({
            'id': 'stop-456',
            'place_id': 'place-789',
            'name': 'Hawa Mahal',
            'day_number': 1,
            'visit_order': 1,
            'distance_from_previous': 0.0,
            'travel_time_minutes': 0,
            'status': 'COMPLETED',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = SmartReplanningService(
        client: client,
        baseUrl: 'http://example.test',
      );

      final result = await service.updateStopStatus(
        tripId: 'trip-123',
        stopOrPlaceId: 'stop-456',
        status: ItineraryStopStatus.completed,
      );

      expect(result.id, 'stop-456');
      expect(result.status, 'COMPLETED');
      expect(result.isCompleted, isTrue);
    });

    test('movePlaceToDay calls post and deserializes response', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/trips/trip-123/itinerary/move-place');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['place_id'], 'place-c');
        expect(body['target_day_number'], 2);
        return http.Response(
          jsonEncode({
            'success': true,
            'reason': null,
            'trip_id': 'trip-123',
            'place_id': 'place-c',
            'source_day_number': 1,
            'target_day_number': 2,
            'source_itinerary': [],
            'target_itinerary': [
              {
                'place_id': 'place-c',
                'name': 'Place C',
                'day_number': 2,
                'visit_order': 1,
                'distance_from_previous': 1.0,
                'travel_time_minutes': 5,
                'status': 'PLANNED',
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = SmartReplanningService(
        client: client,
        baseUrl: 'http://example.test',
      );

      final resp = await service.movePlaceToDay(
        tripId: 'trip-123',
        placeId: 'place-c',
        targetDayNumber: 2,
      );

      expect(resp.success, isTrue);
      expect(resp.targetDayNumber, 2);
      expect(resp.targetItinerary.length, 1);
    });

    test('getItinerary calls get and deserializes OptimizedRoute', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/trips/trip-123/itinerary');
        return http.Response(
          jsonEncode({
            'trip_id': 'trip-123',
            'total_distance': 15.5,
            'total_travel_time_minutes': 45,
            'total_days': 2,
            'optimized_places': [
              {
                'place_id': 'p1',
                'name': 'Place 1',
                'day_number': 1,
                'visit_order': 1,
                'distance_from_previous': 0.0,
                'travel_time_minutes': 0,
                'status': 'COMPLETED',
              },
              {
                'place_id': 'p2',
                'name': 'Place 2',
                'day_number': 2,
                'visit_order': 1,
                'distance_from_previous': 5.2,
                'travel_time_minutes': 15,
                'status': 'PLANNED',
              }
            ],
            'breaks': [],
            'conflicts': [],
            'unscheduled_places': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = SmartReplanningService(
        client: client,
        baseUrl: 'http://example.test',
      );

      final route = await service.getItinerary('trip-123');
      expect(route.tripId, 'trip-123');
      expect(route.places.length, 2);
      expect(route.places[0].status, 'COMPLETED');
      expect(route.places[1].status, 'PLANNED');
    });
  });
}
