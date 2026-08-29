import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/admin/admin_app.dart';

void main() {
  testWidgets('admin overview renders and navigation opens trips', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const YatraCanvasAdminApp());
    await tester.pumpAndSettle();

    expect(find.text('Good morning, Aarav'), findsOneWidget);
    expect(find.text('Route pulse'), findsOneWidget);
    expect(find.text('2,840'), findsOneWidget);

    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();

    expect(find.text('Traveller journeys'), findsOneWidget);
    expect(find.text('Ujjain Spiritual Trail'), findsOneWidget);
  });
}
