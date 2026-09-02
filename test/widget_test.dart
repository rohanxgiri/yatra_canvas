import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/main.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/trip_draft.dart';
import 'package:yatra_canvas/screens/create_trip/destination_selection_screen.dart';
import 'package:yatra_canvas/screens/home/home_screen.dart';
import 'package:yatra_canvas/screens/onboarding/login_screen.dart';
import 'package:yatra_canvas/screens/place_discovery/place_discovery_screen.dart';
import 'package:yatra_canvas/services/city_service.dart';
import 'package:yatra_canvas/services/trip_service.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

void main() {
  testWidgets('opens the onboarding flow from splash', (tester) async {
    await tester.pumpWidget(const YatraCanvasApp());

    expect(find.text('Your journey, mapped.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(
      find.text('Turn your travel ideas\ninto a journey.'),
      findsOneWidget,
    );
    expect(find.text('Continue as Guest'), findsNothing);
  });

  testWidgets('login offers phone, Google, Apple, and guest access', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
    );

    expect(find.text('Mobile number'), findsOneWidget);
    expect(find.text('Continue with Phone'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue as Guest'), findsOneWidget);
  });

  testWidgets('create trip flow advances through all five steps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final draft = TripDraft();
    final cityService = CityService(
      baseUrl: 'http://api.test',
      client: MockClient((request) async {
        if (request.url.path == '/locations/autocomplete') {
          return http.Response('{"results":[]}', 200);
        }
        return http.Response(
          request.method == 'GET' ? '[$_ujjainResponse]' : _ujjainResponse,
          200,
        );
      }),
    );
    final tripService = TripService(
      baseUrl: 'http://api.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/trips');
        return http.Response(
          '{"trip_id":"22222222-2222-4222-8222-222222222222"}',
          201,
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DestinationSelectionScreen(
          draft: draft,
          cityService: cityService,
          tripService: tripService,
        ),
      ),
    );

    expect(find.text('Where are you\ngoing?'), findsOneWidget);

    final continueButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(continueButton.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'uj');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.text('Ujjain'));
    await tester.pumpAndSettle();

    draft
      ..arrivalPoint = 'Ujjain Railway Station'
      ..arrivalLatitude = 23.1793
      ..arrivalLongitude = 75.7849
      ..startLocationName = 'Ujjain Railway Station'
      ..startLatitude = 23.1793
      ..startLongitude = 75.7849;

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('When are you\ntravelling?'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('How are you\nreaching Ujjain?'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('What brings you\nto Ujjain?'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('How do you like\nto travel?'), findsOneWidget);

    await tester.tap(find.text('Find Places For Me'));
    await tester.pump();
    await tester.pump();
    expect(draft.tripId, '22222222-2222-4222-8222-222222222222');
    expect(find.byType(PlaceDiscoveryScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('city search is debounced and selected city is resolved', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final draft = TripDraft(
      destination: const City(
        id: 'old-city-id',
        name: 'Ujjain',
        state: 'Madhya Pradesh',
        country: 'India',
        latitude: 23.1765,
        longitude: 75.7885,
      ),
      arrivalPoint: 'Ujjain Railway Station',
      arrivalLatitude: 23.1793,
      arrivalLongitude: 75.7849,
      startLocationName: 'Ujjain Railway Station',
      startLatitude: 23.1793,
      startLongitude: 75.7849,
    );
    final cityService = CityService(
      baseUrl: 'http://api.test',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/cities/autocomplete') {
          return http.Response('[]', 200);
        }
        return http.Response(
          request.method == 'GET'
              ? '[$_gandhinagarResponse]'
              : _gandhinagarResponse,
          200,
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DestinationSelectionScreen(
          draft: draft,
          cityService: cityService,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'g');
    await tester.pump(const Duration(milliseconds: 500));
    expect(requests, isEmpty);

    await tester.enterText(find.byType(TextField), 'gandhi');
    await tester.pump(const Duration(milliseconds: 399));
    expect(requests, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(requests, hasLength(2));
    expect(requests.first.method, 'GET');
    expect(requests.first.url.path, '/cities/search');
    expect(requests.first.url.queryParameters['query'], 'gandhi');
    expect(requests.last.url.path, '/cities/autocomplete');
    expect(find.text('Gandhinagar'), findsOneWidget);
    expect(find.text('Gujarat, India'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('New'), findsNothing);

    await tester.tap(find.text('Gandhinagar'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(2));
    expect(draft.destination?.id, '11111111-1111-1111-1111-111111111111');
    expect(draft.arrivalPoint, isEmpty);
    expect(draft.arrivalLatitude, isNull);
    expect(draft.startLocationName, isNull);
    expect(draft.startLatitude, isNull);
    expect(find.text('CITY ADDED TO YOUR TRIP'), findsOneWidget);
  });

  testWidgets('Geoapify city resolves and stores UUID', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requests = <http.Request>[];
    final draft = TripDraft();
    final cityService = CityService(
      baseUrl: 'http://api.test',
      client: MockClient((request) async {
        requests.add(request);
        return switch (request.url.path) {
          '/cities/search' => http.Response('[]', 200),
          '/cities/autocomplete' => http.Response(
            jsonEncode([
              {
                'name': 'Gandhinagar',
                'description': 'Gujarat, India',
                'provider_place_id': '11111111-1111-1111-1111-111111111111',
              },
            ]),
            200,
          ),
          '/cities/place-details/11111111-1111-1111-1111-111111111111' =>
            http.Response(_gandhinagarUnresolvedResponse, 200),
          '/cities/resolve' => http.Response(_gandhinagarResponse, 200),
          _ => http.Response('Not found', 404),
        };
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DestinationSelectionScreen(
          draft: draft,
          cityService: cityService,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'gandhi');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Gandhinagar'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Geoapify • OpenStreetMap'), findsOneWidget);

    await tester.tap(find.text('Gandhinagar'));
    await tester.pumpAndSettle();

    expect(requests.map((request) => request.url.path), [
      '/cities/search',
      '/cities/autocomplete',
      '/cities/place-details/11111111-1111-1111-1111-111111111111',
      '/cities/resolve',
    ]);
    expect(draft.destination?.id, '11111111-1111-1111-1111-111111111111');
    expect(find.text('CITY ADDED TO YOUR TRIP'), findsOneWidget);
  });

  testWidgets('city search shows empty and backend error states', (
    tester,
  ) async {
    var shouldFail = false;
    final cityService = CityService(
      baseUrl: 'http://api.test',
      client: MockClient((request) async {
        if (shouldFail) {
          return http.Response('{"detail":"Search service unavailable."}', 503);
        }
        return request.url.path == '/locations/autocomplete'
            ? http.Response('{"results":[]}', 200)
            : http.Response('[]', 200);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DestinationSelectionScreen(cityService: cityService),
      ),
    );

    await tester.enterText(find.byType(TextField), 'zz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('No cities found'), findsOneWidget);

    shouldFail = true;
    await tester.enterText(find.byType(TextField), 'gandhi');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Search service unavailable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Home create navigation opens and returns from trip setup', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Where are you\ngoing?'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Trip'));
    await tester.pumpAndSettle();
    expect(find.text('Where are you\ngoing?'), findsOneWidget);
  });
}

const _gandhinagarResponse = '''
{
  "id": "11111111-1111-1111-1111-111111111111",
  "name": "Gandhinagar",
  "state": "Gujarat",
  "country": "India",
  "latitude": 23.2156,
  "longitude": 72.6369,
  "provider_place_id": "11111111-1111-1111-1111-111111111111",
  "created_at": "2026-08-30T12:00:00Z"
}
''';

const _gandhinagarUnresolvedResponse = '''
{
  "name": "Gandhinagar",
  "state": "Gujarat",
  "country": "India",
  "latitude": 23.2156,
  "longitude": 72.6369,
  "provider_place_id": "11111111-1111-1111-1111-111111111111"
}
''';

const _gandhinagarLocationResponse = '''
{
  "results": [
    {
      "provider": "geoapify",
      "provider_place_id": "geoapify-gandhinagar",
      "name": "Gandhinagar",
      "formatted_address": "Gandhinagar, GJ, India",
      "latitude": 23.2156,
      "longitude": 72.6369,
      "city": "Gandhinagar",
      "state": "Gujarat",
      "country_code": "in",
      "result_type": "city"
    }
  ]
}
''';

const _ujjainResponse = '''
{
  "id": "22222222-2222-2222-2222-222222222222",
  "name": "Ujjain",
  "state": "Madhya Pradesh",
  "country": "India",
  "latitude": 23.1765,
  "longitude": 75.7885,
  "google_place_id": "test_ujjain_001",
  "created_at": "2026-08-30T12:00:00Z"
}
''';
