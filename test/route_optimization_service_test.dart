import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/services/route_optimization_service.dart';

void main() {
  test(
    'RouteOptimizationService posts trip and parses optimized order',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/trips/trip-123/optimize-route');
        expect(request.body, isEmpty);
        return http.Response(
          jsonEncode({
            'trip_id': 'trip-123',
            'optimized_places': [
              {
                'place_id': 'place-b',
                'name': 'Place B',
                'visit_order': 1,
                'distance_from_previous': 2.1,
                'travel_time_minutes': 8,
              },
              {
                'place_id': 'place-a',
                'name': 'Place A',
                'visit_order': 2,
                'distance_from_previous': 1.4,
                'travel_time_minutes': 5,
              },
            ],
            'total_distance': 3.5,
            'total_travel_time_minutes': 13,
          }),
          200,
        );
      });
      final service = RouteOptimizationService(
        client: client,
        baseUrl: 'http://10.0.2.2:8001',
      );

      final route = await service.optimizeRoute('trip-123');

      expect(route.places.map((place) => place.name), ['Place B', 'Place A']);
      expect(route.places.first.distanceFromPrevious, 2.1);
      expect(route.totalDistance, 3.5);
      expect(route.totalTravelTimeMinutes, 13);
    },
  );
}
