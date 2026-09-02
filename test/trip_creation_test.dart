import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/created_trip.dart';
import 'package:yatra_canvas/models/trip_draft.dart';
import 'package:yatra_canvas/models/trip_start_location.dart';
import 'package:yatra_canvas/screens/create_trip/trip_preferences_screen.dart';
import 'package:yatra_canvas/screens/place_discovery/place_discovery_screen.dart';
import 'package:yatra_canvas/services/trip_service.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

void main() {
  test(
    'TripService sends the existing draft and returns a real trip id',
    () async {
      late Map<String, dynamic> requestBody;
      final service = TripService(
        baseUrl: 'http://api.test',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/trips');
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            '{"trip_id":"22222222-2222-4222-8222-222222222222"}',
            201,
          );
        }),
      );
      final draft = _draft();

      final created = await service.createTrip(draft);

      expect(created.tripId, '22222222-2222-4222-8222-222222222222');
      expect(requestBody, {
        'city_id': '11111111-1111-4111-8111-111111111111',
        'start_date': '2026-09-10',
        'end_date': '2026-09-12',
        'days': 3,
        'arrival_place': 'Ujjain Railway Station',
        'arrival_latitude': 23.1793,
        'arrival_longitude': 75.7849,
        'start_location_type': 'hotel',
        'start_location_name': 'Hotel Imperial',
        'start_latitude': 23.1801,
        'start_longitude': 75.7812,
        'start_location_provider': 'geoapify',
        'start_location_provider_place_id': 'geoapify-hotel-imperial',
        'purposes': ['Culture & Heritage', 'Religious / Spiritual'],
        'preferences': ['Balanced', 'Chill', 'Auto / Cab', 'Walking'],
      });
      expect(requestBody.containsKey('user_id'), isFalse);
      expect(requestBody.containsKey('trip_id'), isFalse);
      expect(requestBody.containsKey('created_at'), isFalse);
    },
  );

  test(
    'TripService reports validation, network, and malformed responses',
    () async {
      final validation = TripService(
        baseUrl: 'http://api.test',
        client: MockClient(
          (_) async => http.Response(
            '{"detail":[{"msg":"Value error, Days must match the inclusive trip date range."}]}',
            422,
          ),
        ),
      );
      await expectLater(
        validation.createTrip(_draft()),
        throwsA(
          isA<TripServiceException>().having(
            (error) => error.message,
            'message',
            'Days must match the inclusive trip date range.',
          ),
        ),
      );

      final network = TripService(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        network.createTrip(_draft()),
        throwsA(
          isA<TripServiceException>().having(
            (error) => error.message,
            'message',
            contains('Check your connection'),
          ),
        ),
      );

      final malformed = TripService(
        baseUrl: 'http://api.test',
        client: MockClient((_) async => http.Response('{}', 201)),
      );
      await expectLater(
        malformed.createTrip(_draft()),
        throwsA(
          isA<TripServiceException>().having(
            (error) => error.message,
            'message',
            contains('invalid trip response'),
          ),
        ),
      );
    },
  );

  testWidgets('submission blocks duplicate taps and retains trip id', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final draft = _draft();
    final service = _ControlledTripService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TripPreferencesScreen(draft: draft, tripService: service),
      ),
    );

    final button = find.widgetWithText(FilledButton, 'Find Places For Me');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();

    expect(service.calls, 1);
    expect(find.text('Creating Trip…'), findsOneWidget);
    expect(draft.tripId, isNull);

    service.complete('22222222-2222-4222-8222-222222222222');
    await tester.pump();
    await tester.pump();

    expect(draft.tripId, '22222222-2222-4222-8222-222222222222');
    expect(find.byType(PlaceDiscoveryScreen), findsOneWidget);
    final discovery = tester.widget<PlaceDiscoveryScreen>(
      find.byType(PlaceDiscoveryScreen),
    );
    expect(discovery.tripId, draft.tripId);
    expect(discovery.tripPurposes, draft.purposes);
    expect(discovery.routeStartReady, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed creation shows an error and does not navigate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final draft = _draft();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TripPreferencesScreen(
          draft: draft,
          tripService: _FailingTripService(),
        ),
      ),
    );

    final button = find.widgetWithText(FilledButton, 'Find Places For Me');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(find.text('The trip could not be saved.'), findsOneWidget);
    expect(find.byType(TripPreferencesScreen), findsOneWidget);
    expect(find.byType(PlaceDiscoveryScreen), findsNothing);
    expect(draft.tripId, isNull);
  });
}

TripDraft _draft() {
  return TripDraft(
    destination: const City(
      id: '11111111-1111-4111-8111-111111111111',
      name: 'Ujjain',
      state: 'Madhya Pradesh',
      country: 'India',
      latitude: 23.1765,
      longitude: 75.7885,
    ),
    startDate: DateTime(2026, 9, 10),
    endDate: DateTime(2026, 9, 12),
    durationDays: 3,
    arrivalPoint: 'Ujjain Railway Station',
    arrivalLatitude: 23.1793,
    arrivalLongitude: 75.7849,
    startLocationType: TripStartLocationType.hotel,
    startLocationName: 'Hotel Imperial',
    startLatitude: 23.1801,
    startLongitude: 75.7812,
    startLocationProvider: 'geoapify',
    startLocationProviderPlaceId: 'geoapify-hotel-imperial',
    purposes: {'Religious / Spiritual', 'Culture & Heritage'},
    travelPace: 'Balanced',
    budget: 'Chill',
    transportPreferences: {'Walking', 'Auto / Cab'},
  );
}

class _ControlledTripService extends TripService {
  final _completer = Completer<CreatedTrip>();
  int calls = 0;

  @override
  Future<CreatedTrip> createTrip(TripDraft draft) {
    calls++;
    return _completer.future;
  }

  void complete(String tripId) {
    _completer.complete(CreatedTrip(tripId: tripId));
  }
}

class _FailingTripService extends TripService {
  @override
  Future<CreatedTrip> createTrip(TripDraft draft) {
    throw const TripServiceException('The trip could not be saved.');
  }
}
