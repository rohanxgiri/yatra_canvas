import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/trip_draft.dart';
import 'package:yatra_canvas/screens/create_trip/destination_selection_screen.dart';
import 'package:yatra_canvas/screens/create_trip/select_dates_screen.dart';
import 'package:yatra_canvas/screens/create_trip/arrival_details_screen.dart';
import 'package:yatra_canvas/screens/create_trip/trip_purpose_screen.dart';
import 'package:yatra_canvas/screens/create_trip/trip_preferences_screen.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

void main() {
  testWidgets('planning screens visual and accessible layout review', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader(
      'HomeInter',
    )..addFont(rootBundle.load('lib/assets/fonts/Inter.ttf'))).load();
    final icons = File(
      'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.view(icons.readAsBytesSync().buffer)),
          ))
          .load();
    }
    final draft = TripDraft(
      destination: const City(
        id: 'visual-only',
        name: 'Jaipur',
        state: 'Rajasthan',
        country: 'India',
        latitude: 26.9,
        longitude: 75.8,
      ),
      startDate: DateTime(2027, 2, 10),
      endDate: DateTime(2027, 2, 13),
    );
    for (final width in [393.0, 320.0]) {
      tester.view.physicalSize = Size(width, 852);
      tester.view.devicePixelRatio = 1;
      final screens = <String, Widget>{
        'destination': const DestinationSelectionScreen(),
        'dates': SelectDatesScreen(draft: draft),
        'arrival': ArrivalDetailsScreen(draft: draft),
        'interests': TripPurposeScreen(draft: draft),
        'preferences': TripPreferencesScreen(draft: draft),
      };
      for (final entry in screens.entries) {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 852),
                textScaler: TextScaler.linear(width == 320 ? 1.6 : 1),
                padding: const EdgeInsets.only(top: 28, bottom: 24),
              ),
              child: RepaintBoundary(
                key: const ValueKey('review'),
                child: entry.value,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} at $width',
        );
        if (width == 393) {
          await expectLater(
            find.byKey(const ValueKey('review')),
            matchesGoldenFile('goldens/planning_${entry.key}.png'),
          );
        }
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -1600),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} scrolled at $width',
        );
      }
    }
  });
}
