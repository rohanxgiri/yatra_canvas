import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/optimized_route.dart';
import 'package:yatra_canvas/models/place.dart';
import 'package:yatra_canvas/models/place_image.dart';
import 'package:yatra_canvas/models/recommendation.dart';
import 'package:yatra_canvas/models/saved_place.dart';
import 'package:yatra_canvas/models/trip_day.dart';
import 'package:yatra_canvas/screens/place_discovery/place_discovery_screen.dart';
import 'package:yatra_canvas/services/place_service.dart';
import 'package:yatra_canvas/services/place_image_prefetch_service.dart';
import 'package:yatra_canvas/services/recommendation_cache.dart';
import 'package:yatra_canvas/services/recommendation_service.dart';
import 'package:yatra_canvas/services/route_optimization_service.dart';
import 'package:yatra_canvas/services/saved_place_service.dart';
import 'package:yatra_canvas/services/trip_service.dart';
import 'package:yatra_canvas/theme/app_theme.dart';
import 'package:yatra_canvas/widgets/selection_chip.dart';

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
        expect(request.headers['x-request-id'], 'trip-flow-123');
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
          headers: {
            'content-type': 'application/json',
            'x-refresh-state': 'queued',
            'x-stale-categories': 'religious,heritage',
          },
        );
      });
      final service = RecommendationService(
        client: client,
        baseUrl: 'http://10.0.2.2:8001',
        requestId: 'trip-flow-123',
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
      expect(service.lastRefreshState, RecommendationRefreshState.queued);
      expect(service.lastStaleCategories, {'religious', 'heritage'});
    },
  );

  test('RecommendationService sends and captures pagination cursors', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/cities/city-123/recommendations');
      expect(jsonDecode(request.body), {
        'categories': ['food'],
        'limit': 10,
        'cursor': 'MTA=',
      });
      return http.Response(
        '[]',
        200,
        headers: {'content-type': 'application/json', 'x-next-cursor': 'MjA='},
      );
    });
    final service = RecommendationService(
      client: client,
      baseUrl: 'http://10.0.2.2:8001',
    );

    final recommendations = await service.getRecommendations(
      'city-123',
      [PlaceCategory.food],
      limit: 10,
      cursor: 'MTA=',
    );

    expect(recommendations, isEmpty);
    expect(service.nextCursor, 'MjA=');
  });

  testWidgets('places loading skeleton transitions directly to real cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _ControlledRecommendationService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlaceDiscoveryScreen(
          city: _city,
          tripPurposes: const {'Food Exploration'},
          recommendationService: service,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('place-results-skeleton')),
      findsOneWidget,
    );
    expect(find.text('Controlled Cafe'), findsNothing);

    service.complete([
      const Recommendation(
        id: 'controlled-cafe',
        name: 'Controlled Cafe',
        category: 'cafe',
        latitude: 23.17,
        longitude: 75.78,
        reviewCount: 0,
        isPopular: false,
        isHeritage: false,
        isLocalSpeciality: true,
        matchedCategories: [PlaceCategory.food],
        recommendationScore: 70,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('place-results-skeleton')), findsNothing);
    expect(find.text('Controlled Cafe'), findsOneWidget);
  });

  testWidgets('local recommendations render before backend sync completes', (
    tester,
  ) async {
    final service = _ControlledRecommendationService();
    final cache = _FakeRecommendationCache([
      const Recommendation(
        id: 'cached-cafe',
        name: 'Cached Cafe',
        category: 'cafe',
        latitude: 23.17,
        longitude: 75.78,
        reviewCount: 0,
        isPopular: false,
        isHeritage: false,
        isLocalSpeciality: true,
        matchedCategories: [PlaceCategory.food],
        recommendationScore: 65,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlaceDiscoveryScreen(
          city: _city,
          tripPurposes: const {'Food Exploration'},
          recommendationService: service,
          recommendationCache: cache,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Cached Cafe'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('additional-place-skeletons')),
      findsOneWidget,
    );

    service.complete([
      const Recommendation(
        id: 'cached-cafe',
        name: 'Updated Cafe',
        category: 'cafe',
        latitude: 23.17,
        longitude: 75.78,
        reviewCount: 12,
        isPopular: false,
        isHeritage: false,
        isLocalSpeciality: true,
        matchedCategories: [PlaceCategory.food],
        recommendationScore: 72,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Cached Cafe'), findsNothing);
    expect(find.text('Updated Cafe'), findsOneWidget);
    expect(cache.writtenIds, ['cached-cafe']);
  });

  testWidgets('returned image metadata is sent to client precache', (
    tester,
  ) async {
    final recommendationService = _ControlledRecommendationService();
    final imagePrefetchService = _RecordingPlaceImagePrefetchService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlaceDiscoveryScreen(
          city: _city,
          tripPurposes: const {'Food Exploration'},
          recommendationService: recommendationService,
          placeImagePrefetchService: imagePrefetchService,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(imagePrefetchService.placeIds, isEmpty);

    recommendationService.complete([
      const Recommendation(
        id: 'controlled-cafe',
        name: 'Controlled Cafe',
        category: 'cafe',
        latitude: 23.17,
        longitude: 75.78,
        reviewCount: 0,
        isPopular: false,
        isHeritage: false,
        isLocalSpeciality: true,
        matchedCategories: [PlaceCategory.food],
        recommendationScore: 70,
        image: PlaceImageData(
          status: 'resolved',
          url: 'https://images.example/controlled-cafe.jpg',
        ),
      ),
    ]);
    await tester.pump();
    await tester.pump();

    expect(imagePrefetchService.placeIds, ['controlled-cafe']);
  });

  testWidgets('places loading skeleton fits supported phone widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in <double>[320, 393, 430]) {
      tester.view.physicalSize = Size(width, 844);
      final service = _ControlledRecommendationService();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            key: ValueKey('place-skeleton-$width'),
            city: _city,
            tripPurposes: const {'Food Exploration'},
            recommendationService: service,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('place-results-skeleton')),
        findsOneWidget,
        reason: 'Skeleton should render at $width px.',
      );
      expect(tester.takeException(), isNull);

      service.complete(const []);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('empty recommendation response replaces the skeleton', (
    tester,
  ) async {
    final service = _ControlledRecommendationService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlaceDiscoveryScreen(
          city: _city,
          tripPurposes: const {'Food Exploration'},
          recommendationService: service,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('place-results-skeleton')),
      findsOneWidget,
    );

    service.complete(const []);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('place-results-skeleton')), findsNothing);
    expect(find.text('No matching places found'), findsOneWidget);
  });

  testWidgets('recommendation failure replaces the skeleton with retry UI', (
    tester,
  ) async {
    final service = _ControlledRecommendationService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlaceDiscoveryScreen(
          city: _city,
          tripPurposes: const {'Food Exploration'},
          recommendationService: service,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('place-results-skeleton')),
      findsOneWidget,
    );

    service.completeError(
      const RecommendationServiceException('Controlled fetch failure.'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('place-results-skeleton')), findsNothing);
    expect(find.text('Controlled fetch failure.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

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
              providerPlaceId: 'google-place-id',
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
      await tester.pump();
      await tester.tap(find.text('Show matching places'));
      await tester.pumpAndSettle();

      expect(service.requests, [
        [PlaceCategory.food, PlaceCategory.heritage],
      ]);
      await tester.scrollUntilVisible(find.text('Mahakaleshwar Temple'), 220);
      expect(find.text('Mahakaleshwar Temple'), findsOneWidget);
      expect(find.text('Matches Religious + Heritage'), findsOneWidget);
      expect(find.textContaining('Score 78.3'), findsNothing);

      await tester.scrollUntilVisible(find.text('Add'), 180);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(savedPlaceService.addedPlaceIds, ['place-religious']);
      expect(savedPlaceService.addTripIds, ['trip-123']);
      expect(find.text('1 saved'), findsOneWidget);

      final removeButton = find.widgetWithText(TextButton, 'Remove');
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
      await tester.tap(removeButton);
      await tester.pumpAndSettle();
      expect(savedPlaceService.removedPlaceIds, ['place-religious']);
      expect(find.text('0 saved'), findsOneWidget);
    },
  );

  testWidgets('saved trip purposes seed recommendation filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FakeRecommendationService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlaceDiscoveryScreen(
          city: _city,
          tripId: 'trip-with-purposes',
          tripPurposes: const {'Photography'},
          routeStartReady: true,
          recommendationService: service,
          savedPlaceService: _FakeSavedPlaceService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.requests, [
      [PlaceCategory.tourism, PlaceCategory.heritage],
    ]);
    expect(find.text('Recommended for your trip'), findsOneWidget);
    expect(find.text('From your trip setup'), findsOneWidget);
    expect(find.text('Add another interest'), findsOneWidget);
    expect(find.byType(SelectionChip), findsNothing);

    await tester.tap(find.text('Add another interest'));
    await tester.pumpAndSettle();
    final extraInterests = tester.widgetList<SelectionChip>(
      find.byType(SelectionChip),
    );
    expect(extraInterests, hasLength(5));
    expect(extraInterests.every((chip) => !chip.selected), isTrue);
  });

  testWidgets('duplicate save reloads authoritative backend state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final savedPlaceService = _FakeSavedPlaceService(conflictOnNextAdd: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlaceDiscoveryScreen(
          city: _city,
          tripId: 'runtime-trip-id',
          recommendationService: _FakeRecommendationService(),
          savedPlaceService: savedPlaceService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Religious'));
    await tester.pump();
    await tester.tap(find.text('Show matching places'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Add'), 180);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(savedPlaceService.addTripIds, ['runtime-trip-id']);
    expect(savedPlaceService.loadTripIds, [
      'runtime-trip-id',
      'runtime-trip-id',
    ]);
    expect(find.text('1 saved'), findsOneWidget);
    expect(find.textContaining('already saved'), findsOneWidget);
  });

  testWidgets('failed save is not shown as saved', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final savedPlaceService = _FakeSavedPlaceService(failAdd: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlaceDiscoveryScreen(
          city: _city,
          tripId: 'runtime-trip-id',
          recommendationService: _FakeRecommendationService(),
          savedPlaceService: savedPlaceService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Religious'));
    await tester.pump();
    await tester.tap(find.text('Show matching places'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Add'), 180);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('0 saved'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Add'), findsOneWidget);
    expect(find.text('Controlled save failure.'), findsWidgets);
  });

  testWidgets('selected places reorder persists the complete place order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1800);
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

    final addNotesButton = find.byTooltip('Add notes').first;
    await tester.ensureVisible(addNotesButton);
    await tester.pumpAndSettle();
    await tester.tap(addNotesButton);
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

  testWidgets('route optimization uses a day-shaped itinerary skeleton', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final routeService = _ControlledRouteOptimizationService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlaceDiscoveryScreen(
          city: _city,
          tripId: 'trip-itinerary-loading',
          recommendationService: _FakeRecommendationService(),
          savedPlaceService: _FakeSavedPlaceService(
            initial: [_savedPlace('place-a', 'Place A', 1)],
          ),
          routeOptimizationService: routeService,
          tripService: _FakeTripService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final optimizeButton = find.widgetWithText(FilledButton, 'Optimize Route');
    await tester.ensureVisible(optimizeButton);
    await tester.tap(optimizeButton);
    await tester.pump();

    expect(find.byKey(const ValueKey('itinerary-skeleton')), findsOneWidget);
    expect(find.text('Optimized route'), findsNothing);

    routeService.complete(_threeDayRoute);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('itinerary-skeleton')), findsNothing);
    expect(find.text('Optimized route'), findsOneWidget);
  });

  testWidgets('itinerary distinguishes user rest from an empty light day', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlaceDiscoveryScreen(
          city: _city,
          tripId: 'trip-day-states',
          recommendationService: _FakeRecommendationService(),
          savedPlaceService: _FakeSavedPlaceService(
            initial: [_savedPlace('place-a', 'Place A', 1)],
          ),
          routeOptimizationService: _DayStateRouteOptimizationService(),
          tripService: _FakeTripService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final optimizeButton = find.widgetWithText(FilledButton, 'Optimize Route');
    await tester.ensureVisible(optimizeButton);
    await tester.tap(optimizeButton);
    await tester.pumpAndSettle();

    expect(find.text('Rest day · Take it slow'), findsOneWidget);
    expect(find.text('Light day · Flexible time'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('itinerary-rest-day-2'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('itinerary-flexible-day-3'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('saved settings use backend response and render all fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final savedPlaceService = _FakeSavedPlaceService(
      initial: [_savedPlace('place-a', 'Place A', 1)],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlaceDiscoveryScreen(
          city: _city,
          tripId: 'runtime-trip-settings',
          recommendationService: _FakeRecommendationService(),
          savedPlaceService: savedPlaceService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add notes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Visit before sunrise');
    tester.widget<Slider>(find.byType(Slider)).onChanged!(7);
    tester.widget<SwitchListTile>(find.byType(SwitchListTile).at(0)).onChanged!(
      true,
    );
    tester.widget<SwitchListTile>(find.byType(SwitchListTile).at(1)).onChanged!(
      true,
    );
    await tester.pump();
    await tester.tap(find.text('Save preferences'));
    await tester.pumpAndSettle();

    final update = savedPlaceService.settingsUpdates.single;
    expect(update.tripId, 'runtime-trip-settings');
    expect(update.placeId, 'place-a');
    expect(update.notes, 'Visit before sunrise');
    expect(update.priority, 7);
    expect(update.isLocked, isTrue);
    expect(update.mustVisit, isTrue);
    expect(find.text('Priority 7'), findsOneWidget);
    expect(find.text('Must visit'), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
    expect(find.text('Visit before sunrise'), findsOneWidget);
  });

  testWidgets('failed reorder reloads authoritative backend order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final savedPlaceService = _FakeSavedPlaceService(
      initial: [
        _savedPlace('place-a', 'Place A', 1),
        _savedPlace('place-b', 'Place B', 2),
        _savedPlace('place-c', 'Place C', 3),
      ],
      failReorder: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlaceDiscoveryScreen(
          city: _city,
          tripId: 'runtime-trip-reorder',
          recommendationService: _FakeRecommendationService(),
          savedPlaceService: savedPlaceService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorderItem!(0, 2);
    await tester.pumpAndSettle();

    expect(savedPlaceService.reorderRequests, [
      ['place-b', 'place-c', 'place-a'],
    ]);
    expect(savedPlaceService.loadTripIds, [
      'runtime-trip-reorder',
      'runtime-trip-reorder',
    ]);
    expect(find.text('Controlled reorder failure.'), findsWidgets);
  });

  testWidgets('failed delete keeps the target and unrelated saved places', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final savedPlaceService = _FakeSavedPlaceService(
      initial: [
        _savedPlace('place-a', 'Place A', 1),
        _savedPlace('place-b', 'Place B', 2),
      ],
      failRemove: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PlaceDiscoveryScreen(
          city: _city,
          tripId: 'runtime-trip-delete',
          recommendationService: _FakeRecommendationService(),
          savedPlaceService: savedPlaceService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove place').first);
    await tester.pumpAndSettle();

    expect(savedPlaceService.removeTripIds, ['runtime-trip-delete']);
    expect(find.text('2 saved'), findsOneWidget);
    expect(find.text('Place A'), findsOneWidget);
    expect(find.text('Place B'), findsOneWidget);
    expect(find.text('Controlled delete failure.'), findsWidgets);
  });

  testWidgets(
    'category filter requests filtered recommendations and restores on All',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = _FakeRecommendationService();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: _city,
            tripId: 'trip-filter',
            tripPurposes: const {'Food Exploration'},
            routeStartReady: true,
            recommendationService: service,
            savedPlaceService: _FakeSavedPlaceService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial request with Food
      expect(service.requests, hasLength(1));
      expect(service.purposeRequests.last, {'Food Exploration'});
      expect(service.filterRequests.last, isNull);

      // Tap "Add another interest" and add Cafes
      await tester.tap(find.text('Add another interest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cafes'));
      await tester.pump();
      await tester.tap(find.text('Update recommendations'));
      await tester.pumpAndSettle();

      expect(service.requests, hasLength(2));
      expect(service.requests.last, [PlaceCategory.food, PlaceCategory.cafes]);

      // Now category filter chips are visible (All, Food, Cafes)
      expect(find.byKey(const ValueKey('filter_cafes')), findsOneWidget);

      // Tap Cafes filter chip
      await tester.tap(find.byKey(const ValueKey('filter_cafes')));
      await tester.pumpAndSettle();

      expect(service.filterRequests.last, PlaceCategory.cafes);

      // Tap All filter chip
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      expect(service.filterRequests.last, isNull);
    },
  );
}

const _city = City(
  id: 'city-123',
  name: 'Ujjain',
  state: 'Madhya Pradesh',
  country: 'India',
  latitude: 23.1765,
  longitude: 75.7885,
);

const _threeDayRoute = OptimizedRoute(
  tripId: 'trip-day-states',
  places: [
    OptimizedRoutePlace(
      placeId: 'place-a',
      name: 'Place A',
      dayNumber: 1,
      visitOrder: 1,
      distanceFromPrevious: 1.2,
      travelTimeMinutes: 8,
      category: 'religious',
      normalizedCategory: 'place_of_worship',
    ),
  ],
  totalDistance: 1.2,
  totalTravelTimeMinutes: 8,
  totalDays: 3,
);

class _ControlledRecommendationService extends RecommendationService {
  _ControlledRecommendationService() : super(baseUrl: 'http://example.test');

  final Completer<List<Recommendation>> _completer = Completer();

  void complete(List<Recommendation> recommendations) =>
      _completer.complete(recommendations);

  void completeError(Object error) => _completer.completeError(error);

  @override
  Future<List<Recommendation>> getRecommendations(
    String cityId,
    Iterable<PlaceCategory> categories, {
    int limit = 30,
    String? tripId,
    Iterable<String>? purposes,
    Iterable<String>? interests,
    PlaceCategory? categoryFilter,
    String? cursor,
  }) => _completer.future;

  @override
  void close() {}
}

class _FakeRecommendationCache extends RecommendationCache {
  _FakeRecommendationCache(this.items);

  final List<Recommendation> items;
  List<String> writtenIds = [];

  @override
  String profileKey({
    required String cityId,
    required Iterable<String> purposes,
    required Iterable<PlaceCategory> categories,
    PlaceCategory? categoryFilter,
  }) => 'test-profile';

  @override
  Future<RecommendationCacheSnapshot?> read(String key) async =>
      RecommendationCacheSnapshot(
        recommendations: items,
        savedAt: DateTime.utc(2026, 9, 19),
        lastValidatedAt: DateTime.utc(2026, 9, 19),
        freshness: RecommendationCacheFreshness.fresh,
      );

  @override
  Future<void> write(
    String key,
    String cityId,
    Iterable<Recommendation> recommendations,
  ) async {
    writtenIds = recommendations.map((item) => item.id).toList();
  }
}

class _RecordingPlaceImagePrefetchService extends PlaceImagePrefetchService {
  final List<String> placeIds = [];

  @override
  Future<void> prefetchRecommendations(
    BuildContext context,
    Iterable<Recommendation> recommendations, {
    int concurrency = 4,
    int firstScreenful = 8,
    int nextScreenful = 8,
    String? requestId,
  }) async {
    placeIds.addAll(recommendations.map((place) => place.id));
  }
}

class _FakeTripService extends TripService {
  _FakeTripService() : super(baseUrl: 'http://example.test');

  @override
  Future<List<TripDay>> getTripDays(String tripId) async => [
    TripDay(
      id: 'day-1',
      tripId: tripId,
      dayNumber: 1,
      date: DateTime(2026, 9, 10),
      dayType: DayType.fullDay,
      startTime: '09:00:00',
      endTime: '19:00:00',
    ),
    TripDay(
      id: 'day-2',
      tripId: tripId,
      dayNumber: 2,
      date: DateTime(2026, 9, 11),
      dayType: DayType.rest,
    ),
    TripDay(
      id: 'day-3',
      tripId: tripId,
      dayNumber: 3,
      date: DateTime(2026, 9, 12),
      dayType: DayType.fullDay,
      startTime: '09:00:00',
      endTime: '19:00:00',
    ),
  ];

  @override
  void close() {}
}

class _FakeRecommendationService extends RecommendationService {
  _FakeRecommendationService() : super(baseUrl: 'http://example.test');

  final List<List<PlaceCategory>> requests = [];
  final List<PlaceCategory?> filterRequests = [];
  final List<Set<String>?> purposeRequests = [];

  @override
  Future<List<Recommendation>> getRecommendations(
    String cityId,
    Iterable<PlaceCategory> categories, {
    int limit = 30,
    String? tripId,
    Iterable<String>? purposes,
    Iterable<String>? interests,
    PlaceCategory? categoryFilter,
    String? cursor,
  }) async {
    requests.add(categories.toList(growable: false));
    filterRequests.add(categoryFilter);
    purposeRequests.add(purposes?.toSet());
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
  _FakeSavedPlaceService({
    List<SavedPlace> initial = const [],
    this.conflictOnNextAdd = false,
    this.failAdd = false,
    this.failReorder = false,
    this.failRemove = false,
  }) : savedPlaces = List.of(initial),
       super(baseUrl: 'http://example.test');

  List<SavedPlace> savedPlaces;
  bool conflictOnNextAdd;
  final bool failAdd;
  final bool failReorder;
  final bool failRemove;
  final List<String> loadTripIds = [];
  final List<String> addTripIds = [];
  final List<String> removeTripIds = [];
  final List<String> addedPlaceIds = [];
  final List<String> removedPlaceIds = [];
  final List<List<String>> reorderRequests = [];
  final Map<String, String?> noteUpdates = {};
  final List<
    ({
      String tripId,
      String placeId,
      String? notes,
      int priority,
      bool isLocked,
      bool mustVisit,
    })
  >
  settingsUpdates = [];

  @override
  Future<List<SavedPlace>> getSavedPlaces(String tripId) async {
    loadTripIds.add(tripId);
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
    AssignmentMode assignmentMode = AssignmentMode.auto,
    String? assignedDayId,
    String? notes,
  }) async {
    addTripIds.add(tripId);
    addedPlaceIds.add(placeId);
    if (failAdd) {
      throw const SavedPlaceServiceException(
        'Controlled save failure.',
        statusCode: 500,
      );
    }
    final saved = _savedPlace(
      placeId,
      'Mahakaleshwar Temple',
      customOrder ?? savedPlaces.length + 1,
      notes: notes,
      priority: priority,
      isLocked: isLocked,
      mustVisit: mustVisit,
      assignmentMode: assignmentMode,
      assignedDayId: assignedDayId,
    );
    if (conflictOnNextAdd) {
      conflictOnNextAdd = false;
      savedPlaces = [...savedPlaces, saved];
      throw const SavedPlaceServiceException(
        'This place is already saved to the trip.',
        statusCode: 409,
      );
    }
    savedPlaces = [...savedPlaces, saved];
    return saved;
  }

  @override
  Future<void> removeSavedPlace(String tripId, String placeId) async {
    removeTripIds.add(tripId);
    removedPlaceIds.add(placeId);
    if (failRemove) {
      throw const SavedPlaceServiceException(
        'Controlled delete failure.',
        statusCode: 500,
      );
    }
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
    if (failReorder) {
      throw const SavedPlaceServiceException(
        'Controlled reorder failure.',
        statusCode: 500,
      );
    }
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
    AssignmentMode? assignmentMode,
    String? assignedDayId,
    String? notes,
  }) async {
    settingsUpdates.add((
      tripId: tripId,
      placeId: placeId,
      notes: notes,
      priority: priority,
      isLocked: isLocked,
      mustVisit: mustVisit,
    ));
    noteUpdates[placeId] = notes;
    final current = savedPlaces.firstWhere((item) => item.placeId == placeId);
    final updated = _copySavedPlace(
      current,
      notes: notes,
      priority: priority,
      isLocked: isLocked,
      mustVisit: mustVisit,
      customOrder: customOrder,
      assignmentMode: assignmentMode,
      assignedDayId: assignedDayId,
    );
    savedPlaces = [
      for (final item in savedPlaces)
        if (item.placeId == placeId) updated else item,
    ];
    return updated;
  }

  @override
  Future<SavedPlace> updateAssignment(
    String tripId,
    String placeId, {
    required AssignmentMode assignmentMode,
    String? assignedDayId,
  }) async {
    final current = savedPlaces.firstWhere((item) => item.placeId == placeId);
    final updated = _copySavedPlace(
      current,
      assignmentMode: assignmentMode,
      assignedDayId: assignedDayId,
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
          dayNumber: 1,
          visitOrder: 1,
          distanceFromPrevious: 2.1,
          travelTimeMinutes: 8,
        ),
        OptimizedRoutePlace(
          placeId: 'place-a',
          name: 'Place A',
          dayNumber: 1,
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

class _ControlledRouteOptimizationService extends RouteOptimizationService {
  _ControlledRouteOptimizationService() : super(baseUrl: 'http://example.test');

  final Completer<OptimizedRoute> _completer = Completer();

  void complete(OptimizedRoute route) => _completer.complete(route);

  @override
  Future<OptimizedRoute> optimizeRoute(String tripId) => _completer.future;

  @override
  void close() {}
}

class _DayStateRouteOptimizationService extends RouteOptimizationService {
  _DayStateRouteOptimizationService() : super(baseUrl: 'http://example.test');

  @override
  Future<OptimizedRoute> optimizeRoute(String tripId) async => _threeDayRoute;

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
  AssignmentMode assignmentMode = AssignmentMode.auto,
  String? assignedDayId,
}) {
  return SavedPlace(
    id: 'saved-$placeId',
    tripId: 'trip-123',
    placeId: placeId,
    customOrder: customOrder,
    priority: priority,
    isLocked: isLocked,
    mustVisit: mustVisit,
    assignmentMode: assignmentMode,
    assignedDayId: assignedDayId,
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
  AssignmentMode? assignmentMode,
  String? assignedDayId,
}) {
  return SavedPlace(
    id: savedPlace.id,
    tripId: savedPlace.tripId,
    placeId: savedPlace.placeId,
    customOrder: customOrder ?? savedPlace.customOrder,
    priority: priority ?? savedPlace.priority,
    isLocked: isLocked ?? savedPlace.isLocked,
    mustVisit: mustVisit ?? savedPlace.mustVisit,
    assignmentMode: assignmentMode ?? savedPlace.assignmentMode,
    assignedDayId: assignedDayId ?? savedPlace.assignedDayId,
    notes: notes ?? savedPlace.notes,
    place: savedPlace.place,
  );
}
