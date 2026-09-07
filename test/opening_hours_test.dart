import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/place.dart';

void main() {
  group('OpeningHoursStatus', () {
    test('parses KNOWN, CLOSED, and UNKNOWN correctly', () {
      expect(OpeningHoursStatus.fromString('KNOWN'), OpeningHoursStatus.known);
      expect(OpeningHoursStatus.fromString('closed'), OpeningHoursStatus.closed);
      expect(OpeningHoursStatus.fromString('UNKNOWN'), OpeningHoursStatus.unknown);
      expect(OpeningHoursStatus.fromString(null), OpeningHoursStatus.unknown);
      expect(OpeningHoursStatus.fromString('invalid_status'), OpeningHoursStatus.unknown);
    });

    test('exposes correct apiValue', () {
      expect(OpeningHoursStatus.known.apiValue, 'KNOWN');
      expect(OpeningHoursStatus.closed.apiValue, 'CLOSED');
      expect(OpeningHoursStatus.unknown.apiValue, 'UNKNOWN');
    });
  });

  group('OpeningHoursInterval', () {
    test('deserializes from JSON and containsTime', () {
      final interval = OpeningHoursInterval.fromJson({
        'open': '09:00',
        'close': '11:00',
      });
      expect(interval.open, '09:00');
      expect(interval.close, '11:00');

      expect(interval.containsTime(8, 59), isFalse);
      expect(interval.containsTime(9, 0), isTrue);
      expect(interval.containsTime(10, 30), isTrue);
      expect(interval.containsTime(11, 0), isFalse); // closing bound is exclusive
      expect(interval.containsTime(12, 0), isFalse);
    });
  });

  group('Place Opening Hours integration', () {
    test('deserializes place with split schedule and checks isOpenAt', () {
      // 2026-09-07 is a Monday (weekday == 1)
      final mondayDate = DateTime(2026, 9, 7, 10, 0); // 10:00 AM Monday
      final mondayLunch = DateTime(2026, 9, 7, 12, 30); // 12:30 PM Monday
      final mondayEvening = DateTime(2026, 9, 7, 15, 0); // 15:00 Monday
      final tuesdayMorning = DateTime(2026, 9, 8, 10, 0); // Tuesday

      final json = {
        'id': 'place-123',
        'city_id': 'city-456',
        'name': 'Meenakshi Amman Temple',
        'category': 'heritage',
        'latitude': 9.9195,
        'longitude': 78.1193,
        'review_count': 1200,
        'is_popular': true,
        'is_heritage': true,
        'is_local_speciality': false,
        'opening_hours_status': 'KNOWN',
        'raw_opening_hours': 'Mo 09:00-11:00,14:00-22:00; Tu 09:00-18:00; We off',
        'opening_hours': {
          'monday': [
            {'open': '09:00', 'close': '11:00'},
            {'open': '14:00', 'close': '22:00'},
          ],
          'tuesday': [
            {'open': '09:00', 'close': '18:00'},
          ],
          'wednesday': [],
        },
      };

      final place = Place.fromJson(json);

      expect(place.openingHoursStatus, OpeningHoursStatus.known);
      expect(place.rawOpeningHours, 'Mo 09:00-11:00,14:00-22:00; Tu 09:00-18:00; We off');
      expect(place.openingHours['monday']?.length, 2);

      // Split schedule testing
      expect(place.isOpenAt(mondayDate), isTrue, reason: '10:00 is within 09:00-11:00');
      expect(place.isOpenAt(mondayLunch), isFalse, reason: '12:30 is between split intervals');
      expect(place.isOpenAt(mondayEvening), isTrue, reason: '15:00 is within 14:00-22:00');

      // Tuesday
      expect(place.isOpenAt(tuesdayMorning), isTrue);

      // Wednesday (empty list = closed)
      final wednesdayDate = DateTime(2026, 9, 9, 10, 0);
      expect(place.isOpenAt(wednesdayDate), isFalse);
    });

    test('UNKNOWN status returns null (never assumes open)', () {
      final json = {
        'id': 'place-unknown',
        'city_id': 'city-456',
        'name': 'Mysterious Monument',
        'category': 'sightseeing',
        'latitude': 9.9,
        'longitude': 78.1,
        'review_count': 10,
        'is_popular': false,
        'is_heritage': false,
        'is_local_speciality': false,
        'opening_hours_status': 'UNKNOWN',
        'raw_opening_hours': null,
        'opening_hours': {},
      };

      final place = Place.fromJson(json);
      expect(place.openingHoursStatus, OpeningHoursStatus.unknown);

      final dt = DateTime(2026, 9, 7, 12, 0);
      expect(place.isOpenAt(dt), isNull, reason: 'UNKNOWN must be indeterminate null, never true');
    });

    test('CLOSED status returns false for any datetime', () {
      final json = {
        'id': 'place-closed',
        'city_id': 'city-456',
        'name': 'Permanently Closed Museum',
        'category': 'heritage',
        'latitude': 9.9,
        'longitude': 78.1,
        'review_count': 5,
        'is_popular': false,
        'is_heritage': false,
        'is_local_speciality': false,
        'opening_hours_status': 'CLOSED',
        'raw_opening_hours': 'closed',
        'opening_hours': {},
      };

      final place = Place.fromJson(json);
      expect(place.openingHoursStatus, OpeningHoursStatus.closed);

      final dt = DateTime(2026, 9, 7, 12, 0);
      expect(place.isOpenAt(dt), isFalse);
    });

    test('toJson roundtrip preserves opening hours', () {
      final original = Place(
        id: 'place-rt',
        cityId: 'city-1',
        name: 'Test Shrine',
        category: 'religious',
        latitude: 10.0,
        longitude: 77.0,
        reviewCount: 42,
        isPopular: true,
        isHeritage: true,
        isLocalSpeciality: false,
        openingHoursStatus: OpeningHoursStatus.known,
        rawOpeningHours: '09:00-18:00',
        openingHours: {
          'monday': [const OpeningHoursInterval(open: '09:00', close: '18:00')],
        },
      );

      final json = original.toJson();
      final revived = Place.fromJson(json);

      expect(revived.openingHoursStatus, OpeningHoursStatus.known);
      expect(revived.rawOpeningHours, '09:00-18:00');
      expect(revived.openingHours['monday']?.first.open, '09:00');
      expect(revived.openingHours['monday']?.first.close, '18:00');
    });
  });
}
