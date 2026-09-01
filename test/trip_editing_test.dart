import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/trip_draft.dart';
import 'package:yatra_canvas/models/trip_start_location.dart';
import 'package:yatra_canvas/screens/create_trip/trip_preferences_screen.dart';
import 'package:yatra_canvas/screens/place_discovery/place_discovery_screen.dart';
import 'package:yatra_canvas/services/trip_service.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

void main() {
  test('TripDraft.fromJson deserializes GET /trips/{trip_id} response', () {
    final json = {
      'trip_id': '33333333-3333-4333-8333-333333333333',
      'city_id': '11111111-1111-4111-8111-111111111111',
      'city': {
        'id': '11111111-1111-4111-8111-111111111111',
        'name': 'Ujjain',
        'state': 'Madhya Pradesh',
        'country': 'India',
        'latitude': 23.1765,
        'longitude': 75.7885,
      },
      'trip_name': 'Ujjain Spiritual Trip',
      'days': 4,
      'start_date': '2026-09-10',
      'end_date': '2026-09-13',
      'arrival_place': 'Ujjain Railway Station',
      'arrival_latitude': 23.1793,
      'arrival_longitude': 75.7849,
      'start_location_type': 'hotel',
      'start_location_name': 'Hotel Imperial',
      'start_latitude': 23.1801,
      'start_longitude': 75.7812,
      'start_location_provider': 'geoapify',
      'start_location_provider_place_id': 'geoapify-hotel-imperial',
      'preferences': [
        'Religious / Spiritual',
        'Culture & Heritage',
        'Packed',
        'Boujee',
        'Own Vehicle',
      ],
    };

    final draft = TripDraft.fromJson(json);

    expect(draft.tripId, '33333333-3333-4333-8333-333333333333');
    expect(draft.destination?.name, 'Ujjain');
    expect(draft.destination?.state, 'Madhya Pradesh');
    expect(draft.durationDays, 4);
    expect(draft.startDate, DateTime(2026, 9, 10));
    expect(draft.endDate, DateTime(2026, 9, 13));
    expect(draft.arrivalPoint, 'Ujjain Railway Station');
    expect(draft.arrivalLatitude, 23.1793);
    expect(draft.arrivalLongitude, 75.7849);
    expect(draft.startLocationType, TripStartLocationType.hotel);
    expect(draft.startLocationName, 'Hotel Imperial');
    expect(draft.startLatitude, 23.1801);
    expect(draft.startLongitude, 75.7812);
    expect(draft.startLocationProvider, 'geoapify');
    expect(draft.startLocationProviderPlaceId, 'geoapify-hotel-imperial');
    expect(draft.travelPace, 'Packed');
    expect(draft.budget, 'Boujee');
    expect(draft.transportPreferences, {'Own Vehicle'});
    expect(draft.purposes, {'Religious / Spiritual', 'Culture & Heritage'});
  });

  test('TripService.getTrip loads an existing trip by ID', () async {
    final service = TripService(
      baseUrl: 'http://api.test',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.path,
          '/trips/33333333-3333-4333-8333-333333333333',
        );
        return http.Response(
          jsonEncode({
            'trip_id': '33333333-3333-4333-8333-333333333333',
            'city_id': '11111111-1111-4111-8111-111111111111',
            'city': {
              'id': '11111111-1111-4111-8111-111111111111',
              'name': 'Ujjain',
              'country': 'India',
              'latitude': 23.1765,
              'longitude': 75.7885,
            },
            'trip_name': 'Ujjain Spiritual Trip',
            'days': 3,
            'start_date': '2026-09-10',
            'end_date': '2026-09-12',
            'arrival_place': 'Ujjain Railway Station',
            'start_location_type': 'arrival',
            'start_location_name': 'Ujjain Railway Station',
            'preferences': ['Relaxed', 'Saver', 'Walking'],
          }),
          200,
        );
      }),
    );

    final draft = await service.getTrip('33333333-3333-4333-8333-333333333333');

    expect(draft.tripId, '33333333-3333-4333-8333-333333333333');
    expect(draft.destination?.name, 'Ujjain');
    expect(draft.travelPace, 'Relaxed');
    expect(draft.budget, 'Saver');
    expect(draft.transportPreferences, {'Walking'});
  });

  test('TripService.updateTrip sends PATCH request with supported fields', () async {
    late Map<String, dynamic> patchBody;
    final service = TripService(
      baseUrl: 'http://api.test',
      client: MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(
          request.url.path,
          '/trips/33333333-3333-4333-8333-333333333333',
        );
        patchBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'trip_id': '33333333-3333-4333-8333-333333333333',
            'city_id': '11111111-1111-4111-8111-111111111111',
            'trip_name': 'Ujjain Spiritual Trip',
            'days': 5,
            'start_date': '2026-09-15',
            'end_date': '2026-09-19',
            'arrival_place': 'Indore Airport',
            'arrival_latitude': 22.7217,
            'arrival_longitude': 75.8011,
            'start_location_type': 'hotel',
            'start_location_name': 'Hotel Imperial',
            'start_latitude': 23.1801,
            'start_longitude': 75.7812,
            'start_location_provider': 'geoapify',
            'start_location_provider_place_id': 'geoapify-hotel-imperial',
            'preferences': ['Packed', 'Boujee', 'Own Vehicle', 'Food Exploration'],
          }),
          200,
        );
      }),
    );

    final draft = TripDraft(
      tripId: '33333333-3333-4333-8333-333333333333',
      destination: const City(
        id: '11111111-1111-4111-8111-111111111111',
        name: 'Ujjain',
        country: 'India',
        latitude: 23.1765,
        longitude: 75.7885,
      ),
      startDate: DateTime(2026, 9, 15),
      endDate: DateTime(2026, 9, 19),
      durationDays: 5,
      arrivalPoint: 'Indore Airport',
      arrivalLatitude: 22.7217,
      arrivalLongitude: 75.8011,
      startLocationType: TripStartLocationType.hotel,
      startLocationName: 'Hotel Imperial',
      startLatitude: 23.1801,
      startLongitude: 75.7812,
      startLocationProvider: 'geoapify',
      startLocationProviderPlaceId: 'geoapify-hotel-imperial',
      purposes: {'Food Exploration'},
      travelPace: 'Packed',
      budget: 'Boujee',
      transportPreferences: {'Own Vehicle'},
    );

    final updated = await service.updateTrip(draft.tripId!, draft);

    expect(updated.tripId, '33333333-3333-4333-8333-333333333333');
    expect(patchBody['city_id'], '11111111-1111-4111-8111-111111111111');
    expect(patchBody['start_date'], '2026-09-15');
    expect(patchBody['end_date'], '2026-09-19');
    expect(patchBody['days'], 5);
    expect(patchBody['arrival_place'], 'Indore Airport');
    expect(patchBody.containsKey('user_id'), isFalse);
    expect(patchBody.containsKey('created_at'), isFalse);
  });

  test('TripService reports 404 for unknown trip', () async {
    final service = TripService(
      baseUrl: 'http://api.test',
      client: MockClient(
        (_) async => http.Response('{"detail":"Trip not found."}', 404),
      ),
    );

    await expectLater(
      service.getTrip('00000000-0000-0000-0000-000000000000'),
      throwsA(
        isA<TripServiceException>().having(
          (e) => e.message,
          'message',
          'Trip not found.',
        ),
      ),
    );
  });

  testWidgets(
    'TripPreferencesScreen calls updateTrip for existing trip and navigates without creating a new trip',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final draft = TripDraft(
        tripId: '33333333-3333-4333-8333-333333333333',
        destination: const City(
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Ujjain',
          country: 'India',
          latitude: 23.1765,
          longitude: 75.7885,
        ),
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 12),
        durationDays: 3,
        arrivalPoint: 'Ujjain Railway Station',
      );

      final service = _ControlledEditingTripService();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TripPreferencesScreen(draft: draft, tripService: service),
        ),
      );

      final button = find.widgetWithText(FilledButton, 'Save & Discover Places');
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();

      expect(service.updateCalls, 1);
      expect(service.createCalls, 0);

      service.complete();
      await tester.pump();
      await tester.pump();

      expect(draft.tripId, '33333333-3333-4333-8333-333333333333');
      expect(find.byType(PlaceDiscoveryScreen), findsOneWidget);
      final discovery = tester.widget<PlaceDiscoveryScreen>(
        find.byType(PlaceDiscoveryScreen),
      );
      expect(discovery.tripId, '33333333-3333-4333-8333-333333333333');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _ControlledEditingTripService extends TripService {
  final _completer = Completer<TripDraft>();
  int updateCalls = 0;
  int createCalls = 0;

  @override
  Future<TripDraft> updateTrip(String tripId, TripDraft draft) {
    updateCalls++;
    return _completer.future;
  }

  void complete() {
    _completer.complete(
      TripDraft(
        tripId: '33333333-3333-4333-8333-333333333333',
        destination: const City(
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Ujjain',
          country: 'India',
          latitude: 23.1765,
          longitude: 75.7885,
        ),
      ),
    );
  }
}
