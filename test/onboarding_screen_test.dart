import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/screens/home/home_screen.dart';
import 'package:yatra_canvas/screens/onboarding/onboarding_screen.dart';
import 'package:yatra_canvas/screens/onboarding/splash_screen.dart';
import 'package:yatra_canvas/screens/onboarding/widgets/onboarding_figma_first_screen.dart';
import 'package:yatra_canvas/screens/onboarding/widgets/onboarding_progress_indicator.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

Future<void> pumpStory(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final font = FontLoader('HomeInter')
    ..addFont(rootBundle.load('lib/assets/fonts/Inter.ttf'));
  await font.load();
  final iconFile = File(
    'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
  );
  if (iconFile.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(ByteData.view(iconFile.readAsBytesSync().buffer)),
        ))
        .load();
  }
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          padding: const EdgeInsets.only(top: 28, bottom: 24),
        ),
        child: RepaintBoundary(
          key: const ValueKey('onboarding-render'),
          child: OnboardingScreen(key: UniqueKey()),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage('lib/assets/home/journey_editorial.png'),
      tester.element(find.byType(OnboardingScreen)),
    );
    await precacheImage(
      const AssetImage('lib/assets/home/amber_fort.png'),
      tester.element(find.byType(OnboardingScreen)),
    );
    await precacheImage(
      const AssetImage('lib/assets/home/city_palace.png'),
      tester.element(find.byType(OnboardingScreen)),
    );
    await precacheImage(
      const AssetImage('lib/assets/home/hawa_mahal.png'),
      tester.element(find.byType(OnboardingScreen)),
    );
    await precacheImage(
      const AssetImage('lib/assets/home/jaipur_aqua_map.png'),
      tester.element(find.byType(OnboardingScreen)),
    );
    for (final asset in [
      'lib/assets/onboarding/figma_map/map_albert_hall_pin.png',
      'lib/assets/onboarding/figma_map/map_jal_mahal_pin.png',
      'lib/assets/onboarding/figma_map/map_hawa_mahal_pin.png',
    ]) {
      await precacheImage(
        AssetImage(asset),
        tester.element(find.byType(OnboardingScreen)),
      );
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('onboarding story visual baselines', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpStory(tester);
    for (var page = 1; page <= 4; page++) {
      await expectLater(
        find.byKey(const ValueKey('onboarding-render')),
        matchesGoldenFile('goldens/onboarding_screen_$page.png'),
      );
      if (page < 4) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('launch enters the story directly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        theme: AppTheme.light,
        home: const SplashScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 901));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('story navigation, back swipe and skip enter Home', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpStory(tester);

    // Page 0 -> Page 1
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('around you.'), findsOneWidget);

    // Page 1 -> Page 2 via swipe
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(
      find.text('Beautiful Places\nOne Seamless Experience'),
      findsOneWidget,
    );
    expect(find.textContaining('Jaipur'), findsOneWidget);
    expect(find.byType(OnboardingMapCard), findsOneWidget);

    final indicator = tester.widget<OnboardingProgressIndicator>(
      find.byType(OnboardingProgressIndicator),
    );
    expect(indicator.pageCount, 4);
    expect(indicator.currentPage, 2);
    expect(find.text('Continue').hitTestable(), findsOneWidget);

    // The map is still part of the PageView, so a back swipe returns to page 1.
    await tester.drag(find.byType(PageView), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('around you.'), findsOneWidget);

    // Navigate back to Page 2
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text('Beautiful Places\nOne Seamless Experience'),
      findsOneWidget,
    );

    // Page 2 -> Page 3
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at your pace.'), findsOneWidget);

    // Start Planning enters Home
    await tester.tap(find.text('Start Planning'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    // Test Skip from early screen
    await pumpStory(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets(
    'all story pages support narrow phones, landscape and large text',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in [
        const Size(320, 640),
        const Size(360, 780),
        const Size(360, 800),
        const Size(384, 854),
        const Size(393, 852),
        const Size(393, 873),
        const Size(412, 915),
        const Size(430, 932),
        const Size(432, 960),
        const Size(543, 916),
        const Size(844, 390),
      ]) {
        for (final scale in [1.0, 1.6]) {
          await pumpStory(tester, size: size, textScale: scale);
          for (var page = 0; page < 4; page++) {
            expect(
              tester.takeException(),
              isNull,
              reason: '$size / $scale / $page',
            );
            final label = switch (page) {
              3 => 'Start Planning',
              _ => 'Continue',
            };
            expect(find.text(label).hitTestable(), findsOneWidget);
            expect(find.text('Skip').hitTestable(), findsOneWidget);
            expect(find.byType(OnboardingProgressIndicator), findsOneWidget);
            if (page == 2) {
              final map = tester.getRect(find.byType(OnboardingMapCard));
              expect(map.width / map.height, closeTo(358 / 500, .01));
              expect(map.left, greaterThanOrEqualTo(20));
              expect(map.right, lessThanOrEqualTo(size.width - 20));
              expect(find.text(label).hitTestable(), findsOneWidget);
              if (scale == 1 && size == const Size(360, 780)) {
                await expectLater(
                  find.byKey(const ValueKey('onboarding-render')),
                  matchesGoldenFile('goldens/onboarding_map_360x780.png'),
                );
              }
              if (scale == 1 && size == const Size(432, 960)) {
                await expectLater(
                  find.byKey(const ValueKey('onboarding-render')),
                  matchesGoldenFile('goldens/onboarding_map_432x960.png'),
                );
              }
              if (scale == 1 && size == const Size(543, 916)) {
                await expectLater(
                  find.byKey(const ValueKey('onboarding-render')),
                  matchesGoldenFile('goldens/onboarding_map_543x916.png'),
                );
              }
            }
            if (page < 3) {
              await tester.tap(find.text(label));
              await tester.pumpAndSettle();
            }
          }
        }
      }
    },
  );

  testWidgets(
    'map step uses local Figma assets and keeps Continue navigation',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpStory(tester);

      // Navigate to page 2 (Journey screen)
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(OnboardingMapCard), findsOneWidget);
      for (final asset in [
        'lib/assets/onboarding/figma_map/map_albert_hall_pin.png',
        'lib/assets/onboarding/figma_map/map_jal_mahal_pin.png',
        'lib/assets/onboarding/figma_map/map_hawa_mahal_pin.png',
      ]) {
        expect(
          find.byWidgetPredicate(
            (widget) => widget is Image && widget.image == AssetImage(asset),
          ),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('at your pace.'), findsOneWidget);
    },
  );

  testWidgets(
    'map step supports reduced motion without changing its composition',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: OnboardingMapStep(isActive: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingMapCard), findsOneWidget);
      final routePaint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(const ValueKey('onboarding-map-route')),
          matching: find.byType(CustomPaint),
        ),
      );
      expect((routePaint.painter as dynamic).progress, 1);
    },
  );

  testWidgets('map waits until active, then draws progressively and settles', (
    tester,
  ) async {
    Widget mapStep({required bool isActive}) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: OnboardingMapStep(isActive: isActive)),
    );

    await tester.pumpWidget(mapStep(isActive: false));

    double routeProgress() {
      final routePaint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(const ValueKey('onboarding-map-route')),
          matching: find.byType(CustomPaint),
        ),
      );
      return (routePaint.painter as dynamic).progress as double;
    }

    expect(routeProgress(), 0);
    await tester.pump(const Duration(seconds: 1));
    expect(routeProgress(), 0);

    await tester.pumpWidget(mapStep(isActive: true));
    expect(routeProgress(), 0);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(routeProgress(), allOf(greaterThan(0), lessThan(1)));
    await tester.pump(const Duration(milliseconds: 2200));
    expect(routeProgress(), 1);
  });
}
