import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/utils/place_image_fallbacks.dart';
import 'package:yatra_canvas/widgets/place_image.dart';

void main() {
  test('raw category overrides legacy normalized other fallback', () {
    expect(
      placeFallbackAsset(
        normalizedCategory: 'other',
        rawCategory: 'heritage',
        name: 'Hawa Mahal',
      ),
      'assets/images/place_fallbacks/fort_palace.webp',
    );
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  group('Scenario F: Place Fallback Asset & Category Coverage', () {
    const requiredNormalizedCategories = [
      'restaurant',
      'cafe',
      'landmark',
      'place_of_worship',
      'museum',
      'park_garden',
      'waterfall',
      'hill_viewpoint',
      'market_shopping',
      'other',
    ];

    const requiredAliases = [
      'food',
      'heritage',
      'tourism',
      'religious',
      'cafes',
      'markets',
      'nature',
    ];

    for (final category in requiredNormalizedCategories) {
      test('Normalized category "$category" must have a non-null fallback asset', () {
        final asset = placeFallbackAsset(normalizedCategory: category);
        expect(
          asset,
          isNotNull,
          reason:
              'Normalized category "$category" unexpectedly returned null fallback asset.',
        );
        final file = File(asset!);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'Mapped asset "$asset" for category "$category" does not exist on disk.',
        );
      });
    }

    for (final alias in requiredAliases) {
      test('Alias/input category "$alias" must resolve to a valid fallback asset', () {
        final asset = placeFallbackAsset(rawCategory: alias);
        expect(
          asset,
          isNotNull,
          reason:
              'Alias category "$alias" unexpectedly returned null fallback asset.',
        );
        final file = File(asset!);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'Mapped asset "$asset" for alias "$alias" does not exist on disk.',
        );
      });
    }

    testWidgets(
      'PlaceImage with "landmark" must render an asset image, not neutral placeholder',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 200,
                child: PlaceImage(
                  name: 'Historic Clock Tower',
                  normalizedCategory: 'landmark',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Must find an Image widget with an AssetImage, not the neutral placeholder icon
        expect(
          find.byType(Image),
          findsOneWidget,
          reason: 'Expected an asset Image widget for "landmark".',
        );
        expect(
          find.byIcon(Icons.landscape_rounded),
          findsNothing,
          reason: 'Should not show neutral fallback icon.',
        );
      },
    );

    testWidgets(
      'PlaceImage with "heritage" must render an asset image, not neutral placeholder',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 200,
                child: PlaceImage(
                  name: 'Ancient Temple Ruins',
                  normalizedCategory: 'heritage',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(Image),
          findsOneWidget,
          reason: 'Expected an asset Image widget for "heritage".',
        );
      },
    );
  });
}
