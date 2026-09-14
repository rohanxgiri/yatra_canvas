import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/theme/app_theme.dart';
import 'package:yatra_canvas/theme/yc_motion.dart';
import 'package:yatra_canvas/widgets/trip_generation_experience.dart';
import 'package:yatra_canvas/widgets/yc_pressable.dart';

void main() {
  testWidgets('pressable compresses and recovers without Material ink', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: YCPressable(
              semanticLabel: 'Choose heritage',
              onTap: () {},
              child: const SizedBox(width: 120, height: 52),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(YCPressable)),
    );
    await tester.pump(YCMotion.press);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, .98);
    expect(find.byType(InkWell), findsNothing);

    await gesture.up();
    await tester.pump(YCMotion.press);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  testWidgets('press feedback respects reduced motion', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: YCPressable(
              onTap: () {},
              child: const SizedBox(width: 120, height: 52),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
      Duration.zero,
    );
  });

  testWidgets('trip generation uses contextual phases without a spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const TripGenerationExperience(destination: 'Jaipur'),
      ),
    );

    expect(find.text('Building your Yatra'), findsOneWidget);
    expect(find.text('Creating your trip'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Keeping your dates and pace together'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('trip generation fits small, standard and large phones', (
    tester,
  ) async {
    final cases = <(Size, double)>[
      (const Size(320, 640), 1.6),
      (const Size(393, 852), 1),
      (const Size(430, 932), 1),
    ];

    for (final phone in cases) {
      tester.view.physicalSize = phone.$1;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: phone.$1,
              textScaler: TextScaler.linear(phone.$2),
            ),
            child: const TripGenerationExperience(destination: 'Jaipur'),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: '${phone.$1} at ${phone.$2}x text',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
