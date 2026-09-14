import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/admin/admin_app.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/trip_draft.dart';
import 'package:yatra_canvas/models/yatra_session.dart';
import 'package:yatra_canvas/screens/account/account_screens.dart';
import 'package:yatra_canvas/screens/create_trip/destination_selection_screen.dart';
import 'package:yatra_canvas/screens/home/home_screen.dart';
import 'package:yatra_canvas/screens/home/widgets/continue_planning_card.dart';
import 'package:yatra_canvas/screens/home/widgets/home_style.dart';
import 'package:yatra_canvas/theme/app_theme.dart';
import 'package:yatra_canvas/widgets/yatra_bottom_navigation.dart';

Finder action(String label) =>
    find.byWidgetPredicate((w) => w is HomeAction && w.label == label);

void main() {
  tearDown(() {
    YatraSession.instance.clearRecentTrips();
    YatraSession.instance.setName('Traveller');
  });

  for (final width in [320.0, 393.0, 430.0]) {
    testWidgets('guest navigation, saved empty state and profile at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 852),
              textScaler: TextScaler.linear(width == 320 ? 1.6 : 1),
            ),
            child: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mekur'), findsNothing);
      await tester.tap(action('Saved'));
      await tester.pumpAndSettle();
      expect(find.byType(SavedScreen), findsOneWidget);
      expect(find.byType(YatraBottomNavigation), findsOneWidget);
      expect(
        tester
            .widget<YatraBottomNavigation>(find.byType(YatraBottomNavigation))
            .currentIndex,
        3,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Back to exploring'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to exploring'));
      await tester.pumpAndSettle();
      expect(find.text('Get Inspired to Go'), findsOneWidget);
      await tester.tap(action('Profile'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('0 destinations to dream about'), findsOneWidget);
      expect(tester.takeException(), isNull);
      YatraSession.instance.setName('Ananya');
      await tester.pumpAndSettle();
      expect(find.text('Ananya'), findsOneWidget);
      await tester.tap(action('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Ananya'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('real saved trip populates hero and opens its existing ID', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    YatraSession.instance.remember(
      TripDraft(
        tripId: 'saved-session-trip',
        destination: const City(
          id: 'jaipur',
          name: 'Jaipur',
          country: 'India',
          latitude: 26.9,
          longitude: 75.8,
        ),
        startDate: DateTime(2027, 2, 10),
        endDate: DateTime(2027, 2, 12),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ContinuePlanningCard>(find.byType(ContinuePlanningCard))
          .trip!
          .tripId,
      'saved-session-trip',
    );
    expect(find.text('72%'), findsNothing);
    await tester.ensureVisible(action('Continue planning'));
    await tester.pumpAndSettle();
    await tester.tap(action('Continue planning'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TripSummaryScreen>(find.byType(TripSummaryScreen))
          .draft
          .tripId,
      'saved-session-trip',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('destination card carries its city into the real search flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(action('Jaipur, Rajasthan'), 300);
    await tester.pumpAndSettle();
    await tester.tap(action('Jaipur, Rajasthan'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DestinationSelectionScreen>(
            find.byType(DestinationSelectionScreen),
          )
          .initialQuery,
      'Jaipur',
    );
  });

  testWidgets('compact admin menu opens the separate operational drawer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const YatraCanvasAdminApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
