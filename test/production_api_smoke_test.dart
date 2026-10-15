import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:yatra_canvas/config/api_config.dart';
import 'package:yatra_canvas/models/place.dart';
import 'package:yatra_canvas/services/city_service.dart';
import 'package:yatra_canvas/services/location_service.dart';
import 'package:yatra_canvas/services/place_service.dart';

// Explicit opt-in, GET only. Default regression runs never depend on production.
void main() {
  const enabled = bool.fromEnvironment('RUN_PRODUCTION_READS');
  test(
    'Render read contracts deserialize into existing Flutter models',
    () async {
      final client = http.Client();
      addTearDown(client.close);
      final base = ApiConfig.productionBaseUrl;
      final status = await client
          .get(Uri.parse('$base/'))
          .timeout(const Duration(seconds: 75));
      expect(status.statusCode, 200);
      expect(jsonDecode(status.body)['service'], 'YatraCanvas API');
      final docs = await client.get(Uri.parse('$base/docs'));
      expect(docs.statusCode, 200);
      final cities = await CityService(
        client: client,
        baseUrl: base,
      ).searchCities('Jaipur');
      expect(cities, isNotEmpty);
      final city = cities.firstWhere((city) => city.name == 'Jaipur');
      expect(city.id, isNotEmpty);
      final response = await client.get(
        Uri.parse('$base/cities/${city.id}/places?limit=2'),
      );
      expect(response.statusCode, 200);
      final places = (jsonDecode(response.body) as List)
          .map((value) => Place.fromJson(value as Map<String, dynamic>))
          .toList();
      expect(places, isNotEmpty);
      expect(places.every((place) => place.cityId == city.id), isTrue);
      final search = await PlaceService(
        client: client,
        baseUrl: base,
      ).searchPlaces(city.id!, 'Hawa', limit: 2);
      expect(search.any((place) => place.name == 'Hawa Mahal'), isTrue);
      final suggestions = await LocationService(
        client: client,
        baseUrl: base,
      ).autocomplete('Ziro', hotelOnly: false, limit: 2);
      expect(suggestions, isNotEmpty);
      final schema = jsonDecode(
        (await client.get(Uri.parse('$base/openapi.json'))).body,
      ) as Map;
      final tripProperties =
          schema['components']['schemas']['TripCreate']['properties'] as Map;
      expect(tripProperties.containsKey('request_id'), isTrue);
      expect(
        (schema['paths'] as Map).containsKey('/trips/{trip_id}/optimize-route'),
        isTrue,
      );
      final me = await client.get(Uri.parse('$base/api/auth/me'));
      expect(me.statusCode, 401);
    },
    skip: !enabled
        ? 'Opt in with --dart-define=RUN_PRODUCTION_READS=true (read only).'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
