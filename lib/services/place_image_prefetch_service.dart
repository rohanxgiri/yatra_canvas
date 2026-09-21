import 'dart:developer' as developer;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/recommendation.dart';

typedef PlaceImagePrecacheRunner = Future<void> Function(
  ImageProvider provider,
  BuildContext context,
  ImageErrorListener onError,
);

class PlaceImagePrefetchService {
  PlaceImagePrefetchService({PlaceImagePrecacheRunner? precacheRunner})
    : _precacheRunner = precacheRunner ?? _defaultPrecache;

  final PlaceImagePrecacheRunner _precacheRunner;
  final Set<String> _successfulPlaceIds = <String>{};

  bool wasSuccessfullyPrefetched(String placeId) =>
      _successfulPlaceIds.contains(placeId);

  Future<void> prefetchRecommendations(
    BuildContext context,
    Iterable<Recommendation> recommendations, {
    int concurrency = 4,
    int firstScreenful = 8,
    int nextScreenful = 8,
    String? requestId,
  }) async {
    final candidates = recommendations
        .where((place) => place.image?.bestUrl != null)
        .take(firstScreenful + nextScreenful)
        .toList(growable: false);
    final batchSize = concurrency.clamp(1, 8).toInt();
    for (var offset = 0; offset < candidates.length; offset += batchSize) {
      final end = (offset + batchSize).clamp(0, candidates.length).toInt();
      await Future.wait(
        candidates
            .sublist(offset, end)
            .map(
              (place) => prefetchPlace(context, place, requestId: requestId),
            ),
      );
    }
  }

  Future<bool> prefetchPlace(
    BuildContext context,
    Recommendation place, {
    String? requestId,
  }) async {
    if (_successfulPlaceIds.contains(place.id)) return true;
    final url = place.image?.bestUrl;
    if (url == null) return false;

    final stopwatch = Stopwatch()..start();
    _log('[IMAGE PREFETCH START] requestId=$requestId placeId=${place.id}');
    Object? failure;
    try {
      await _precacheRunner(
        CachedNetworkImageProvider(url),
        context,
        (error, _) => failure = error,
      );
    } on Object catch (error) {
      failure = error;
    }

    if (failure != null) {
      _log(
        '[IMAGE PREFETCH FAILED] requestId=$requestId placeId=${place.id} '
        'runtimeType=${failure.runtimeType} elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      return false;
    }

    _successfulPlaceIds.add(place.id);
    _log(
      '[IMAGE PREFETCH SUCCESS] requestId=$requestId placeId=${place.id} '
      'elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    return true;
  }

  static Future<void> _defaultPrecache(
    ImageProvider provider,
    BuildContext context,
    ImageErrorListener onError,
  ) => precacheImage(provider, context, onError: onError);

  static void _log(String message) {
    if (kDebugMode) {
      developer.log(message, name: 'PlaceImagePrefetchService');
    }
  }
}
