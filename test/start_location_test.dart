import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/models/trip_draft.dart';
import 'package:yatra_canvas/models/trip_start_location.dart';
import 'package:yatra_canvas/screens/create_trip/arrival_details_screen.dart';
import 'package:yatra_canvas/services/device_location_service.dart';
import 'package:yatra_canvas/services/location_service.dart';
import 'package:yatra_canvas/services/trip_service.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

void main() {
  test('location and trip services use normalized backend endpoints', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/locations/autocomplete') {
        return http.Response('{"results":[$_hotelSuggestionJson]}', 200);
      }
      if (request.url.path == '/trips/trip-123/start-location') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body, {
          'start_location_type': 'hotel',
          'start_location_name': 'Hotel Imperial, Ujjain, India',
          'start_latitude': 23.1801,
          'start_longitude': 75.7812,
          'start_location_provider': 'geoapify',
          'start_location_provider_place_id': 'geoapify-hotel-imperial',
        });
        return http.Response(_tripStartJson, 200);
      }
      return http.Response('Not found', 404);
    });
    final locations = LocationService(
      client: client,
      baseUrl: 'http://api.test',
    );
    final trips = TripService(client: client, baseUrl: 'http://api.test');

    final suggestions = await locations.autocomplete(
      'imperial',
      hotelOnly: true,
      latitude: 23.1765,
      longitude: 75.7885,
    );
    expect(suggestions.single.name, 'Hotel Imperial');
    final saved = await trips.updateStartLocation(
      'trip-123',
      type: TripStartLocationType.hotel,
      name: suggestions.single.formattedAddress,
      latitude: suggestions.single.latitude,
      longitude: suggestions.single.longitude,
      provider: suggestions.single.provider,
      providerPlaceId: suggestions.single.providerPlaceId,
    );
    expect(saved.type, TripStartLocationType.hotel);
    expect(requests.first.url.queryParameters, {
      'query': 'imperial',
      'type': 'amenity',
      'country_code': 'in',
      'limit': '5',
      'latitude': '23.1765',
      'longitude': '75.7885',
    });
  });

  testWidgets(
    'hotel start is searched, resolved, and saved before continuing',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final draft = TripDraft(
        tripId: 'trip-123',
        arrivalLatitude: 23.1793,
        arrivalLongitude: 75.7849,
      );
      final locationService = _FakeLocationService();
      final tripService = _FakeTripService();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ArrivalDetailsScreen(
            draft: draft,
            locationService: locationService,
            tripService: tripService,
            deviceLocationService: _FakeDeviceLocationService(),
          ),
        ),
      );

      await tester.ensureVisible(find.text('Hotel'));
      await tester.tap(find.text('Hotel'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search hotels in your city'),
        'imperial',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(locationService.hotelOnly, isTrue);
      expect(find.text('Hotel Imperial'), findsOneWidget);
      expect(
        find.text('Powered by Geoapify • © OpenStreetMap contributors'),
        findsOneWidget,
      );
      await tester.tap(find.text('Hotel Imperial'));
      await tester.pumpAndSettle();
      expect(
        find.text('Powered by Geoapify • © OpenStreetMap contributors'),
        findsOneWidget,
      );
      expect(draft.startLocationType, TripStartLocationType.arrival);

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Continue'));
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(draft.startLocationType, TripStartLocationType.hotel);
      expect(draft.startLocationName, 'Hotel Imperial, Ujjain, India');
      expect(draft.startLatitude, 23.1801);
      expect(draft.startLocationProvider, 'geoapify');
      expect(draft.startLocationProviderPlaceId, 'geoapify-hotel-imperial');
      expect(tripService.savedType, TripStartLocationType.hotel);
      expect(tripService.savedTripId, 'trip-123');
      expect(find.text('What brings you\nto Ujjain?'), findsOneWidget);
    },
  );

  testWidgets('current location permission denial is explained and retryable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ArrivalDetailsScreen(
          draft: TripDraft(),
          locationService: _FakeLocationService(),
          tripService: _FakeTripService(),
          deviceLocationService: _DeniedDeviceLocationService(),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Current location'));
    await tester.tap(find.text('Current location'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Location permission was denied. Choose another start or try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(button.onPressed, isNull);
  });
}

class _FakeLocationService extends LocationService {
  bool? hotelOnly;

  @override
  Future<List<LocationSuggestion>> autocomplete(
    String query, {
    required bool hotelOnly,
    double? latitude,
    double? longitude,
  }) async {
    this.hotelOnly = hotelOnly;
    return const [
      LocationSuggestion(
        provider: 'geoapify',
        providerPlaceId: 'geoapify-hotel-imperial',
        name: 'Hotel Imperial',
        formattedAddress: 'Hotel Imperial, Ujjain, India',
        latitude: 23.1801,
        longitude: 75.7812,
        city: 'Ujjain',
        state: 'Madhya Pradesh',
        countryCode: 'in',
        resultType: 'amenity',
      ),
    ];
  }
}

class _FakeTripService extends TripService {
  String? savedTripId;
  TripStartLocationType? savedType;

  @override
  Future<TripStartLocation> updateStartLocation(
    String tripId, {
    required TripStartLocationType type,
    String? name,
    double? latitude,
    double? longitude,
    String? provider,
    String? providerPlaceId,
  }) async {
    savedTripId = tripId;
    savedType = type;
    return TripStartLocation(
      tripId: tripId,
      type: type,
      name: name!,
      latitude: latitude!,
      longitude: longitude!,
      provider: provider,
      providerPlaceId: providerPlaceId,
    );
  }
}

class _FakeDeviceLocationService extends DeviceLocationService {
  @override
  Future<DevicePosition> getCurrentPosition() async {
    return const DevicePosition(latitude: 23.1765, longitude: 75.7885);
  }
}

class _DeniedDeviceLocationService extends DeviceLocationService {
  @override
  Future<DevicePosition> getCurrentPosition() async {
    throw const DeviceLocationException(
      'Location permission was denied. Choose another start or try again.',
    );
  }
}

const _hotelSuggestionJson = '''
{
  "provider": "geoapify",
  "provider_place_id": "geoapify-hotel-imperial",
  "name": "Hotel Imperial",
  "formatted_address": "Hotel Imperial, Ujjain, India",
  "latitude": 23.1801,
  "longitude": 75.7812,
  "city": "Ujjain",
  "state": "Madhya Pradesh",
  "country_code": "in",
  "result_type": "amenity"
}
''';

const _tripStartJson = '''
{
  "trip_id": "trip-123",
  "start_location_type": "hotel",
  "start_location_name": "Hotel Imperial",
  "start_latitude": 23.1801,
  "start_longitude": 75.7812,
  "start_location_provider": "geoapify",
  "start_location_provider_place_id": "geoapify-hotel-imperial"
}
''';
