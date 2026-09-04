import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/trip_draft.dart';
import 'package:yatra_canvas/screens/create_trip/select_dates_screen.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

void main() {
  testWidgets('SelectDatesScreen uses dynamic dates without hardcoding', (
    tester,
  ) async {
    final now = DateTime.now();
    final draft = TripDraft();

    // Verify initial start/end date defaults to today/future
    final today = DateTime(now.year, now.month, now.day);
    expect(draft.startDate.isBefore(today), isFalse);
    expect(draft.endDate.isBefore(draft.startDate), isFalse);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SelectDatesScreen(draft: draft),
      ),
    );
    await tester.pumpAndSettle();

    // Verify header and dynamic month/year display
    expect(find.text('When are you\ntravelling?'), findsOneWidget);
    expect(find.byType(SelectDatesScreen), findsOneWidget);

    // Verify navigation buttons exist
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

    // Tap next month
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();

    // Tap previous month
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
  });
}
