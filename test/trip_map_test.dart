import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/created_trip.dart';
import 'package:yatra_canvas/models/optimized_route.dart';
import 'package:yatra_canvas/models/place.dart';
import 'package:yatra_canvas/models/route_geometry.dart';
import 'package:yatra_canvas/models/saved_place.dart';
import 'package:yatra_canvas/models/trip_draft.dart';
import 'package:yatra_canvas/models/trip_start_location.dart';
import 'package:yatra_canvas/screens/trip_map/trip_map_screen.dart';
import 'package:yatra_canvas/services/route_geometry_service.dart';
import 'package:yatra_canvas/services/route_optimization_service.dart';
import 'package:yatra_canvas/services/saved_place_service.dart';
import 'package:yatra_canvas/services/trip_service.dart';

class MockTripService implements TripService {
  @override
  void close() {}

  @override
  Future<CreatedTrip> createTrip(TripDraft draft) => throw UnimplementedError();

  @override
  Future<TripDraft> getTrip(String tripId) async {
    return TripDraft(
      tripId: tripId,
      destination: const City(
        id: 'c1',
        name: 'Delhi',
        country: 'India',
        providerPlaceId: '123',
        latitude: 28.5,
        longitude: 77.1,
      ),
      startDate: DateTime.now(),
      endDate: DateTime.now().add(const Duration(days: 2)),
      startLocationType: TripStartLocationType.arrival,
      startLocationName: 'Airport',
      startLatitude: 28.55616,
      startLongitude: 77.10028,
    );
  }

  @override
  Future<TripStartLocation> updateStartLocation(
    String tripId, {
    required TripStartLocationType type,
    String? name,
    double? latitude,
    double? longitude,
    String? provider,
    String? providerPlaceId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<TripDraft> updateTrip(String tripId, TripDraft changes) {
    throw UnimplementedError();
  }
}

class MockSavedPlaceService implements SavedPlaceService {
  @override
  void close() {}

  @override
  Future<List<SavedPlace>> getSavedPlaces(String tripId) async {
    return [
      SavedPlace(
        id: 's1',
        tripId: 't1',
        placeId: 'p1',
        customOrder: 1,
        priority: 1,
        isLocked: false,
        mustVisit: false,
        place: const Place(
          id: 'p1',
          cityId: 'c1',
          name: 'India Gate',
          category: 'Tourism',
          latitude: 28.6129,
          longitude: 77.2295,
          reviewCount: 100,
          isPopular: true,
          isHeritage: true,
          isLocalSpeciality: false,
        ),
      ),
      SavedPlace(
        id: 's2',
        tripId: 't1',
        placeId: 'p2',
        customOrder: 2,
        priority: 2,
        isLocked: false,
        mustVisit: false,
        place: const Place(
          id: 'p2',
          cityId: 'c1',
          name: 'Red Fort',
          category: 'Heritage',
          latitude: 28.6562,
          longitude: 77.2410,
          reviewCount: 50,
          isPopular: true,
          isHeritage: true,
          isLocalSpeciality: false,
        ),
      ),
    ];
  }

  @override
  Future<SavedPlace> addSavedPlace(
    String tripId,
    String placeId, {
    int? customOrder,
    bool isLocked = false,
    bool mustVisit = false,
    String? notes,
    int priority = 0,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> removeSavedPlace(String tripId, String savedPlaceId) {
    throw UnimplementedError();
  }

  Future<List<SavedPlace>> updateOrder(
    String tripId,
    List<String> orderedPlaceIds,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<List<SavedPlace>> reorderSavedPlaces(
    String tripId,
    List<String> orderedPlaceIds,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<SavedPlace> updateNotes(
    String tripId,
    String savedPlaceId,
    String? notes,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<SavedPlace> updateSettings(
    String tripId,
    String savedPlaceId, {
    int? customOrder,
    bool? isLocked,
    bool? mustVisit,
    String? notes,
    int? priority,
  }) {
    throw UnimplementedError();
  }
}

class MockRouteOptimizationService implements RouteOptimizationService {
  @override
  void close() {}

  @override
  Future<OptimizedRoute> optimizeRoute(String tripId) async {
    return const OptimizedRoute(
      tripId: 't1',
      totalDistance: 15.0,
      totalTravelTimeMinutes: 45,
      places: [
        OptimizedRoutePlace(
          placeId: 'p1',
          name: 'India Gate',
          dayNumber: 1,
          visitOrder: 1,
          distanceFromPrevious: 10.0,
          travelTimeMinutes: 30,
        ),
        OptimizedRoutePlace(
          placeId: 'p2',
          name: 'Red Fort',
          dayNumber: 2,
          visitOrder: 1,
          distanceFromPrevious: 5.0,
          travelTimeMinutes: 15,
        ),
      ],
    );
  }
}

class MockRouteGeometryService implements RouteGeometryService {
  MockRouteGeometryService({this.shouldFail = false});

  final bool shouldFail;

  @override
  void close() {}

  @override
  Future<TripRouteGeometry> getRouteGeometry(
    String tripId, {
    int? dayNumber,
  }) async {
    if (shouldFail) {
      throw const RouteGeometryServiceException('Provider unavailable');
    }
    return const TripRouteGeometry(
      tripId: 't1',
      totalDistanceMeters: 18500.0,
      totalDurationSeconds: 2400.0,
      days: [
        DayRouteGeometry(
          dayNumber: 1,
          points: [
            LatLng(28.55616, 77.10028),
            LatLng(28.58000, 77.15000),
            LatLng(28.6129, 77.2295),
          ],
          distanceMeters: 10500.0,
          durationSeconds: 1500.0,
        ),
        DayRouteGeometry(
          dayNumber: 2,
          points: [
            LatLng(28.55616, 77.10028),
            LatLng(28.60000, 77.18000),
            LatLng(28.6562, 77.2410),
          ],
          distanceMeters: 8000.0,
          durationSeconds: 900.0,
        ),
      ],
    );
  }
}

void main() {
  testWidgets(
    'TripMapScreen displays markers and PolylineLayer for road route geometry',
    (WidgetTester tester) async {
      final tripService = MockTripService();
      final savedPlaceService = MockSavedPlaceService();
      final routeOptimizationService = MockRouteOptimizationService();
      final routeGeometryService = MockRouteGeometryService();

      await tester.pumpWidget(
        MaterialApp(
          home: TripMapScreen(
            tripId: 't1',
            tripService: tripService,
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeOptimizationService,
            routeGeometryService: routeGeometryService,
          ),
        ),
      );

      // Initially loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump();
      await tester.pump(const Duration(seconds: 1)); // allow futures to complete

      // Check if error occurred
      if (find.byIcon(Icons.error_outline_rounded).evaluate().isNotEmpty) {
        final text = tester.widget<Text>(find.byType(Text).last).data;
        fail('Map failed to load: $text');
      }

      // After loading, FlutterMap should be visible
      expect(find.byType(FlutterMap), findsOneWidget);

      // PolylineLayer should be present
      expect(find.byType(PolylineLayer), findsOneWidget);

      // Markers should be present
      expect(find.byType(MarkerLayer), findsOneWidget);

      // Placeholder warning banner should NOT be present
      expect(
        find.text('Road-route geometry is not yet available.'),
        findsNothing,
      );

      // Verify polylines rendered: all days initially
      final polylineLayer = tester.widget<PolylineLayer>(
        find.byType(PolylineLayer),
      );
      expect(polylineLayer.polylines.length, 2);
      expect(polylineLayer.polylines[0].points.length, 3);
      expect(polylineLayer.polylines[1].points.length, 3);
    },
  );

  testWidgets(
    'TripMapScreen day filter updates visible polylines',
    (WidgetTester tester) async {
      final tripService = MockTripService();
      final savedPlaceService = MockSavedPlaceService();
      final routeOptimizationService = MockRouteOptimizationService();
      final routeGeometryService = MockRouteGeometryService();

      await tester.pumpWidget(
        MaterialApp(
          home: TripMapScreen(
            tripId: 't1',
            tripService: tripService,
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeOptimizationService,
            routeGeometryService: routeGeometryService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open day filter menu
      await tester.tap(find.byIcon(Icons.filter_list_rounded));
      await tester.pumpAndSettle();

      // Select Day 1
      await tester.tap(find.text('Day 1'));
      await tester.pumpAndSettle();

      // Only Day 1 polyline should be visible now
      final polylineLayer = tester.widget<PolylineLayer>(
        find.byType(PolylineLayer),
      );
      expect(polylineLayer.polylines.length, 1);
      expect(
        polylineLayer.polylines[0].points.last,
        const LatLng(28.6129, 77.2295),
      );
    },
  );

  testWidgets(
    'TripMapScreen degrades gracefully when route geometry fails',
    (WidgetTester tester) async {
      final tripService = MockTripService();
      final savedPlaceService = MockSavedPlaceService();
      final routeOptimizationService = MockRouteOptimizationService();
      final routeGeometryService = MockRouteGeometryService(shouldFail: true);

      await tester.pumpWidget(
        MaterialApp(
          home: TripMapScreen(
            tripId: 't1',
            tripService: tripService,
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeOptimizationService,
            routeGeometryService: routeGeometryService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Map renders without crash
      expect(find.byType(FlutterMap), findsOneWidget);

      // Markers still present
      expect(find.byType(MarkerLayer), findsOneWidget);

      // PolylineLayer has 0 polylines
      final polylineLayer = tester.widget<PolylineLayer>(
        find.byType(PolylineLayer),
      );
      expect(polylineLayer.polylines, isEmpty);
    },
  );
}
