import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/main.dart';
import 'package:yatra_canvas/admin/admin_app.dart';
import 'package:yatra_canvas/screens/home/home_screen.dart';

import 'support/auth_fakes.dart';

void main() {
  testWidgets('guest is the default on cold launch and after restart', (
    tester,
  ) async {
    final store = MemorySessionStore();
    for (var launch = 0; launch < 2; launch++) {
      final auth = testAuth(store: store);
      await tester.pumpWidget(YatraCanvasApp(auth: auth));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(auth.session, isNull);
      expect(store.value, isNull);
      expect(find.text('Sign In'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    }
  });
  testWidgets('AC-3 old admin entrypoint never bypasses authentication', (
    tester,
  ) async {
    final auth = testAuth();
    addTearDown(auth.dispose);
    await tester.pumpWidget(YatraCanvasAdminApp(auth: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });
}
