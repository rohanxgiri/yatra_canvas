import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/trip_draft.dart';
import 'package:yatra_canvas/models/yatra_session.dart';
import 'package:yatra_canvas/screens/account/account_screens.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

void main() {
  tearDown(() {
    YatraSession.instance.clearRecentTrips();
    YatraSession.instance.setName('Traveller');
    YatraSession.instance.setPace('Balanced');
  });

  test('session remembers only saved snapshots and updates without duplicates', () {
    final session = YatraSession.instance;
    session.remember(TripDraft());
    expect(session.trips, isEmpty);
    final draft = TripDraft(tripId: 'saved-trip', purposes: {'Food'});
    session.remember(draft);
    draft.purposes.add('Nature');
    draft.durationDays = 7;
    expect(session.trips.single.purposes, {'Food'});
    expect(session.trips.single.durationDays, 2);
    session.remember(draft);
    expect(session.trips, hasLength(1));
    expect(session.trips.single.durationDays, 7);
  });

  testWidgets('account screens fit narrow phones and enlarged text', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader('HomeInter')..addFont(rootBundle.load('lib/assets/fonts/Inter.ttf'))).load();
    final icons = File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
    }
    for (final width in [393.0, 320.0]) {
      tester.view.physicalSize = Size(width, 852);
      tester.view.devicePixelRatio = 1;
      final favorites = <String>{'Jaipur'};
      for (final entry in <String, Widget>{
        'profile': ProfileScreen(favorites: favorites, onFavorite: favorites.remove),
        'saved': SavedScreen(favorites: favorites, onFavorite: favorites.remove),
        'history': const TripHistoryScreen(),
        'settings': const SettingsScreen(),
      }.entries) {
        await tester.pumpWidget(MaterialApp(
          key: UniqueKey(), theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 852), textScaler: TextScaler.linear(width == 320 ? 1.6 : 1), padding: const EdgeInsets.only(top: 28, bottom: 24)),
            child: RepaintBoundary(key: const ValueKey('account-review'), child: entry.value),
          ),
        ));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          for (final image in tester.widgetList<Image>(find.byType(Image))) {
            await precacheImage(image.image, tester.element(find.byType(Image).first));
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${entry.key} at $width');
        if (width == 393) {
          await expectLater(find.byKey(const ValueKey('account-review')), matchesGoldenFile('goldens/account_${entry.key}.png'));
        }
        await tester.drag(find.byType(ListView).first, const Offset(0, -1400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${entry.key} scrolled at $width');
      }
    }
  });
}
