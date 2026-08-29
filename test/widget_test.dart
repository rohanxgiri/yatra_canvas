import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/main.dart';
import 'package:yatra_canvas/screens/create_trip/destination_selection_screen.dart';
import 'package:yatra_canvas/screens/home/home_screen.dart';
import 'package:yatra_canvas/screens/onboarding/login_screen.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

void main() {
  testWidgets('opens the onboarding flow from splash', (tester) async {
    await tester.pumpWidget(const YatraCanvasApp());

    expect(find.text('Your journey, mapped.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(
      find.text('Turn your travel ideas\ninto a journey.'),
      findsOneWidget,
    );
    expect(find.text('Continue as Guest'), findsNothing);
  });

  testWidgets('login offers phone, Google, Apple, and guest access', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
    );

    expect(find.text('Mobile number'), findsOneWidget);
    expect(find.text('Continue with Phone'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue as Guest'), findsOneWidget);
  });

  testWidgets('create trip flow advances through all five steps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const DestinationSelectionScreen(),
      ),
    );

    expect(find.text('Where are you\ngoing?'), findsOneWidget);
    expect(find.text('Ujjain'), findsWidgets);

    final continueButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(continueButton.onPressed, isNull);

    await tester.tap(
      find.widgetWithText(ActionChip, 'Ujjain, Madhya Pradesh'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('When are you\ntravelling?'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('How are you\nreaching Ujjain?'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('What brings you\nto Ujjain?'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('How do you like\nto travel?'), findsOneWidget);

    await tester.tap(find.text('Find Places For Me'));
    await tester.pumpAndSettle();
    expect(find.text('Trip setup complete'), findsOneWidget);
    expect(
      find.text('Next, YatraCanvas will find places that match your journey.'),
      findsOneWidget,
    );
  });

  testWidgets('destination search filters local mock data', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const DestinationSelectionScreen(),
      ),
    );

    await tester.enterText(find.byType(TextField), 'jai');
    await tester.pump();

    expect(find.text('Jaipur'), findsOneWidget);
    expect(find.text('Varanasi'), findsNothing);
  });

  testWidgets('Home create navigation opens and returns from trip setup', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Where are you\ngoing?'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Trip'));
    await tester.pumpAndSettle();
    expect(find.text('Where are you\ngoing?'), findsOneWidget);
  });
}
