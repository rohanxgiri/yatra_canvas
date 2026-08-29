import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/trip_draft.dart';
import 'package:yatra_canvas/screens/create_trip/trip_preferences_screen.dart';
import 'package:yatra_canvas/screens/onboarding/personal_interests_screen.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

void main() {
  testWidgets('onboarding skips the removed quick check-in screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const PersonalInterestsScreen()),
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Let’s Personalise'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('I already have a good system'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keeping plans in one place'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Build a complete itinerary'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Turn saved ideas into a day that flows'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      find.text('Plans feel better when everyone has a voice'),
      findsOneWidget,
    );
    expect(find.text('Does this sound familiar?'), findsNothing);
  });

  testWidgets('trip preferences use the new budget labels', (tester) async {
    final draft = TripDraft();
    expect(draft.budget, 'Chill');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TripPreferencesScreen(draft: draft),
      ),
    );

    expect(find.text('Saver'), findsOneWidget);
    expect(find.text('Chill'), findsOneWidget);
    expect(find.text('Boujee'), findsOneWidget);
    expect(find.text('Moderate'), findsNothing);
    expect(find.text('Comfortable'), findsNothing);
  });
}
