import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/auth_session.dart';
import 'package:yatra_canvas/screens/auth/auth_gate.dart';
import 'package:yatra_canvas/screens/auth/auth_form.dart';

import 'support/auth_fakes.dart';

void main() {
  for (final role in [UserRole.user, UserRole.admin]) {
    testWidgets(
      'restored ${role.value} skips introduction and logout goes to guest Home',
      (tester) async {
        final store = MemorySessionStore()
          ..value = jsonEncode(testSession(role).toJson());
        final auth = testAuth(
          repository: FakeAuthRepository()..role = role,
          store: store,
        );
        addTearDown(auth.dispose);
        var introBuilds = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: AuthGate(
              auth: auth,
              onboardingBuilder: (_, _) {
                introBuilds++;
                return const Text('Introduction');
              },
              userBuilder: (_) => const Scaffold(body: Text('Traveller home')),
              adminBuilder: (_) => const Scaffold(body: Text('Admin console')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            role == UserRole.admin ? 'Admin console' : 'Traveller home',
          ),
          findsOneWidget,
        );
        expect(introBuilds, 0);
        await auth.logout();
        await tester.pumpAndSettle();
        expect(find.text('Traveller home'), findsOneWidget);
        expect(find.byType(AuthForm), findsNothing);
        expect(introBuilds, 0);
        expect(
          Navigator.of(tester.element(find.text('Traveller home'))).canPop(),
          isFalse,
        );
      },
    );
  }
  for (final role in [UserRole.user, UserRole.admin]) {
    testWidgets(
      'AC-2 ${role.value} enters correct experience directly and logout resets history',
      (tester) async {
        final repo = FakeAuthRepository()..role = role;
        final auth = testAuth(repository: repo);
        addTearDown(auth.dispose);
        await auth.login('email', 'secret');
        var userBuilds = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: AuthGate(
              auth: auth,
              userBuilder: (_) {
                userBuilds++;
                return const Scaffold(body: Text('Traveller home'));
              },
              adminBuilder: (_) => const Scaffold(body: Text('Admin console')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            role == UserRole.admin ? 'Admin console' : 'Traveller home',
          ),
          findsOneWidget,
        );
        if (role == UserRole.admin) expect(userBuilds, 0);
        final context = tester.element(
          find.text(
            role == UserRole.admin ? 'Admin console' : 'Traveller home',
          ),
        );
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Private detail')),
          ),
        );
        await tester.pumpAndSettle();
        await auth.logout();
        await tester.pumpAndSettle();
        expect(find.text('Traveller home'), findsOneWidget);
        expect(find.byType(AuthForm), findsNothing);
        expect(find.text('Private detail'), findsNothing);
        expect(
          Navigator.of(tester.element(find.text('Traveller home'))).canPop(),
          isFalse,
        );
      },
    );
  }
  testWidgets(
    'AC-1 validates fields, toggles password, dedicated signup and honest reset',
    (tester) async {
      final auth = testAuth();
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(home: AuthGate(auth: auth, requireAuthentication: true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      await tester.tap(find.byTooltip('Show Password'));
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('Password')),
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        isFalse,
      );
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'person@example.org');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No email was sent'), findsOneWidget);
      await tester.tap(find.text('Back to sign in'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Create an account'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.byKey(const ValueKey('Full name')), findsOneWidget);
      expect(find.byKey(const ValueKey('Confirm password')), findsOneWidget);
    },
  );
}
