import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yatra_canvas/services/backend_client.dart';
import 'package:yatra_canvas/services/city_service.dart';

void main() {
  for (final status in [429, 500, 502, 503, 504]) {
    test('GET retries $status once with request correlation intact', () async {
      var calls = 0;
      final client = BackendClient(
        retryDelay: Duration.zero,
        network: MockClient((request) async {
          expect(request.headers['x-request-id'], 'flow-123');
          expect(request.headers['authorization'], 'Bearer test-token');
          return http.Response(
            ++calls == 1 ? 'unavailable' : '[]',
            calls == 1 ? status : 200,
          );
        }),
      );
      final response = await client.get(
        Uri.parse('https://api.test/cities'),
        headers: {
          'X-Request-ID': 'flow-123',
          'Authorization': 'Bearer test-token',
        },
      );
      expect(response.statusCode, 200);
      expect(calls, 2);
      client.close();
    });
  }
  test('persistent outage is surfaced after two attempts', () async {
    var calls = 0;
    final client = BackendClient(
      retryDelay: Duration.zero,
      network: MockClient((_) async {
        calls++;
        throw http.ClientException('DNS failure');
      }),
    );
    await expectLater(
      CityService(
        client: client,
        baseUrl: 'https://api.test',
      ).searchCities('Ziro'),
      throwsA(isA<CityServiceException>()),
    );
    expect(calls, 2);
    client.close();
  });
  test(
    'long Retry-After does not make immediate repeated provider calls',
    () async {
      var calls = 0;
      final client = BackendClient(
        retryDelay: Duration.zero,
        network: MockClient((_) async {
          calls++;
          return http.Response('limited', 429, headers: {'retry-after': '60'});
        }),
      );
      expect(
        (await client.get(Uri.parse('https://api.test/cities'))).statusCode,
        429,
      );
      expect(calls, 1);
      client.close();
    },
  );
  for (final method in ['POST', 'PATCH', 'PUT', 'DELETE']) {
    test('$method is sent once even when the server fails', () async {
      var calls = 0;
      final client = BackendClient(
        retryDelay: Duration.zero,
        network: MockClient((request) async {
          calls++;
          expect(jsonDecode(request.body)['request_id'], 'same-request');
          return http.Response('unavailable', 503);
        }),
      );
      final request = http.Request(method, Uri.parse('https://api.test/trips'))
        ..body = jsonEncode({'request_id': 'same-request'});
      expect((await client.send(request)).statusCode, 503);
      expect(calls, 1);
      client.close();
    });
  }
  test('malformed success and missing required fields are errors, valid empty is empty', () async {
    for (final body in ['<html>starting</html>', '{}', '[{"name":"Ziro"}]']) {
      final service = CityService(
        baseUrl: 'https://api.test',
        client: MockClient((_) async => http.Response(body, 200)),
      );
      await expectLater(
        service.searchCities('Ziro'),
        throwsA(isA<CityServiceException>()),
      );
    }
    final service = CityService(
      baseUrl: 'https://api.test',
      client: MockClient((_) async => http.Response('[]', 200)),
    );
    expect(await service.searchCities('Ziro'), isEmpty);
  });
}
