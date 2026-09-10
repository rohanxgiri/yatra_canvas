import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/screens/explore/explore_page.dart';
import 'package:yatra_canvas/screens/home/home_screen.dart';
import 'package:yatra_canvas/screens/home/widgets/home_destination_card.dart';
import 'package:yatra_canvas/screens/home/widgets/home_style.dart';
import 'package:yatra_canvas/screens/home/widgets/yatra_favorite_button.dart';
import 'package:yatra_canvas/theme/app_theme.dart';
import 'package:yatra_canvas/widgets/yatra_bottom_navigation.dart';

Future<void> _pumpShell(
  WidgetTester tester,
  double width, {
  double height = 900,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final font = FontLoader('HomeInter')
    ..addFont(rootBundle.load('lib/assets/fonts/Inter.ttf'));
  await font.load();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          padding: const EdgeInsets.only(top: 28, bottom: 24),
        ),
        child: const RepaintBoundary(
          key: ValueKey('shell-render'),
          child: HomeScreen(),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    final context = tester.element(find.byType(HomeScreen));
    for (final name in ['ujjain', 'jaipur', 'varanasi']) {
      await precacheImage(AssetImage('lib/assets/home/$name.png'), context);
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Explore 393 px visual baseline', (tester) async {
    await _pumpShell(tester, 393);
    await tester.tap(_action('Explore'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('shell-render')),
      matchesGoldenFile('goldens/explore_393.png'),
    );
  });

  testWidgets('one navigation glides from Home to Explore and changes page', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpShell(tester, 393);
    expect(find.byType(YatraBottomNavigation), findsOneWidget);
    expect(
      tester
          .getSemantics(_action('Home'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    final start = tester.getTopLeft(
      find.byKey(const ValueKey('yatra-nav-selection')),
    );

    await tester.tap(_action('Explore'));
    await tester.pumpAndSettle();
    final end = tester.getTopLeft(
      find.byKey(const ValueKey('yatra-nav-selection')),
    );
    expect(end.dx, greaterThan(start.dx));
    expect(
      tester
          .widget<AnimatedPositioned>(
            find.byKey(const ValueKey('yatra-nav-selection')),
          )
          .duration,
      const Duration(milliseconds: 280),
    );

    expect(find.byType(YatraBottomNavigation), findsOneWidget);
    expect(find.byType(ExplorePage), findsOneWidget);
    expect(
      tester
          .getSemantics(_action('Explore'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    expect(find.text('Get Inspired to Go'), findsOneWidget);
    expect(find.textContaining('Escape The Ordinary'), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
    expect(
      find.descendant(
        of: find.byType(YatraBottomNavigation),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    expect(find.byType(InkResponse), findsNothing);
    semantics.dispose();
  });

  testWidgets('carousel shows side cards and pagination follows a swipe', (
    tester,
  ) async {
    await _pumpShell(tester, 393);
    await tester.tap(_action('Explore'));
    await tester.pumpAndSettle();

    final pageView = find.byKey(const ValueKey('explore-carousel'));
    final viewport = tester.getSize(pageView);
    final cards = find.byType(ExploreCategoryCard);
    expect(cards, findsAtLeastNWidgets(3));
    final selectedCard = find.byWidgetPredicate(
      (widget) =>
          widget is ExploreCategoryCard &&
          widget.category.title == 'Spiritual Journeys',
    );
    final cardWidth = tester.getSize(selectedCard).width;
    expect(cardWidth / viewport.width, closeTo(.82, .02));
    expect(
      tester.getRect(cards.first).right,
      greaterThan(tester.getRect(pageView).left),
    );

    await tester.drag(pageView, const Offset(-280, 0));
    await tester.pumpAndSettle();
    final food = tester.widget<ExploreCategoryCard>(
      find.byWidgetPredicate(
        (widget) =>
            widget is ExploreCategoryCard &&
            widget.category.title == 'Food Trails',
      ),
    );
    expect(food.selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 393.0, 412.0, 430.0]) {
    testWidgets('Explore is responsive and reachable at $width px', (
      tester,
    ) async {
      await _pumpShell(tester, width);
      await tester.tap(_action('Explore'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(YatraBottomNavigation), findsOneWidget);

      await tester.drag(
        find.byKey(const ValueKey('explore-scroll')),
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      expect(find.text('Popular Destinations'), findsOneWidget);
      expect(find.byType(HomeDestinationCard), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      final nav = tester.getRect(find.byType(YatraBottomNavigation));
      expect(nav.bottom, lessThanOrEqualTo(876));
    });
  }

  testWidgets('favorite state is shared by Home and Explore', (tester) async {
    await _pumpShell(tester, 393);
    await tester.tap(_action('Explore'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('explore-scroll')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    final jaipur = find.byWidgetPredicate(
      (widget) => widget is YatraFavoriteButton && widget.name == 'Jaipur',
    );
    expect(tester.widget<YatraFavoriteButton>(jaipur).selected, isTrue);
    await tester.tap(jaipur);
    await tester.pumpAndSettle();

    await tester.tap(_action('Home'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    final homeJaipur = find.byWidgetPredicate(
      (widget) => widget is YatraFavoriteButton && widget.name == 'Jaipur',
    );
    expect(tester.widget<YatraFavoriteButton>(homeJaipur).selected, isFalse);
  });
}

Finder _action(String label) => find.byWidgetPredicate(
  (widget) => widget is HomeAction && widget.label == label,
);
