import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/admin/admin_app.dart';
import 'package:yatra_canvas/main.dart';
import 'package:yatra_canvas/screens/home/home_screen.dart';
import 'package:yatra_canvas/screens/onboarding/personal_interests_screen.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

void main() {
  testWidgets('launch story reaches home without a sign-in detour', (tester) async {
    await tester.pumpWidget(const YatraCanvasApp());
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Find somewhere\nworth going.'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('legacy personalisation entry follows the three-page story', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const PersonalInterestsScreen()));
    for (var page = 0; page < 2; page++) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Start Planning'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });
  testWidgets('all admin navigation destinations render', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const YatraCanvasAdminApp());
    await tester.pumpAndSettle();

    const destinations = <String, String>{
      'Trips': 'Traveller journeys',
      'Destinations': 'Manage the places travellers can discover.',
      'Travellers': 'A simple view of people planning with YatraCanvas.',
      'Reports': 'Review content flagged by travellers.',
      'Overview': 'Route pulse',
    };

    for (final entry in destinations.entries) {
      await tester.tap(find.text(entry.key).first);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
    }
  });
}

