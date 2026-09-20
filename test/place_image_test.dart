import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/place.dart';
import 'package:yatra_canvas/models/place_image.dart';
import 'package:yatra_canvas/utils/place_image_fallbacks.dart';
import 'package:yatra_canvas/widgets/place_card.dart';
import 'package:yatra_canvas/widgets/place_image.dart';

void main() {
  test('Place tolerates an absent or null image payload', () {
    final base = <String, dynamic>{
      'id': 'p1',
      'city_id': 'c1',
      'name': 'Hawa Mahal',
      'category': 'heritage',
      'latitude': 26.9,
      'longitude': 75.8,
      'review_count': 0,
      'is_popular': false,
      'is_heritage': true,
      'is_local_speciality': false,
    };

    expect(Place.fromJson(base).image, isNull);
    expect(Place.fromJson({...base, 'image': null}).image, isNull);
  });

  test('fallback resolver maps normalized categories to real assets', () {
    expect(
      placeFallbackAsset(normalizedCategory: 'place_of_worship'),
      endsWith('/temple.webp'),
    );
    expect(
      placeFallbackAsset(rawCategory: 'nature', name: 'Amber waterfall'),
      endsWith('/waterfall.webp'),
    );
    expect(
      placeFallbackAsset(rawCategory: 'nature'),
      endsWith('/park_garden.webp'),
    );
    expect(
      placeFallbackAsset(rawCategory: 'heritage', name: 'Amber Fort'),
      endsWith('/fort_palace.webp'),
    );
    expect(placeFallbackAsset(rawCategory: 'heritage'), isNull);
    expect(placeFallbackAsset(rawCategory: 'tourism'), isNull);
    expect(placeFallbackAsset(normalizedCategory: 'entertainment'), isNull);
  });

  testWidgets('every mapped category resolves to a bundled WebP asset', (
    tester,
  ) async {
    const categories = <String>[
      'cafe',
      'place_of_worship',
      'museum',
      'park_garden',
      'fort_palace',
      'lake_riverfront',
      'hill_viewpoint',
      'market_shopping',
      'beach',
      'desert',
      'waterfall',
      'forest',
      'restaurant',
      'hotel',
      'wildlife',
    ];

    for (final category in categories) {
      final path = placeFallbackAsset(normalizedCategory: category);
      expect(path, isNotNull, reason: category);
      expect(path!, endsWith('.webp'), reason: category);
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0), reason: category);
    }

    expect(placeFallbackAsset(normalizedCategory: 'landmark'), isNull);
    expect(placeFallbackAsset(normalizedCategory: 'entertainment'), isNull);
    expect(placeFallbackAsset(normalizedCategory: 'other'), isNull);
    expect(placeFallbackAsset(normalizedCategory: 'unknown'), isNull);
  });

  testWidgets('missing metadata renders the local category asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          height: 180,
          child: PlaceImage(
            name: 'Jal Mahal',
            normalizedCategory: 'lake_riverfront',
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('place_image_state_unknown')), findsOneWidget);
    expect(find.byKey(const Key('place_image_local_fallback')), findsOneWidget);
    expect(find.text('Photo unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'valid remote metadata uses an image-region loading placeholder',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            width: 320,
            height: 180,
            child: PlaceImage(
              name: 'Hawa Mahal',
              image: PlaceImageData(
                status: 'resolved',
                url: 'https://images.example/hawa.jpg',
              ),
              normalizedCategory: 'landmark',
            ),
          ),
        ),
      );

      final widget = tester.widget<CachedNetworkImage>(
        find.byKey(const Key('place_image_remote')),
      );
      expect(widget.imageUrl, 'https://images.example/hawa.jpg');
      expect(
        find.byKey(const Key('place_image_state_loading')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('place_image_neutral_fallback')),
        findsNothing,
      );
    },
  );

  testWidgets('network failure settles on fallback without layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(8),
            child: PlaceCard(
              name: 'Broken image venue',
              description:
                  'Still usable when the image provider is unavailable.',
              category: 'Cafe',
              normalizedCategory: 'cafe',
              imageData: PlaceImageData(
                status: 'resolved',
                url: 'http://127.0.0.1:1/unavailable.jpg',
              ),
            ),
          ),
        ),
      ),
    );

    final cached = tester.widget<CachedNetworkImage>(
      find.byKey(const Key('place_image_remote')),
    );
    final errorFallback = cached.errorWidget!(
      tester.element(find.byKey(const Key('place_image_remote'))),
      cached.imageUrl,
      StateError('controlled image failure'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(width: 320, height: 180, child: errorFallback),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('place_image_state_error')), findsOneWidget);
    expect(find.byKey(const Key('place_image_local_fallback')), findsOneWidget);
    expect(find.byKey(const Key('place_image_neutral_fallback')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('not-found metadata uses a correct local category asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          height: 180,
          child: PlaceImage(
            name: 'No provider photo',
            normalizedCategory: 'museum',
            image: PlaceImageData(status: 'not_found'),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('place_image_state_not_found')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('place_image_local_fallback')), findsOneWidget);
  });

  testWidgets('unknown category guarantees the neutral fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          height: 180,
          child: PlaceImage(
            name: 'Unknown place',
            normalizedCategory: 'unknown',
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('place_image_local_fallback')), findsNothing);
    expect(
      find.byKey(const Key('place_image_neutral_fallback')),
      findsOneWidget,
    );
  });

  testWidgets('local asset failure falls through to the neutral fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          height: 180,
          child: PlaceImage(name: 'Cafe', normalizedCategory: 'cafe'),
        ),
      ),
    );

    final localImage = tester.widget<Image>(
      find.byKey(const Key('place_image_local_fallback')),
    );
    final neutral = localImage.errorBuilder!(
      tester.element(find.byKey(const Key('place_image_local_fallback'))),
      StateError('controlled asset failure'),
      StackTrace.current,
    );
    await tester.pumpWidget(
      MaterialApp(home: SizedBox(width: 320, height: 180, child: neutral)),
    );

    expect(
      find.byKey(const Key('place_image_neutral_fallback')),
      findsOneWidget,
    );
  });

  test('invalid resolved image URL maps to the error state', () {
    const image = PlaceImageData(status: 'resolved', url: 'not-an-http-image');

    expect(image.state, PlaceImageState.error);
    expect(image.bestUrl, isNull);
  });

  testWidgets(
    'injected image provider supports deterministic success rendering',
    (tester) async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 180,
            child: PlaceImage(
              name: 'Loaded image',
              testImageProvider: MemoryImage(bytes),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(
        find.byKey(const Key('place_image_state_success')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('place_image_state_loading')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('remote loading skeleton is replaced by the success state', (
    tester,
  ) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          height: 180,
          child: PlaceImage(
            name: 'Hawa Mahal',
            image: PlaceImageData(
              status: 'resolved',
              url: 'https://images.example/hawa.jpg',
            ),
          ),
        ),
      ),
    );

    final cached = tester.widget<CachedNetworkImage>(
      find.byKey(const Key('place_image_remote')),
    );
    expect(find.byKey(const Key('place_image_state_loading')), findsOneWidget);

    final success = cached.imageBuilder!(
      tester.element(find.byKey(const Key('place_image_remote'))),
      MemoryImage(bytes),
    );
    await tester.pumpWidget(
      MaterialApp(home: SizedBox(width: 320, height: 180, child: success)),
    );

    expect(find.byKey(const Key('place_image_state_loading')), findsNothing);
    expect(find.byKey(const Key('place_image_state_success')), findsOneWidget);
  });

  testWidgets('place cards keep a stable image layout across device widths', (
    tester,
  ) async {
    for (final width in <double>[320, 360, 393, 430, 768]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(12),
              child: PlaceCard(
                name: 'Amber Fort',
                description:
                    'A historic hilltop fort with courtyards and city views.',
                category: 'Heritage',
                normalizedCategory: 'fort_palace',
                actionLabel: 'Add to trip',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'width=$width');
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('place image card visual regression', (tester) async {
    tester.view.physicalSize = const Size(393, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fallbackProvider = ResizeImage.resizeIfNeeded(
      900,
      null,
      AssetImage(placeFallbackAsset(normalizedCategory: 'fort_palace')!),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFFF7F8F4),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 361,
                height: 535,
                child: RepaintBoundary(
                  key: const Key('place_image_visual'),
                  child: PlaceCard(
                    name: 'Amber Fort',
                    description: 'Hilltop courtyards, gateways, and sweeping Jaipur views.',
                    image: fallbackProvider,
                    category: 'Heritage',
                    normalizedCategory: 'fort_palace',
                    meta: '4.8 · 18,420 reviews',
                    actionLabel: 'Add to trip',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await precacheImage(
        fallbackProvider,
        tester.element(find.byKey(const Key('place_image_visual'))),
      );
    });
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('place_image_visual')),
      matchesGoldenFile('goldens/place_image_system.png'),
    );
  });
}
