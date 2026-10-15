import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/trip_draft.dart';
import 'package:yatra_canvas/models/yatra_session.dart';
import 'package:yatra_canvas/screens/account/account_screens.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

import 'support/auth_fakes.dart';

TripDraft _saved() => TripDraft(
  tripId: 'offline_saved',
  destination: const City(
    id: 'jaipur',
    name: 'Jaipur',
    country: 'India',
    latitude: 26.9,
    longitude: 75.8,
  ),
);

void main() {
  tearDown(() => YatraSession.instance.clearRecentTrips());
  testWidgets(
    'persisted local trip reappears in existing history after memory is lost',
    (tester) async {
      YatraSession.instance.clearRecentTrips();
      final auth = testAuth();
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TripHistoryScreen(
            auth: auth,
            loadOfflineTrips: () async => [_saved()],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Jaipur'), findsOneWidget);
      expect(YatraSession.instance.trips.single.tripId, 'offline_saved');
    },
  );
  testWidgets('storage failure retains current plans and retry recovers', (
    tester,
  ) async {
    final auth = testAuth();
    addTearDown(auth.dispose);
    var fail = true;
    YatraSession.instance.remember(TripDraft(tripId: 'online_existing'));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TripHistoryScreen(
          auth: auth,
          loadOfflineTrips: () async {
            if (fail) throw StateError('storage unavailable');
            return [_saved()];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved trips could not load'), findsOneWidget);
    expect(YatraSession.instance.trips.single.tripId, 'online_existing');
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Saved trips could not load'), findsNothing);
    expect(YatraSession.instance.trips, hasLength(2));
  });
  testWidgets(
    'a late history read cannot expose another account after logout',
    (tester) async {
      final auth = testAuth();
      addTearDown(auth.dispose);
      final pending = Completer<List<TripDraft>>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TripHistoryScreen(
            auth: auth,
            loadOfflineTrips: () => pending.future,
          ),
        ),
      );
      await auth.logout();
      pending.complete([_saved()]);
      await tester.pumpAndSettle();
      expect(YatraSession.instance.trips, isEmpty);
      expect(find.text('Jaipur'), findsNothing);
    },
  );
}
