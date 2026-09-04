import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/optimized_route.dart';
import 'package:yatra_canvas/models/place.dart';
import 'package:yatra_canvas/models/recommendation.dart';
import 'package:yatra_canvas/models/route_geometry.dart';
import 'package:yatra_canvas/models/saved_place.dart';
import 'package:yatra_canvas/models/trip_start_location.dart';
import 'package:yatra_canvas/screens/place_discovery/place_discovery_screen.dart';
import 'package:yatra_canvas/screens/trip_map/trip_map_screen.dart';
import 'package:yatra_canvas/services/place_service.dart';
import 'package:yatra_canvas/services/recommendation_service.dart';
import 'package:yatra_canvas/services/route_geometry_service.dart';
import 'package:yatra_canvas/services/route_optimization_service.dart';
import 'package:yatra_canvas/services/saved_place_service.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

const _kochi = City(
  id: 'city-kochi',
  name: 'Kochi',
  state: 'Kerala',
  country: 'India',
  latitude: 9.9312,
  longitude: 76.2673,
);

class _FakePlaceService implements PlaceService {
  final List<String> searchCalls = [];
  bool failSearch = false;
  List<PlaceSearchResult> mockSearchResults = [];

  @override
  void close() {}

  @override
  Future<List<Place>> discoverPlaces(String cityId, PlaceCategory category) async => [];

  @override
  Future<List<PlaceSearchResult>> searchPlaces(String cityId, String query, {int limit = 10}) async {
    searchCalls.add('$cityId:$query');
    if (failSearch) throw const PlaceServiceException('Location search is unavailable.');
    return mockSearchResults;
  }

  @override
  Future<Place> resolvePlace(String cityId, PlaceSearchResult result) async {
    return Place(
      id: result.placeId ?? 'resolved-${result.externalPlaceId ?? result.name}',
      cityId: cityId,
      name: result.name,
      category: result.category,
      latitude: result.latitude,
      longitude: result.longitude,
      reviewCount: 10,
      isPopular: false,
      isHeritage: false,
      isLocalSpeciality: false,
    );
  }
}

class _FakeSavedPlaceService implements SavedPlaceService {
  _FakeSavedPlaceService({List<SavedPlace>? initial}) : _saved = initial ?? [];

  List<SavedPlace> _saved;
  final List<String> addedPlaceIds = [];

  @override
  void close() {}

  @override
  Future<List<SavedPlace>> getSavedPlaces(String tripId) async => _saved;

  @override
  Future<SavedPlace> addSavedPlace(
    String tripId,
    String placeId, {
    int? customOrder,
    bool isLocked = false,
    bool mustVisit = false,
    String? notes,
    int priority = 0,
  }) async {
    addedPlaceIds.add(placeId);
    final placeName = placeId.contains('hill-palace')
        ? 'Hill Palace Museum'
        : 'Place $placeId';
    final sp = SavedPlace(
      id: 'saved-$placeId',
      tripId: tripId,
      placeId: placeId,
      customOrder: customOrder ?? _saved.length + 1,
      priority: priority,
      isLocked: isLocked,
      mustVisit: mustVisit,
      place: Place(
        id: placeId,
        cityId: 'city-kochi',
        name: placeName,
        category: 'heritage',
        latitude: 9.95,
        longitude: 76.25,
        reviewCount: 10,
        isPopular: false,
        isHeritage: false,
        isLocalSpeciality: false,
      ),
    );
    _saved = [..._saved, sp];
    return sp;
  }

  @override
  Future<void> removeSavedPlace(String tripId, String placeId) async {
    _saved = _saved.where((sp) => sp.placeId != placeId).toList();
  }

  @override
  Future<List<SavedPlace>> reorderSavedPlaces(String tripId, List<String> placeIds) async => _saved;

  @override
  Future<SavedPlace> updateNotes(String tripId, String savedPlaceId, String? notes) async {
    return _saved.firstWhere((sp) => sp.placeId == savedPlaceId);
  }

  @override
  Future<SavedPlace> updateSettings(String tripId, String placeId, {String? notes, int? priority, bool? isLocked, bool? mustVisit, int? customOrder}) async {
    return _saved.firstWhere((sp) => sp.placeId == placeId);
  }
}

class _FakeRecommendationService implements RecommendationService {
  @override
  void close() {}

  @override
  Future<List<Recommendation>> getRecommendations(
    String cityId,
    Iterable<PlaceCategory> categories, {
    String? tripId,
    Iterable<String>? purposes,
    Iterable<String>? interests,
    PlaceCategory? categoryFilter,
    int limit = 30,
  }) async => [];

  @override
  Future<void> prefetchCityPlaces(
    String cityId, {
    required String stage,
    Iterable<PlaceCategory>? categories,
  }) async {}
}

class _FakeRouteOptimizationService implements RouteOptimizationService {
  @override
  void close() {}

  @override
  Future<OptimizedRoute> optimizeRoute(String tripId) async {
    return const OptimizedRoute(
      tripId: 'trip-1',
      totalDays: 3,
      places: [
        OptimizedRoutePlace(
          placeId: 'p1',
          name: 'Mattancherry Palace',
          dayNumber: 1,
          visitOrder: 1,
          distanceFromPrevious: 1.0,
          travelTimeMinutes: 10,
        ),
        OptimizedRoutePlace(
          placeId: 'p3',
          name: 'Fort Kochi Beach',
          dayNumber: 3,
          visitOrder: 1,
          distanceFromPrevious: 2.0,
          travelTimeMinutes: 15,
        ),
      ],
      totalDistance: 3.0,
      totalTravelTimeMinutes: 25,
      breaks: [],
      conflicts: [],
    );
  }
}

class _FakeRouteGeometryService implements RouteGeometryService {
  bool fail = false;

  @override
  void close() {}

  @override
  Future<TripRouteGeometry> getRouteGeometry(String tripId, {int? dayNumber}) async {
    if (fail) throw const RouteGeometryServiceException('Route geometry provider offline');
    return const TripRouteGeometry(
      tripId: 'trip-1',
      days: [
        DayRouteGeometry(
          dayNumber: 1,
          points: [
            LatLng(9.95, 76.25),
            LatLng(9.96, 76.24),
          ],
          distanceMeters: 1000,
          durationSeconds: 600,
        ),
      ],
      totalDistanceMeters: 1000,
      totalDurationSeconds: 600,
    );
  }
}

void main() {
  group('Part 1: Multi-Day Day-Sequence Integrity', () {
    test('OptimizedRoute models 1, 3, 5, 7 logical days deterministically', () {
      // 1-day trip
      const route1 = OptimizedRoute(
        tripId: 't1',
        totalDays: 1,
        places: [],
        totalDistance: 0,
        totalTravelTimeMinutes: 0,
      );
      expect(route1.logicalDays, [1]);

      // 3-day trip with sparse places (only day 1 and day 3, Day 2 has 0 stops)
      const route3 = OptimizedRoute(
        tripId: 't3',
        totalDays: 3,
        places: [
          OptimizedRoutePlace(
            placeId: 'p1',
            name: 'P1',
            dayNumber: 1,
            visitOrder: 1,
            distanceFromPrevious: 0,
            travelTimeMinutes: 0,
          ),
          OptimizedRoutePlace(
            placeId: 'p3',
            name: 'P3',
            dayNumber: 3,
            visitOrder: 1,
            distanceFromPrevious: 0,
            travelTimeMinutes: 0,
          ),
        ],
        totalDistance: 0,
        totalTravelTimeMinutes: 0,
      );
      expect(route3.logicalDays, [1, 2, 3]);
      expect(route3.placesByDay[1]?.length, 1);
      expect(route3.placesByDay[2], isEmpty);
      expect(route3.placesByDay[3]?.length, 1);

      // 5-day trip
      const route5 = OptimizedRoute(
        tripId: 't5',
        totalDays: 5,
        places: [],
        totalDistance: 0,
        totalTravelTimeMinutes: 0,
      );
      expect(route5.logicalDays, [1, 2, 3, 4, 5]);

      // 7-day trip
      const route7 = OptimizedRoute(
        tripId: 't7',
        totalDays: 7,
        places: [],
        totalDistance: 0,
        totalTravelTimeMinutes: 0,
      );
      expect(route7.logicalDays, [1, 2, 3, 4, 5, 6, 7]);
    });

    testWidgets('Empty day renders with friendly notice and does not disappear', (tester) async {
      tester.view.physicalSize = const Size(430, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final savedService = _FakeSavedPlaceService(
        initial: [
          SavedPlace(
            id: 's1',
            tripId: 't1',
            placeId: 'p1',
            customOrder: 1,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: const Place(
              id: 'p1',
              cityId: 'city-kochi',
              name: 'Mattancherry Palace',
              category: 'heritage',
              latitude: 9.95,
              longitude: 76.25,
              reviewCount: 10,
              isPopular: true,
              isHeritage: true,
              isLocalSpeciality: false,
            ),
          ),
          SavedPlace(
            id: 's2',
            tripId: 't1',
            placeId: 'p3',
            customOrder: 2,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: const Place(
              id: 'p3',
              cityId: 'city-kochi',
              name: 'Fort Kochi Beach',
              category: 'nature',
              latitude: 9.96,
              longitude: 76.24,
              reviewCount: 10,
              isPopular: true,
              isHeritage: false,
              isLocalSpeciality: false,
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: _kochi,
            tripId: 'trip-1',
            durationDays: 3,
            savedPlaceService: savedService,
            recommendationService: _FakeRecommendationService(),
            routeOptimizationService: _FakeRouteOptimizationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Optimize Route
      final optButton = find.widgetWithText(FilledButton, 'Optimize Route');
      await tester.ensureVisible(optButton);
      await tester.tap(optButton);
      await tester.pumpAndSettle();

      // Check all 3 days are displayed
      expect(find.text('Day 1'), findsOneWidget);
      expect(find.text('Day 2'), findsOneWidget);
      expect(find.text('Day 3'), findsOneWidget);

      // Check Day 2 shows empty state
      expect(
        find.text('No places scheduled yet. Add a place or optimize your itinerary.'),
        findsOneWidget,
      );
    });
  });

  group('Part 2: Manual Place Search & Add', () {
    testWidgets('tap search reveals debounced input, searches destination context, and adds place', (tester) async {
      tester.view.physicalSize = const Size(430, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakePlaceService = _FakePlaceService();
      fakePlaceService.mockSearchResults = [
        const PlaceSearchResult(
          name: 'Hill Palace Museum',
          category: 'heritage',
          latitude: 9.9535,
          longitude: 76.3639,
          distanceMeters: 8500,
          externalPlaceId: 'geo-hill-palace',
          source: 'geoapify',
        ),
      ];

      final savedService = _FakeSavedPlaceService();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: _kochi,
            tripId: 'trip-1',
            placeService: fakePlaceService,
            savedPlaceService: savedService,
            recommendationService: _FakeRecommendationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Search button is visible
      final searchButton = find.byKey(const ValueKey('open-place-search-button'));
      expect(searchButton, findsOneWidget);
      expect(find.text('Search another place'), findsOneWidget);

      // 2. Tap search button opens search input
      await tester.tap(searchButton);
      await tester.pumpAndSettle();

      final searchInput = find.byKey(const ValueKey('manual-place-search-field'));
      expect(searchInput, findsOneWidget);

      // 3. Enter query
      await tester.enterText(searchInput, 'Palace');
      await tester.pump(const Duration(milliseconds: 400)); // debounce
      await tester.pumpAndSettle();

      // Verify destination context was passed
      expect(fakePlaceService.searchCalls, contains('city-kochi:Palace'));

      // 4. Verify search result is displayed
      expect(find.text('Hill Palace Museum'), findsOneWidget);
      expect(find.textContaining('8.5 km away'), findsOneWidget);

      // 5. Add to trip
      final addButton = find.byKey(const ValueKey('add-search-result-geo-hill-palace'));
      expect(addButton, findsOneWidget);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Verify place was saved and count updated
      expect(savedService.addedPlaceIds, contains('resolved-geo-hill-palace'));
      expect(find.text('1 saved'), findsOneWidget);

      // 6. Verify duplicate prevention
      expect(find.byTooltip('Already in trip'), findsOneWidget);
    });

    testWidgets('Search error displays non-destructive message on failure', (tester) async {
      tester.view.physicalSize = const Size(430, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakePlaceService = _FakePlaceService()..failSearch = true;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: _kochi,
            tripId: 'trip-1',
            placeService: fakePlaceService,
            savedPlaceService: _FakeSavedPlaceService(),
            recommendationService: _FakeRecommendationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-place-search-button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('manual-place-search-field')), 'Museum');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Location search is unavailable.'), findsOneWidget);
    });
  });

  group('Part 3: Interactive Map Performance & Progressive Rendering', () {
    testWidgets('TripMapScreen renders base map and markers immediately with pre-passed state', (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final preloadedPlaces = [
        SavedPlace(
          id: 's1',
          tripId: 'trip-1',
          placeId: 'p1',
          customOrder: 1,
          priority: 0,
          isLocked: false,
          mustVisit: false,
          place: const Place(
            id: 'p1',
            cityId: 'city-kochi',
            name: 'Mattancherry Palace',
            category: 'heritage',
            latitude: 9.95,
            longitude: 76.25,
            reviewCount: 10,
            isPopular: true,
            isHeritage: true,
            isLocalSpeciality: false,
          ),
        ),
      ];

      final preloadedRoute = const OptimizedRoute(
        tripId: 'trip-1',
        totalDays: 3,
        places: [
          OptimizedRoutePlace(
            placeId: 'p1',
            name: 'Mattancherry Palace',
            dayNumber: 1,
            visitOrder: 1,
            distanceFromPrevious: 0,
            travelTimeMinutes: 0,
          ),
        ],
        totalDistance: 0,
        totalTravelTimeMinutes: 0,
      );

      final geomService = _FakeRouteGeometryService();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TripMapScreen(
            tripId: 'trip-1',
            initialStartLocation: const TripStartLocation(
              tripId: 'trip-1',
              type: TripStartLocationType.arrival,
              name: 'Airport',
              latitude: 10.15,
              longitude: 76.40,
            ),
            initialSavedPlaces: preloadedPlaces,
            initialOptimizedRoute: preloadedRoute,
            initialDurationDays: 3,
            routeGeometryService: geomService,
          ),
        ),
      );

      // On frame 1, base map and markers are rendered without blocking
      await tester.pump();

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Day filter popup menu shows all logical days
      final dayFilterBtn = find.byType(PopupMenuButton<int?>);
      expect(dayFilterBtn, findsOneWidget);
      await tester.tap(dayFilterBtn);
      await tester.pumpAndSettle();

      // Verify all logical days are present in filter menu
      expect(find.text('Day 1'), findsOneWidget);
      expect(find.text('Day 2'), findsOneWidget);
      expect(find.text('Day 3'), findsOneWidget);

      // Select Day 2 (which has 0 stops)
      await tester.tap(find.text('Day 2'));
      await tester.pumpAndSettle();

      // Verify Day 2 empty notice is shown and map remains functional
      expect(find.text('Day 2 · No places scheduled yet.'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets('TripMapScreen degrades gracefully when route geometry fails', (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final geomService = _FakeRouteGeometryService()..fail = true;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TripMapScreen(
            tripId: 'trip-1',
            initialSavedPlaces: [
              SavedPlace(
                id: 's1',
                tripId: 'trip-1',
                placeId: 'p1',
                customOrder: 1,
                priority: 0,
                isLocked: false,
                mustVisit: false,
                place: const Place(
                  id: 'p1',
                  cityId: 'city-kochi',
                  name: 'Fort Kochi',
                  category: 'heritage',
                  latitude: 9.96,
                  longitude: 76.24,
                  reviewCount: 5,
                  isPopular: true,
                  isHeritage: true,
                  isLocalSpeciality: false,
                ),
              ),
            ],
            initialOptimizedRoute: const OptimizedRoute(
              tripId: 'trip-1',
              totalDays: 2,
              places: [],
              totalDistance: 0,
              totalTravelTimeMinutes: 0,
            ),
            routeGeometryService: geomService,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Map is still visible and interactive
      expect(find.byType(FlutterMap), findsOneWidget);
    });
  });
}
