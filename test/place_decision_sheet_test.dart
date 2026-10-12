import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/place.dart';
import 'package:yatra_canvas/models/recommendation.dart';
import 'package:yatra_canvas/widgets/place_decision_sheet.dart';

const recommendation = Recommendation(
  id: 'demo-poi',
  name: 'Demo Heritage Place',
  category: 'heritage',
  latitude: 26.9,
  longitude: 75.8,
  reviewCount: 0,
  isPopular: false,
  isHeritage: true,
  isLocalSpeciality: false,
  matchedCategories: [PlaceCategory.heritage],
  recommendationScore: 82,
  placeDetails: Place(
    id: 'demo-poi',
    cityId: 'jaipur',
    name: 'Demo Heritage Place',
    category: 'heritage',
    latitude: 26.9,
    longitude: 75.8,
    reviewCount: 0,
    isPopular: false,
    isHeritage: true,
    isLocalSpeciality: false,
    description: 'A preserved courtyard with traditional architecture.',
  ),
);

Widget screen({Future<bool> Function()? onToggle, Recommendation item = recommendation}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox.expand(
          child: PlaceDecisionSheet(
            recommendation: item,
            cityName: 'Jaipur',
            initiallySelected: false,
            categoryLabel: 'Heritage',
            matchDescription: 'Matches your heritage interests',
            meta: 'Jaipur',
            onToggle: onToggle,
          ),
        ),
      ),
    );

void main() {
  testWidgets('details describe the place without adding it', (tester) async {
    var saves = 0;
    await tester.pumpWidget(screen(onToggle: () async { saves++; return true; }));
    expect(find.text('A preserved courtyard with traditional architecture.'), findsOneWidget);
    expect(find.text('Before you visit'), findsOneWidget);
    expect(find.textContaining('Opening hours unavailable'), findsOneWidget);
    expect(saves, 0);
  });

  testWidgets('add only happens on explicit button tap', (tester) async {
    var saves = 0;
    await tester.pumpWidget(screen(onToggle: () async { saves++; return true; }));
    await tester.tap(find.byKey(const ValueKey('place-decision-action')));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.text('Remove from itinerary'), findsOneWidget);
  });

  testWidgets('details are readable without a created trip', (tester) async {
    await tester.pumpWidget(screen());
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('place-decision-action')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Save trip first'), findsOneWidget);
  });

  testWidgets('unavailable description is not fabricated', (tester) async {
    await tester.pumpWidget(screen(item: const Recommendation(
      id: 'unknown',
      name: 'Unknown Place',
      category: 'heritage',
      latitude: 26.9,
      longitude: 75.8,
      reviewCount: 0,
      isPopular: false,
      isHeritage: false,
      isLocalSpeciality: false,
      matchedCategories: [PlaceCategory.heritage],
      recommendationScore: 75,
    )));
    expect(find.textContaining('A detailed description is not available'), findsOneWidget);
  });
}
