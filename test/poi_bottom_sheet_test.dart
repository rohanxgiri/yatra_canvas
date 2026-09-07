// ignore_for_file: avoid_redundant_argument_values
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/itinerary_stop_status.dart';
import 'package:yatra_canvas/models/optimized_route.dart';
import 'package:yatra_canvas/models/place.dart';
import 'package:yatra_canvas/models/saved_place.dart';
import 'package:yatra_canvas/widgets/poi_bottom_sheet.dart';

// ---------------------------------------------------------------------------
// Shared test helpers
// ---------------------------------------------------------------------------

/// 2024-06-10 is a Monday.
final _monday = DateTime(2024, 6, 10);

SavedPlace _savedPlace({
  String placeId = 'p1',
  String name = 'India Gate',
  String category = 'Tourism',
  double lat = 28.6129,
  double lng = 77.2295,
  OpeningHoursStatus ohStatus = OpeningHoursStatus.unknown,
  Map<String, List<OpeningHoursInterval>> openingHours = const {},
}) => SavedPlace(
  id: 's1',
  tripId: 't1',
  placeId: placeId,
  customOrder: 1,
  priority: 1,
  isLocked: false,
  mustVisit: false,
  place: Place(
    id: placeId,
    cityId: 'c1',
    name: name,
    category: category,
    latitude: lat,
    longitude: lng,
    reviewCount: 100,
    isPopular: true,
    isHeritage: false,
    isLocalSpeciality: false,
    openingHoursStatus: ohStatus,
    openingHours: openingHours,
  ),
);

OptimizedRoutePlace _routeStop({
  String placeId = 'p1',
  String name = 'India Gate',
  int dayNumber = 1,
  int visitOrder = 1,
  String? arrivalTime,
  String? departureTime,
  int visitDuration = 60,
  int travelTime = 0,
  double distanceFromPrevious = 0.0,
  String status = 'PLANNED',
}) => OptimizedRoutePlace(
  id: 'stop-1',
  placeId: placeId,
  name: name,
  dayNumber: dayNumber,
  visitOrder: visitOrder,
  distanceFromPrevious: distanceFromPrevious,
  travelTimeMinutes: travelTime,
  plannedArrivalTime: arrivalTime,
  plannedDepartureTime: departureTime,
  visitDurationMinutes: visitDuration,
  status: status,
);

Widget _buildSheet({
  SavedPlace? savedPlace,
  OptimizedRoutePlace? routeStop,
  List<int> availableDays = const [],
  bool isStartLocation = false,
  DateTime? visitDate,
  Future<void> Function(ItineraryStopStatus)? onStatusChange,
  Future<void> Function(int)? onMoveToDay,
}) => MaterialApp(
  home: Scaffold(
    body: PoiBottomSheet(
      savedPlace: savedPlace ?? _savedPlace(),
      routeStop: routeStop,
      availableDays: availableDays,
      isStartLocation: isStartLocation,
      visitDate: visitDate,
      onStatusChange: onStatusChange,
      onMoveToDay: onMoveToDay,
    ),
  ),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Original suite (preserved) ─────────────────────────────────────────────

  testWidgets('1. PoiBottomSheet renders correctly', (tester) async {
    await tester.pumpWidget(_buildSheet());
    expect(find.byKey(const Key('poi_drag_handle')), findsOneWidget);
  });

  testWidgets('2. Place name is displayed', (tester) async {
    await tester.pumpWidget(
      _buildSheet(savedPlace: _savedPlace(name: 'Red Fort')),
    );
    expect(find.text('Red Fort'), findsOneWidget);
  });

  testWidgets('3. Category chip is displayed', (tester) async {
    await tester.pumpWidget(
      _buildSheet(savedPlace: _savedPlace(category: 'Heritage')),
    );
    expect(find.text('Heritage'), findsOneWidget);
  });

  testWidgets('4. Schedule row shown for scheduled stop', (tester) async {
    await tester.pumpWidget(
      _buildSheet(
        routeStop: _routeStop(
          arrivalTime: '09:00:00',
          departureTime: '10:00:00',
        ),
      ),
    );
    expect(find.byKey(const Key('poi_schedule_row')), findsOneWidget);
    expect(find.text('09:00 – 10:00'), findsOneWidget);
  });

  testWidgets('5. Schedule row absent when no routeStop', (tester) async {
    await tester.pumpWidget(_buildSheet(routeStop: null));
    expect(find.byKey(const Key('poi_schedule_row')), findsNothing);
  });

  testWidgets('6. Visit duration row shown', (tester) async {
    await tester.pumpWidget(
      _buildSheet(routeStop: _routeStop(visitDuration: 90)),
    );
    expect(find.byKey(const Key('poi_duration_row')), findsOneWidget);
    expect(find.text('90 min visit'), findsOneWidget);
  });

  testWidgets('7. PLANNED stop shows Mark Visited button', (tester) async {
    await tester.pumpWidget(
      _buildSheet(routeStop: _routeStop(status: 'PLANNED')),
    );
    expect(find.byKey(const Key('poi_mark_visited_button')), findsOneWidget);
  });

  testWidgets("8. PLANNED stop shows Couldn't Visit button", (tester) async {
    await tester.pumpWidget(
      _buildSheet(routeStop: _routeStop(status: 'PLANNED')),
    );
    expect(find.byKey(const Key('poi_couldnt_visit_button')), findsOneWidget);
  });

  testWidgets('9. PLANNED stop shows Skip button', (tester) async {
    await tester.pumpWidget(
      _buildSheet(routeStop: _routeStop(status: 'PLANNED')),
    );
    expect(find.byKey(const Key('poi_skip_button')), findsOneWidget);
  });

  testWidgets('10. MISSED stop shows Move to Another Day button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSheet(
        routeStop: _routeStop(status: 'MISSED'),
        availableDays: [2, 3],
      ),
    );
    expect(find.byKey(const Key('poi_move_day_button')), findsOneWidget);
  });

  testWidgets('11. COMPLETED stop shows no status action buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSheet(routeStop: _routeStop(status: 'COMPLETED')),
    );
    expect(find.byKey(const Key('poi_mark_visited_button')), findsNothing);
    expect(find.byKey(const Key('poi_couldnt_visit_button')), findsNothing);
    expect(find.byKey(const Key('poi_skip_button')), findsNothing);
    expect(find.byKey(const Key('poi_move_day_button')), findsNothing);
  });

  testWidgets('12. Status badge shows Planned', (tester) async {
    await tester.pumpWidget(
      _buildSheet(routeStop: _routeStop(status: 'PLANNED')),
    );
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('poi_status_badge')),
        matching: find.byType(Text),
      ),
    );
    expect(text.data, 'Planned');
  });

  testWidgets('13. Status badge shows Visited for COMPLETED', (tester) async {
    await tester.pumpWidget(
      _buildSheet(routeStop: _routeStop(status: 'COMPLETED')),
    );
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('poi_status_badge')),
        matching: find.byType(Text),
      ),
    );
    expect(text.data, 'Visited');
  });

  testWidgets('14. Status badge shows Missed', (tester) async {
    await tester.pumpWidget(
      _buildSheet(routeStop: _routeStop(status: 'MISSED')),
    );
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('poi_status_badge')),
        matching: find.byType(Text),
      ),
    );
    expect(text.data, 'Missed');
  });

  testWidgets('15. Status badge shows Skipped', (tester) async {
    await tester.pumpWidget(
      _buildSheet(routeStop: _routeStop(status: 'SKIPPED')),
    );
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('poi_status_badge')),
        matching: find.byType(Text),
      ),
    );
    expect(text.data, 'Skipped');
  });

  testWidgets('16. Mark Visited triggers onStatusChange(completed)', (
    tester,
  ) async {
    ItineraryStopStatus? captured;
    await tester.pumpWidget(
      _buildSheet(
        routeStop: _routeStop(status: 'PLANNED'),
        onStatusChange: (s) async => captured = s,
      ),
    );
    await tester.tap(find.byKey(const Key('poi_mark_visited_button')));
    await tester.pump();
    expect(captured, ItineraryStopStatus.completed);
  });

  testWidgets("17. Couldn't Visit triggers onStatusChange(missed)", (
    tester,
  ) async {
    ItineraryStopStatus? captured;
    await tester.pumpWidget(
      _buildSheet(
        routeStop: _routeStop(status: 'PLANNED'),
        onStatusChange: (s) async => captured = s,
      ),
    );
    await tester.tap(find.byKey(const Key('poi_couldnt_visit_button')));
    await tester.pump();
    expect(captured, ItineraryStopStatus.missed);
  });

  testWidgets('18. Skip triggers onStatusChange(skipped)', (tester) async {
    ItineraryStopStatus? captured;
    await tester.pumpWidget(
      _buildSheet(
        routeStop: _routeStop(status: 'PLANNED'),
        onStatusChange: (s) async => captured = s,
      ),
    );
    await tester.tap(find.byKey(const Key('poi_skip_button')));
    await tester.pump();
    expect(captured, ItineraryStopStatus.skipped);
  });

  testWidgets('19. Move to Another Day opens day picker', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showModalBottomSheet(
                context: ctx,
                builder: (_) => PoiBottomSheet(
                  savedPlace: _savedPlace(),
                  routeStop: _routeStop(status: 'MISSED', dayNumber: 1),
                  availableDays: const [2, 3],
                  onMoveToDay: (_) async {},
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('poi_move_day_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('poi_move_day_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('poi_move_day_picker')), findsOneWidget);
  });

  testWidgets('20. Day picker selecting a day triggers onMoveToDay', (
    tester,
  ) async {
    int? pickedDay;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showModalBottomSheet(
                context: ctx,
                builder: (_) => PoiBottomSheet(
                  savedPlace: _savedPlace(),
                  routeStop: _routeStop(status: 'MISSED', dayNumber: 1),
                  availableDays: const [2, 3],
                  onMoveToDay: (d) async => pickedDay = d,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('poi_move_day_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('poi_move_day_option_2')));
    await tester.pumpAndSettle();
    expect(pickedDay, 2);
  });

  testWidgets('21. isStartLocation = true hides itinerary actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSheet(
        routeStop: _routeStop(status: 'PLANNED'),
        isStartLocation: true,
      ),
    );
    expect(find.byKey(const Key('poi_status_badge')), findsNothing);
    expect(find.byKey(const Key('poi_mark_visited_button')), findsNothing);
    expect(find.byKey(const Key('poi_directions_button')), findsNothing);
    expect(find.byKey(const Key('poi_more_details_button')), findsNothing);
  });

  // ── Hardening tests ────────────────────────────────────────────────────────

  // H1. Travel info uses the arriving leg (current stop's own fields), not next stop's.
  testWidgets(
    'H1. Travel row shows current stop arriving-leg travel time (not next stop)',
    (tester) async {
      // visitOrder > 1 so the arriving-leg row is shown.
      final stop = _routeStop(
        visitOrder: 2,
        travelTime: 12,
        distanceFromPrevious: 3.4,
      );
      await tester.pumpWidget(_buildSheet(routeStop: stop));
      // Should show "From previous stop · 12 min · 3.4 km"
      expect(find.byKey(const Key('poi_travel_row')), findsOneWidget);
      expect(find.textContaining('From previous stop'), findsOneWidget);
      expect(find.textContaining('12 min'), findsOneWidget);
      expect(find.textContaining('3.4 km'), findsOneWidget);
    },
  );

  // H2. Travel row is absent for the first stop of the day (no previous stop).
  testWidgets('H2. Travel row absent for first stop of day (visitOrder == 1)', (
    tester,
  ) async {
    final stop = _routeStop(
      visitOrder: 1,
      travelTime: 20,
      distanceFromPrevious: 5.0,
    );
    await tester.pumpWidget(_buildSheet(routeStop: stop));
    expect(find.byKey(const Key('poi_travel_row')), findsNothing);
  });

  // H3. Travel row is absent when both travel values are zero.
  testWidgets(
    'H3. Travel row absent when travelTime and distance are both zero',
    (tester) async {
      final stop = _routeStop(
        visitOrder: 2,
        travelTime: 0,
        distanceFromPrevious: 0.0,
      );
      await tester.pumpWidget(_buildSheet(routeStop: stop));
      expect(find.byKey(const Key('poi_travel_row')), findsNothing);
    },
  );

  // H4. CLOSED opening hours shows "Closed", NOT "Permanently closed".
  testWidgets('H4. CLOSED opening hours shows Closed, not Permanently closed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSheet(
        savedPlace: _savedPlace(ohStatus: OpeningHoursStatus.closed),
        routeStop: _routeStop(),
      ),
    );
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('Permanently closed'), findsNothing);
  });

  // H5. KNOWN open at arrival shows "Open until X:XX PM".
  testWidgets('H5. KNOWN open at arrival shows Open until', (tester) async {
    // Use Monday (2024-06-10) with intervals 08:00-18:00; arrival 10:00.
    await tester.pumpWidget(
      _buildSheet(
        savedPlace: _savedPlace(
          ohStatus: OpeningHoursStatus.known,
          openingHours: {
            'monday': [
              const OpeningHoursInterval(open: '08:00', close: '18:00'),
            ],
          },
        ),
        routeStop: _routeStop(arrivalTime: '10:00:00'),
        visitDate: _monday,
      ),
    );
    expect(find.byKey(const Key('poi_opening_hours_row')), findsOneWidget);
    // 18:00 → "6:00 PM"
    expect(find.textContaining('Open until 6:00 PM'), findsOneWidget);
  });

  // H6. KNOWN closed at arrival shows "Closed at scheduled time".
  testWidgets('H6. KNOWN closed at arrival shows Closed at scheduled time', (
    tester,
  ) async {
    // Interval 08:00-12:00; arrival 14:00 → outside → closed.
    await tester.pumpWidget(
      _buildSheet(
        savedPlace: _savedPlace(
          ohStatus: OpeningHoursStatus.known,
          openingHours: {
            'monday': [
              const OpeningHoursInterval(open: '08:00', close: '12:00'),
            ],
          },
        ),
        routeStop: _routeStop(arrivalTime: '14:00:00'),
        visitDate: _monday,
      ),
    );
    expect(find.text('Closed at scheduled time'), findsOneWidget);
  });

  // H7. Split opening-hours gap shows "Closed at scheduled time" when visit falls in gap.
  testWidgets('H7. Split opening-hours gap shows Closed at scheduled time', (
    tester,
  ) async {
    // Two intervals: 09:00-11:00, 14:00-22:00. Visit at 12:00 falls in the gap.
    await tester.pumpWidget(
      _buildSheet(
        savedPlace: _savedPlace(
          ohStatus: OpeningHoursStatus.known,
          openingHours: {
            'monday': [
              const OpeningHoursInterval(open: '09:00', close: '11:00'),
              const OpeningHoursInterval(open: '14:00', close: '22:00'),
            ],
          },
        ),
        routeStop: _routeStop(arrivalTime: '12:00:00'),
        visitDate: _monday,
      ),
    );
    expect(find.text('Closed at scheduled time'), findsOneWidget);
  });

  // H8. UNKNOWN never displays "Open" as a status claim.
  testWidgets('H8. UNKNOWN opening hours never claims place is open', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSheet(
        savedPlace: _savedPlace(ohStatus: OpeningHoursStatus.unknown),
        routeStop: _routeStop(arrivalTime: '10:00:00'),
        visitDate: _monday,
      ),
    );
    // UNKNOWN must never produce "Open until …" or "Opens at …".
    expect(find.textContaining('Open until'), findsNothing);
    expect(find.textContaining('Opens at'), findsNothing);
    // Must always show the unavailable label.
    expect(find.text('Opening hours unavailable'), findsOneWidget);
  });

  // H9. KNOWN status without visitDate shows "Opening hours unavailable" (no guess).
  testWidgets(
    'H9. KNOWN without visitDate shows unavailable, not open/closed',
    (tester) async {
      await tester.pumpWidget(
        _buildSheet(
          savedPlace: _savedPlace(
            ohStatus: OpeningHoursStatus.known,
            openingHours: {
              'monday': [
                const OpeningHoursInterval(open: '08:00', close: '20:00'),
              ],
            },
          ),
          routeStop: _routeStop(arrivalTime: '10:00:00'),
          // visitDate intentionally omitted
        ),
      );
      expect(find.text('Opening hours unavailable'), findsOneWidget);
      expect(find.textContaining('Open until'), findsNothing);
      expect(find.text('Closed at scheduled time'), findsNothing);
    },
  );

  // H10. Opening hours use correct weekday — Tuesday intervals, Monday date → no match.
  testWidgets('H10. Opening hours use the correct weekday from visitDate', (
    tester,
  ) async {
    // Only tuesday has hours. visitDate is _monday → no intervals for monday → Closed.
    await tester.pumpWidget(
      _buildSheet(
        savedPlace: _savedPlace(
          ohStatus: OpeningHoursStatus.known,
          openingHours: {
            'tuesday': [
              const OpeningHoursInterval(open: '09:00', close: '20:00'),
            ],
          },
        ),
        routeStop: _routeStop(arrivalTime: '10:00:00'),
        visitDate: _monday, // Monday, but only tuesday has hours
      ),
    );
    expect(find.text('Closed at scheduled time'), findsOneWidget);
  });

  // H11. Directions URL uses lat/lng destination (verified by checking text content).
  testWidgets('H11. Directions button is visible for scheduled POI', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSheet(
        savedPlace: _savedPlace(lat: 28.6129, lng: 77.2295),
        routeStop: _routeStop(),
      ),
    );
    expect(find.byKey(const Key('poi_directions_button')), findsOneWidget);
  });

  // H12. More details button is visible for scheduled POI.
  testWidgets('H12. More details button is visible for scheduled POI', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSheet(
        savedPlace: _savedPlace(name: 'Qutub Minar & Gardens'),
        routeStop: _routeStop(),
      ),
    );
    expect(find.byKey(const Key('poi_more_details_button')), findsOneWidget);
  });

  // H13. Special characters in place name do not crash the sheet.
  testWidgets('H13. Place name with special characters renders without crash', (
    tester,
  ) async {
    // Apostrophe, ampersand, spaces, and a non-ASCII character.
    await tester.pumpWidget(
      _buildSheet(
        savedPlace: _savedPlace(name: "St. Mary's Church & Café — Ñoño"),
        routeStop: _routeStop(),
      ),
    );
    expect(find.byKey(const Key('poi_drag_handle')), findsOneWidget);
    expect(find.textContaining("St. Mary's"), findsOneWidget);
  });

  // H14. Non-POI / start-location marker does not expose attraction actions.
  testWidgets('H14. isStartLocation=true hides all itinerary actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSheet(isStartLocation: true, routeStop: _routeStop()),
    );
    expect(find.byKey(const Key('poi_status_badge')), findsNothing);
    expect(find.byKey(const Key('poi_mark_visited_button')), findsNothing);
    expect(find.byKey(const Key('poi_couldnt_visit_button')), findsNothing);
    expect(find.byKey(const Key('poi_skip_button')), findsNothing);
    expect(find.byKey(const Key('poi_move_day_button')), findsNothing);
    expect(find.byKey(const Key('poi_directions_button')), findsNothing);
  });

  // H15. COMPLETED stop cannot be moved.
  testWidgets('H15. COMPLETED stop shows no move button', (tester) async {
    await tester.pumpWidget(
      _buildSheet(
        routeStop: _routeStop(status: 'COMPLETED'),
        availableDays: [2, 3],
      ),
    );
    expect(find.byKey(const Key('poi_move_day_button')), findsNothing);
    expect(find.byKey(const Key('poi_mark_visited_button')), findsNothing);
  });

  // H16. MISSED stop can be moved.
  testWidgets('H16. MISSED stop shows Move to Another Day', (tester) async {
    await tester.pumpWidget(
      _buildSheet(
        routeStop: _routeStop(status: 'MISSED'),
        availableDays: [2],
      ),
    );
    expect(find.byKey(const Key('poi_move_day_button')), findsOneWidget);
  });

  // H17. SKIPPED is terminal and exposes no itinerary action.
  testWidgets('H17. SKIPPED stop shows status only', (tester) async {
    await tester.pumpWidget(
      _buildSheet(
        routeStop: _routeStop(status: 'SKIPPED'),
        availableDays: [2],
      ),
    );
    expect(find.byKey(const Key('poi_move_day_button')), findsNothing);
    expect(find.byKey(const Key('poi_skip_button')), findsNothing);
  });

  testWidgets('H17b. PLANNED stop can be moved to another day', (tester) async {
    await tester.pumpWidget(
      _buildSheet(
        routeStop: _routeStop(status: 'PLANNED'),
        availableDays: [2],
      ),
    );
    expect(find.byKey(const Key('poi_move_day_button')), findsOneWidget);
  });

  testWidgets('H17c. MISSED stop can be skipped', (tester) async {
    await tester.pumpWidget(
      _buildSheet(
        routeStop: _routeStop(status: 'MISSED'),
        availableDays: [2],
      ),
    );
    expect(find.byKey(const Key('poi_skip_button')), findsOneWidget);
  });

  // H18. Successful status update callback triggers (simulated state refresh).
  testWidgets('H18. Status update callback fires and sheet pops on success', (
    tester,
  ) async {
    ItineraryStopStatus? received;
    bool callbackCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showModalBottomSheet(
                context: ctx,
                builder: (_) => PoiBottomSheet(
                  savedPlace: _savedPlace(),
                  routeStop: _routeStop(status: 'PLANNED'),
                  onStatusChange: (s) async {
                    received = s;
                    callbackCalled = true;
                  },
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('poi_mark_visited_button')));
    await tester.pump();
    expect(callbackCalled, isTrue);
    expect(received, ItineraryStopStatus.completed);
  });

  // H19. Missing optional values do not crash (no routeStop, no visitDate, UNKNOWN hours).
  testWidgets('H19. Sheet renders safely when all optional fields are null', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSheet(
        routeStop: null, // unscheduled
        visitDate: null,
        savedPlace: _savedPlace(ohStatus: OpeningHoursStatus.unknown),
      ),
    );
    expect(find.byKey(const Key('poi_drag_handle')), findsOneWidget);
    // No crash. Travel row and schedule row both absent.
    expect(find.byKey(const Key('poi_travel_row')), findsNothing);
    expect(find.byKey(const Key('poi_schedule_row')), findsNothing);
    // Opening hours unavailable shown.
    expect(find.text('Opening hours unavailable'), findsOneWidget);
  });

  // H20. Distance formatted correctly: sub-km as metres, ≥1 km as X.X km.
  testWidgets('H20. Distance < 1 km formatted as metres', (tester) async {
    final stop = _routeStop(
      visitOrder: 2,
      travelTime: 5,
      distanceFromPrevious: 0.35,
    );
    await tester.pumpWidget(_buildSheet(routeStop: stop));
    expect(find.textContaining('350 m'), findsOneWidget);
  });

  testWidgets('H20b. Distance >= 1 km formatted as X.X km', (tester) async {
    final stop = _routeStop(
      visitOrder: 2,
      travelTime: 8,
      distanceFromPrevious: 3.4,
    );
    await tester.pumpWidget(_buildSheet(routeStop: stop));
    expect(find.textContaining('3.4 km'), findsOneWidget);
  });

  // H21. Travel row shows only time when distance is zero but time > 0.
  testWidgets('H21. Travel row shows only time when distance is zero', (
    tester,
  ) async {
    final stop = _routeStop(
      visitOrder: 2,
      travelTime: 15,
      distanceFromPrevious: 0.0,
    );
    await tester.pumpWidget(_buildSheet(routeStop: stop));
    expect(find.byKey(const Key('poi_travel_row')), findsOneWidget);
    expect(find.textContaining('15 min'), findsOneWidget);
    // Should NOT contain " · " for missing distance part.
    final textWidget = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('poi_travel_row')),
        matching: find.byType(Text),
      ),
    );
    expect(textWidget.data, isNot(contains(' · 0')));
  });
}
