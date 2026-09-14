import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/screens/home/home_screen.dart';
import 'package:yatra_canvas/screens/home/widgets/continue_planning_card.dart';
import 'package:yatra_canvas/screens/home/widgets/home_destination_card.dart';
import 'package:yatra_canvas/screens/home/widgets/where_next_card.dart';
import 'package:yatra_canvas/screens/home/widgets/home_style.dart';
import 'package:yatra_canvas/screens/home/widgets/yatra_favorite_button.dart';
import 'package:yatra_canvas/screens/home/widgets/yatra_refractive_glass.dart';
import 'package:yatra_canvas/theme/app_theme.dart';
import 'package:yatra_canvas/screens/create_trip/destination_selection_screen.dart';
import 'package:yatra_canvas/widgets/yatra_bottom_navigation.dart';

Future<void> _pumpHome(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
  EdgeInsets safeArea = EdgeInsets.zero,
}) async {
  tester.view.physicalSize = size;
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
          size: size,
          textScaler: TextScaler.linear(textScale),
          padding: safeArea,
        ),
        child: const RepaintBoundary(
          key: ValueKey('home-render'),
          child: HomeScreen(),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    final context = tester.element(find.byType(HomeScreen));
    for (final name in [
      'home_background',
      'avatar',
      'journey_editorial',
      'ujjain',
      'jaipur',
      'varanasi',
      'udaipur',
      'manali',
      'goa',
      'rishikesh',
    ]) {
      await precacheImage(AssetImage('lib/assets/home/$name.png'), context);
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('approved frame proportions and rendered appearance', (
    tester,
  ) async {
    await _pumpHome(tester, const Size(700, 1463));
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(ContinuePlanningCard)),
      predicate<Size>((size) => size.width == 620 && size.height >= 341),
    );
    expect(
      tester.getTopLeft(find.byType(ContinuePlanningCard)).dy,
      greaterThan(300),
    );
    expect(tester.getSize(find.byType(WhereNextCard)), const Size(620, 252));
    expect(
      tester.getSize(find.byType(HomeDestinationCard).first),
      const Size(300, 234),
    );
    expect(
      tester.getSize(find.byType(YatraBottomNavigation)),
      const Size(500, 99),
    );
    await expectLater(
      find.byKey(const ValueKey('home-render')),
      matchesGoldenFile('goldens/home_700x1463.png'),
    );
  });

  testWidgets('phone render keeps navigation above system gesture area', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      const Size(390, 844),
      safeArea: const EdgeInsets.only(top: 24, bottom: 24),
    );
    expect(tester.takeException(), isNull);
    final navigation = tester.getRect(find.byType(YatraBottomNavigation));
    expect(navigation.bottom, lessThanOrEqualTo(820));
    await expectLater(
      find.byKey(const ValueKey('home-render')),
      matchesGoldenFile('goldens/home_390x844.png'),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(YatraBottomNavigation),
        matching: _action('Create Trip'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Where are you going?'), findsOneWidget);
  });

  for (final size in [
    const Size(320, 640),
    const Size(600, 900),
    const Size(844, 390),
  ]) {
    testWidgets('home scrolls without overflow at $size and enlarged text', (
      tester,
    ) async {
      await _pumpHome(tester, size, textScale: 2);
      expect(tester.takeException(), isNull);
      // A short landscape viewport lazily builds this sliver after scrolling.
      if (find.text('Somewhere\nworth going.').evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          find.text('Somewhere\nworth going.'),
          200,
        );
        await tester.pumpAndSettle();
      }
      expect(
        tester.getBottomLeft(find.text('Somewhere\nworth going.')).dy,
        lessThan(
          tester.getTopLeft(find.text('Choose a place. Make it your own.')).dy,
        ),
      );
      for (final name in [
        'Jaipur',
        'Varanasi',
        'Udaipur',
        'Manali',
        'Goa',
        'Rishikesh',
      ]) {
        final heart = _action('Favorite $name');
        if (heart.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            heart,
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
        }
        final titleFinder = find.descendant(
          of: find.ancestor(
            of: heart,
            matching: find.byType(HomeDestinationCard),
          ),
          matching: find.text(name),
        ).first;
        expect(
          tester.getBottomLeft(heart).dy,
          lessThan(tester.getTopLeft(titleFinder).dy),
          reason: 'Enlarged caption must stay below the larger glass heart',
        );
      }
      expect(find.byType(HomeDestinationCard), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(_action('Home'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('search and first-trip hero open trip creation', (tester) async {
    await _pumpHome(tester, const Size(700, 1463));
    await tester.tap(_action('Where do you want to go?'));
    await tester.pumpAndSettle();
    expect(find.text('Where are you going?'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate((w) => w is HomeAction && w.label == 'Back'),
    );
    await tester.pumpAndSettle();
    await tester.tap(_action('Plan your first trip'));
    await tester.pumpAndSettle();
    expect(find.text('Where are you going?'), findsOneWidget);
  });

  for (final width in [360.0, 393.0, 412.0, 430.0]) {
    testWidgets(
      'phone $width: cards, favorites, safe area and responsive scrolling',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await _pumpHome(
          tester,
          Size(width, 900),
          safeArea: const EdgeInsets.only(top: 28, bottom: 24),
        );
        final hero = tester.getRect(find.byType(ContinuePlanningCard));
        final where = tester.getRect(find.byType(WhereNextCard));
        expect(hero.width, where.width);
        expect(hero.left, inInclusiveRange(20, 26));
        expect(
          tester.getBottomLeft(find.text('Somewhere\nworth going.')).dy,
          lessThan(
            tester
                .getTopLeft(find.text('Choose a place. Make it your own.'))
                .dy,
          ),
        );
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
        await tester.pumpAndSettle();
        final cards = find.byType(HomeDestinationCard);
        expect(tester.getSize(cards.first), tester.getSize(cards.last));
        final jaipur = find.byWidgetPredicate(
          (w) => w is YatraFavoriteButton && w.name == 'Jaipur',
        );
        final varanasi = find.byWidgetPredicate(
          (w) => w is YatraFavoriteButton && w.name == 'Varanasi',
        );
        expect(tester.getSize(jaipur), const Size(48, 48));
        expect(tester.widget<YatraFavoriteButton>(jaipur).selected, isFalse);
        expect(tester.widget<YatraFavoriteButton>(varanasi).selected, isFalse);
        expect(
          tester
              .getSemantics(_action('Favorite Jaipur'))
              .getSemanticsData()
              .flagsCollection
              .isToggled,
          ui.Tristate.isFalse,
        );
        await tester.tap(jaipur);
        await tester.pumpAndSettle();
        expect(tester.widget<YatraFavoriteButton>(jaipur).selected, isTrue);
        await tester.tap(varanasi);
        await tester.pumpAndSettle();
        expect(tester.widget<YatraFavoriteButton>(varanasi).selected, isTrue);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.byType(YatraBottomNavigation)).bottom,
          lessThan(876),
        );
        await expectLater(
          find.byKey(const ValueKey('home-render')),
          matchesGoldenFile('goldens/home_refined_${width.toInt()}.png'),
        );
        await tester.tap(_action('Home'));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('Welcome back')).dy,
          greaterThanOrEqualTo(28),
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'navigation exposes all five accessible and tappable actions without ink or tooltips',
    (tester) async {
      final calls = <String>[];
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: YatraBottomNavigation(
                scale: .56,
                currentIndex: 0,
                onDestinationSelected: (index) => calls.add(
                  ['Home', 'Explore', 'Create Trip', 'Saved', 'Profile'][index],
                ),
              ),
            ),
          ),
        ),
      );
      for (final label in [
        'Home',
        'Explore',
        'Create Trip',
        'Saved',
        'Profile',
      ]) {
        final node = tester.getSemantics(_action(label));
        expect(node.label, label);
        expect(
          node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isTrue,
        );
        await tester.tap(_action(label));
        await tester.pumpAndSettle();
      }
      expect(calls, ['Home', 'Explore', 'Create Trip', 'Saved', 'Profile']);
      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(InkResponse), findsNothing);
      expect(find.byType(Tooltip), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'hover has no state layer; press scales and cancel restores; keyboard activates',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 80,
                height: 60,
                child: HomeAction(
                  label: 'Glass control',
                  onTap: () => taps++,
                  child: const Text('Glass'),
                ),
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(_action('Glass control')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(Tooltip), findsNothing);
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      await mouse.down(tester.getCenter(_action('Glass control')));
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        .97,
      );
      await mouse.cancel();
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      expect(taps, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(taps, 1);
      await mouse.removePointer();
    },
  );

  testWidgets(
    'glass consistently uses clipped native blur without shader loading',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 48,
                height: 48,
                child: YatraRefractiveGlass(child: SizedBox.expand()),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(tester.getSize(find.byType(ClipRRect)), const Size(48, 48));
      expect(
        tester
            .widget<BackdropFilter>(find.byType(BackdropFilter))
            .filter
            .toString(),
        contains('blur'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'popular destinations grid renders 6 cards with independent favorite and navigation',
    (tester) async {
      await _pumpHome(tester, const Size(700, 1463));
      expect(find.byType(HomeDestinationCard), findsWidgets);

      // Verify each destination card exists with proper labels
      const destinations = [
        ('Jaipur', 'Rajasthan'),
        ('Varanasi', 'Uttar Pradesh'),
        ('Udaipur', 'Rajasthan'),
        ('Manali', 'Himachal Pradesh'),
        ('Goa', 'Goa'),
        ('Rishikesh', 'Uttarakhand'),
      ];

      for (final dest in destinations) {
        final card = find.byWidgetPredicate(
          (w) => w is HomeAction && w.label == '${dest.$1}, ${dest.$2}',
        );
        if (card.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            card,
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
        }
        expect(card, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.text(dest.$1)),
          findsWidgets,
        );
        expect(
          find.descendant(of: card, matching: find.text(dest.$2)),
          findsWidgets,
        );
      }

      // Verify favorite toggle does not trigger navigation
      final udaipurHeart = find.byWidgetPredicate(
        (w) => w is YatraFavoriteButton && w.name == 'Udaipur',
      );
      expect(tester.widget<YatraFavoriteButton>(udaipurHeart).selected, isFalse);
      await tester.tap(udaipurHeart);
      await tester.pumpAndSettle();
      expect(tester.widget<YatraFavoriteButton>(udaipurHeart).selected, isTrue);
      // Navigation should NOT have opened DestinationSelectionScreen
      expect(find.byType(DestinationSelectionScreen), findsNothing);

      // Verify tapping the destination card opens destination selection
      final cardAction = find.byWidgetPredicate(
        (w) => w is HomeAction && w.label == 'Udaipur, Rajasthan',
      );
      await tester.tap(cardAction);
      await tester.pumpAndSettle();
      expect(find.byType(DestinationSelectionScreen), findsOneWidget);
    },
  );
}

Finder _action(String label) =>
    find.byWidgetPredicate((w) => w is HomeAction && w.label == label);
