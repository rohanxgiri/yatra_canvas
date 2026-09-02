import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/optimized_route.dart';

void main() {
  group('Time-Aware OptimizedRoute Models', () {
    test('parses time fields, breaks, and conflicts from JSON', () {
      final json = {
        'trip_id': 'trip-123',
        'total_distance': 12.5,
        'total_travel_time_minutes': 45,
        'optimized_places': [
          {
            'place_id': 'place-1',
            'name': 'Hawa Mahal',
            'day_number': 1,
            'visit_order': 1,
            'distance_from_previous': 5.2,
            'travel_time_minutes': 15,
            'planned_arrival_time': '09:15:00',
            'planned_departure_time': '10:00:00',
            'visit_duration_minutes': 45,
            'is_opening_hours_known': true,
          },
          {
            'place_id': 'place-2',
            'name': 'City Palace',
            'day_number': 1,
            'visit_order': 2,
            'distance_from_previous': 2.1,
            'travel_time_minutes': 10,
            'planned_arrival_time': '10:10:00',
            'planned_departure_time': '12:10:00',
            'visit_duration_minutes': 120,
            'is_opening_hours_known': false,
          },
        ],
        'breaks': [
          {
            'day_number': 1,
            'start_time': '12:30:00',
            'end_time': '13:30:00',
            'duration_minutes': 60,
            'label': 'Midday Break / Lunch',
          }
        ],
        'conflicts': [
          "'Albert Hall' cannot fit within Day 1 touring hours.",
        ],
      };

      final route = OptimizedRoute.fromJson(json);
      expect(route.tripId, 'trip-123');
      expect(route.places.length, 2);
      expect(route.places[0].formattedTimeWindow, '09:15 – 10:00');
      expect(route.places[0].visitDurationMinutes, 45);
      expect(route.places[0].isOpeningHoursKnown, isTrue);

      expect(route.places[1].formattedTimeWindow, '10:10 – 12:10');
      expect(route.places[1].visitDurationMinutes, 120);

      expect(route.breaks.length, 1);
      expect(route.breaks[0].formattedTimeWindow, '12:30 – 13:30');
      expect(route.breaks[0].label, 'Midday Break / Lunch');

      expect(route.conflicts.length, 1);
      expect(route.conflicts[0], contains('Albert Hall'));
    });

    test('handles nullable time fields without crashing', () {
      final json = {
        'trip_id': 'trip-456',
        'total_distance': 5.0,
        'total_travel_time_minutes': 15,
        'optimized_places': [
          {
            'place_id': 'place-1',
            'name': 'Amer Fort',
            'day_number': 1,
            'visit_order': 1,
            'distance_from_previous': 5.0,
            'travel_time_minutes': 15,
          },
        ],
      };

      final route = OptimizedRoute.fromJson(json);
      expect(route.places[0].plannedArrivalTime, isNull);
      expect(route.places[0].formattedTimeWindow, isNull);
      expect(route.breaks, isEmpty);
      expect(route.conflicts, isEmpty);
    });
  });
}
