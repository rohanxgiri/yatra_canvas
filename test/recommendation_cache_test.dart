import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/place.dart';
import 'package:yatra_canvas/services/recommendation_cache.dart';

void main() {
  test('profile key is stable across purpose and category ordering', () {
    final cache = RecommendationCache();

    final first = cache.profileKey(
      cityId: 'manali',
      purposes: const ['Nature', 'Photography'],
      categories: const [PlaceCategory.nature, PlaceCategory.heritage],
    );
    final reordered = cache.profileKey(
      cityId: 'manali',
      purposes: const ['Photography', 'Nature'],
      categories: const [PlaceCategory.heritage, PlaceCategory.nature],
    );

    expect(first, reordered);
    expect(first, matches(RegExp(r'^manali:[0-9a-f]{8}$')));
  });

  test('profile key changes when the category filter changes', () {
    final cache = RecommendationCache();

    final all = cache.profileKey(
      cityId: 'manali',
      purposes: const ['Nature'],
      categories: const [PlaceCategory.nature],
    );
    final filtered = cache.profileKey(
      cityId: 'manali',
      purposes: const ['Nature'],
      categories: const [PlaceCategory.nature],
      categoryFilter: PlaceCategory.nature,
    );

    expect(filtered, isNot(all));
  });
}
