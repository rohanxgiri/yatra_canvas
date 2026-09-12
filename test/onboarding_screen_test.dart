import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/screens/home/home_screen.dart';
import 'package:yatra_canvas/screens/onboarding/onboarding_screen.dart';
import 'package:yatra_canvas/screens/onboarding/splash_screen.dart';
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
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('onboarding story visual baselines', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpStory(tester);
    for (var page = 1; page <= 3; page++) {
      await expectLater(
        find.byKey(const ValueKey('onboarding-render')),
        matchesGoldenFile('goldens/onboarding_screen_$page.png'),
      );
      if (page < 3) {
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
  testWidgets('story navigation and skip enter Home', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpStory(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('around you.'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('at your pace.'), findsOneWidget);
    await tester.tap(find.text('Start Planning'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    await pumpStory(tester);
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
        const Size(393, 852),
        const Size(430, 932),
        const Size(844, 390),
      ]) {
        for (final scale in [1.0, 1.6]) {
          await pumpStory(tester, size: size, textScale: scale);
          for (var page = 0; page < 3; page++) {
            expect(
              tester.takeException(),
              isNull,
              reason: '$size / $scale / $page',
            );
            final label = page < 2 ? 'Continue' : 'Start Planning';
            expect(find.text(label).hitTestable(), findsOneWidget);
            if (page < 2) {
              await tester.tap(find.text(label));
              await tester.pumpAndSettle();
            }
          }
        }
      }
    },
  );
}
