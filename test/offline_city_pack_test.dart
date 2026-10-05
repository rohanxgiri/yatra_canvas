import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yatra_canvas/services/city_pack_repository.dart';
import 'package:yatra_canvas/services/local_first_client.dart';
import 'package:yatra_canvas/services/location_service.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/trip_draft.dart';
import 'package:yatra_canvas/screens/create_trip/arrival_details_screen.dart';
import 'package:yatra_canvas/screens/create_trip/start_point_picker.dart';
import 'package:yatra_canvas/screens/trip_map/trip_map_screen.dart';
import 'package:yatra_canvas/models/trip_start_location.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:yatra_canvas/services/trip_service.dart';
import 'package:yatra_canvas/services/place_prefetch_service.dart';
import 'package:yatra_canvas/theme/app_theme.dart';
import 'package:yatra_canvas/services/local_itinerary_planner.dart';
import 'package:yatra_canvas/models/optimized_route.dart';
import 'package:yatra_canvas/models/route_geometry.dart';
import 'package:yatra_canvas/models/place.dart';
import 'package:yatra_canvas/models/recommendation.dart';
import 'package:yatra_canvas/models/saved_place.dart';
import 'package:yatra_canvas/widgets/poi_bottom_sheet.dart';

class FileAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

class ChangedManifestAssets extends FileAssets {
  @override
  Future<ByteData> load(String key) async {
    final data = await super.load(key);
    if (!key.endsWith('/manifest.json')) return data;
    final manifest = jsonDecode(utf8.decode(data.buffer.asUint8List())) as Map;
    manifest['pack_version'] = 'upgrade-test';
    return ByteData.sublistView(
      Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
    );
  }
}

class UnavailableFtsAssets extends FileAssets {
  UnavailableFtsAssets(this.bytes);
  final Uint8List bytes;
  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('/city_pack.sqlite')) return ByteData.sublistView(bytes);
    final data = await super.load(key);
    if (!key.endsWith('/manifest.json')) return data;
    final manifest = jsonDecode(utf8.decode(data.buffer.asUint8List())) as Map;
    manifest['database_sha256'] = sha256.convert(bytes).toString();
    manifest['checksums']['city_pack.sqlite'] = manifest['database_sha256'];
    return ByteData.sublistView(
      Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
    );
  }
}

Future<void> loadOfflineVisualFonts() async {
  for (final family in ['HomeInter', 'Segoe UI', 'Inter']) {
    await (FontLoader(
      family,
    )..addFont(rootBundle.load('lib/assets/fonts/Inter.ttf'))).load();
  }
  final icons = File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer))))
        .load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late CityPackRepository packs;
  late OfflineTripStore trips;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('yatra-pack-test-');
    packs = CityPackRepository(
      bundle: FileAssets(),
      factory: databaseFactoryFfi,
      directory: directory.path,
    );
    trips = OfflineTripStore(
      factory: databaseFactoryFfi,
      directory: directory.path,
    );
  });
  tearDown(() async {
    await trips.close();
    await packs.close();
    await directory.delete(recursive: true);
  });

  test(
    'offline location filters separate hotels stations and airports',
    () async {
      var calls = 0;
      final client = LocalFirstClient(
        packs: packs,
        trips: trips,
        allowEnrichment: false,
        network: MockClient((_) async {
          calls++;
          throw StateError('No network');
        }),
      );
      final service = LocationService(
        client: client,
        baseUrl: 'http://offline.test',
      );
      final stations = await service.autocomplete(
        '',
        hotelOnly: false,
        cityId: 'jaipur',
        locationKind: 'station',
      );
      expect(stations.map((s) => s.name), contains('Mansarovar metro station'));
      expect(
        stations.map((s) => s.name),
        contains('Jaipur Junction railway station'),
      );
      final junction = await service.autocomplete(
        'jaipur railway station',
        hotelOnly: false,
        cityId: 'jaipur',
        locationKind: 'station',
      );
      expect(junction.single.name, 'Jaipur Junction railway station');
      expect(junction.single.latitude, 26.920203);
      expect(junction.single.longitude, 75.786923);
      expect(stations.any((s) => s.name.contains('Airport')), isFalse);
      final airports = await service.autocomplete(
        '',
        hotelOnly: false,
        cityId: 'jaipur',
        locationKind: 'airport',
      );
      expect(airports.single.name, 'Jaipur International Airport');
      final hotels = await service.autocomplete(
        '',
        hotelOnly: true,
        cityId: 'jaipur',
      );
      expect(hotels, isNotEmpty);
      expect(
        hotels.any(
          (s) => stations.any((t) => s.providerPlaceId == t.providerPlaceId),
        ),
        isFalse,
      );
      final hawa = await service.autocomplete(
        'hawa mahal jaipur',
        hotelOnly: false,
        cityId: 'jaipur',
      );
      expect(hawa.map((s) => s.name), contains('Hawa Mahal Jaipur'));
      expect(calls, 0);
    },
  );

  test(
    'offline starting suggestions satisfy the typed location contract',
    () async {
      var networkCalls = 0;
      final client = LocalFirstClient(
        packs: packs,
        trips: trips,
        allowEnrichment: false,
        network: MockClient((_) async {
          networkCalls++;
          throw StateError('Network must not run');
        }),
      );
      final service = LocationService(
        client: client,
        baseUrl: 'http://offline.test',
      );
      final suggestions = await service.autocomplete(
        'Mansarovar',
        hotelOnly: false,
        latitude: 26.915458,
        longitude: 75.818982,
      );
      expect(
        suggestions.any((s) => s.name == 'Mansarovar metro station'),
        isTrue,
      );
      expect(suggestions.every((s) => s.countryCode == 'in'), isTrue);
      expect(networkCalls, 0);
      final hotels = await service.autocomplete(
        '',
        hotelOnly: true,
        cityId: 'jaipur',
      );
      expect(hotels, isNotEmpty);
      final db = await packs.database('jaipur');
      for (final hotel in hotels) {
        expect(
          (await db.query(
            'places',
            columns: ['category'],
            where: 'id = ?',
            whereArgs: [hotel.providerPlaceId],
          )).single['category'],
          'hotel',
        );
      }
      expect(
        await service.autocomplete(
          'nonexistentstationxyz',
          hotelOnly: false,
          cityId: 'jaipur',
        ),
        isEmpty,
      );
      expect(networkCalls, 0);
      client.close();
    },
  );

  test('SQLite without FTS5 searches real names, aliases and hotels offline', () async {
    // Reproduce Android's unsupported virtual-table module in an isolated copy.
    final fixture = await File('assets/citypacks/jaipur/city_pack.sqlite')
        .copy('${directory.path}/no-fts.sqlite');
    final writer = await databaseFactoryFfi.openDatabase(fixture.path);
    await writer.execute('PRAGMA writable_schema = ON');
    await writer.rawUpdate(
      "UPDATE sqlite_master SET sql = replace(sql, 'USING fts5', 'USING unavailable_fts5') WHERE name = 'place_search'",
    );
    await writer.close();
    final portable = CityPackRepository(
      bundle: UnavailableFtsAssets(await fixture.readAsBytes()),
      factory: databaseFactoryFfi,
      directory: '${directory.path}/portable',
    );
    addTearDown(portable.close);
    final db = await portable.database('jaipur');
    await expectLater(
      db.rawQuery(
        "SELECT * FROM place_search WHERE place_search MATCH 'Mansarovar'",
      ),
      throwsA(isA<DatabaseException>()),
    );
    final station = await portable.getCityPlaces('jaipur', query: 'Mansarovar');
    expect(station.any((p) => p['name'] == 'Mansarovar metro station'), isTrue);
    final hotels = await portable.getCityPlaces(
      'jaipur',
      query: 'hotel',
      hotelOnly: true,
      limit: 2,
    );
    expect(hotels, hasLength(2));
    for (final hotel in hotels) {
      expect(
        (await db.query(
          'places',
          columns: ['category'],
          where: 'id = ?',
          whereArgs: [hotel['id']],
        )).single['category'],
        'hotel',
      );
    }
    final aliasRow = (await db.rawQuery(
      "SELECT id, aliases FROM places WHERE aliases != '[]' LIMIT 1",
    )).single;
    final alias =
        (jsonDecode(aliasRow['aliases'] as String) as List).first as String;
    expect(
      (await portable.getCityPlaces(
        'jaipur',
        query: alias,
      )).any((p) => p['id'] == aliasRow['id']),
      isTrue,
    );
    expect(
      await portable.getCityPlaces('jaipur', query: 'unknownstationxyz'),
      isEmpty,
    );
    expect(await portable.getCityPlaces('jaipur', query: '%_'), isEmpty);
  });

  testWidgets(
    'offline itinerary renders route lines without online map requests',
    (tester) async {
      await loadOfflineVisualFonts();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader('Inter')..addFont(
            Future.value(
              ByteData.view(
                File('lib/assets/fonts/Inter.ttf').readAsBytesSync().buffer,
              ),
            ),
          ))
          .load();
      final places = (await tester.runAsync(
        () => packs.getCityPlaces('jaipur', limit: 3),
      ))!;
      final selected = [
        for (var i = 0; i < places.length; i++)
          <String, dynamic>{
            'id': 'selection$i',
            'trip_id': 'offline_map',
            'place_id': places[i]['id'],
            'custom_order': i,
            'priority': 0,
            'is_locked': false,
            'must_visit': false,
            'assignment_mode': 'AUTO',
            'place': places[i],
          },
      ];
      final state = <String, dynamic>{
        'trip': {
          'trip_id': 'offline_map',
          'city': {'latitude': 26.9, 'longitude': 75.8},
          'start_latitude': 26.96799,
          'start_longitude': 75.76536,
        },
        'saved': selected,
        'days': [
          {
            'day_number': 1,
            'date': '2026-10-05',
            'day_type': 'FULL_DAY',
            'start_time': '09:00',
            'end_time': '19:00',
          },
        ],
        'route': null,
      };
      final route = OptimizedRoute.fromJson(LocalItineraryPlanner.plan(state));
      expect(route.places, isNotEmpty);
      for (final width in [393.0, 320.0]) {
        tester.view.physicalSize = Size(width, 852);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 852),
                textScaler: TextScaler.linear(width == 320 ? 1.6 : 1),
              ),
              child: RepaintBoundary(
                key: boundary,
                child: TripMapScreen(
                  tripId: 'offline_map',
                  initialDurationDays: 1,
                  initialStartLocation: const TripStartLocation(
                    tripId: 'offline_map',
                    type: TripStartLocationType.custom,
                    name: 'Chosen point',
                    latitude: 26.96799,
                    longitude: 75.76536,
                  ),
                  initialSavedPlaces: selected
                      .map(SavedPlace.fromJson)
                      .toList(),
                  initialOptimizedRoute: route,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TileLayer), findsNothing);
        expect(find.text('Offline route overview'), findsOneWidget);
        expect(
          tester
              .widget<PolylineLayer>(find.byType(PolylineLayer))
              .polylines
              .single
              .points
              .length,
          route.places.length + 1,
        );
        expect(tester.takeException(), isNull);
        if (width == 393 && const bool.fromEnvironment('CAPTURE_START_FIX')) {
          await tester.runAsync(() async {
            final rendered =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await rendered.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File('docs/verification/offline-route-overview.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            rendered.dispose();
          });
        }
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'offline point picker renders bundled markers and accepts an unlisted point',
    (tester) async {
      await loadOfflineVisualFonts();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('lib/assets/fonts/Inter.ttf'))).load();
      final icons = File(
        'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
      );
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.view(icons.readAsBytesSync().buffer)),
            ))
            .load();
      }
      var calls = 0;
      final client = LocalFirstClient(
        packs: packs,
        trips: trips,
        allowEnrichment: false,
        network: MockClient((_) async {
          calls++;
          throw StateError('No network');
        }),
      );
      final locations = LocationService(
        client: client,
        baseUrl: 'http://offline.test',
      );
      await tester.runAsync(
        () => locations.autocomplete('', hotelOnly: false, cityId: 'jaipur'),
      );
      for (final width in [393.0, 320.0]) {
        tester.view.physicalSize = Size(width, 852);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 852),
                textScaler: TextScaler.linear(width == 320 ? 1.6 : 1),
              ),
              child: RepaintBoundary(
                key: boundary,
                child: StartPointPicker(
                  cityName: 'Jaipur',
                  cityId: 'jaipur',
                  latitude: 26.915458,
                  longitude: 75.818982,
                  locationService: locations,
                ),
              ),
            ),
          ),
        );
        final landmark = find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Albert Hall Museum',
        );
        for (var i = 0; i < 20 && landmark.evaluate().isEmpty; i++) {
          await tester.pump();
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
        }
        await tester.pumpAndSettle();
        expect(landmark, findsOneWidget);
        // Nearby landmarks keep accessible names without covering each other in text.
        expect(find.text('Albert Hall Museum'), findsNothing);
        await tester.tapAt(
          tester.getTopLeft(find.byType(FlutterMap)) + const Offset(25, 25),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(find.text('Chosen point in Jaipur'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Use this starting point'),
              )
              .onPressed,
          isNotNull,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'Point picker at $width',
        );
        if (width == 393 && const bool.fromEnvironment('CAPTURE_START_FIX')) {
          await tester.runAsync(() async {
            final rendered =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final data = await rendered.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('docs/verification/offline-point-picker.png')
                .writeAsBytes(data!.buffer.asUint8List());
            rendered.dispose();
          });
        }
      }
      await tester.pumpWidget(const SizedBox());
      expect(calls, 0);
      client.close();
    },
  );

  testWidgets(
    'real bundled place starts and persists a trip with zero network requests',
    (tester) async {
      await (FontLoader(
        'HomeInter',
      )..addFont(rootBundle.load('lib/assets/fonts/Inter.ttf'))).load();
      await (FontLoader(
        'Inter',
      )..addFont(rootBundle.load('lib/assets/fonts/Inter.ttf'))).load();
      final icons = File(
        'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
      );
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.view(icons.readAsBytesSync().buffer)),
            ))
            .load();
      }
      tester.view.physicalSize = const Size(393, 852);
      await loadOfflineVisualFonts();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var networkCalls = 0;
      final client = LocalFirstClient(
        packs: packs,
        trips: trips,
        allowEnrichment: false,
        network: MockClient((_) async {
          networkCalls++;
          throw StateError('No network');
        }),
      );
      final locations = LocationService(
        client: client,
        baseUrl: 'http://offline.test',
      );
      final tripService = TripService(
        client: client,
        baseUrl: 'http://offline.test',
      );
      final prefetch = PlacePrefetchService(
        client: client,
        baseUrl: 'http://offline.test',
      );
      final draft = TripDraft(
        destination: const City(
          id: 'jaipur',
          name: 'Jaipur',
          country: 'India',
          latitude: 26.915458,
          longitude: 75.818982,
        ),
      );
      final boundary = GlobalKey();
      await tester.runAsync(() async {
        await locations.autocomplete('', hotelOnly: false, cityId: 'jaipur');
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RepaintBoundary(
            key: boundary,
            child: ArrivalDetailsScreen(
              draft: draft,
              locationService: locations,
              tripService: tripService,
              prefetchService: prefetch,
            ),
          ),
        ),
      );
      for (
        var i = 0;
        i < 20 &&
            find
                .text('Bundled city places • Available offline')
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
      }
      await tester.pumpAndSettle();
      expect(
        find.text('Bundled city places • Available offline'),
        findsOneWidget,
      );
      Future<void> finishLocalSearch() async {
        for (var i = 0; i < 8; i++) {
          await tester.pump();
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
        }
        await tester.pumpAndSettle();
      }

      final hotelDefaults = (await tester.runAsync(
        () => locations.autocomplete('', hotelOnly: true, cityId: 'jaipur'),
      ))!;
      await tester.ensureVisible(find.text('Hotel'));
      await tester.tap(find.text('Hotel'));
      await finishLocalSearch();
      expect(
        find.widgetWithText(ListTile, hotelDefaults.first.name),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Search places'));
      await tester.tap(find.text('Search places'));
      await finishLocalSearch();
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'Train'));
      await tester.tap(find.widgetWithText(FilterChip, 'Train'));
      await finishLocalSearch();
      expect(
        find.widgetWithText(ListTile, 'Jaipur Junction railway station'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ListTile, 'Jaipur International Airport'),
        findsNothing,
      );
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'Flight'));
      await tester.tap(find.widgetWithText(FilterChip, 'Flight'));
      await finishLocalSearch();
      expect(
        find.widgetWithText(ListTile, 'Jaipur International Airport'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'Flight'));
      await tester.tap(find.widgetWithText(FilterChip, 'Flight'));
      await finishLocalSearch();
      await tester.ensureVisible(
        find.byKey(const ValueKey('start-place-search')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('start-place-search')),
        'Jaipur railway station',
      );
      await tester.pump(const Duration(milliseconds: 410));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(ListTile, 'Jaipur Junction railway station'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_START_FIX')) {
        await tester.runAsync(() async {
          final rendered =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await rendered.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File('docs/verification/offline-start-location-v2.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          rendered.dispose();
        });
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(draft.arrivalMethod, isEmpty);
      expect(draft.startLocationProvider, 'city_pack');
      final created = await tester.runAsync(
        () => tripService.createTrip(draft),
      );
      expect(created, isNotNull);
      final saved = await tester.runAsync(
        () => client.get(
          Uri.parse('http://offline.test/trips/${created!.tripId}'),
        ),
      );
      final body = jsonDecode(saved!.body) as Map;
      expect(body['start_latitude'], draft.startLatitude);
      expect(body['start_location_name'], contains('Jaipur Junction'));
      expect(networkCalls, 0);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );

  test('pack upgrade replaces the previous installed DB; corrupted copy is recovered', () async {
    await packs.database('jaipur');
    await packs.close();
    final upgraded = CityPackRepository(
      bundle: ChangedManifestAssets(),
      factory: databaseFactoryFfi,
      directory: directory.path,
    );
    final db = await upgraded.database('jaipur');
    expect(
      (await upgraded.diagnostics('jaipur'))['pack_version'],
      'upgrade-test',
    );
    expect(
      Directory('${directory.path}/citypacks/jaipur')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sqlite')),
      hasLength(1),
    );
    final path = db.path;
    await upgraded.close();
    await File(path).writeAsBytes([1, 2, 3]);
    final damaged = CityPackRepository(
      bundle: ChangedManifestAssets(),
      factory: databaseFactoryFfi,
      directory: directory.path,
    );
    expect(
      (await (await damaged.database('jaipur')).rawQuery('PRAGMA quick_check'))
          .single
          .values
          .single,
      'ok',
    );
    await damaged.close();
  });

  test('SQLite pagination exposes every packaged row and canonical aliases offline', () async {
    final client = LocalFirstClient(
      packs: packs,
      trips: trips,
      allowEnrichment: false,
      network: MockClient(
        (_) async => throw StateError('Network must not run'),
      ),
    );
    final ids = <String>{};
    String? cursor;
    do {
      final response = await client.post(
        Uri.parse('http://offline.test/cities/jaipur/recommendations'),
        body: jsonEncode({'limit': 100, 'cursor': ?cursor}),
      );
      expect(response.statusCode, 200);
      ids.addAll(
        (jsonDecode(response.body) as List).map((p) => p['id'] as String),
      );
      final recommendation = Recommendation.fromJson(
        Map<String, dynamic>.from(
          (jsonDecode(response.body) as List).first as Map,
        ),
      );
      expect(recommendation.placeDetails?.baseSource, 'city_pack');
      expect(
        Recommendation.fromJson(recommendation.toJson())
            .placeDetails
            ?.packVersion,
        isNotNull,
      );
      cursor = response.headers['x-next-cursor'];
    } while (cursor != null);
    expect(ids.length, (await packs.diagnostics('jaipur'))['place_count']);
    final db = await packs.database('jaipur');
    final row = (await db.rawQuery(
      "SELECT id,aliases FROM places WHERE aliases != '[]' LIMIT 1",
    )).single;
    final alias =
        (jsonDecode(row['aliases'] as String) as List).first as String;
    expect(
      (await packs.getCityPlaces(
        'jaipur',
        query: alias,
      )).any((p) => p['id'] == row['id']),
      isTrue,
    );
    client.close();
  });

  test('real Jaipur SQLite installs, indexed queries and media work offline', () async {
    final cities = await packs.searchCities('Jaipur');
    final id = cities.single['id'] as String;
    final places = await packs.getCityPlaces(id, limit: 500);
    expect(places.length, 500);
    expect(Place.fromJson(places.first).id, places.first['id']);
    final search = await packs.getCityPlaces(id, query: 'Jantar Mantar');
    expect(search, isNotEmpty);
    expect(await packs.getPlace(id, search.first['id'] as String), isNotNull);
    final cafes = await packs.getCityPlaces(id, category: 'cafes');
    expect(cafes.every((p) => p['category'] == 'cafes'), isTrue);
    final db = await packs.database(id);
    expect(
      (await db.rawQuery('PRAGMA quick_check')).single.values.single,
      'ok',
    );
    final media = await db.rawQuery(
      'SELECT primary_image_path FROM places WHERE primary_image_path IS NOT NULL LIMIT 1',
    );
    expect(media, isNotEmpty);
    expect(
      await File('assets/citypacks/$id/${media.single['primary_image_path']}')
          .exists(),
      isTrue,
    );
    final diagnostics = await packs.diagnostics(id);
    // Host timings are deliberately distinguished from physical-device timings.
    // ignore: avoid_print
    print('CITYPACK_HOST_TIMINGS ${jsonEncode(diagnostics['timings_ms'])}');
    await packs.close();
    final reopened = CityPackRepository(
      bundle: FileAssets(),
      factory: databaseFactoryFfi,
      directory: directory.path,
    );
    expect(
      await reopened.getPlace(id, search.first['id'] as String),
      isNotNull,
    );
    await reopened.close();
  });

  testWidgets(
    'bundled repaired POI renders its real photo and local description',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final row = (await tester.runAsync(
        () => packs.getPlace('jaipur', 'yc_in_rj_jaipur_suraj_pol_gate'),
      ))!;
      final place = Place.fromJson(row);
      expect(place.description, isNotEmpty);
      expect(place.image?.bundledPath, isNotNull);
      final thumbnailWatch = Stopwatch()..start();
      await tester.runAsync(() async {
        final bytes = await rootBundle.load(place.image!.thumbnailAssetPath!);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThan(0));
        frame.image.dispose();
        codec.dispose();
      });
      thumbnailWatch.stop();
      // ignore: avoid_print
      print(
        'CITYPACK_THUMBNAIL_HOST_MS ${thumbnailWatch.elapsedMicroseconds / 1000}',
      );
      final boundary = GlobalKey();
      await (FontLoader(
        'HomeInter',
      )..addFont(rootBundle.load('lib/assets/fonts/Inter.ttf'))).load();
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('lib/assets/fonts/Inter.ttf'))).load();
      final icons = File(
        'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
      );
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.sublistView(icons.readAsBytesSync())),
            ))
            .load();
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: PoiBottomSheet(
                savedPlace: SavedPlace(
                  id: 'local',
                  tripId: 'offline_acceptance',
                  placeId: place.id,
                  customOrder: 0,
                  priority: 0,
                  isLocked: false,
                  mustVisit: false,
                  place: place,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          ResizeImage(AssetImage(place.image!.assetPath!), width: 900),
          boundary.currentContext!,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('place_image_bundled')), findsOneWidget);
      expect(find.text(place.description!), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_CITY_LOOP')) {
        await tester.runAsync(() async {
          final rendered =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await rendered.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final file = File('docs/verification/offline-suraj-pol.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          rendered.dispose();
        });
      }
    },
  );

  test('runtime enrichment fills missing fields without changing canonical identity', () async {
    final base = {
      'id': 'stable',
      'name': 'Canonical',
      'latitude': 26.9,
      'description': 'Reviewed',
      'website': null,
      'image': null,
      'hours_verification': 'VERIFIED',
    };
    final merged = CityPackRepository.mergeMissingFields(base, {
      'id': 'provider',
      'name': 'Changed',
      'latitude': 0,
      'description': 'Weaker',
      'website': 'https://example.org',
      'opening_hours': {'monday': []},
    });
    expect(merged['id'], 'stable');
    expect(merged['name'], 'Canonical');
    expect(merged['description'], 'Reviewed');
    expect(merged['hours_verification'], 'VERIFIED');
    expect(merged['website'], 'https://example.org');
  });

  test('prepared city trip, selection, days and itinerary survive restart with network unavailable', () async {
    final city = (await packs.searchCities('Jaipur')).single;
    final id = city['id'] as String;
    var calls = 0;
    final client = LocalFirstClient(
      packs: packs,
      trips: trips,
      network: MockClient((r) async {
        calls++;
        return http.Response('[]', 200);
      }),
    );
    final create = await client.post(
      Uri.parse('http://offline.test/trips'),
      body: jsonEncode({
        'request_id': 'acceptance',
        'start_latitude': 26.96799,
        'start_longitude': 75.76536,
        'city_id': id,
        'start_date': '2026-10-05',
        'end_date': '2026-10-06',
        'days': 2,
      }),
    );
    expect(create.statusCode, 201);
    final tripId = (jsonDecode(create.body) as Map)['trip_id'];
    final selected = await packs.getCityPlaces(id, limit: 3);
    for (final place in selected) {
      final response = await client.post(
        Uri.parse('http://offline.test/trips/$tripId/saved-places'),
        body: jsonEncode({'place_id': place['id']}),
      );
      expect(response.statusCode, 201);
    }
    expect(
      jsonDecode(
        (await client.get(Uri.parse('http://offline.test/trips/$tripId/days')))
            .body,
      ),
      hasLength(2),
    );
    final response = await client.post(
      Uri.parse('http://offline.test/trips/$tripId/optimize-route'),
    );
    expect(response.statusCode, 200, reason: response.body);
    expect(
      OptimizedRoute.fromJson(jsonDecode(response.body) as Map<String, dynamic>)
          .places,
      isNotEmpty,
    );
    final route = OptimizedRoute.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    expect(route.routeGeometry!.isOfflineOverview, isTrue);
    expect(route.routeGeometry!.days, isNotEmpty);
    for (final day in route.routeGeometry!.days) {
      expect(day.points.first.latitude, 26.96799);
      expect(day.points.first.longitude, 75.76536);
      final stops = route.places
          .where((p) => p.dayNumber == day.dayNumber)
          .toList();
      expect(day.points, hasLength(stops.length + 1));
      for (var i = 0; i < stops.length; i++) {
        final place = selected.firstWhere((p) => p['id'] == stops[i].placeId);
        expect(day.points[i + 1].latitude, place['latitude']);
        expect(day.points[i + 1].longitude, place['longitude']);
      }
    }
    final geometryResponse = await client.get(
      Uri.parse('http://offline.test/trips/$tripId/route-geometry'),
    );
    expect(
      TripRouteGeometry.fromJson(
        jsonDecode(geometryResponse.body) as Map<String, dynamic>,
      ).days,
      hasLength(route.routeGeometry!.days.length),
    );
    expect(calls, 0);
    await trips.close();
    trips = OfflineTripStore(
      factory: databaseFactoryFfi,
      directory: directory.path,
    );
    final persisted = await trips.handle(
      tripId as String,
      'itinerary',
      'GET',
      {},
      packs,
    );
    expect((persisted.data as Map)['optimized_places'], isNotEmpty);
    await packs.close();
    final upgrade = CityPackRepository(
      bundle: ChangedManifestAssets(),
      factory: databaseFactoryFfi,
      directory: directory.path,
    );
    final impact = await trips.handle(
      tripId,
      'replan-impact',
      'GET',
      {},
      upgrade,
    );
    expect((impact.data as Map)['is_stale'], isTrue);
    final replanned = await trips.handle(
      tripId,
      'optimize-route',
      'POST',
      {},
      upgrade,
    );
    expect((replanned.data as Map)['pack_version'], 'upgrade-test');
    expect(
      ((await trips.handle(tripId, 'replan-impact', 'GET', {}, upgrade)).data
          as Map)['is_stale'],
      isFalse,
    );
    await upgrade.close();
    final unsupported = await client.get(
      Uri.parse('http://offline.test/cities/not-packed/recommendations'),
    );
    expect(unsupported.statusCode, 200);
    expect(calls, 1);
    client.close();
  });

  test(
    'verified split hours constrain visits; unknown and unverified stay usable',
    () {
      Map<String, dynamic> place(String id, String status, String? raw) => {
        'id': id,
        'name': id,
        'latitude': 26.9,
        'longitude': 75.8,
        'recommended_visit_minutes': 60,
        'category': 'tourism',
        'hours_verification': status,
        'opening_hours': parseWeeklyHours(raw),
      };
      final selected = [
        place('closed', 'VERIFIED', 'Mo off'),
        place('split', 'VERIFIED', 'Mo 11:00-12:00,17:00-18:00'),
        place('unknown', 'UNKNOWN', null),
        place('soft', 'UNVERIFIED', 'Mo off'),
      ];
      final route = LocalItineraryPlanner.plan({
        'trip': {
          'trip_id': 'test',
          'city': {'latitude': 26.9, 'longitude': 75.8},
        },
        'days': [
          {
            'id': 'day',
            'day_number': 1,
            'date': '2026-10-05',
            'day_type': 'FULL_DAY',
            'start_time': '09:00',
            'end_time': '19:00',
          },
        ],
        'saved': [
          for (var i = 0; i < selected.length; i++)
            {
              'place_id': selected[i]['id'],
              'place': selected[i],
              'custom_order': i,
            },
        ],
      });
      final stops = (route['optimized_places'] as List).cast<Map>();
      expect(stops.any((p) => p['place_id'] == 'closed'), isFalse);
      expect(
        stops.firstWhere(
          (p) => p['place_id'] == 'split',
        )['planned_arrival_time'],
        '11:00',
      );
      expect(stops.any((p) => p['place_id'] == 'unknown'), isTrue);
      expect(stops.any((p) => p['place_id'] == 'soft'), isTrue);
      expect(parseWeeklyHours('Mo unknown; Tu off')['monday'], isNull);
      expect(parseWeeklyHours('Mo unknown; Tu off')['tuesday'], isEmpty);
      final partial = Place.fromJson({
        ...place('partial', 'VERIFIED', 'Tu off'),
        'city_id': 'test',
        'base_source': 'city_pack',
        'opening_hours_status': 'KNOWN',
        'review_count': 0,
        'is_popular': false,
        'is_heritage': false,
        'is_local_speciality': false,
      });
      expect(partial.isOpenAt(DateTime(2026, 10, 5, 10)), isNull);
      expect(partial.isOpenAt(DateTime(2026, 10, 6, 10)), isFalse);
    },
  );
}
