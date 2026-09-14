import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/trip_draft.dart';
import 'package:yatra_canvas/screens/home/widgets/continue_planning_card.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

void main() {
  testWidgets('planning card matches reference and keeps real trip data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader(
      'HomeInter',
    )..addFont(rootBundle.load('lib/assets/fonts/Inter.ttf'))).load();
    final trip = TripDraft(
      tripId: 'visual-fixture',
      destination: const City(
        name: 'Ujjain',
        country: 'India',
        latitude: 23.17,
        longitude: 75.78,
      ),
      startDate: DateTime(2026, 8, 25),
      endDate: DateTime(2026, 8, 28),
      durationDays: 4,
    );
    var tapped = false;
    for (final width in [350.0, 554.0]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: RepaintBoundary(
                  key: const ValueKey('card'),
                  child: ContinuePlanningCard(
                    trip: trip,
                    onContinue: () => tapped = true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('lib/assets/home/ujjain.png'),
          tester.element(find.byType(ContinuePlanningCard)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Ujjain\nSpiritual Trip'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .75,
      );
      final action = tester.getRect(find.text('CONTINUE'));
      final title = tester.getRect(find.text('Ujjain\nSpiritual Trip'));
      expect(action.top, greaterThan(title.bottom));
      expect(
        action.center.dx,
        greaterThan(tester.getCenter(find.byType(ContinuePlanningCard)).dx),
      );
      await expectLater(
        find.byKey(const ValueKey('card')),
        matchesGoldenFile('goldens/continue_planning_${width.toInt()}.png'),
      );
      await tester.tap(find.text('CONTINUE'));
      expect(tapped, isTrue);
      tapped = false;
    }
    trip.startLatitude = 23.17;
    trip.startLongitude = 75.78;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ContinuePlanningCard(trip: trip, onContinue: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
  });
}
