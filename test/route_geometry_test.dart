import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yatra_canvas/models/route_geometry.dart';

void main() {
  group('RouteGeometry Model Tests', () {
    test('deserializes TripRouteGeometry with days, coordinates, and legs', () {
      final json = {
        'trip_id': 'trip-123',
        'total_distance_meters': 15200.5,
        'total_duration_seconds': 1800.0,
        'days': [
          {
            'day_number': 1,
            'coordinates': [
              [26.9124, 75.7873],
              [26.9150, 75.7900],
              [26.9239, 75.8267],
            ],
            'distance_meters': 7500.0,
            'duration_seconds': 900.0,
            'legs': [
              {
                'start_latitude': 26.9124,
                'start_longitude': 75.7873,
                'end_latitude': 26.9239,
                'end_longitude': 75.8267,
                'distance_meters': 7500.0,
                'duration_seconds': 900.0,
              },
            ],
          },
          {
            'day_number': 2,
            'coordinates': [
              [26.9124, 75.7873],
              [26.9855, 75.8513],
            ],
            'distance_meters': 7700.5,
            'duration_seconds': 900.0,
            'legs': [],
          },
        ],
      };

      final routeGeometry = TripRouteGeometry.fromJson(json);

      expect(routeGeometry.tripId, 'trip-123');
      expect(routeGeometry.totalDistanceMeters, 15200.5);
      expect(routeGeometry.totalDurationSeconds, 1800.0);
      expect(routeGeometry.days.length, 2);

      final day1 = routeGeometry.days[0];
      expect(day1.dayNumber, 1);
      expect(day1.points.length, 3);
      expect(day1.points[0], const LatLng(26.9124, 75.7873));
      expect(day1.points[2], const LatLng(26.9239, 75.8267));
      expect(day1.legs.length, 1);
      expect(day1.legs[0].distanceMeters, 7500.0);

      final day2 = routeGeometry.days[1];
      expect(day2.dayNumber, 2);
      expect(day2.points.length, 2);

      // Test pointsForDay
      expect(routeGeometry.pointsForDay(1).length, 3);
      expect(routeGeometry.pointsForDay(2).length, 2);
      expect(routeGeometry.pointsForDay(null).length, 5);
      expect(routeGeometry.pointsForDay(3).length, 0);
    });

    test('handles empty coordinates and null distance safely', () {
      final json = {
        'trip_id': 'trip-empty',
        'days': [
          {
            'day_number': 1,
            'coordinates': <dynamic>[],
          },
        ],
      };

      final routeGeometry = TripRouteGeometry.fromJson(json);
      expect(routeGeometry.tripId, 'trip-empty');
      expect(routeGeometry.totalDistanceMeters, isNull);
      expect(routeGeometry.days.length, 1);
      expect(routeGeometry.days[0].points, isEmpty);
    });
  });
}
