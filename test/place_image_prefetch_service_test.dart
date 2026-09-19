import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/place.dart';
import 'package:yatra_canvas/models/place_image.dart';
import 'package:yatra_canvas/models/recommendation.dart';
import 'package:yatra_canvas/services/place_image_prefetch_service.dart';

void main() {
  testWidgets('successful image precache is recorded only after completion', (
    tester,
  ) async {
    final service = PlaceImagePrefetchService(
      precacheRunner: (_, _, _) async {},
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));
    final place = _recommendation(
      'place-success',
      'https://img.test/photo.jpg',
    );

    expect(await service.prefetchPlace(context, place), isTrue);
    expect(service.wasSuccessfullyPrefetched(place.id), isTrue);
  });

  testWidgets('precache onError is detected and never marked successful', (
    tester,
  ) async {
    final service = PlaceImagePrefetchService(
      precacheRunner: (_, _, onError) async {
        onError(StateError('controlled failure'), StackTrace.current);
      },
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));
    final place = _recommendation('place-failure', 'https://img.test/404.jpg');

    expect(await service.prefetchPlace(context, place), isFalse);
    expect(service.wasSuccessfullyPrefetched(place.id), isFalse);
  });

  testWidgets('invalid image URL is not passed to precacheImage', (
    tester,
  ) async {
    var calls = 0;
    final service = PlaceImagePrefetchService(
      precacheRunner: (_, _, _) async {
        calls++;
      },
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));
    final place = _recommendation('place-invalid', 'file:///tmp/photo.jpg');

    expect(await service.prefetchPlace(context, place), isFalse);
    expect(calls, 0);
    expect(service.wasSuccessfullyPrefetched(place.id), isFalse);
  });
}

Recommendation _recommendation(String id, String url) => Recommendation(
  id: id,
  name: 'Test place',
  category: 'tourism',
  latitude: 25.57,
  longitude: 91.88,
  reviewCount: 0,
  isPopular: false,
  isHeritage: false,
  isLocalSpeciality: false,
  matchedCategories: const [PlaceCategory.tourism],
  recommendationScore: 50,
  image: PlaceImageData(status: 'resolved', url: url),
);
