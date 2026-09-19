import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/widgets/yc_skeleton.dart';

void main() {
  testWidgets('skeleton tone pulses subtly while animations are enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: YCSkeletonPulse(
          label: 'Loading',
          child: YCSkeletonBlock(key: Key('block'), width: 100, height: 20),
        ),
      ),
    );
    final initial = _blockColor(tester);

    await tester.pump(const Duration(milliseconds: 525));

    expect(_blockColor(tester), isNot(initial));
  });

  testWidgets('skeleton tone remains still for reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: YCSkeletonPulse(
            label: 'Loading',
            child: YCSkeletonBlock(key: Key('block'), width: 100, height: 20),
          ),
        ),
      ),
    );
    final initial = _blockColor(tester);

    await tester.pump(const Duration(milliseconds: 525));

    expect(_blockColor(tester), initial);
  });
}

Color? _blockColor(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byKey(const Key('block')),
      matching: find.byType(Container),
    ),
  );
  return (container.decoration! as BoxDecoration).color;
}
