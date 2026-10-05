import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

/// Immutable packaged places. Runtime enrichment and trips use separate databases.
class CityPackRepository {
  CityPackRepository({
    AssetBundle? bundle,
    DatabaseFactory? factory,
    this.directory,
  }) : bundle = bundle ?? rootBundle,
       // The public argument remains `factory`, rather than the private field name.
       // ignore: prefer_initializing_formals
       _factory = factory;

  static final shared = CityPackRepository();
  final AssetBundle bundle;
  final DatabaseFactory? _factory;
  DatabaseFactory get factory => _factory ?? databaseFactory;
  final String? directory;
  Future<Map<String, dynamic>>? _index;
  final Map<String, Future<Database>> _databases = {};
  final Set<String> _withoutFullTextSearch = {};
  final Map<String, Map<String, dynamic>> _manifests = {};
  final Map<String, double> timings = {};
  Database? _cache;
  Future<Database>? _cacheOpening;
  final cachedImages = ValueNotifier<Map<String, Map<String, dynamic>>>({});

  Future<Map<String, dynamic>> get index => _index ??= _loadIndex();
  Future<Map<String, dynamic>> _loadIndex() async {
    if (kIsWeb) return {};
    try {
      return Map<String, dynamic>.from(
        jsonDecode(await bundle.loadString('assets/citypacks/index.json'))
            as Map,
      );
    } on FlutterError {
      return {};
    }
  }

  Future<bool> hasCityPack(String cityId) async =>
      (await index).containsKey(cityId);
  Future<Map<String, dynamic>?> city(String cityId) async {
    final row = (await index)[cityId];
    return row is Map
        ? {
            ...Map<String, dynamic>.from(row),
            'id': cityId,
            'provider_name': 'city_pack',
          }
        : null;
  }

  Future<List<Map<String, dynamic>>> searchCities(String query) async {
    final term = query.trim().toLowerCase();
    return [
      for (final entry in (await index).entries)
        if ('${entry.key} ${entry.value['name']} ${entry.value['state']}'
            .toLowerCase()
            .contains(term))
          {
            ...Map<String, dynamic>.from(entry.value as Map),
            'id': entry.key,
            'provider_name': 'city_pack',
          },
    ];
  }

  Future<Database> database(String cityId) {
    return _databases.putIfAbsent(
      cityId,
      () => _install(cityId).catchError((Object error) {
        _databases.remove(cityId);
        throw error;
      }),
    );
  }

  Future<Database> _install(String cityId) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(cityId)) {
      throw const FormatException('Invalid city ID');
    }
    final watch = Stopwatch()..start();
    final prefix = 'assets/citypacks/$cityId';
    final manifest = Map<String, dynamic>.from(
      jsonDecode(await bundle.loadString('$prefix/manifest.json')) as Map,
    );
    if (manifest['schema_version'] != 1 ||
        manifest['city_id'] != cityId ||
        manifest['validated'] != true) {
      throw const FormatException('Unsupported city pack');
    }
    final digest = manifest['database_sha256'] as String;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid database digest');
    }
    final checksums = Map<String, dynamic>.from(manifest['checksums'] as Map);
    final revision = sha256
        .convert(utf8.encode(jsonEncode(manifest)))
        .toString();
    final root = Directory(
      '${directory ?? await factory.getDatabasesPath()}/citypacks/$cityId',
    );
    await root.create(recursive: true);
    final file = File('${root.path}/$revision.sqlite');
    if (!await file.exists() ||
        sha256.convert(await file.readAsBytes()).toString() != digest) {
      // Validate every declared bundled artifact before making the database visible.
      List<int>? databaseBytes;
      for (final entry in checksums.entries) {
        if (entry.key.contains('..') ||
            entry.key.contains('\\') ||
            entry.key.startsWith('/')) {
          throw const FormatException('Invalid city pack path');
        }
        final bytes = (await bundle.load('$prefix/${entry.key}')).buffer
            .asUint8List();
        if (sha256.convert(bytes).toString() != entry.value) {
          throw FormatException('City pack checksum failed: ${entry.key}');
        }
        if (entry.key == 'city_pack.sqlite') databaseBytes = bytes;
      }
      if (databaseBytes == null || checksums['city_pack.sqlite'] != digest) {
        throw const FormatException('Missing city database');
      }
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(databaseBytes, flush: true);
      // No existing valid revision is removed until its replacement opens successfully.
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }
    timings['install:$cityId'] = watch.elapsedMicroseconds / 1000;
    watch.reset();
    final db = await factory.openDatabase(
      file.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    try {
      if ((await db.rawQuery('PRAGMA quick_check')).first.values.first !=
              'ok' ||
          (await db.rawQuery('SELECT count(*) AS n FROM places')).first['n'] !=
              manifest['place_count']) {
        throw const FormatException('City pack database failed validation');
      }
    } on Object {
      await db.close();
      rethrow;
    }
    _manifests[cityId] = manifest;
    timings['open:$cityId'] = watch.elapsedMicroseconds / 1000;
    for (final entity in root.listSync()) {
      if (entity is File &&
          entity.absolute.uri != file.absolute.uri &&
          entity.path.endsWith('.sqlite')) {
        await entity.delete();
      }
    }
    if (kDebugMode) {
      developer.log(
        '$cityId pack=${manifest['pack_version']} source=${manifest['source_release']} db=${file.path} timings=$timings',
        name: 'CityPack',
      );
    }
    return db;
  }

  Future<List<Map<String, dynamic>>> getCityPlaces(
    String cityId, {
    String? category,
    List<String> categories = const [],
    String? query,
    bool hotelOnly = false,
    String? locationKind,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await database(cityId);
    final watch = Stopwatch()..start();
    final where = <String>[];
    final args = <Object?>[];
    // The current airport record has a generic station subcategory, so names
    // disambiguate transport kinds rather than trusting that field alone.
    const airport =
        "(LOWER(name) LIKE '%airport%' OR subcategory IN ('airport', 'aerodrome'))";
    if (locationKind == 'airport') {
      where.add("category = 'transport' AND $airport");
    }
    if (locationKind == 'station') {
      where.add(
        "category = 'transport' AND (subcategory IN ('station', 'railway_station', 'train_station', 'metro_station') OR LOWER(name) LIKE '%railway station%' OR LOWER(name) LIKE '%metro station%') AND NOT $airport",
      );
    }
    if (hotelOnly) {
      where.add(
        "(category IN ('hotel', 'hotels', 'accommodation', 'lodging') OR subcategory IN ('hotel', 'guest_house', 'hostel', 'motel'))",
      );
    }
    if (category != null) {
      where.add('runtime_category = ?');
      args.add(category == 'cafes' ? 'cafe' : category);
    } else if (categories.isNotEmpty) {
      where.add(
        'runtime_category IN (${List.filled(categories.length, '?').join(',')})',
      );
      args.addAll(categories.map((c) => c == 'cafes' ? 'cafe' : c));
    }
    final cityName = (await city(cityId))?['name']?.toString().toLowerCase();
    final tokens = query == null
        ? <String>[]
        : RegExp(
            r'[\p{L}\p{N}]+',
            unicode: true,
          ).allMatches(query).map((m) => m.group(0)!.toLowerCase()).toList();
    // Users commonly append the selected city ("hawa mahal jaipur"). The
    // pack is already city scoped; that qualifier must not exclude the POI.
    if (tokens.length > 1 && cityName != null) {
      tokens.removeWhere((t) => cityName.split(' ').contains(t));
    }
    if (query?.trim().isNotEmpty == true && tokens.isEmpty) return [];

    Future<List<Map<String, Object?>>> search({required bool fullText}) {
      final predicates = [...where];
      final parameters = [...args];
      if (tokens.isNotEmpty) {
        if (fullText) {
          predicates.add(
            'id IN (SELECT place_id FROM place_search WHERE place_search MATCH ?)',
          );
          parameters.add(tokens.map((t) => '"$t"*').join(' AND '));
        } else {
          // Android system SQLite may lack FTS5. Ordinary fields remain readable
          // in the same immutable pack, including names and canonical aliases.
          for (final token in tokens) {
            predicates.add(
              "(COALESCE(normalized_name, '') || ' ' || COALESCE(name, '') || ' ' || COALESCE(name_en, '') || ' ' || COALESCE(name_hi, '') || ' ' || COALESCE(aliases, '')) LIKE ?",
            );
            parameters.add('%${token.toLowerCase()}%');
          }
        }
      }
      return db.query(
        'places',
        where: predicates.isEmpty ? null : predicates.join(' AND '),
        whereArgs: parameters,
        orderBy:
            '${locationKind == 'station' ? "CASE WHEN subcategory = 'railway_station' THEN 0 ELSE 1 END, " : ''}travel_relevance_score DESC, prominence_score DESC, id',
        limit: limit.clamp(1, 500),
        offset: math.max(0, offset),
      );
    }

    late List<Map<String, Object?>> rows;
    try {
      rows = await search(fullText: !_withoutFullTextSearch.contains(cityId));
    } on DatabaseException catch (error) {
      final message = error.toString().toLowerCase();
      if (tokens.isEmpty ||
          !(message.contains('no such module:') && message.contains('fts5') ||
              message.contains('no such table: place_search'))) {
        rethrow;
      }
      _withoutFullTextSearch.add(cityId);
      rows = await search(fullText: false);
    }
    timings['${query != null
            ? 'search'
            : category != null
            ? 'category'
            : 'places'}:$cityId'] =
        watch.elapsedMicroseconds / 1000;
    final cached = await (await _runtimeCache()).query(
      'enrichment',
      where: 'expires_at > ?',
      whereArgs: [DateTime.now().toUtc().toIso8601String()],
    );
    final byId = {
      for (final row in cached)
        row['place_id']: jsonDecode(row['payload'] as String) as Map,
    };
    return [
      for (final row in rows)
        if (byId[row['id']] case final fields?)
          mergeMissingFields(
            _place(cityId, row),
            Map<String, dynamic>.from(fields),
          )
        else
          _place(cityId, row),
    ];
  }

  Future<Map<String, dynamic>?> getPlace(String cityId, String placeId) async {
    final watch = Stopwatch()..start();
    final rows = await (await database(cityId))
        .query('places', where: 'id = ?', whereArgs: [placeId], limit: 1);
    timings['detail:$cityId'] = watch.elapsedMicroseconds / 1000;
    return rows.isEmpty ? null : _withEnrichment(_place(cityId, rows.single));
  }

  Future<List<Map<String, dynamic>>> getNearbyPlaces(
    String cityId,
    double lat,
    double lon, {
    double radiusMeters = 1000,
    int limit = 50,
  }) async {
    final db = await database(cityId);
    final dy = radiusMeters / 111320;
    final dx = dy / math.max(.01, math.cos(lat * math.pi / 180).abs());
    final rows = await db.query(
      'places',
      where: 'latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?',
      whereArgs: [lat - dy, lat + dy, lon - dx, lon + dx],
      limit: 500,
    );
    final places = [for (final row in rows) _place(cityId, row)]
      ..sort(
        (a, b) => distanceMeters(
          lat,
          lon,
          a['latitude'],
          a['longitude'],
        ).compareTo(distanceMeters(lat, lon, b['latitude'], b['longitude'])),
      );
    return places
        .where(
          (p) =>
              distanceMeters(lat, lon, p['latitude'], p['longitude']) <=
              radiusMeters,
        )
        .take(limit)
        .toList();
  }

  Map<String, dynamic> _place(String cityId, Map<String, Object?> row) {
    final status = row['opening_hours_status'];
    final image = row['image_metadata'] == null
        ? null
        : jsonDecode(row['image_metadata']! as String) as Map<String, dynamic>;
    final schedule = parseWeeklyHours(
      row['opening_hours_normalized'] as String? ??
          row['opening_hours'] as String?,
    );
    return {
      ...row,
      'city_id': cityId,
      'category': row['runtime_category'] == 'cafe'
          ? 'cafes'
          : row['runtime_category'],
      'normalized_category': row['subcategory'] ?? row['category'],
      'review_count': 0,
      'is_popular': row['tier'] == 'core_destination',
      'is_heritage': row['runtime_category'] == 'heritage',
      'is_local_speciality': false,
      'raw_opening_hours': row['opening_hours'],
      'hours_verification': status,
      'opening_hours_status': status == 'UNKNOWN' || schedule.isEmpty
          ? 'UNKNOWN'
          : 'KNOWN',
      'opening_hours': schedule,
      'base_source': 'city_pack',
      'pack_version': _manifests[cityId]?['pack_version'],
      'aliases': jsonDecode(row['aliases'] as String? ?? '[]'),
      'image': image == null
          ? null
          : {
              ...image,
              'asset_path': 'assets/citypacks/$cityId/${image['local_path']}',
              'thumbnail_asset_path':
                  'assets/citypacks/$cityId/${image['thumbnail_path']}',
              'provider': 'city_pack',
              'source_url': image['source_page'],
              'status': 'resolved',
              'media_class': row['media_class'],
            },
    };
  }

  Future<Database> _runtimeCache() => _cacheOpening ??= _openCache();
  Future<Database> _openCache() async => _cache = await factory.openDatabase(
    '${directory ?? await factory.getDatabasesPath()}/yatracanvas_enrichment.sqlite',
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE enrichment (place_id TEXT PRIMARY KEY, payload TEXT NOT NULL, expires_at TEXT NOT NULL)',
      ),
    ),
  );

  Future<void> cacheEnrichment(
    String placeId,
    Map<String, dynamic> fields, {
    Duration ttl = const Duration(hours: 24),
  }) async {
    await (await _runtimeCache()).insert('enrichment', {
      'place_id': placeId,
      'payload': jsonEncode(fields),
      'expires_at': DateTime.now().toUtc().add(ttl).toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (fields['image'] is Map) {
      cachedImages.value = {
        ...cachedImages.value,
        placeId: Map<String, dynamic>.from(fields['image'] as Map),
      };
    }
  }

  Future<Map<String, dynamic>> _withEnrichment(
    Map<String, dynamic> base,
  ) async {
    final rows = await (await _runtimeCache()).query(
      'enrichment',
      where: 'place_id = ?',
      whereArgs: [base['id']],
      limit: 1,
    );
    if (rows.isEmpty ||
        DateTime.parse(rows.single['expires_at'] as String)
            .isBefore(DateTime.now().toUtc())) {
      return base;
    }
    return mergeMissingFields(
      base,
      Map<String, dynamic>.from(
        jsonDecode(rows.single['payload'] as String) as Map,
      ),
    );
  }

  static Map<String, dynamic> mergeMissingFields(
    Map<String, dynamic> base,
    Map<String, dynamic> enrichment,
  ) {
    final result = Map<String, dynamic>.from(base);
    for (final field in ['description', 'website', 'image']) {
      if (base[field] == null || base[field] == '') {
        result[field] = enrichment[field] ?? base[field];
      }
    }
    if (base['hours_verification'] == 'UNKNOWN' &&
        enrichment['opening_hours'] is Map &&
        (enrichment['opening_hours'] as Map).isNotEmpty) {
      result.addAll({
        'opening_hours': enrichment['opening_hours'],
        'opening_hours_status': 'KNOWN',
        'hours_verification': 'UNVERIFIED',
        'raw_opening_hours': enrichment['raw_opening_hours'],
      });
    }
    result['enrichment_state'] = 'cached';
    return result;
  }

  Future<Map<String, dynamic>> diagnostics(String cityId) async {
    await database(cityId);
    return {...?_manifests[cityId], 'timings_ms': timings};
  }

  Future<void> close() async {
    for (final future in _databases.values.toList()) {
      await (await future).close();
    }
    _databases.clear();
    _withoutFullTextSearch.clear();
    await _cache?.close();
    _cache = null;
    _cacheOpening = null;
  }

  static double distanceMeters(
    double lat,
    double lon,
    double otherLat,
    double otherLon,
  ) {
    final dy = (otherLat - lat) * math.pi / 180,
        dx = (otherLon - lon) * math.pi / 180;
    final a =
        math.pow(math.sin(dy / 2), 2) +
        math.cos(lat * math.pi / 180) *
            math.cos(otherLat * math.pi / 180) *
            math.pow(math.sin(dx / 2), 2);
    return 6371000 *
        2 *
        math.atan2(math.sqrt(a), math.sqrt(math.max(0, 1 - a)));
  }
}

/// Only simple weekly syntax is projected. Unsupported seasonal/PH rules stay unknown.
/// No parser invents an interval when the source cannot be understood.
Map<String, List<Map<String, String>>> parseWeeklyHours(String? raw) {
  if (raw == null || raw.trim().isEmpty) return {};
  const codes = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
  const names = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  if (raw.trim() == '24/7') {
    return {
      for (final day in names)
        day: [
          {'open': '00:00', 'close': '24:00'},
        ],
    };
  }
  final result = <String, List<Map<String, String>>>{};
  for (final part in raw.split(';')) {
    final match = RegExp(
      r'^\s*(?:((?:Mo|Tu|We|Th|Fr|Sa|Su)(?:[-,](?:Mo|Tu|We|Th|Fr|Sa|Su))*)\s+)?(unknown|off|closed|\d{2}:\d{2}-\d{2}:\d{2}(?:,\s*\d{2}:\d{2}-\d{2}:\d{2})*)\s*$',
    ).firstMatch(part);
    if (match == null) return {};
    final selected = <int>{};
    if (match[1] == null) {
      selected.addAll(List.generate(7, (i) => i));
    } else {
      for (final range in match[1]!.split(',')) {
        final limits = range.split('-'),
            start = codes.indexOf(limits.first),
            end = codes.indexOf(limits.last);
        var day = start;
        while (true) {
          selected.add(day);
          if (day == end) break;
          day = (day + 1) % 7;
        }
      }
    }
    if (match[2] == 'unknown') {
      for (final day in selected) {
        result.remove(names[day]);
      }
      continue;
    }
    final intervals = <Map<String, String>>[];
    if (match[2] != 'off' && match[2] != 'closed') {
      for (final times in match[2]!.split(',')) {
        final pair = times.trim().split('-');
        int minute(String value) {
          final p = value.split(':');
          return int.parse(p[0]) * 60 + int.parse(p[1]);
        }

        final open = minute(pair[0]), close = minute(pair[1]);
        if (open < 0 ||
            open >= 1440 ||
            close > 1440 ||
            close <= open ||
            int.parse(pair[0].split(':')[1]) > 59 ||
            int.parse(pair[1].split(':')[1]) > 59) {
          return {};
        }
        intervals.add({'open': pair[0], 'close': pair[1]});
      }
    }
    for (final day in selected) {
      result[names[day]] = intervals;
    }
  }
  return result;
}
