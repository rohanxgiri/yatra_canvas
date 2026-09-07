import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/optimized_route.dart';
import 'package:yatra_canvas/models/smart_replanning.dart';

void main() {
  final unscheduled = {
    'place_id': 'p2',
    'name': 'Museum',
    'reason': 'LOCKED_DAY_INFEASIBLE',
    'assigned_day_id': 'day3',
  };
  test('Planner result preserves sparse days, unknown hours and unscheduled reason', () {
    final route = OptimizedRoute.fromJson({
      'trip_id': 'trip',
      'total_days': 5,
      'total_distance': 1,
      'total_travel_time_minutes': 10,
      'optimized_places': [
        {
          'place_id': 'p1',
          'name': 'Park',
          'day_number': 3,
          'visit_order': 1,
          'distance_from_previous': 1,
          'travel_time_minutes': 10,
          'planned_arrival_time': '10:00:00',
          'planned_departure_time': '11:00:00',
          'is_opening_hours_known': false,
        },
      ],
      'unscheduled_places': [unscheduled],
    });
    expect(route.placesByDay.keys, [1, 2, 3, 4, 5]);
    expect(route.placesByDay[2], isEmpty);
    expect(route.places.single.isOpeningHoursKnown, isFalse);
    expect(route.unscheduledPlaces.single.reason, 'LOCKED_DAY_INFEASIBLE');
    expect(route.unscheduledPlaces.single.assignedDayId, 'day3');
  });
  test('Legacy results and previews default to an empty unscheduled list', () {
    expect(
      OptimizedRoute.fromJson({
        'trip_id': 'trip',
        'total_distance': 0,
        'total_travel_time_minutes': 0,
      }).unscheduledPlaces,
      isEmpty,
    );
    expect(
      TripReplanPreview.fromJson({'trip_id': 'trip'}).unscheduledPlaces,
      isEmpty,
    );
    expect(
      TripReplanPreview.fromJson({
        'trip_id': 'trip',
        'unscheduled_places': [unscheduled],
      }).unscheduledPlaces.single.placeId,
      'p2',
    );
  });
}
