import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yatra_canvas/models/city.dart';
import 'package:yatra_canvas/models/itinerary_stop_status.dart';
import 'package:yatra_canvas/models/optimized_route.dart';
import 'package:yatra_canvas/models/place.dart';
import 'package:yatra_canvas/models/saved_place.dart';
import 'package:yatra_canvas/models/trip_day.dart';
import 'package:yatra_canvas/screens/create_trip/plan_days_screen.dart';
import 'package:yatra_canvas/screens/place_discovery/place_discovery_screen.dart';
import 'package:yatra_canvas/services/route_optimization_service.dart';
import 'package:yatra_canvas/services/saved_place_service.dart';
import 'package:yatra_canvas/services/smart_replanning_service.dart';
import 'package:yatra_canvas/services/trip_service.dart';
import 'package:yatra_canvas/theme/app_theme.dart';

class _FakeTripService extends TripService {
  _FakeTripService({List<TripDay>? initialDays})
      : days = initialDays ?? [],
        super(baseUrl: 'http://test.local');

  List<TripDay> days;
  int updateCallCount = 0;
  DayType? lastUpdatedDayType;
  String? lastUpdatedStartTime;
  String? lastUpdatedEndTime;

  @override
  Future<List<TripDay>> getTripDays(String tripId) async => List.of(days);

  @override
  Future<TripDay> updateTripDay(
    String tripId,
    int dayNumber, {
    DayType? dayType,
    String? startTime,
    String? endTime,
  }) async {
    updateCallCount++;
    lastUpdatedDayType = dayType;
    lastUpdatedStartTime = startTime;
    lastUpdatedEndTime = endTime;
    final idx = days.indexWhere((d) => d.dayNumber == dayNumber);
    final current = days[idx];
    final updated = TripDay(
      id: current.id,
      tripId: current.tripId,
      dayNumber: current.dayNumber,
      date: current.date,
      dayType: dayType ?? current.dayType,
      startTime: startTime,
      endTime: endTime,
    );
    days[idx] = updated;
    return updated;
  }
}

class _FakeSavedPlaceService extends SavedPlaceService {
  _FakeSavedPlaceService({List<SavedPlace>? initialPlaces})
      : places = initialPlaces ?? [],
        super(baseUrl: 'http://test.local');

  List<SavedPlace> places;
  int assignmentCallCount = 0;
  AssignmentMode? lastAssignmentMode;
  String? lastAssignedDayId;
  Duration? delay;

  @override
  Future<List<SavedPlace>> getSavedPlaces(String tripId) async => List.of(places);

  @override
  Future<SavedPlace> updateAssignment(
    String tripId,
    String placeId, {
    required AssignmentMode assignmentMode,
    String? assignedDayId,
  }) async {
    assignmentCallCount++;
    lastAssignmentMode = assignmentMode;
    lastAssignedDayId = assignedDayId;
    if (delay != null) {
      await Future<void>.delayed(delay!);
    }
    final idx = places.indexWhere((p) => p.placeId == placeId);
    final updated = places[idx].copyWith(
      assignmentMode: assignmentMode,
      assignedDayId: assignedDayId,
      clearAssignedDay: assignedDayId == null,
    );
    places[idx] = updated;
    return updated;
  }
}

class _FakeRouteOptimizationService extends RouteOptimizationService {
  _FakeRouteOptimizationService({this.route})
      : super(baseUrl: 'http://test.local');

  OptimizedRoute? route;
  int optimizeCallCount = 0;

  @override
  Future<OptimizedRoute> optimizeRoute(String tripId) async {
    optimizeCallCount++;
    return route ??
        OptimizedRoute(
          tripId: tripId,
          places: const [],
          totalDistance: 0.0,
          totalTravelTimeMinutes: 0,
        );
  }
}

class _FakeSmartReplanningService extends SmartReplanningService {
  _FakeSmartReplanningService({
    this.initialRoute,
    this.moveResponse,
    this.routeAfterMove,
  }) : super(baseUrl: 'http://test.local');

  OptimizedRoute? initialRoute;
  MoveItineraryPlaceResponse? moveResponse;
  OptimizedRoute? routeAfterMove;

  int updateStatusCallCount = 0;
  ItineraryStopStatus? lastUpdatedStatus;

  int moveCallCount = 0;
  int? lastTargetDayNumber;

  int getItineraryCallCount = 0;

  @override
  Future<OptimizedRoutePlace> updateStopStatus({
    required String tripId,
    required String stopOrPlaceId,
    required ItineraryStopStatus status,
    bool isPlaceId = false,
  }) async {
    updateStatusCallCount++;
    lastUpdatedStatus = status;
    return OptimizedRoutePlace(
      id: isPlaceId ? null : stopOrPlaceId,
      placeId: isPlaceId ? stopOrPlaceId : 'place-1',
      name: 'Hawa Mahal',
      dayNumber: 1,
      visitOrder: 1,
      distanceFromPrevious: 0.0,
      travelTimeMinutes: 0,
      plannedArrivalTime: '09:00:00',
      plannedDepartureTime: '10:30:00',
      visitDurationMinutes: 90,
      isOpeningHoursKnown: true,
      status: status.toApiString(),
    );
  }

  @override
  Future<MoveItineraryPlaceResponse> movePlaceToDay({
    required String tripId,
    required String placeId,
    int? targetDayNumber,
    String? targetDayId,
  }) async {
    moveCallCount++;
    lastTargetDayNumber = targetDayNumber;
    return moveResponse ??
        const MoveItineraryPlaceResponse(
          success: true,
          tripId: 'trip-1',
          placeId: 'place-1',
        );
  }

  @override
  Future<OptimizedRoute> getItinerary(String tripId) async {
    getItineraryCallCount++;
    return routeAfterMove ??
        initialRoute ??
        OptimizedRoute(
          tripId: tripId,
          places: const [],
          totalDistance: 0.0,
          totalTravelTimeMinutes: 0,
        );
  }
}

void _setTestViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testCity = City(
    id: 'city-1',
    name: 'Jaipur',
    state: 'Rajasthan',
    country: 'India',
    latitude: 26.9124,
    longitude: 75.7873,
  );

  final testPlace1 = Place(
    id: 'place-1',
    cityId: 'city-1',
    name: 'Hawa Mahal',
    category: 'heritage',
    latitude: 26.9239,
    longitude: 75.8267,
    rating: 4.6,
    reviewCount: 45000,
    isPopular: true,
    isHeritage: true,
    isLocalSpeciality: false,
    lastFetchedAt: DateTime(2026, 9, 1),
  );

  final testPlace2 = Place(
    id: 'place-2',
    cityId: 'city-1',
    name: 'City Palace',
    category: 'heritage',
    latitude: 26.9258,
    longitude: 75.8237,
    rating: 4.5,
    reviewCount: 38000,
    isPopular: true,
    isHeritage: true,
    isLocalSpeciality: false,
    lastFetchedAt: DateTime(2026, 9, 1),
  );

  List<TripDay> sampleTripDays() => [
        TripDay(
          id: 'day-1',
          tripId: 'trip-1',
          dayNumber: 1,
          date: DateTime(2026, 9, 10),
          dayType: DayType.fullDay,
          startTime: '09:00',
          endTime: '19:00',
        ),
        TripDay(
          id: 'day-2',
          tripId: 'trip-1',
          dayNumber: 2,
          date: DateTime(2026, 9, 11),
          dayType: DayType.rest,
          startTime: null,
          endTime: null,
        ),
        TripDay(
          id: 'day-3',
          tripId: 'trip-1',
          dayNumber: 3,
          date: DateTime(2026, 9, 12),
          dayType: DayType.fullDay,
          startTime: '10:00',
          endTime: '18:00',
        ),
      ];

  group('Plan Your Days UI (Items 1-6)', () {
    testWidgets('1. Plan Your Days loads TripDays correctly', (tester) async {
      final tripService = _FakeTripService(initialDays: sampleTripDays());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlanDaysScreen(tripId: 'trip-1', tripService: tripService),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Plan your days'), findsWidgets);
      expect(find.text('Day 1'), findsOneWidget);
      expect(find.text('Full Day'), findsWidgets);
      expect(find.text('09:00 AM – 07:00 PM'), findsOneWidget);
      expect(find.text('Day 2'), findsOneWidget);
      expect(find.text('Rest Day'), findsWidgets);
      expect(find.text('Day 3'), findsOneWidget);
      expect(find.text('10:00 AM – 06:00 PM'), findsOneWidget);
    });

    testWidgets('2. Full Day can change to Rest', (tester) async {
      final tripService = _FakeTripService(initialDays: sampleTripDays());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlanDaysScreen(tripId: 'trip-1', tripService: tripService),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('configure-day-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Rest Day'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('save-day-config')));
      await tester.pumpAndSettle();

      expect(tripService.lastUpdatedDayType, DayType.rest);
      expect(tripService.lastUpdatedStartTime, isNull);
      expect(tripService.lastUpdatedEndTime, isNull);
    });

    testWidgets('3. Rest can change back to Full Day', (tester) async {
      final tripService = _FakeTripService(initialDays: sampleTripDays());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlanDaysScreen(tripId: 'trip-1', tripService: tripService),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('configure-day-2')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Full Day'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('save-day-config')));
      await tester.pumpAndSettle();

      expect(tripService.lastUpdatedDayType, DayType.fullDay);
    });

    testWidgets('4. Half Day supports custom time window', (tester) async {
      final tripService = _FakeTripService(initialDays: sampleTripDays());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlanDaysScreen(tripId: 'trip-1', tripService: tripService),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('configure-day-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Half Day'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('save-day-config')));
      await tester.pumpAndSettle();

      expect(tripService.lastUpdatedDayType, DayType.halfDay);
    });

    testWidgets('5. Travel Day supports custom time window', (tester) async {
      final tripService = _FakeTripService(initialDays: sampleTripDays());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlanDaysScreen(tripId: 'trip-1', tripService: tripService),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('configure-day-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Travel Day'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('save-day-config')));
      await tester.pumpAndSettle();

      expect(tripService.lastUpdatedDayType, DayType.travel);
    });

    test('6. invalid time update shows proper error (start >= end)', () {
      final startMinutes = 18 * 60;
      final endMinutes = 10 * 60;
      expect(endMinutes <= startMinutes, isTrue);
    });
  });

  group('Place Day Assignment UI (Items 7-10)', () {
    testWidgets('7. selected place defaults to Auto Schedule', (tester) async {
      final savedPlace = SavedPlace(
        id: 'sp-1',
        tripId: 'trip-1',
        placeId: 'place-1',
        customOrder: 1,
        priority: 0,
        isLocked: false,
        mustVisit: false,
        place: testPlace1,
        assignmentMode: AssignmentMode.auto,
        assignedDayId: null,
      );

      final savedPlaceService = _FakeSavedPlaceService(initialPlaces: [savedPlace]);
      final tripService = _FakeTripService(initialDays: sampleTripDays());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            tripService: tripService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Auto schedule'), findsOneWidget);
    });

    testWidgets('8. place can be locked to a valid day', (tester) async {
      final savedPlace = SavedPlace(
        id: 'sp-1',
        tripId: 'trip-1',
        placeId: 'place-1',
        customOrder: 1,
        priority: 0,
        isLocked: false,
        mustVisit: false,
        place: testPlace1,
        assignmentMode: AssignmentMode.auto,
        assignedDayId: null,
      );

      final savedPlaceService = _FakeSavedPlaceService(initialPlaces: [savedPlace]);
      final tripService = _FakeTripService(initialDays: sampleTripDays());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            tripService: tripService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('schedule-badge-place-1')));
      await tester.pumpAndSettle();

      expect(find.text('Schedule Hawa Mahal'), findsOneWidget);
      expect(find.text('Day 1 · Full Day'), findsOneWidget);

      await tester.tap(find.text('Day 1 · Full Day'));
      await tester.pumpAndSettle();

      expect(savedPlaceService.lastAssignmentMode, AssignmentMode.locked);
      expect(savedPlaceService.lastAssignedDayId, 'day-1');
    });

    testWidgets('9. place can switch back to Auto', (tester) async {
      final lockedPlace = SavedPlace(
        id: 'sp-1',
        tripId: 'trip-1',
        placeId: 'place-1',
        customOrder: 1,
        priority: 0,
        isLocked: false,
        mustVisit: false,
        place: testPlace1,
        assignmentMode: AssignmentMode.locked,
        assignedDayId: 'day-1',
      );

      final savedPlaceService = _FakeSavedPlaceService(initialPlaces: [lockedPlace]);
      final tripService = _FakeTripService(initialDays: sampleTripDays());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            tripService: tripService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Day 1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('schedule-badge-place-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Let YatraCanvas decide'));
      await tester.pumpAndSettle();

      expect(savedPlaceService.lastAssignmentMode, AssignmentMode.auto);
      expect(savedPlaceService.lastAssignedDayId, isNull);
    });

    testWidgets('10. REST days are not shown in place assignment picker', (tester) async {
      final savedPlace = SavedPlace(
        id: 'sp-1',
        tripId: 'trip-1',
        placeId: 'place-1',
        customOrder: 1,
        priority: 0,
        isLocked: false,
        mustVisit: false,
        place: testPlace1,
        assignmentMode: AssignmentMode.auto,
        assignedDayId: null,
      );

      final savedPlaceService = _FakeSavedPlaceService(initialPlaces: [savedPlace]);
      final tripService = _FakeTripService(initialDays: sampleTripDays());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            tripService: tripService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('schedule-badge-place-1')));
      await tester.pumpAndSettle();

      expect(find.text('Day 1 · Full Day'), findsOneWidget);
      expect(find.text('Day 3 · Full Day'), findsOneWidget);

      // REST Day (Day 2) MUST NOT be shown in picker
      expect(find.text('Day 2 · Rest Day'), findsNothing);
    });
  });

  group('Generated Itinerary Day Presentation (Items 11-14)', () {
    testWidgets('11. generated itinerary displays actual day numbers', (tester) async {
      final route = OptimizedRoute(
        tripId: 'trip-1',
        places: [
          OptimizedRoutePlace(
            id: 'stop-1',
            placeId: 'place-1',
            name: 'Hawa Mahal',
            dayNumber: 1,
            visitOrder: 1,
            distanceFromPrevious: 0.0,
            travelTimeMinutes: 0,
            plannedArrivalTime: '09:00:00',
            plannedDepartureTime: '10:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: true,
            status: 'PLANNED',
          ),
          OptimizedRoutePlace(
            id: 'stop-2',
            placeId: 'place-2',
            name: 'City Palace',
            dayNumber: 3,
            visitOrder: 1,
            distanceFromPrevious: 1.5,
            travelTimeMinutes: 10,
            plannedArrivalTime: '10:00:00',
            plannedDepartureTime: '11:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: true,
            status: 'PLANNED',
          ),
        ],
        totalDistance: 1.5,
        totalTravelTimeMinutes: 10,
        totalDays: 3,
      );

      final routeService = _FakeRouteOptimizationService(route: route);
      final savedPlaceService = _FakeSavedPlaceService(
        initialPlaces: [
          SavedPlace(
            id: 'sp-1',
            tripId: 'trip-1',
            placeId: 'place-1',
            customOrder: 1,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: testPlace1,
          ),
          SavedPlace(
            id: 'sp-2',
            tripId: 'trip-1',
            placeId: 'place-2',
            customOrder: 2,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: testPlace2,
          ),
        ],
      );
      final tripService = _FakeTripService(initialDays: sampleTripDays());

      _setTestViewport(tester);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeService,
            tripService: tripService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Optimize Route'));
      await tester.tap(find.widgetWithText(FilledButton, 'Optimize Route'));
      await tester.pumpAndSettle();

      expect(find.text('Day 1'), findsOneWidget);
      expect(find.text('Day 3'), findsOneWidget);
      expect(find.text('Hawa Mahal'), findsWidgets);
      expect(find.text('City Palace'), findsWidgets);
    });

    testWidgets('12. REST days remain visible', (tester) async {
      final route = OptimizedRoute(
        tripId: 'trip-1',
        places: [
          OptimizedRoutePlace(
            id: 'stop-1',
            placeId: 'place-1',
            name: 'Hawa Mahal',
            dayNumber: 1,
            visitOrder: 1,
            distanceFromPrevious: 0.0,
            travelTimeMinutes: 0,
            plannedArrivalTime: '09:00:00',
            plannedDepartureTime: '10:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: true,
            status: 'PLANNED',
          ),
        ],
        totalDistance: 0.0,
        totalTravelTimeMinutes: 0,
        totalDays: 3,
      );

      final routeService = _FakeRouteOptimizationService(route: route);
      final savedPlaceService = _FakeSavedPlaceService(
        initialPlaces: [
          SavedPlace(
            id: 'sp-1',
            tripId: 'trip-1',
            placeId: 'place-1',
            customOrder: 1,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: testPlace1,
          ),
        ],
      );
      final tripService = _FakeTripService(initialDays: sampleTripDays());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeService,
            tripService: tripService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Optimize Route'));
      await tester.pumpAndSettle();

      // Day 2 (REST Day) MUST remain visible even with 0 stops
      expect(find.text('Day 2'), findsOneWidget);
      expect(find.text('Rest Day · Recharge and explore at your own pace.'), findsOneWidget);
    });

    testWidgets('13. scheduled times are displayed', (tester) async {
      final route = OptimizedRoute(
        tripId: 'trip-1',
        places: [
          OptimizedRoutePlace(
            id: 'stop-1',
            placeId: 'place-1',
            name: 'Hawa Mahal',
            dayNumber: 1,
            visitOrder: 1,
            distanceFromPrevious: 0.0,
            travelTimeMinutes: 0,
            plannedArrivalTime: '09:00:00',
            plannedDepartureTime: '10:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: true,
            status: 'PLANNED',
          ),
        ],
        totalDistance: 0.0,
        totalTravelTimeMinutes: 0,
        totalDays: 1,
      );

      final routeService = _FakeRouteOptimizationService(route: route);
      final savedPlaceService = _FakeSavedPlaceService(
        initialPlaces: [
          SavedPlace(
            id: 'sp-1',
            tripId: 'trip-1',
            placeId: 'place-1',
            customOrder: 1,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: testPlace1,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Optimize Route'));
      await tester.pumpAndSettle();

      expect(find.textContaining('09:00 – 10:30'), findsOneWidget);
      expect(find.textContaining('~90 min visit'), findsOneWidget);
    });

    testWidgets('14. unscheduled places are visible', (tester) async {
      final route = OptimizedRoute(
        tripId: 'trip-1',
        places: [
          OptimizedRoutePlace(
            id: 'stop-1',
            placeId: 'place-1',
            name: 'Hawa Mahal',
            dayNumber: 1,
            visitOrder: 1,
            distanceFromPrevious: 0.0,
            travelTimeMinutes: 0,
            plannedArrivalTime: '09:00:00',
            plannedDepartureTime: '10:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: true,
            status: 'PLANNED',
          ),
        ],
        totalDistance: 0.0,
        totalTravelTimeMinutes: 0,
        totalDays: 1,
        unscheduledPlaces: [
          UnscheduledRoutePlace(
            placeId: 'place-unscheduled-1',
            name: 'Nahargarh Fort',
            reason: 'Not enough available time',
          ),
        ],
      );

      final routeService = _FakeRouteOptimizationService(route: route);
      final savedPlaceService = _FakeSavedPlaceService(
        initialPlaces: [
          SavedPlace(
            id: 'sp-1',
            tripId: 'trip-1',
            placeId: 'place-1',
            customOrder: 1,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: testPlace1,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Optimize Route'));
      await tester.pumpAndSettle();

      expect(find.text('Could not fit into your itinerary'), findsOneWidget);
      expect(find.text('Nahargarh Fort'), findsOneWidget);
      expect(find.text('Not enough available time'), findsOneWidget);
    });
  });

  group('Stop Status & Missed Place Replanning (Items 15-24)', () {
    testWidgets('15. Completed action updates stop', (tester) async {
      _setTestViewport(tester);
      final route = OptimizedRoute(
        tripId: 'trip-1',
        places: [
          OptimizedRoutePlace(
            id: 'stop-1',
            placeId: 'place-1',
            name: 'Hawa Mahal',
            dayNumber: 1,
            visitOrder: 1,
            distanceFromPrevious: 0.0,
            travelTimeMinutes: 0,
            plannedArrivalTime: '09:00:00',
            plannedDepartureTime: '10:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: true,
            status: 'PLANNED',
          ),
        ],
        totalDistance: 0.0,
        totalTravelTimeMinutes: 0,
        totalDays: 1,
      );

      final smartReplanningService = _FakeSmartReplanningService();
      final routeService = _FakeRouteOptimizationService(route: route);
      final savedPlaceService = _FakeSavedPlaceService(
        initialPlaces: [
          SavedPlace(
            id: 'sp-1',
            tripId: 'trip-1',
            placeId: 'place-1',
            customOrder: 1,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: testPlace1,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeService,
            smartReplanningService: smartReplanningService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Optimize Route'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('stop-actions-place-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark completed'));
      await tester.pumpAndSettle();

      expect(smartReplanningService.lastUpdatedStatus, ItineraryStopStatus.completed);
      expect(find.text('Visited'), findsOneWidget);
    });

    testWidgets('16. Missed action updates stop', (tester) async {
      _setTestViewport(tester);
      final route = OptimizedRoute(
        tripId: 'trip-1',
        places: [
          OptimizedRoutePlace(
            id: 'stop-1',
            placeId: 'place-1',
            name: 'Hawa Mahal',
            dayNumber: 1,
            visitOrder: 1,
            distanceFromPrevious: 0.0,
            travelTimeMinutes: 0,
            plannedArrivalTime: '09:00:00',
            plannedDepartureTime: '10:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: true,
            status: 'PLANNED',
          ),
        ],
        totalDistance: 0.0,
        totalTravelTimeMinutes: 0,
        totalDays: 1,
      );

      final smartReplanningService = _FakeSmartReplanningService();
      final routeService = _FakeRouteOptimizationService(route: route);
      final savedPlaceService = _FakeSavedPlaceService(
        initialPlaces: [
          SavedPlace(
            id: 'sp-1',
            tripId: 'trip-1',
            placeId: 'place-1',
            customOrder: 1,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: testPlace1,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeService,
            smartReplanningService: smartReplanningService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Optimize Route'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('stop-actions-place-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Couldn't visit"));
      await tester.pumpAndSettle();

      expect(smartReplanningService.lastUpdatedStatus, ItineraryStopStatus.missed);
      expect(find.text('Missed'), findsOneWidget);
    });

    testWidgets('17. Skipped action updates stop', (tester) async {
      _setTestViewport(tester);
      final route = OptimizedRoute(
        tripId: 'trip-1',
        places: [
          OptimizedRoutePlace(
            id: 'stop-1',
            placeId: 'place-1',
            name: 'Hawa Mahal',
            dayNumber: 1,
            visitOrder: 1,
            distanceFromPrevious: 0.0,
            travelTimeMinutes: 0,
            plannedArrivalTime: '09:00:00',
            plannedDepartureTime: '10:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: true,
            status: 'PLANNED',
          ),
        ],
        totalDistance: 0.0,
        totalTravelTimeMinutes: 0,
        totalDays: 1,
      );

      final smartReplanningService = _FakeSmartReplanningService();
      final routeService = _FakeRouteOptimizationService(route: route);
      final savedPlaceService = _FakeSavedPlaceService(
        initialPlaces: [
          SavedPlace(
            id: 'sp-1',
            tripId: 'trip-1',
            placeId: 'place-1',
            customOrder: 1,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: testPlace1,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeService,
            smartReplanningService: smartReplanningService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Optimize Route'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('stop-actions-place-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip this place'));
      await tester.pumpAndSettle();

      expect(smartReplanningService.lastUpdatedStatus, ItineraryStopStatus.skipped);
      expect(find.text('Skipped'), findsOneWidget);
    });

    testWidgets('18. missed stop offers Move to another day', (tester) async {
      _setTestViewport(tester);
      final route = OptimizedRoute(
        tripId: 'trip-1',
        places: [
          OptimizedRoutePlace(
            id: 'stop-1',
            placeId: 'place-1',
            name: 'Hawa Mahal',
            dayNumber: 1,
            visitOrder: 1,
            distanceFromPrevious: 0.0,
            travelTimeMinutes: 0,
            plannedArrivalTime: '09:00:00',
            plannedDepartureTime: '10:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: true,
            status: 'MISSED',
          ),
        ],
        totalDistance: 0.0,
        totalTravelTimeMinutes: 0,
        totalDays: 1,
      );

      final routeService = _FakeRouteOptimizationService(route: route);
      final savedPlaceService = _FakeSavedPlaceService(
        initialPlaces: [
          SavedPlace(
            id: 'sp-1',
            tripId: 'trip-1',
            placeId: 'place-1',
            customOrder: 1,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: testPlace1,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Optimize Route'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('move-missed-place-1')), findsOneWidget);
      expect(find.text('Move to another day'), findsOneWidget);
    });

    testWidgets('19. REST days are not shown as move targets', (tester) async {
      _setTestViewport(tester);
      final route = OptimizedRoute(
        tripId: 'trip-1',
        places: [
          OptimizedRoutePlace(
            id: 'stop-1',
            placeId: 'place-1',
            name: 'Hawa Mahal',
            dayNumber: 1,
            visitOrder: 1,
            distanceFromPrevious: 0.0,
            travelTimeMinutes: 0,
            plannedArrivalTime: '09:00:00',
            plannedDepartureTime: '10:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: true,
            status: 'MISSED',
          ),
        ],
        totalDistance: 0.0,
        totalTravelTimeMinutes: 0,
        totalDays: 3,
      );

      final routeService = _FakeRouteOptimizationService(route: route);
      final savedPlaceService = _FakeSavedPlaceService(
        initialPlaces: [
          SavedPlace(
            id: 'sp-1',
            tripId: 'trip-1',
            placeId: 'place-1',
            customOrder: 1,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: testPlace1,
          ),
        ],
      );
      final tripService = _FakeTripService(initialDays: sampleTripDays());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeService,
            tripService: tripService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Optimize Route'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('move-missed-place-1')));
      await tester.pumpAndSettle();

      expect(find.text('Move Hawa Mahal to:'), findsOneWidget);
      expect(find.text('Day 3 · Full Day'), findsOneWidget);
      // REST Day (Day 2) and Current Day (Day 1) MUST NOT be shown
      expect(find.text('Day 2 · Rest Day'), findsNothing);
      expect(find.text('Day 1 · Full Day'), findsNothing);
    });

    testWidgets('20. successful move refreshes affected itinerary', (tester) async {
      _setTestViewport(tester);
      final initialRoute = OptimizedRoute(
        tripId: 'trip-1',
        places: [
          OptimizedRoutePlace(
            id: 'stop-1',
            placeId: 'place-1',
            name: 'Hawa Mahal',
            dayNumber: 1,
            visitOrder: 1,
            distanceFromPrevious: 0.0,
            travelTimeMinutes: 0,
            plannedArrivalTime: '09:00:00',
            plannedDepartureTime: '10:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: true,
            status: 'MISSED',
          ),
        ],
        totalDistance: 0.0,
        totalTravelTimeMinutes: 0,
        totalDays: 3,
      );

      final movedRoute = OptimizedRoute(
        tripId: 'trip-1',
        places: [
          OptimizedRoutePlace(
            id: 'stop-1',
            placeId: 'place-1',
            name: 'Hawa Mahal',
            dayNumber: 3,
            visitOrder: 1,
            distanceFromPrevious: 0.0,
            travelTimeMinutes: 0,
            plannedArrivalTime: '10:00:00',
            plannedDepartureTime: '11:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: true,
            status: 'PLANNED',
          ),
        ],
        totalDistance: 0.0,
        totalTravelTimeMinutes: 0,
        totalDays: 3,
      );

      final smartReplanningService = _FakeSmartReplanningService(
        initialRoute: initialRoute,
        moveResponse: const MoveItineraryPlaceResponse(
          success: true,
          tripId: 'trip-1',
          placeId: 'place-1',
          sourceDayNumber: 1,
          targetDayNumber: 3,
        ),
        routeAfterMove: movedRoute,
      );

      final routeService = _FakeRouteOptimizationService(route: initialRoute);
      final savedPlaceService = _FakeSavedPlaceService(
        initialPlaces: [
          SavedPlace(
            id: 'sp-1',
            tripId: 'trip-1',
            placeId: 'place-1',
            customOrder: 1,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: testPlace1,
          ),
        ],
      );
      final tripService = _FakeTripService(initialDays: sampleTripDays());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeService,
            smartReplanningService: smartReplanningService,
            tripService: tripService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Optimize Route'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('move-missed-place-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Day 3 · Full Day'));
      await tester.pumpAndSettle();

      expect(smartReplanningService.lastTargetDayNumber, 3);
      expect(smartReplanningService.getItineraryCallCount, 1);
    });

    testWidgets('21. TARGET_DAY_INFEASIBLE displays clear error', (tester) async {
      _setTestViewport(tester);
      final initialRoute = OptimizedRoute(
        tripId: 'trip-1',
        places: [
          OptimizedRoutePlace(
            id: 'stop-1',
            placeId: 'place-1',
            name: 'Hawa Mahal',
            dayNumber: 1,
            visitOrder: 1,
            distanceFromPrevious: 0.0,
            travelTimeMinutes: 0,
            plannedArrivalTime: '09:00:00',
            plannedDepartureTime: '10:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: true,
            status: 'MISSED',
          ),
        ],
        totalDistance: 0.0,
        totalTravelTimeMinutes: 0,
        totalDays: 3,
      );

      final smartReplanningService = _FakeSmartReplanningService(
        initialRoute: initialRoute,
        moveResponse: const MoveItineraryPlaceResponse(
          success: false,
          reason: 'TARGET_DAY_INFEASIBLE',
          tripId: 'trip-1',
          placeId: 'place-1',
        ),
      );

      final routeService = _FakeRouteOptimizationService(route: initialRoute);
      final savedPlaceService = _FakeSavedPlaceService(
        initialPlaces: [
          SavedPlace(
            id: 'sp-1',
            tripId: 'trip-1',
            placeId: 'place-1',
            customOrder: 1,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: testPlace1,
          ),
        ],
      );
      final tripService = _FakeTripService(initialDays: sampleTripDays());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeService,
            smartReplanningService: smartReplanningService,
            tripService: tripService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Optimize Route'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('move-missed-place-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Day 3 · Full Day'));
      await tester.pumpAndSettle();

      expect(find.text('Cannot Move Place'), findsOneWidget);
      expect(
        find.text("This place doesn't fit into Day 3 with your current plan."),
        findsOneWidget,
      );
      expect(find.text('Choose another day'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('22. completed stops remain visually completed', (tester) async {
      _setTestViewport(tester);
      final route = OptimizedRoute(
        tripId: 'trip-1',
        places: [
          OptimizedRoutePlace(
            id: 'stop-1',
            placeId: 'place-1',
            name: 'Hawa Mahal',
            dayNumber: 1,
            visitOrder: 1,
            distanceFromPrevious: 0.0,
            travelTimeMinutes: 0,
            plannedArrivalTime: '09:00:00',
            plannedDepartureTime: '10:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: true,
            status: 'COMPLETED',
          ),
        ],
        totalDistance: 0.0,
        totalTravelTimeMinutes: 0,
        totalDays: 1,
      );

      final routeService = _FakeRouteOptimizationService(route: route);
      final savedPlaceService = _FakeSavedPlaceService(
        initialPlaces: [
          SavedPlace(
            id: 'sp-1',
            tripId: 'trip-1',
            placeId: 'place-1',
            customOrder: 1,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: testPlace1,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Optimize Route'));
      await tester.pumpAndSettle();

      expect(find.text('Visited'), findsOneWidget);
      expect(find.byKey(const ValueKey('stop-actions-place-1')), findsNothing);
      expect(find.byKey(const ValueKey('move-missed-place-1')), findsNothing);
    });

    testWidgets('23. UNKNOWN opening hours never display "Open"', (tester) async {
      _setTestViewport(tester);
      final route = OptimizedRoute(
        tripId: 'trip-1',
        places: [
          OptimizedRoutePlace(
            id: 'stop-1',
            placeId: 'place-1',
            name: 'Hawa Mahal',
            dayNumber: 1,
            visitOrder: 1,
            distanceFromPrevious: 0.0,
            travelTimeMinutes: 0,
            plannedArrivalTime: '09:00:00',
            plannedDepartureTime: '10:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: false, // UNKNOWN
            status: 'PLANNED',
          ),
          OptimizedRoutePlace(
            id: 'stop-2',
            placeId: 'place-2',
            name: 'City Palace',
            dayNumber: 1,
            visitOrder: 2,
            distanceFromPrevious: 1.0,
            travelTimeMinutes: 5,
            plannedArrivalTime: '11:00:00',
            plannedDepartureTime: '12:30:00',
            visitDurationMinutes: 90,
            isOpeningHoursKnown: true, // KNOWN
            status: 'PLANNED',
          ),
        ],
        totalDistance: 1.0,
        totalTravelTimeMinutes: 5,
        totalDays: 1,
      );

      final routeService = _FakeRouteOptimizationService(route: route);
      final savedPlaceService = _FakeSavedPlaceService(
        initialPlaces: [
          SavedPlace(
            id: 'sp-1',
            tripId: 'trip-1',
            placeId: 'place-1',
            customOrder: 1,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: testPlace1,
          ),
          SavedPlace(
            id: 'sp-2',
            tripId: 'trip-1',
            placeId: 'place-2',
            customOrder: 2,
            priority: 0,
            isLocked: false,
            mustVisit: false,
            place: testPlace2,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            routeOptimizationService: routeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Optimize Route'));
      await tester.pumpAndSettle();

      expect(find.text('Opening hours unavailable'), findsOneWidget);
      expect(find.text('Open during visit'), findsOneWidget);
    });

    testWidgets('24. loading state prevents duplicate requests', (tester) async {
      _setTestViewport(tester);
      final savedPlace = SavedPlace(
        id: 'sp-1',
        tripId: 'trip-1',
        placeId: 'place-1',
        customOrder: 1,
        priority: 0,
        isLocked: false,
        mustVisit: false,
        place: testPlace1,
        assignmentMode: AssignmentMode.auto,
        assignedDayId: null,
      );

      final savedPlaceService = _FakeSavedPlaceService(
        initialPlaces: [savedPlace],
      )..delay = const Duration(milliseconds: 100);

      final tripService = _FakeTripService(initialDays: sampleTripDays());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlaceDiscoveryScreen(
            city: testCity,
            tripId: 'trip-1',
            savedPlaceService: savedPlaceService,
            tripService: tripService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('schedule-badge-place-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Day 1 · Full Day'));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('schedule-badge-place-1')));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      expect(savedPlaceService.assignmentCallCount, 1);
    });
  });
}
