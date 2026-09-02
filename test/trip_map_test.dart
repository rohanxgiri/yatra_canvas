import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/created_trip.dart';
import 'package:yatra_canvas/models/optimized_route.dart';
import 'package:yatra_canvas/models/saved_place.dart';

import 'package:yatra_canvas/models/trip_draft.dart';
import 'package:yatra_canvas/models/trip_start_location.dart';
import 'package:yatra_canvas/screens/trip_map/trip_map_screen.dart';
import 'package:yatra_canvas/services/route_optimization_service.dart';
import 'package:yatra_canvas/services/saved_place_service.dart';
import 'package:yatra_canvas/services/trip_service.dart';
import 'package:yatra_canvas/models/place.dart';

class MockTripService implements TripService {
  @override
  void close() {}

  @override
  Future<CreatedTrip> createTrip(TripDraft draft) => throw UnimplementedError();

  @override
  Future<TripDraft> getTrip(String tripId) async {
    return TripDraft(
      tripId: tripId,
      destination: const City(id: 'c1', name: 'Delhi', country: 'India', providerPlaceId: '123', latitude: 28.5, longitude: 77.1),
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
  Future<SavedPlace> addSavedPlace(String tripId, String placeId, {int? customOrder, bool isLocked = false, bool mustVisit = false, String? notes, int priority = 0}) {
    throw UnimplementedError();
  }

  @override
  Future<void> removeSavedPlace(String tripId, String savedPlaceId) {
    throw UnimplementedError();
  }

  Future<List<SavedPlace>> updateOrder(String tripId, List<String> orderedPlaceIds) {
    throw UnimplementedError();
  }

  @override
  Future<List<SavedPlace>> reorderSavedPlaces(String tripId, List<String> orderedPlaceIds) {
    throw UnimplementedError();
  }

  @override
  Future<SavedPlace> updateNotes(String tripId, String savedPlaceId, String? notes) {
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
          dayNumber: 1,
          visitOrder: 2,
          distanceFromPrevious: 5.0,
          travelTimeMinutes: 15,
        ),
      ],
    );
  }
}

void main() {
  testWidgets('TripMapScreen displays markers for start location and optimized route', (WidgetTester tester) async {
    final tripService = MockTripService();
    final savedPlaceService = MockSavedPlaceService();
    final routeOptimizationService = MockRouteOptimizationService();

    await tester.pumpWidget(
      MaterialApp(
        home: TripMapScreen(
          tripId: 't1',
          tripService: tripService,
          savedPlaceService: savedPlaceService,
          routeOptimizationService: routeOptimizationService,
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

    // The road-route geometry message should be present
    expect(find.text('Road-route geometry is not yet available.'), findsOneWidget);

    // There should be MarkerLayer inside
    expect(find.byType(MarkerLayer), findsOneWidget);
  });
}
