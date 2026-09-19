import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/place.dart';
import '../models/recommendation.dart';

enum RecommendationCacheFreshness { fresh, staleUsable, expired }

class RecommendationCacheSnapshot {
  const RecommendationCacheSnapshot({
    required this.recommendations,
    required this.savedAt,
    required this.lastValidatedAt,
    required this.freshness,
  });

  final List<Recommendation> recommendations;
  final DateTime savedAt;
  final DateTime lastValidatedAt;
  final RecommendationCacheFreshness freshness;

  bool get isUsable => freshness != RecommendationCacheFreshness.expired;
}

/// Durable, versioned recommendation snapshots for cache-first Discover Places.
class RecommendationCache {
  RecommendationCache({
    this.freshTtl = const Duration(hours: 24),
    this.staleUsableTtl = const Duration(days: 7),
    this.eventualExpiry = const Duration(days: 30),
    this.schemaVersion = 1,
  });

  final Duration freshTtl;
  final Duration staleUsableTtl;
  final Duration eventualExpiry;
  final int schemaVersion;
  Database? _database;
  Future<Database>? _opening;

  String profileKey({
    required String cityId,
    required Iterable<String> purposes,
    required Iterable<PlaceCategory> categories,
    PlaceCategory? categoryFilter,
  }) {
    final purposeValues = purposes.map((value) => value.trim()).toList()
      ..sort();
    final categoryValues = categories.map((value) => value.apiValue).toList()
      ..sort();
    final canonical = <String>[
      cityId.trim(),
      purposeValues.join(','),
      categoryValues.join(','),
      categoryFilter?.apiValue ?? '',
    ].join('|');
    return '${cityId.trim()}:${_fnv1a64(canonical)}';
  }

  Future<RecommendationCacheSnapshot?> read(String key) async {
    try {
      final db = await _db();
      final rows = await db.query(
        'recommendation_snapshots',
        where: 'cache_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      if (row['schema_version'] != schemaVersion) {
        await db.delete(
          'recommendation_snapshots',
          where: 'cache_key = ?',
          whereArgs: [key],
        );
        return null;
      }

      final savedAt = DateTime.parse(row['saved_at']! as String).toUtc();
      final validatedAt = DateTime.parse(row['last_validated_at']! as String)
          .toUtc();
      final age = DateTime.now().toUtc().difference(validatedAt);
      final freshness = age <= freshTtl
          ? RecommendationCacheFreshness.fresh
          : age <= staleUsableTtl
          ? RecommendationCacheFreshness.staleUsable
          : RecommendationCacheFreshness.expired;
      if (age > eventualExpiry) {
        await db.delete(
          'recommendation_snapshots',
          where: 'cache_key = ?',
          whereArgs: [key],
        );
        return null;
      }
      final payload = jsonDecode(row['payload']! as String) as List<dynamic>;
      return RecommendationCacheSnapshot(
        recommendations: payload
            .map(
              (item) => Recommendation.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
        savedAt: savedAt,
        lastValidatedAt: validatedAt,
        freshness: freshness,
      );
    } on Object catch (error) {
      _debugLog('read failed ${error.runtimeType}');
      return null;
    }
  }

  Future<void> write(
    String key,
    String cityId,
    Iterable<Recommendation> recommendations,
  ) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final payload = jsonEncode(
        recommendations.map((item) => item.toJson()).toList(growable: false),
      );
      final db = await _db();
      await db.insert('recommendation_snapshots', {
        'cache_key': key,
        'city_id': cityId,
        'payload': payload,
        'saved_at': now,
        'last_validated_at': now,
        'schema_version': schemaVersion,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } on Object catch (error) {
      _debugLog('write failed ${error.runtimeType}');
    }
  }

  Future<Database> _db() async {
    final existing = _database;
    if (existing != null) return existing;
    final opening = _opening;
    if (opening != null) return opening;
    final future = _open();
    _opening = future;
    return future;
  }

  Future<Database> _open() async {
    final path = '${await getDatabasesPath()}/yatracanvas_recommendations.db';
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (database, _) => database.execute('''
        CREATE TABLE recommendation_snapshots (
          cache_key TEXT PRIMARY KEY,
          city_id TEXT NOT NULL,
          payload TEXT NOT NULL,
          saved_at TEXT NOT NULL,
          last_validated_at TEXT NOT NULL,
          schema_version INTEGER NOT NULL
        )
      '''),
    );
    _database = db;
    return db;
  }

  static String _fnv1a64(String input) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(input)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static void _debugLog(String message) {
    if (kDebugMode) {
      developer.log(message, name: 'RecommendationCache');
    }
  }
}
