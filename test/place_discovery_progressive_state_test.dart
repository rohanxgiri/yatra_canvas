import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/place.dart';
import 'package:yatra_canvas/models/recommendation.dart';
import 'package:yatra_canvas/screens/place_discovery/place_discovery_screen.dart';
import 'package:yatra_canvas/services/recommendation_cache.dart';
import 'package:yatra_canvas/services/recommendation_service.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

void main() {
  testWidgets('cold empty refresh renders preparation instead of final empty', (
    tester,
  ) async {
    final service = _ScriptedRecommendationService([
      const _ResponseStep(state: RecommendationRefreshState.queued),
    ]);

    await _pumpScreen(
      tester,
      service: service,
      pollDelay: const Duration(hours: 1),
    );

    expect(
      find.byKey(const ValueKey('place-preparation-state')),
      findsOneWidget,
    );
    expect(find.text('Preparing places for Ujjain'), findsOneWidget);
    expect(find.text('No matching places found'), findsNothing);
    expect(find.textContaining('took longer than expected'), findsNothing);
  });

  testWidgets('cached data stays visible while refresh remains active', (
    tester,
  ) async {
    final cache = _SnapshotCache([_recommendation(1, prefix: 'Cached')]);
    final service = _ScriptedRecommendationService([
      const _ResponseStep(state: RecommendationRefreshState.refreshing),
    ]);

    await _pumpScreen(
      tester,
      service: service,
      cache: cache,
      pollDelay: const Duration(hours: 1),
    );

    expect(find.text('Cached place 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recommendation-data-cached')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('recommendation-refresh-refreshing')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('place-results-skeleton')), findsNothing);
    expect(cache.writeCount, 0);
  });

  testWidgets('three server cards exit skeleton while refresh continues', (
    tester,
  ) async {
    final service = _ScriptedRecommendationService([
      _ResponseStep(
        recommendations: _recommendations(3, prefix: 'Partial'),
        state: RecommendationRefreshState.refreshing,
      ),
    ]);

    await _pumpScreen(tester, service: service);

    expect(find.text('Partial place 1'), findsOneWidget);
    expect(find.text('Partial place 2'), findsOneWidget);
    expect(find.text('Partial place 3'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recommendation-data-partial')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('place-results-skeleton')), findsNothing);
  });

  testWidgets('idle server data reaches complete state', (tester) async {
    final service = _ScriptedRecommendationService([
      _ResponseStep(recommendations: _recommendations(3, prefix: 'Complete')),
    ]);

    await _pumpScreen(tester, service: service);

    expect(
      find.byKey(const ValueKey('recommendation-data-complete')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('recommendation-refresh-idle')),
      findsNothing,
    );
  });

  testWidgets('refresh failure keeps partial cards and warns non-blockingly', (
    tester,
  ) async {
    final service = _ScriptedRecommendationService([
      _ResponseStep(
        recommendations: _recommendations(3, prefix: 'Retained'),
        state: RecommendationRefreshState.refreshFailed,
      ),
    ]);

    await _pumpScreen(tester, service: service);

    expect(find.text('Retained place 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recommendation-data-partial')),
      findsOneWidget,
    );
    expect(find.textContaining('could not finish'), findsOneWidget);
    expect(find.byKey(const ValueKey('error')), findsNothing);
  });

  testWidgets('network failure keeps cached cards', (tester) async {
    final cache = _SnapshotCache([_recommendation(1, prefix: 'Offline')]);
    final service = _ScriptedRecommendationService([
      const _ResponseStep(
        error: RecommendationServiceException('Controlled network failure.'),
      ),
    ]);

    await _pumpScreen(tester, service: service, cache: cache);

    expect(find.text('Offline place 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recommendation-data-cached')),
      findsOneWidget,
    );
    expect(find.text('Controlled network failure.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recommendation-refresh-refreshFailed')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('error')), findsNothing);
    expect(cache.writeCount, 0);
  });

  testWidgets('empty refresh polling stops after the configured bound', (
    tester,
  ) async {
    final service = _ScriptedRecommendationService([
      const _ResponseStep(state: RecommendationRefreshState.refreshing),
      const _ResponseStep(state: RecommendationRefreshState.refreshing),
      const _ResponseStep(state: RecommendationRefreshState.refreshing),
    ]);

    await _pumpScreen(
      tester,
      service: service,
      pollDelay: const Duration(milliseconds: 10),
      maxPollAttempts: 2,
    );
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();

    expect(service.callCount, 3);
    expect(
      find.byKey(const ValueKey('place-preparation-state')),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(service.callCount, 3);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required RecommendationService service,
  RecommendationCache? cache,
  Duration pollDelay = const Duration(seconds: 2),
  int maxPollAttempts = 3,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: PlaceDiscoveryScreen(
        city: _city,
        tripPurposes: const {'Food Exploration'},
        recommendationService: service,
        recommendationCache: cache,
        emptyRefreshPollDelay: pollDelay,
        maxEmptyRefreshPollAttempts: maxPollAttempts,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

const _city = City(
  id: 'city-123',
  name: 'Ujjain',
  state: 'Madhya Pradesh',
  country: 'India',
  latitude: 23.1765,
  longitude: 75.7885,
);

List<Recommendation> _recommendations(int count, {required String prefix}) => [
  for (var index = 1; index <= count; index++)
    _recommendation(index, prefix: prefix),
];

Recommendation _recommendation(int index, {required String prefix}) =>
    Recommendation(
      id: '${prefix.toLowerCase()}-$index',
      name: '$prefix place $index',
      category: 'food',
      latitude: 23.17 + (index / 1000),
      longitude: 75.78,
      reviewCount: 0,
      isPopular: false,
      isHeritage: false,
      isLocalSpeciality: true,
      matchedCategories: const [PlaceCategory.food],
      recommendationScore: 60 + index.toDouble(),
    );

class _ResponseStep {
  const _ResponseStep({
    this.recommendations = const [],
    this.state = RecommendationRefreshState.idle,
    this.error,
  });

  final List<Recommendation> recommendations;
  final RecommendationRefreshState state;
  final Object? error;
}

class _ScriptedRecommendationService extends RecommendationService {
  _ScriptedRecommendationService(this.steps)
    : super(baseUrl: 'http://example.test');

  final List<_ResponseStep> steps;
  int callCount = 0;
  RecommendationRefreshState _state = RecommendationRefreshState.idle;

  @override
  RecommendationRefreshState get lastRefreshState => _state;

  @override
  Future<List<Recommendation>> getRecommendations(
    String cityId,
    Iterable<PlaceCategory> categories, {
    int limit = 30,
    String? tripId,
    Iterable<String>? purposes,
    Iterable<String>? interests,
    PlaceCategory? categoryFilter,
    String? cursor,
  }) async {
    final index = callCount.clamp(0, steps.length - 1).toInt();
    final step = steps[index];
    callCount++;
    _state = step.state;
    if (step.error case final error?) throw error;
    return step.recommendations;
  }

  @override
  void close() {}
}

class _SnapshotCache extends RecommendationCache {
  _SnapshotCache(this.items);

  final List<Recommendation> items;
  int writeCount = 0;

  @override
  String profileKey({
    required String cityId,
    required Iterable<String> purposes,
    required Iterable<PlaceCategory> categories,
    PlaceCategory? categoryFilter,
  }) => 'progressive-state-profile';

  @override
  Future<RecommendationCacheSnapshot?> read(String key) async =>
      RecommendationCacheSnapshot(
        recommendations: items,
        savedAt: DateTime.now().toUtc(),
        lastValidatedAt: DateTime.now().toUtc(),
        freshness: RecommendationCacheFreshness.fresh,
      );

  @override
  Future<void> write(
    String key,
    String cityId,
    Iterable<Recommendation> recommendations,
  ) async {
    writeCount++;
  }
}
