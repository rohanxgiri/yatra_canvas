import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/place.dart';
import 'package:yatra_canvas/models/trip_draft.dart';
import 'package:yatra_canvas/screens/create_trip/destination_selection_screen.dart';
import 'package:yatra_canvas/screens/create_trip/trip_purpose_screen.dart';
import 'package:yatra_canvas/screens/place_discovery/place_discovery_screen.dart';
import 'package:yatra_canvas/services/city_service.dart';
import 'package:yatra_canvas/services/place_prefetch_service.dart';
import 'package:yatra_canvas/services/recommendation_service.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

void main() {
  const testCity = City(
    id: 'kochi-123',
    name: 'Kochi',
    state: 'Kerala',
    country: 'India',
    latitude: 9.9312,
    longitude: 76.2673,
  );

  test(
    'RecommendationService prefetchCityPlaces issues POST /places/prefetch',
    () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        if (request.url.path == '/places/prefetch') {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'city_id': 'kochi-123',
              'city_name': 'Kochi',
              'stage': 'destination_confirmed',
              'categories_requested': ['tourism', 'heritage'],
              'categories_skipped_sufficient': [],
              'categories_enriched': ['tourism', 'heritage'],
              'duplicate_refreshes_prevented': 0,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final service = RecommendationService(
        client: client,
        baseUrl: 'http://10.0.2.2:8001',
      );

      await service.prefetchCityPlaces(
        'kochi-123',
        stage: 'destination_confirmed',
        categories: [PlaceCategory.tourism, PlaceCategory.heritage],
      );

      expect(capturedBody, isNotNull);
      expect(capturedBody!['city_id'], 'kochi-123');
      expect(capturedBody!['stage'], 'destination_confirmed');
      expect(capturedBody!['categories'], ['tourism', 'heritage']);
    },
  );

  testWidgets(
    'DestinationSelectionScreen starts prefetch without delaying navigation',
    (tester) async {
      var prefetchCalled = false;
      final releasePrefetch = Completer<void>();

      final client = MockClient((request) async {
        if (request.url.path == '/places/prefetch') {
          prefetchCalled = true;
          await releasePrefetch.future;
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200);
      });

      final cityService = CityService(
        client: client,
        baseUrl: 'http://10.0.2.2:8001',
      );
      final prefetchService = PlacePrefetchService(
        client: client,
        baseUrl: 'http://10.0.2.2:8001',
      );

      final draft = TripDraft()..destination = testCity;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DestinationSelectionScreen(
            draft: draft,
            cityService: cityService,
            prefetchService: prefetchService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find and tap Continue button
      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      expect(continueButton, findsOneWidget);
      await tester.tap(continueButton);

      // The next screen renders while the enqueue request is still pending.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(prefetchCalled, isTrue);
      expect(find.text('When are you travelling?'), findsOneWidget);
      releasePrefetch.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('TripPurposeScreen starts targeted enrichment and navigates', (
    tester,
  ) async {
    Map<String, dynamic>? payload;
    final client = MockClient((request) async {
      payload = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{}', 202);
    });
    final prefetchService = PlacePrefetchService(
      client: client,
      baseUrl: 'http://api.test',
    );
    final draft = TripDraft()..destination = testCity;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TripPurposeScreen(draft: draft, prefetchService: prefetchService),
      ),
    );
    await tester.pumpAndSettle();

    // Select 'Food Exploration' and 'Culture & Heritage'
    await tester.tap(find.text('Food Exploration'));
    await tester.tap(find.text('Culture & Heritage'));
    await tester.pump();

    // Tap Continue
    final continueButton = find.widgetWithText(FilledButton, 'Continue');
    await tester.tap(continueButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Navigated to preferences
    expect(find.text('How do you like to travel?'), findsOneWidget);

    expect(payload?['stage'], 'interests_confirmed');
    expect(payload?['categories'], containsAll(<String>['food', 'heritage']));
  });

  test(
    'PlacePrefetchService deduplicates identical in-flight requests',
    () async {
      final release = Completer<void>();
      var calls = 0;
      final service = PlacePrefetchService(
        baseUrl: 'http://api.test',
        client: MockClient((_) async {
          calls++;
          await release.future;
          return http.Response('{}', 202);
        }),
      );

      final first = service.prefetchCity(
        'kochi-123',
        stage: PrefetchStage.destinationConfirmed,
      );
      final second = service.prefetchCity(
        'kochi-123',
        stage: PrefetchStage.destinationConfirmed,
      );
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
      release.complete();
      await Future.wait([first, second]);
    },
  );

  test('PlacePrefetchService sends date and start-location stages', () async {
    final payloads = <Map<String, dynamic>>[];
    final service = PlacePrefetchService(
      baseUrl: 'http://api.test',
      client: MockClient((request) async {
        payloads.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{}', 202);
      }),
    );

    await service.prefetchCity(
      'kochi-123',
      stage: PrefetchStage.datesConfirmed,
      startDate: DateTime(2026, 9, 10),
      endDate: DateTime(2026, 9, 12),
    );
    await service.prefetchCity(
      'kochi-123',
      stage: PrefetchStage.startLocationConfirmed,
      startLatitude: 9.93,
      startLongitude: 76.26,
    );

    expect(payloads[0]['stage'], 'dates_confirmed');
    expect(payloads[0]['start_date'], '2026-09-10');
    expect(payloads[1]['stage'], 'start_location_confirmed');
    expect(payloads[1]['start_latitude'], 9.93);
  });

  testWidgets(
    'PlaceDiscoveryScreen preserves existing recommendations when reload fails',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var callCount = 0;
      final client = MockClient((request) async {
        if (request.url.path.contains('/recommendations')) {
          callCount++;
          if (callCount == 1) {
            return http.Response(
              jsonEncode([
                {
                  'id': 'place-fort-kochi',
                  'name': 'Fort Kochi Beach',
                  'category': 'tourism',
                  'latitude': 9.9658,
                  'longitude': 76.2421,
                  'rating': 4.5,
                  'review_count': 120,
                  'is_popular': true,
                  'is_heritage': true,
                  'is_local_speciality': false,
                  'matched_categories': ['tourism'],
                  'recommendation_score': 88.0,
                  'recommendation_reason': 'Popular tourist spot',
                  'access_confidence': 'PUBLIC_LIKELY',
                  'is_saved': false,
                },
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          } else {
            // Second call (e.g. reload or retry) fails
            return http.Response('Overpass timeout', 504);
          }
        }
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final recService = RecommendationService(
        client: client,
        baseUrl: 'http://10.0.2.2:8001',
      );

      tester.view.physicalSize = const Size(390, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripPurposes: const {'Sightseeing'},
            recommendationService: recService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial recommendations rendered
      expect(find.text('Fort Kochi Beach'), findsOneWidget);

      // Trigger pull-to-refresh
      final refreshIndicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      await refreshIndicator.onRefresh();
      await tester.pumpAndSettle();

      // Recommendations MUST still be visible! Not covered by blocking error screen!
      expect(find.text('Fort Kochi Beach'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    },
  );
}

