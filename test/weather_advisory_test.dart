import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/models/weather_advisory.dart';
import 'package:yatra_canvas/screens/place_discovery/widgets/weather_advisory_card.dart';
import 'package:yatra_canvas/services/weather_advisory_service.dart';

void main() {
  group('WeatherAdvisory Models', () {
    test('TripWeatherAdvisories.fromJson parses correctly', () {
      final json = {
        'trip_id': '11111111-1111-1111-1111-111111111111',
        'status': 'ok',
        'advisories': [
          {
            'id': 'advisory-1-d1-very_hot',
            'day_number': 1,
            'condition': 'very_hot',
            'severity': 'warning',
            'summary': 'Day 1 between 1:00 PM–5:00 PM may be very hot.',
            'affected_start': '2026-08-25T13:00:00Z',
            'affected_end': '2026-08-25T17:00:00Z',
            'affected_place_ids': ['22222222-2222-2222-2222-222222222222'],
            'affected_place_names': ['Amer Fort'],
            'actions': ['continue', 'suggest_alternatives', 'rearrange_day'],
          },
        ],
      };

      final parsed = TripWeatherAdvisories.fromJson(json);
      expect(parsed.tripId, '11111111-1111-1111-1111-111111111111');
      expect(parsed.status, 'ok');
      expect(parsed.advisories.length, 1);

      final adv = parsed.advisories.first;
      expect(adv.id, 'advisory-1-d1-very_hot');
      expect(adv.dayNumber, 1);
      expect(adv.condition, 'very_hot');
      expect(adv.severity, 'warning');
      expect(adv.affectedPlaceNames, ['Amer Fort']);
    });

    test('DayRearrangePreview.fromJson parses correctly', () {
      final json = {
        'trip_id': '11111111-1111-1111-1111-111111111111',
        'day_number': 1,
        'explanation': 'Proposed adjustment: Outdoor visits in morning',
        'original_places': [
          {
            'place_id': '22222222-2222-2222-2222-222222222222',
            'name': 'Amer Fort',
            'visit_order': 1,
            'time_window': '1:30 PM',
            'is_alternative': false,
            'environment': 'outdoor',
          },
        ],
        'proposed_places': [
          {
            'place_id': '22222222-2222-2222-2222-222222222222',
            'name': 'Amer Fort',
            'visit_order': 1,
            'time_window': '9:30 AM',
            'is_alternative': false,
            'environment': 'outdoor',
          },
        ],
      };

      final parsed = DayRearrangePreview.fromJson(json);
      expect(parsed.dayNumber, 1);
      expect(parsed.proposedPlaces.length, 1);
      expect(parsed.proposedPlaces.first.timeWindow, '9:30 AM');
    });
  });

  group('WeatherAdvisoryService', () {
    test('getAdvisories parses 200 response', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/weather-advisories')) {
          return http.Response(
            jsonEncode({
              'trip_id': 'test-trip',
              'status': 'ok',
              'advisories': [
                {
                  'id': 'adv-1',
                  'day_number': 1,
                  'condition': 'heavy_rain',
                  'severity': 'warning',
                  'summary': 'Heavy rain expected on Day 1',
                  'affected_place_ids': [],
                  'affected_place_names': [],
                  'actions': ['continue'],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = WeatherAdvisoryService(
        client: mockClient,
        baseUrl: 'http://localhost:8000',
      );

      final res = await service.getAdvisories('test-trip');
      expect(res, isNotNull);
      expect(res!.status, 'ok');
      expect(res.advisories.length, 1);
      expect(res.advisories.first.condition, 'heavy_rain');
    });

    test('getAdvisories degrades safely on 500 error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final service = WeatherAdvisoryService(
        client: mockClient,
        baseUrl: 'http://localhost:8000',
      );

      final res = await service.getAdvisories('test-trip');
      expect(res, isNull);
    });

    test('getAlternatives parses list of indoor alternatives', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/weather-alternatives')) {
          return http.Response(
            jsonEncode([
              {
                'place_id': 'alt-1',
                'name': 'Albert Hall Museum',
                'category': 'museum',
                'reason': 'Sheltered indoor cultural attraction',
                'environment': 'indoor',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = WeatherAdvisoryService(
        client: mockClient,
        baseUrl: 'http://localhost:8000',
      );

      final res = await service.getAlternatives('test-trip', 1, 'hot');
      expect(res.length, 1);
      expect(res.first.name, 'Albert Hall Museum');
    });
  });

  group('WeatherAdvisoryCard Widget', () {
    testWidgets('renders advisory summary and continue button', (tester) async {
      final advisory = WeatherAdvisory(
        id: 'adv-123',
        dayNumber: 2,
        condition: 'very_hot',
        severity: 'warning',
        summary: 'Day 2 afternoon may be very hot. 2 outdoor places affected.',
        actions: const ['continue', 'suggest_alternatives', 'rearrange_day'],
      );

      var dismissed = false;
      var applied = false;

      final mockClient = MockClient((request) async => http.Response('{}', 200));
      final service = WeatherAdvisoryService(
        client: mockClient,
        baseUrl: 'http://localhost:8000',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeatherAdvisoryCard(
              tripId: 'test-trip',
              advisory: advisory,
              weatherService: service,
              onDismiss: () => dismissed = true,
              onApplied: () => applied = true,
            ),
          ),
        ),
      );

      expect(find.text('Weather Advisory · Day 2'), findsOneWidget);
      expect(
        find.text('Day 2 afternoon may be very hot. 2 outdoor places affected.'),
        findsOneWidget,
      );
      expect(find.text('Continue as planned'), findsOneWidget);
      expect(find.text('Suggest alternatives'), findsOneWidget);
      expect(find.text('Rearrange this day'), findsOneWidget);

      // Tap default "Continue as planned"
      await tester.tap(find.text('Continue as planned'));
      await tester.pump();

      expect(dismissed, isTrue);
      expect(applied, isFalse);
    });
  });
}
