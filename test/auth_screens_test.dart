import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/screens/auth/account_entry_screen.dart';
import 'package:yatra_canvas/screens/auth/sign_in_screen.dart';
import 'package:yatra_canvas/screens/auth/sign_up_screen.dart';
import 'package:yatra_canvas/screens/onboarding/login_screen.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

void main() {
  testWidgets(
    'account surfaces remain usable on a narrow phone with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final screen in <Widget>[
        const AccountEntryScreen(),
        const SignInScreen(),
        const SignUpScreen(),
        const LoginScreen(),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: AppTheme.light,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(1.6),
                padding: EdgeInsets.only(top: 28, bottom: 24),
              ),
              child: screen,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: screen.runtimeType.toString(),
        );

        final scrollable = find.byType(Scrollable);
        if (scrollable.evaluate().isNotEmpty) {
          await tester.drag(scrollable.first, const Offset(0, -900));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${screen.runtimeType} after scrolling',
          );
        }
      }
    },
  );

  testWidgets('legacy guest entry is honest about account availability', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
    );

    expect(find.text('Continue as Guest'), findsOneWidget);
    expect(
      find.textContaining('Account sign-in is not available yet'),
      findsOneWidget,
    );
    expect(find.text('Continue with Google'), findsNothing);
  });
}
