import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/services/saved_place_service.dart';

void main() {
  test(
    'SavedPlaceService persists list, add, notes, reorder, and remove',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response('[]', 200);
        }
        if (request.method == 'POST') {
          expect(jsonDecode(request.body), {
            'place_id': 'place-1',
            'custom_order': 1,
            'priority': 0,
            'is_locked': false,
            'must_visit': false,
            'notes': null,
          });
          return http.Response(jsonEncode(_savedPlaceJson()), 201);
        }
        if (request.method == 'PATCH' &&
            request.url.path.endsWith('/reorder')) {
          expect(jsonDecode(request.body), {
            'places': [
              {'place_id': 'place-2', 'custom_order': 1},
              {'place_id': 'place-1', 'custom_order': 2},
            ],
          });
          return http.Response(
            jsonEncode([
              _savedPlaceJson(
                id: 'saved-2',
                placeId: 'place-2',
                name: 'Place B',
                order: 1,
              ),
              _savedPlaceJson(order: 2),
            ]),
            200,
          );
        }
        if (request.method == 'PATCH') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body.containsKey('priority')) {
            expect(body, {
              'notes': 'Do not skip',
              'priority': 10,
              'is_locked': true,
              'must_visit': true,
              'custom_order': 1,
            });
            return http.Response(
              jsonEncode(
                _savedPlaceJson(
                  notes: 'Do not skip',
                  priority: 10,
                  isLocked: true,
                  mustVisit: true,
                ),
              ),
              200,
            );
          }
          expect(jsonDecode(request.body), {'notes': 'Morning visit'});
          return http.Response(
            jsonEncode(_savedPlaceJson(notes: 'Morning visit')),
            200,
          );
        }
        if (request.method == 'DELETE') {
          return http.Response('', 204);
        }
        return http.Response('unexpected', 500);
      });
      final service = SavedPlaceService(
        client: client,
        baseUrl: 'http://10.0.2.2:8001',
      );

      expect(await service.getSavedPlaces('trip-1'), isEmpty);
      final added = await service.addSavedPlace(
        'trip-1',
        'place-1',
        customOrder: 1,
      );
      expect(added.place.name, 'Place A');

      final notes = await service.updateNotes(
        'trip-1',
        'place-1',
        'Morning visit',
      );
      expect(notes.notes, 'Morning visit');

      final preferred = await service.updateSettings(
        'trip-1',
        'place-1',
        notes: 'Do not skip',
        priority: 10,
        isLocked: true,
        mustVisit: true,
        customOrder: 1,
      );
      expect(preferred.priority, 10);
      expect(preferred.isLocked, isTrue);
      expect(preferred.mustVisit, isTrue);

      final reordered = await service.reorderSavedPlaces('trip-1', [
        'place-2',
        'place-1',
      ]);
      expect(reordered.map((item) => item.placeId), ['place-2', 'place-1']);

      await service.removeSavedPlace('trip-1', 'place-1');
      expect(requests.map((request) => request.method), [
        'GET',
        'POST',
        'PATCH',
        'PATCH',
        'PATCH',
        'DELETE',
      ]);
    },
  );
}

Map<String, Object?> _savedPlaceJson({
  String id = 'saved-1',
  String placeId = 'place-1',
  String name = 'Place A',
  int order = 1,
  String? notes,
  int priority = 0,
  bool isLocked = false,
  bool mustVisit = false,
}) {
  return {
    'id': id,
    'trip_id': 'trip-1',
    'place_id': placeId,
    'custom_order': order,
    'notes': notes,
    'priority': priority,
    'is_locked': isLocked,
    'must_visit': mustVisit,
    'created_at': '2026-08-30T10:00:00Z',
    'place': {
      'id': placeId,
      'city_id': 'city-123',
      'name': name,
      'category': 'religious',
      'latitude': 23.18,
      'longitude': 75.77,
      'rating': 4.7,
      'review_count': 1000,
      'is_popular': true,
      'is_heritage': false,
      'is_local_speciality': false,
      'last_fetched_at': null,
      'created_at': '2026-08-30T10:00:00Z',
    },
  };
}
