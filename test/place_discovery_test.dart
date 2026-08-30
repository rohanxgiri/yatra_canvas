import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/optimized_route.dart';
import 'package:yatra_canvas/models/place.dart';
import 'package:yatra_canvas/models/recommendation.dart';
import 'package:yatra_canvas/models/saved_place.dart';
import 'package:yatra_canvas/screens/place_discovery/place_discovery_screen.dart';
import 'package:yatra_canvas/services/place_service.dart';
import 'package:yatra_canvas/services/recommendation_service.dart';
import 'package:yatra_canvas/services/route_optimization_service.dart';
import 'package:yatra_canvas/services/saved_place_service.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

void main() {
  test('PlaceService requests and parses a discovery category', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/cities/city-123/discover-places');
      expect(request.url.queryParameters['category'], 'religious');
      return http.Response(
        jsonEncode([
          {
            'id': 'place-123',
            'city_id': 'city-123',
            'name': 'Mahakaleshwar Temple',
            'category': 'religious',
            'latitude': 23.1828,
            'longitude': 75.7682,
            'rating': 4.8,
            'review_count': 15000,
            'is_popular': true,
            'is_heritage': false,
            'is_local_speciality': false,
            'last_fetched_at': '2026-08-30T10:00:00Z',
            'created_at': '2026-08-30T10:00:00Z',
          },
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = PlaceService(
      client: client,
      baseUrl: 'http://10.0.2.2:8001',
    );

    final places = await service.discoverPlaces(
      'city-123',
      PlaceCategory.religious,
    );

    expect(places, hasLength(1));
    expect(places.single.name, 'Mahakaleshwar Temple');
    expect(places.single.rating, 4.8);
    expect(places.single.isPopular, isTrue);
  });

  test(
    'RecommendationService posts selected categories and parses scores',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/cities/city-123/recommendations');
        expect(jsonDecode(request.body), {
          'categories': ['religious', 'food', 'heritage'],
          'limit': 30,
        });
        return http.Response(
          jsonEncode([
            {
              'id': 'place-123',
              'name': 'Mahakaleshwar Temple',
              'category': 'heritage',
              'latitude': 23.1828,
              'longitude': 75.7682,
              'rating': 4.8,
              'review_count': 120000,
              'is_popular': true,
              'is_heritage': true,
              'is_local_speciality': false,
              'matched_categories': ['religious', 'heritage'],
              'recommendation_score': 78.3,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = RecommendationService(
        client: client,
        baseUrl: 'http://10.0.2.2:8001',
      );

      final recommendations = await service.getRecommendations('city-123', [
        PlaceCategory.religious,
        PlaceCategory.food,
        PlaceCategory.heritage,
      ]);

      expect(recommendations, hasLength(1));
      expect(recommendations.single.recommendationScore, 78.3);
      expect(recommendations.single.matchedCategories, [
        PlaceCategory.religious,
        PlaceCategory.heritage,
      ]);
    },
  );

  testWidgets(
    'discovery screen selects multiple interests and requests ranking',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = _FakeRecommendationService();
      final savedPlaceService = _FakeSavedPlaceService();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: const City(
              id: 'city-123',
              name: 'Ujjain',
              state: 'Madhya Pradesh',
              country: 'India',
              latitude: 23.1765,
              longitude: 75.7885,
              googlePlaceId: 'google-ujjain',
            ),
            tripId: 'trip-123',
            recommendationService: service,
            savedPlaceService: savedPlaceService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.requests, isEmpty);
      await tester.tap(find.text('Food'));
      await tester.tap(find.text('Heritage'));
      await tester.tap(find.text('Get Recommendations'));
      await tester.pumpAndSettle();

      expect(service.requests, [
        [PlaceCategory.religious, PlaceCategory.food, PlaceCategory.heritage],
      ]);
      await tester.scrollUntilVisible(find.text('Mahakaleshwar Temple'), 220);
      expect(find.text('Mahakaleshwar Temple'), findsOneWidget);
      expect(find.text('Matches Religious + Heritage'), findsOneWidget);
      expect(find.textContaining('Score 78.3'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Add'), 180);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(savedPlaceService.addedPlaceIds, ['place-religious']);
      expect(find.text('1 saved'), findsOneWidget);

      final removeButton = find.widgetWithText(TextButton, 'Remove');
      await tester.drag(find.byType(ListView), const Offset(0, -220));
      await tester.pumpAndSettle();
      await tester.tap(removeButton);
      await tester.pumpAndSettle();
      expect(savedPlaceService.removedPlaceIds, ['place-religious']);
      expect(find.text('0 saved'), findsOneWidget);
    },
  );

  testWidgets('selected places reorder persists the complete place order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final savedPlaceService = _FakeSavedPlaceService(
      initial: [
        _savedPlace('place-a', 'Place A', 1),
        _savedPlace('place-b', 'Place B', 2),
        _savedPlace('place-c', 'Place C', 3),
      ],
    );
    final routeOptimizationService = _FakeRouteOptimizationService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlaceDiscoveryScreen(
          city: const City(
            id: 'city-123',
            name: 'Ujjain',
            state: 'Madhya Pradesh',
            country: 'India',
            latitude: 23.1765,
            longitude: 75.7885,
          ),
          tripId: 'trip-123',
          recommendationService: _FakeRecommendationService(),
          savedPlaceService: savedPlaceService,
          routeOptimizationService: routeOptimizationService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add notes').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Visit before sunrise');
    await tester.tap(find.text('Save preferences'));
    await tester.pumpAndSettle();
    expect(savedPlaceService.noteUpdates, {'place-a': 'Visit before sunrise'});

    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorderItem!(0, 2);
    await tester.pumpAndSettle();

    expect(savedPlaceService.reorderRequests, [
      ['place-b', 'place-c', 'place-a'],
    ]);

    final optimizeButton = find.widgetWithText(FilledButton, 'Optimize Route');
    await tester.ensureVisible(optimizeButton);
    await tester.pumpAndSettle();
    await tester.tap(optimizeButton);
    await tester.pumpAndSettle();

    expect(routeOptimizationService.tripIds, ['trip-123']);
    expect(find.text('Optimized route'), findsOneWidget);
    expect(find.text('From arrival · 2.1 km · 8 min'), findsOneWidget);
    expect(find.text('3.5 km · 13 min'), findsOneWidget);
  });
}

class _FakeRecommendationService extends RecommendationService {
  _FakeRecommendationService() : super(baseUrl: 'http://example.test');

  final List<List<PlaceCategory>> requests = [];

  @override
  Future<List<Recommendation>> getRecommendations(
    String cityId,
    Iterable<PlaceCategory> categories, {
    int limit = 30,
  }) async {
    requests.add(categories.toList(growable: false));
    return [
      const Recommendation(
        id: 'place-religious',
        name: 'Mahakaleshwar Temple',
        category: 'heritage',
        latitude: 23.1828,
        longitude: 75.7682,
        rating: 4.8,
        reviewCount: 120000,
        isPopular: true,
        isHeritage: true,
        isLocalSpeciality: false,
        matchedCategories: [PlaceCategory.religious, PlaceCategory.heritage],
        recommendationScore: 78.3,
      ),
    ];
  }

  @override
  void close() {}
}

class _FakeSavedPlaceService extends SavedPlaceService {
  _FakeSavedPlaceService({List<SavedPlace> initial = const []})
    : savedPlaces = List.of(initial),
      super(baseUrl: 'http://example.test');

  List<SavedPlace> savedPlaces;
  final List<String> addedPlaceIds = [];
  final List<String> removedPlaceIds = [];
  final List<List<String>> reorderRequests = [];
  final Map<String, String?> noteUpdates = {};

  @override
  Future<List<SavedPlace>> getSavedPlaces(String tripId) async {
    return List.of(savedPlaces);
  }

  @override
  Future<SavedPlace> addSavedPlace(
    String tripId,
    String placeId, {
    int? customOrder,
    int priority = 0,
    bool isLocked = false,
    bool mustVisit = false,
    String? notes,
  }) async {
    addedPlaceIds.add(placeId);
    final saved = _savedPlace(
      placeId,
      'Mahakaleshwar Temple',
      customOrder ?? savedPlaces.length + 1,
      notes: notes,
      priority: priority,
      isLocked: isLocked,
      mustVisit: mustVisit,
    );
    savedPlaces = [...savedPlaces, saved];
    return saved;
  }

  @override
  Future<void> removeSavedPlace(String tripId, String placeId) async {
    removedPlaceIds.add(placeId);
    savedPlaces = [
      for (final savedPlace in savedPlaces)
        if (savedPlace.placeId != placeId) savedPlace,
    ];
  }

  @override
  Future<List<SavedPlace>> reorderSavedPlaces(
    String tripId,
    List<String> placeIds,
  ) async {
    reorderRequests.add(List.of(placeIds));
    final byId = {for (final item in savedPlaces) item.placeId: item};
    savedPlaces = [
      for (var index = 0; index < placeIds.length; index++)
        _copySavedPlace(byId[placeIds[index]]!, customOrder: index + 1),
    ];
    return List.of(savedPlaces);
  }

  @override
  Future<SavedPlace> updateNotes(
    String tripId,
    String placeId,
    String? notes,
  ) async {
    noteUpdates[placeId] = notes;
    final current = savedPlaces.firstWhere((item) => item.placeId == placeId);
    final updated = _copySavedPlace(current, notes: notes);
    savedPlaces = [
      for (final item in savedPlaces)
        if (item.placeId == placeId) updated else item,
    ];
    return updated;
  }

  @override
  Future<SavedPlace> updateSettings(
    String tripId,
    String placeId, {
    required int priority,
    required bool isLocked,
    required bool mustVisit,
    required int customOrder,
    String? notes,
  }) async {
    noteUpdates[placeId] = notes;
    final current = savedPlaces.firstWhere((item) => item.placeId == placeId);
    final updated = _copySavedPlace(
      current,
      notes: notes,
      priority: priority,
      isLocked: isLocked,
      mustVisit: mustVisit,
      customOrder: customOrder,
    );
    savedPlaces = [
      for (final item in savedPlaces)
        if (item.placeId == placeId) updated else item,
    ];
    return updated;
  }

  @override
  void close() {}
}

class _FakeRouteOptimizationService extends RouteOptimizationService {
  _FakeRouteOptimizationService() : super(baseUrl: 'http://example.test');

  final List<String> tripIds = [];

  @override
  Future<OptimizedRoute> optimizeRoute(String tripId) async {
    tripIds.add(tripId);
    return const OptimizedRoute(
      tripId: 'trip-123',
      places: [
        OptimizedRoutePlace(
          placeId: 'place-c',
          name: 'Place C',
          visitOrder: 1,
          distanceFromPrevious: 2.1,
          travelTimeMinutes: 8,
        ),
        OptimizedRoutePlace(
          placeId: 'place-a',
          name: 'Place A',
          visitOrder: 2,
          distanceFromPrevious: 1.4,
          travelTimeMinutes: 5,
        ),
      ],
      totalDistance: 3.5,
      totalTravelTimeMinutes: 13,
    );
  }

  @override
  void close() {}
}

SavedPlace _savedPlace(
  String placeId,
  String name,
  int customOrder, {
  String? notes,
  int priority = 0,
  bool isLocked = false,
  bool mustVisit = false,
}) {
  return SavedPlace(
    id: 'saved-$placeId',
    tripId: 'trip-123',
    placeId: placeId,
    customOrder: customOrder,
    priority: priority,
    isLocked: isLocked,
    mustVisit: mustVisit,
    notes: notes,
    place: Place(
      id: placeId,
      cityId: 'city-123',
      name: name,
      category: 'religious',
      latitude: 23.18,
      longitude: 75.77,
      rating: 4.7,
      reviewCount: 1000,
      isPopular: true,
      isHeritage: false,
      isLocalSpeciality: false,
    ),
  );
}

SavedPlace _copySavedPlace(
  SavedPlace savedPlace, {
  int? customOrder,
  String? notes,
  int? priority,
  bool? isLocked,
  bool? mustVisit,
}) {
  return SavedPlace(
    id: savedPlace.id,
    tripId: savedPlace.tripId,
    placeId: savedPlace.placeId,
    customOrder: customOrder ?? savedPlace.customOrder,
    priority: priority ?? savedPlace.priority,
    isLocked: isLocked ?? savedPlace.isLocked,
    mustVisit: mustVisit ?? savedPlace.mustVisit,
    notes: notes ?? savedPlace.notes,
    place: savedPlace.place,
  );
}
