import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/screens/explore/explore_page.dart';
import 'package:yatra_canvas/screens/home/home_screen.dart';
import 'package:yatra_canvas/screens/home/widgets/home_style.dart';
import 'package:yatra_canvas/screens/home/widgets/yatra_favorite_button.dart';
import 'package:yatra_canvas/theme/app_theme.dart';
import 'package:yatra_canvas/widgets/yatra_bottom_navigation.dart';

// Cross-platform smoke test, also run explicitly with --platform chrome.
void main() {
  testWidgets(
    'web-safe home paints, scrolls, toggles and navigates at phone widths',
    (tester) async {
      final font = FontLoader('HomeInter')
        ..addFont(rootBundle.load('lib/assets/fonts/Inter.ttf'));
      await font.load();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [360.0, 393.0, 412.0, 430.0]) {
        tester.view.physicalSize = Size(width, 820);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: HomeScreen(key: ValueKey(width)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsWidgets);
        expect(find.byType(Tooltip), findsNothing);
        expect(find.byType(InkWell), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is HomeAction && widget.label == 'Explore',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ExplorePage), findsOneWidget);
        expect(find.byType(PageView), findsOneWidget);
        expect(find.byType(YatraBottomNavigation), findsOneWidget);
        expect(find.byType(BackdropFilter), findsWidgets);
        expect(find.byType(Tooltip), findsNothing);
        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is HomeAction && widget.label == 'Home',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ExplorePage), findsNothing);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
        await tester.pumpAndSettle();
        final favorite = find.byWidgetPredicate(
          (w) => w is YatraFavoriteButton && w.name == 'Varanasi',
        );
        await tester.ensureVisible(favorite);
        await tester.tap(favorite);
        await tester.pumpAndSettle();
        expect(tester.widget<YatraFavoriteButton>(favorite).selected, isTrue);
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.descendant(
            of: find.byType(YatraBottomNavigation),
            matching: find.byWidgetPredicate(
              (w) => w is HomeAction && w.label == 'Create Trip',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Where are you\ngoing?'), findsOneWidget);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
      }
    },
  );
}
