import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/models/trip_day.dart';
import 'package:yatra_canvas/services/trip_service.dart';

void main() {
  group('TripDay model and DayType', () {
    test('DayType resolves values and labels correctly', () {
      expect(DayType.fromJson('FULL_DAY'), DayType.fullDay);
      expect(DayType.fromJson('HALF_DAY'), DayType.halfDay);
      expect(DayType.fromJson('REST'), DayType.rest);
      expect(DayType.fromJson('TRAVEL'), DayType.travel);
      expect(DayType.fromJson('unknown'), DayType.fullDay);

      expect(DayType.fullDay.apiValue, 'FULL_DAY');
      expect(DayType.halfDay.apiValue, 'HALF_DAY');
      expect(DayType.rest.apiValue, 'REST');
      expect(DayType.travel.apiValue, 'TRAVEL');

      expect(DayType.fullDay.label, 'Full Day');
      expect(DayType.halfDay.label, 'Half Day');
      expect(DayType.rest.label, 'Rest Day');
      expect(DayType.travel.label, 'Travel Day');
    });

    test('TripDay.fromJson deserializes valid JSON', () {
      final json = {
        'id': '11111111-1111-4111-8111-111111111111',
        'trip_id': '22222222-2222-4222-8222-222222222222',
        'day_number': 1,
        'date': '2026-10-01',
        'day_type': 'FULL_DAY',
        'start_time': '09:00:00',
        'end_time': '19:00:00',
      };

      final day = TripDay.fromJson(json);
      expect(day.id, '11111111-1111-4111-8111-111111111111');
      expect(day.tripId, '22222222-2222-4222-8222-222222222222');
      expect(day.dayNumber, 1);
      expect(day.date, DateTime(2026, 10, 1));
      expect(day.dayType, DayType.fullDay);
      expect(day.startTime, '09:00:00');
      expect(day.endTime, '19:00:00');
    });

    test('TripDay allows null start_time and end_time for REST days', () {
      final json = {
        'id': '11111111-1111-4111-8111-111111111111',
        'trip_id': '22222222-2222-4222-8222-222222222222',
        'day_number': 2,
        'date': '2026-10-02',
        'day_type': 'REST',
        'start_time': null,
        'end_time': null,
      };

      final day = TripDay.fromJson(json);
      expect(day.dayType, DayType.rest);
      expect(day.startTime, isNull);
      expect(day.endTime, isNull);
    });

    test('TripDay.toJson serializes to API format', () {
      final day = TripDay(
        id: '11111111-1111-4111-8111-111111111111',
        tripId: '22222222-2222-4222-8222-222222222222',
        dayNumber: 3,
        date: DateTime(2026, 10, 3),
        dayType: DayType.halfDay,
        startTime: '09:00:00',
        endTime: '14:00:00',
      );

      final json = day.toJson();
      expect(json['id'], '11111111-1111-4111-8111-111111111111');
      expect(json['day_number'], 3);
      expect(json['date'], '2026-10-03');
      expect(json['day_type'], 'HALF_DAY');
      expect(json['start_time'], '09:00:00');
      expect(json['end_time'], '14:00:00');
    });
  });

  group('TripService day endpoints', () {
    test('getTripDays returns ordered list of trip days', () async {
      final service = TripService(
        baseUrl: 'http://api.test',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/trips/trip-123/days');
          return http.Response(
            jsonEncode([
              {
                'id': 'd1',
                'trip_id': 'trip-123',
                'day_number': 1,
                'date': '2026-10-01',
                'day_type': 'FULL_DAY',
                'start_time': '09:00:00',
                'end_time': '19:00:00',
              },
              {
                'id': 'd2',
                'trip_id': 'trip-123',
                'day_number': 2,
                'date': '2026-10-02',
                'day_type': 'REST',
                'start_time': null,
                'end_time': null,
              },
            ]),
            200,
          );
        }),
      );

      final days = await service.getTripDays('trip-123');
      expect(days.length, 2);
      expect(days[0].dayNumber, 1);
      expect(days[0].dayType, DayType.fullDay);
      expect(days[1].dayNumber, 2);
      expect(days[1].dayType, DayType.rest);
    });

    test('updateTripDay sends PATCH request and returns updated TripDay', () async {
      final service = TripService(
        baseUrl: 'http://api.test',
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/trips/trip-123/days/2');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['day_type'], 'REST');

          return http.Response(
            jsonEncode({
              'id': 'd2',
              'trip_id': 'trip-123',
              'day_number': 2,
              'date': '2026-10-02',
              'day_type': 'REST',
              'start_time': null,
              'end_time': null,
            }),
            200,
          );
        }),
      );

      final updated = await service.updateTripDay(
        'trip-123',
        2,
        dayType: DayType.rest,
      );
      expect(updated.dayNumber, 2);
      expect(updated.dayType, DayType.rest);
      expect(updated.startTime, isNull);
    });

    test('updateTripDay throws TripServiceException on error response', () async {
      final service = TripService(
        baseUrl: 'http://api.test',
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({'detail': 'Day 99 not found for trip.'}),
            404,
          );
        }),
      );

      expect(
        () => service.updateTripDay('trip-123', 99, dayType: DayType.rest),
        throwsA(
          isA<TripServiceException>().having(
            (e) => e.message,
            'message',
            contains('Day 99 not found for trip.'),
          ),
        ),
      );
    });
  });
}
