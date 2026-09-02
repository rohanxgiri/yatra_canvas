import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/smart_replanning.dart';

void main() {
  group('Smart Re-planning Models', () {
    test('parses TripReplanImpact from JSON correctly', () {
      final json = {
        'trip_id': 'trip-123',
        'is_stale': true,
        'requires_replan_preview': true,
        'reasons': [
          '1 saved place(s) are not yet scheduled in the itinerary.',
        ],
        'summary': 'Itinerary is out of sync with your saved places.',
      };

      final impact = TripReplanImpact.fromJson(json);
      expect(impact.tripId, 'trip-123');
      expect(impact.isStale, isTrue);
      expect(impact.requiresReplanPreview, isTrue);
      expect(impact.reasons.length, 1);
      expect(impact.summary, contains('out of sync'));
    });

    test('parses TripReplanPreview and MovedPlace from JSON correctly', () {
      final json = {
        'trip_id': 'trip-123',
        'is_stale': true,
        'summary': '1 place(s) added, 1 stop(s) rescheduled.',
        'added_places': ['City Palace'],
        'removed_places': <String>[],
        'moved_places': [
          {
            'place_id': 'place-albert',
            'name': 'Albert Hall',
            'from_day': 1,
            'from_time': '15:00:00',
            'to_day': 1,
            'to_time': '16:20:00',
          }
        ],
        'travel_time_delta_minutes': 25,
        'proposed_itinerary': [
          {
            'place_id': 'place-cp',
            'name': 'City Palace',
            'day_number': 1,
            'visit_order': 1,
            'distance_from_previous': 3.5,
            'travel_time_minutes': 12,
            'planned_arrival_time': '09:15:00',
            'planned_departure_time': '11:15:00',
            'visit_duration_minutes': 120,
            'is_opening_hours_known': false,
          }
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
        'conflicts': <String>[],
      };

      final preview = TripReplanPreview.fromJson(json);
      expect(preview.tripId, 'trip-123');
      expect(preview.isStale, isTrue);
      expect(preview.addedPlaces, contains('City Palace'));
      expect(preview.removedPlaces, isEmpty);
      expect(preview.movedPlaces.length, 1);
      expect(preview.movedPlaces[0].name, 'Albert Hall');
      expect(preview.movedPlaces[0].moveDescription, contains('15:00'));
      expect(preview.movedPlaces[0].moveDescription, contains('16:20'));
      expect(preview.travelTimeDeltaMinutes, 25);
      expect(preview.proposedItinerary.length, 1);
      expect(preview.breaks.length, 1);
    });

    test('MovedPlace describes day changes properly', () {
      const moved = MovedPlace(
        placeId: 'p-1',
        name: 'Amer Fort',
        fromDay: 1,
        toDay: 2,
        fromTime: '16:00:00',
        toTime: '09:30:00',
      );
      expect(moved.moveDescription, 'Moved from Day 1 at 16:00 → Day 2 at 09:30');
    });
  });
}
