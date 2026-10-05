import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import 'city_pack_repository.dart';
import 'local_itinerary_planner.dart';
import '../models/place.dart';

/// Application service gateway. It routes prepared cities to local repositories,
/// and preserves the existing HTTP transport for all other cities and trips.
/// Injected service clients are retained unchanged for existing integration tests.
class LocalFirstClient extends http.BaseClient {
  LocalFirstClient({
    http.Client? network,
    CityPackRepository? packs,
    OfflineTripStore? trips,
    this.allowEnrichment = true,
  }) : network = network ?? http.Client(),
       packs = packs ?? CityPackRepository.shared,
       trips = trips ?? OfflineTripStore.shared;

  final http.Client network;
  final CityPackRepository packs;
  final OfflineTripStore trips;
  final bool allowEnrichment;
  static final Set<String> _enriching = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _origin = '${request.url.scheme}://${request.url.authority}';
    final segments = request.url.pathSegments;
    final body = request is http.Request && request.body.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(request.body) as Map)
        : <String, dynamic>{};
    Object? data;
    var status = 200;
    final headers = <String, String>{
      'content-type': 'application/json; charset=utf-8',
    };
    try {
      if (segments.length == 2 &&
          segments[0] == 'cities' &&
          ['search', 'autocomplete'].contains(segments[1])) {
        final local = await packs.searchCities(
          request.url.queryParameters['query'] ?? '',
        );
        if (local.isEmpty) return await network.send(request);
        data = segments[1] == 'autocomplete' ? <Object>[] : local;
      } else if (segments.join('/') == 'cities/resolve') {
        final local = await packs.searchCities(body['name'] as String? ?? '');
        data = local
            .where(
              (c) =>
                  c['name'].toString().toLowerCase() ==
                      body['name'].toString().toLowerCase() &&
                  (body['state'] == null || c['state'] == body['state']) &&
                  c['country'] == body['country'],
            )
            .firstOrNull;
        if (data == null) return await network.send(request);
      } else if (segments.length >= 3 &&
          segments[0] == 'cities' &&
          await packs.hasCityPack(segments[1])) {
        final cityId = segments[1], action = segments.skip(2).join('/');
        if (action == 'recommendations' || action == 'discover-places') {
          final filter =
              body['category_filter'] as String? ??
              request.url.queryParameters['category'];
          final categories = filter != null
              ? [filter]
              : (body['categories'] as List? ?? []);
          final offset = int.tryParse(body['cursor'] as String? ?? '') ?? 0;
          final limit = (body['limit'] as int? ?? 30).clamp(1, 100);
          final places = await packs.getCityPlaces(
            cityId,
            category: filter,
            categories: categories.cast<String>(),
            offset: offset,
            limit: limit + 1,
          );
          final matching = places
              .where(
                (p) => categories.isEmpty || categories.contains(p['category']),
              )
              .toList();
          final selected = matching.take(limit).toList();
          for (final place
              in selected
                  .where((p) => p['enrichment_state'] != 'cached')
                  .take(2)) {
            if (allowEnrichment) unawaited(enrich(cityId, place));
          }
          if (limit < matching.length) {
            headers['x-next-cursor'] = '${offset + limit}';
          }
          headers['x-refresh-state'] = 'idle';
          data = action == 'discover-places'
              ? selected
              : [
                  for (final p in selected)
                    {
                      ...p,
                      'matched_categories': [p['category']],
                      'recommendation_score': p['travel_relevance_score'] ?? 0,
                      'recommendation_reason':
                          'Available offline in the $cityId city pack',
                      'access_confidence': 'UNKNOWN',
                    },
                ];
        } else if (action == 'places/search') {
          final places = await packs.getCityPlaces(
            cityId,
            query: request.url.queryParameters['query'],
            limit:
                int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 10,
          );
          data = [
            for (final p in places)
              {
                ...p,
                'place_id': p['id'],
                'external_place_id': p['id'],
                'source': 'city_pack',
              },
          ];
        } else if (action == 'places/resolve') {
          data = body['external_place_id'] is String
              ? await packs.getPlace(
                  cityId,
                  body['external_place_id'] as String,
                )
              : null;
          data ??= (await packs.getCityPlaces(
            cityId,
            query: body['name'] as String?,
            limit: 10,
          )).where((p) => p['name'] == body['name']).firstOrNull;
          if (data == null) {
            status = 404;
            data = {'detail': 'Place is not available in this offline pack.'};
          }
        } else {
          return await network.send(request);
        }
      } else if (segments.join('/') == 'places/prefetch' &&
          await packs.hasCityPack(body['city_id'] as String? ?? '')) {
        await packs.getCityPlaces(body['city_id'] as String, limit: 8);
        status = 202;
        data = {'state': 'completed', 'source': 'city_pack'};
      } else if (segments.length == 1 &&
          segments.single == 'trips' &&
          request.method == 'POST' &&
          await packs.hasCityPack(body['city_id'] as String? ?? '')) {
        data = await trips.create(body, packs);
        status = 201;
      } else if (segments.length >= 2 &&
          segments[0] == 'trips' &&
          segments[1].startsWith('offline_')) {
        final result = await trips.handle(
          segments[1],
          segments.skip(2).join('/'),
          request.method,
          body,
          packs,
        );
        status = result.status;
        data = result.data;
      } else if (segments.join('/') == 'locations/autocomplete') {
        final cities = (await packs.index).values.cast<Map>();
        final lat = double.tryParse(
              request.url.queryParameters['latitude'] ?? '',
            ),
            lon = double.tryParse(
              request.url.queryParameters['longitude'] ?? '',
            );
        final requestedCity = request.url.queryParameters['city_id'];
        final city =
            requestedCity != null && await packs.hasCityPack(requestedCity)
            ? await packs.city(requestedCity)
            : lat == null || lon == null
            ? null
            : cities
                  .where(
                    (c) =>
                        CityPackRepository.distanceMeters(
                          lat,
                          lon,
                          (c['latitude'] as num).toDouble(),
                          (c['longitude'] as num).toDouble(),
                        ) <
                        50000,
                  )
                  .firstOrNull;
        if (city == null) return await network.send(request);
        final places = await packs.getCityPlaces(
          city['city_id'] as String,
          query: request.url.queryParameters['query'],
          hotelOnly: request.url.queryParameters['type'] == 'amenity',
          locationKind: request.url.queryParameters['location_kind'],
          limit: int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 5,
        );
        data = {
          'results': [
            for (final p in places)
              {
                'name': p['name'],
                'formatted_address':
                    '${p['name']}, ${p['address'] ?? city['name']}',
                'latitude': p['latitude'],
                'longitude': p['longitude'],
                'provider': 'city_pack',
                'provider_place_id': p['id'],
                'country_code': 'in',
                'result_type': 'amenity',
                'city': city['name'],
                'state': city['state'],
              },
          ],
        };
      } else {
        return await network.send(request);
      }
    } on FormatException catch (error) {
      status = 422;
      data = {'detail': error.message};
    } on StateError catch (error) {
      status = 409;
      data = {'detail': error.message};
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(status == 204 ? '' : jsonEncode(data))),
      status,
      headers: headers,
      request: request,
    );
  }

  /// Optional field enrichment is bounded, isolated and never awaited by navigation.
  /// Provider IDs returned by the backend do not replace the packaged stable ID.
  Future<void> enrich(String cityId, Map<String, dynamic> place) async {
    final pid = place['id'] as String;
    if ((place['image'] != null && place['hours_verification'] != 'UNKNOWN') ||
        !_enriching.add(pid)) {
      return;
    }
    var cached = false;
    try {
      // A packed city ID is not a backend UUID. Resolve provider identity first.
      final city = await packs.city(cityId);
      if (city == null) return;
      final resolved = await network
          .post(
            Uri.parse('$_origin/cities/resolve'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              for (final field in [
                'name',
                'state',
                'country',
                'latitude',
                'longitude',
              ])
                field: city[field],
            }),
          )
          .timeout(const Duration(seconds: 4));
      if (resolved.statusCode != 200) return;
      final backendCity = jsonDecode(resolved.body) as Map;
      final response = await network
          .post(
            Uri.parse('$_origin/cities/${backendCity['id']}/places/resolve'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': place['name'],
              'latitude': place['latitude'],
              'longitude': place['longitude'],
              'category': place['category'],
            }),
          )
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(
          jsonDecode(response.body) as Map,
        );
        final parsed = Place.fromJson(payload);
        await packs.cacheEnrichment(pid, {
          for (final field in [
            'description',
            'website',
            'opening_hours',
            'raw_opening_hours',
          ])
            field: payload[field],
          if (parsed.image?.hasRemoteImage == true) 'image': payload['image'],
        });
        cached = true;
      }
    } on Object {
      // Offline, timeout, provider miss: the existing local record and fallback remain usable.
    } finally {
      _enriching.remove(pid);
      if (!cached) {
        try {
          await packs.cacheEnrichment(
            pid,
            {},
            ttl: const Duration(minutes: 15),
          );
        } on Object {
          /* Local storage failure must not break discovery. */
        }
      }
    }
  }

  String _origin = '';
  void setOrigin(String origin) {
    _origin = origin;
  }

  @override
  void close() {
    network.close();
    super.close();
  }
}

class LocalResponse {
  const LocalResponse(this.data, [this.status = 200]);
  final Object? data;
  final int status;
}

class OfflineTripStore {
  // ignore: prefer_initializing_formals
  OfflineTripStore({DatabaseFactory? factory, this.directory})
    // Preserve the public injectable argument and defer default SQLite setup.
    // ignore: prefer_initializing_formals
    : _factory = factory;
  static final shared = OfflineTripStore();
  final DatabaseFactory? _factory;
  DatabaseFactory get factory => _factory ?? databaseFactory;
  final String? directory;
  Future<Database>? _opening;
  Future<Database> database() => _opening ??= _open();
  Future<Database> _open() async => factory.openDatabase(
    '${directory ?? await factory.getDatabasesPath()}/yatracanvas_offline_trips.sqlite',
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE trips (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
      ),
    ),
  );

  Future<Map<String, dynamic>> create(
    Map<String, dynamic> body,
    CityPackRepository packs,
  ) async {
    final id = 'offline_${body['request_id']}';
    final city = await packs.city(body['city_id'] as String);
    final days = body['days'] as int? ?? 1;
    if (days < 1 ||
        days > 30 ||
        body['request_id'] is! String ||
        city == null) {
      throw const FormatException('Invalid local trip');
    }
    final start = DateTime.parse(body['start_date'] as String);
    final db = await database();
    await db.transaction((txn) async {
      final existing = await txn.query(
        'trips',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (existing.isNotEmpty) {
        final previous =
            jsonDecode(existing.single['payload'] as String) as Map;
        if (jsonEncode(previous['request']) != jsonEncode(body)) {
          throw StateError('Trip request ID was reused with different data.');
        }
        return;
      }
      final state = {
        'request': body,
        'pack_version': (await packs.diagnostics(
          body['city_id'] as String,
        ))['pack_version'],
        'trip': {
          ...body,
          'trip_id': id,
          'city': city,
          'preferences': [
            ...?body['preferences'] as List?,
            ...?body['purposes'] as List?,
          ],
        },
        'days': [
          for (var i = 0; i < days; i++)
            {
              'id': '$id:day:${i + 1}',
              'trip_id': id,
              'day_number': i + 1,
              'date': start
                  .add(Duration(days: i))
                  .toIso8601String()
                  .split('T')
                  .first,
              'day_type': 'FULL_DAY',
              'start_time': '09:00',
              'end_time': '19:00',
            },
        ],
        'saved': <Object>[],
        'route': null,
        'stale': false,
      };
      await txn.insert('trips', {'id': id, 'payload': jsonEncode(state)});
    });
    return {'trip_id': id};
  }

  Future<LocalResponse> handle(
    String id,
    String action,
    String method,
    Map<String, dynamic> body,
    CityPackRepository packs,
  ) async {
    final db = await database();
    return db.transaction((txn) async {
      final rows = await txn.query(
        'trips',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        return const LocalResponse({'detail': 'Offline trip not found.'}, 404);
      }
      final state = Map<String, dynamic>.from(
        jsonDecode(rows.single['payload'] as String) as Map,
      );
      final trip = state['trip'] as Map<String, dynamic>;
      final saved = (state['saved'] as List).cast<Map<String, dynamic>>();
      final days = (state['days'] as List).cast<Map<String, dynamic>>();
      Object? result;
      var status = 200, changed = method != 'GET';
      final packVersion = (await packs.diagnostics(
        trip['city_id'] as String,
      ))['pack_version'];
      final packChanged = state['pack_version'] != packVersion;
      if (packChanged) {
        state['pack_version'] = packVersion;
        if (state['route'] != null) state['stale'] = true;
        changed = true;
      }
      Future<void> refreshPlaces() async {
        for (final selection in saved) {
          selection['place'] =
              await packs.getPlace(
                trip['city_id'] as String,
                selection['place_id'] as String,
              ) ??
              selection['place'];
        }
      }

      if (packChanged) await refreshPlaces();

      void assignment(Map<String, dynamic> selection) {
        if (selection['assignment_mode'] == 'LOCKED') {
          final day = days
              .where((d) => d['id'] == selection['assigned_day_id'])
              .firstOrNull;
          if (day == null ||
              day['day_type'] == 'REST' ||
              LocalItineraryPlanner.minute(day['end_time'], 1140) <=
                  LocalItineraryPlanner.minute(day['start_time'], 540)) {
            throw StateError('Choose an active sightseeing day for the lock.');
          }
        } else {
          selection['assigned_day_id'] = null;
        }
      }

      if (action.isEmpty) {
        if (method == 'PATCH') {
          if (body['city_id'] != null && body['city_id'] != trip['city_id']) {
            throw StateError(
              'Create a new trip to change its offline destination.',
            );
          }
          final count = body['days'] as int? ?? days.length;
          if (count < 1 || count > 30) {
            throw const FormatException('Invalid trip length');
          }
          if (count < days.length &&
              ((state['route']?['optimized_places'] as List? ?? []).any(
                    (p) => p['day_number'] > count,
                  ) ||
                  saved.any(
                    (s) =>
                        s['assigned_day_id'] != null &&
                        !days
                            .take(count)
                            .any((d) => d['id'] == s['assigned_day_id']),
                  ))) {
            throw StateError(
              'Remove scheduled or locked places before shortening this trip.',
            );
          }
          trip.addAll(body);
          trip['preferences'] = [
            ...?body['preferences'] as List?,
            ...?body['purposes'] as List?,
          ];
          final start = DateTime.parse(trip['start_date'] as String);
          final newDays = [
            for (var i = 0; i < count; i++)
              {
                ...(i < days.length
                    ? days[i]
                    : {
                        'id': '$id:day:${i + 1}',
                        'trip_id': id,
                        'day_number': i + 1,
                        'day_type': 'FULL_DAY',
                        'start_time': '09:00',
                        'end_time': '19:00',
                      }),
                'date': start
                    .add(Duration(days: i))
                    .toIso8601String()
                    .split('T')
                    .first,
              },
          ];
          state['days'] = newDays;
          state['stale'] = true;
        }
        result = trip;
      } else if (action == 'start-location') {
        trip.addAll(body);
        state['stale'] = true;
        result = trip;
      } else if (action == 'days') {
        result = days;
      } else if (action.startsWith('days/')) {
        final number = int.tryParse(action.split('/').last);
        final day = days.where((d) => d['day_number'] == number).firstOrNull;
        if (day == null) {
          return const LocalResponse({'detail': 'Trip day not found.'}, 404);
        }
        final proposed = {...day, ...body};
        if (saved.any((s) => s['assigned_day_id'] == day['id']) &&
            (proposed['day_type'] == 'REST' ||
                LocalItineraryPlanner.minute(proposed['end_time'], 1140) <=
                    LocalItineraryPlanner.minute(
                      proposed['start_time'],
                      540,
                    ))) {
          throw StateError('This day has locked places.');
        }
        day.addAll(body);
        state['stale'] = true;
        result = day;
      } else if (action == 'saved-places' && method == 'POST') {
        if (saved.any((s) => s['place_id'] == body['place_id'])) {
          throw StateError('This place is already saved.');
        }
        final place = await packs.getPlace(
          trip['city_id'] as String,
          body['place_id'] as String,
        );
        if (place == null) {
          return const LocalResponse({
            'detail': 'Offline place not found.',
          }, 404);
        }
        final selection = <String, dynamic>{
          'id': '$id:${place['id']}',
          'trip_id': id,
          'place_id': place['id'],
          'custom_order': saved.length + 1,
          'priority': 0,
          'is_locked': false,
          'must_visit': false,
          'assignment_mode': 'AUTO',
          'assigned_day_id': null,
          ...body,
          'place': place,
        };
        assignment(selection);
        saved.add(selection);
        state['stale'] = true;
        result = selection;
        status = 201;
      } else if (action == 'saved-places') {
        await refreshPlaces();
        result = saved;
      } else if (action == 'saved-places/reorder') {
        for (final item in body['places'] as List) {
          saved.firstWhere(
            (s) => s['place_id'] == item['place_id'],
          )['custom_order'] = item['custom_order'];
        }
        saved.sort(
          (a, b) =>
              (a['custom_order'] as int).compareTo(b['custom_order'] as int),
        );
        state['stale'] = true;
        result = saved;
      } else if (action.startsWith('saved-places/')) {
        final pid = action.split('/').last;
        final selection = saved.where((s) => s['place_id'] == pid).firstOrNull;
        if (selection == null) {
          return const LocalResponse({'detail': 'Saved place not found.'}, 404);
        }
        if (method == 'DELETE') {
          saved.remove(selection);
          status = 204;
        } else {
          final proposed = {...selection, ...body};
          assignment(proposed);
          selection.addAll(proposed);
          result = selection;
        }
        state['stale'] = true;
      } else if (action == 'optimize-route' || action == 'replan-apply') {
        await refreshPlaces();
        state['route'] = LocalItineraryPlanner.plan(state);
        state['route']['pack_version'] = packVersion;
        state['stale'] = false;
        result = state['route'];
      } else if (action == 'itinerary') {
        result = state['route'] == null
            ? {
                'trip_id': id,
                'optimized_places': [],
                'total_days': days.length,
                'total_distance': 0,
                'total_travel_time_minutes': 0,
              }
            : {
                ...state['route'] as Map,
                'route_geometry': LocalItineraryPlanner.geometry(state),
              };
      } else if (action == 'route-geometry') {
        result = LocalItineraryPlanner.geometry(state);
      } else if (action == 'replan-impact') {
        result = {
          'trip_id': id,
          'is_stale': state['stale'],
          'requires_replan_preview': state['stale'],
          'reasons': [],
          'summary': 'Offline trip uses bundled city data.',
        };
      } else if (action == 'replan-preview') {
        await refreshPlaces();
        final proposed = LocalItineraryPlanner.plan(state);
        result = {
          ...proposed,
          'is_stale': state['stale'],
          'summary': 'Preview uses approximate local travel times.',
          'added_places': [],
          'removed_places': [],
          'moved_places': [],
          'travel_time_delta_minutes':
              (proposed['total_travel_time_minutes'] as int) -
              (state['route']?['total_travel_time_minutes'] as int? ?? 0),
          'proposed_itinerary': proposed['optimized_places'],
        };
        changed = packChanged;
      } else if (action.startsWith('itinerary/stops/') ||
          action.startsWith('itinerary/places/')) {
        final stops = (state['route']?['optimized_places'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        final field = action.startsWith('itinerary/stops/') ? 'id' : 'place_id';
        final stop = stops
            .where((p) => p[field] == action.split('/').last)
            .firstOrNull;
        if (stop == null) {
          return const LocalResponse({
            'detail': 'Itinerary stop not found.',
          }, 404);
        }
        if (['COMPLETED', 'SKIPPED'].contains(stop['status']) ||
            !['COMPLETED', 'MISSED', 'SKIPPED'].contains(body['status'])) {
          throw StateError('Invalid stop status transition.');
        }
        if (stop['status'] == 'MISSED' && body['status'] != 'SKIPPED') {
          throw StateError('A missed stop may be skipped or moved.');
        }
        stop['status'] = body['status'];
        result = stop;
      } else if (action == 'itinerary/move-place') {
        final stops = (state['route']?['optimized_places'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        final stop = stops
            .where((p) => p['place_id'] == body['place_id'])
            .firstOrNull;
        final target = days
            .where(
              (d) =>
                  d['id'] == body['target_day_id'] ||
                  d['day_number'] == body['target_day_number'],
            )
            .firstOrNull;
        if (stop == null ||
            target == null ||
            target['day_type'] == 'REST' ||
            ['COMPLETED', 'SKIPPED'].contains(stop['status']) ||
            stop['day_number'] == target['day_number']) {
          throw StateError('Choose a different active day for this place.');
        }
        final draft = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(state)) as Map,
        );
        (draft['route']['optimized_places'] as List).removeWhere(
          (p) => p['place_id'] == body['place_id'],
        );
        final selection = (draft['saved'] as List).firstWhere(
          (s) => s['place_id'] == body['place_id'],
        );
        selection['assignment_mode'] = 'LOCKED';
        selection['assigned_day_id'] = target['id'];
        final proposed = LocalItineraryPlanner.plan(
          draft,
          affectedDays: {
            stop['day_number'] as int,
            target['day_number'] as int,
          },
        );
        final expected =
            stops
                .where(
                  (s) =>
                      [
                        stop['day_number'],
                        target['day_number'],
                      ].contains(s['day_number']) &&
                      s['status'] == 'PLANNED',
                )
                .map((s) => s['place_id'])
                .toSet()
              ..add(body['place_id']);
        final actual = (proposed['optimized_places'] as List)
            .map((s) => s['place_id'])
            .toSet();
        if (!actual.containsAll(expected)) {
          return const LocalResponse({
            'success': false,
            'reason': 'TARGET_DAY_INFEASIBLE',
          });
        }
        state['saved'] = draft['saved'];
        state['route'] = proposed;
        state['route']['pack_version'] = packVersion;
        state['stale'] = false;
        result = {
          'success': true,
          'trip_id': id,
          'place_id': body['place_id'],
          'source_day_number': stop['day_number'],
          'target_day_number': target['day_number'],
          'source_itinerary': (proposed['optimized_places'] as List)
              .where((p) => p['day_number'] == stop['day_number'])
              .toList(),
          'target_itinerary': (proposed['optimized_places'] as List)
              .where((p) => p['day_number'] == target['day_number'])
              .toList(),
          'updated_itinerary': proposed,
        };
      } else if (action == 'weather-advisories') {
        result = {
          'trip_id': id,
          'status': 'weather_unavailable',
          'advisories': [],
        };
      } else if (action == 'ignore-weather') {
        result = {'success': true};
      } else {
        return const LocalResponse({
          'detail': 'This action is unavailable for offline trips.',
        }, 422);
      }
      if (changed) {
        await txn.update(
          'trips',
          {'payload': jsonEncode(state)},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      return LocalResponse(result, status);
    });
  }

  Future<void> close() async {
    if (_opening != null) await (await _opening!).close();
    _opening = null;
  }
}
