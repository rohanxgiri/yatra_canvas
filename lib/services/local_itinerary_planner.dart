import 'dart:math' as math;

import 'city_pack_repository.dart';

/// Bounded local scheduling using packaged durations, coordinates and TripDays.
/// Road travel is estimated, and the backend OR-Tools solver stays the online path.
class LocalItineraryPlanner {
  /// A route overview joins scheduled coordinates in visit order. These lines
  /// describe an itinerary, not a road path or turn-by-turn directions.
  static Map<String, dynamic> geometry(
    Map<String, dynamic> state, {
    Map<String, dynamic>? route,
  }) {
    final trip = state['trip'] as Map;
    final stops =
        ((route ?? state['route'])?['optimized_places'] as List? ?? [])
            .cast<Map>();
    final saved = (state['saved'] as List).cast<Map>();
    final origin = <double>[
      (trip['start_latitude'] ??
              trip['arrival_latitude'] ??
              trip['city']['latitude'] as num)
          .toDouble(),
      (trip['start_longitude'] ??
              trip['arrival_longitude'] ??
              trip['city']['longitude'] as num)
          .toDouble(),
    ];
    final days = <Map<String, dynamic>>[];
    for (final number
        in stops.map((s) => s['day_number'] as int).toSet().toList()..sort()) {
      final ordered =
          stops
              .where(
                (s) => s['day_number'] == number && s['status'] != 'SKIPPED',
              )
              .toList()
            ..sort(
              (a, b) =>
                  (a['visit_order'] as int).compareTo(b['visit_order'] as int),
            );
      final coordinates = <List<double>>[origin];
      for (final stop in ordered) {
        final place = saved
            .where((s) => s['place_id'] == stop['place_id'])
            .firstOrNull?['place'];
        if (place != null) {
          coordinates.add([
            (place['latitude'] as num).toDouble(),
            (place['longitude'] as num).toDouble(),
          ]);
        }
      }
      if (coordinates.length > 1) {
        days.add({'day_number': number, 'coordinates': coordinates});
      }
    }
    return {
      'trip_id': trip['trip_id'],
      'geometry_kind': 'offline_overview',
      'days': days,
    };
  }

  static int minute(String? time, int fallback) {
    final parts = time?.split(':');
    if (parts == null || parts.length < 2) return fallback;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  static String clock(int value) =>
      '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';

  static Map<String, dynamic> plan(
    Map<String, dynamic> state, {
    Set<int>? affectedDays,
  }) {
    final trip = state['trip'] as Map<String, dynamic>;
    final days = (state['days'] as List).cast<Map<String, dynamic>>();
    final saved = (state['saved'] as List).cast<Map<String, dynamic>>();
    if (saved.length > 50) {
      throw const FormatException('Choose at most 50 places');
    }
    final old = (state['route']?['optimized_places'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final route = <Map<String, dynamic>>[];
    final breaks = <Map<String, dynamic>>[];
    final conflicts = <String>[
      'Travel uses approximate local coordinate estimates.',
    ];
    final unscheduled = <Map<String, dynamic>>[];
    if (affectedDays != null) {
      route.addAll(old.where((p) => !affectedDays.contains(p['day_number'])));
    }
    // Execution history is immutable during reoptimization.
    route.addAll(
      old.where(
        (p) =>
            (affectedDays == null || affectedDays.contains(p['day_number'])) &&
            ['COMPLETED', 'SKIPPED', 'MISSED'].contains(p['status']),
      ),
    );
    final used = route.map((p) => p['place_id']).toSet();
    final candidates =
        saved.where((s) => !used.contains(s['place_id'])).toList()..sort((
          a,
          b,
        ) {
          int importance(Map<String, dynamic> s) =>
              (s['assignment_mode'] == 'LOCKED' ? 10000 : 0) +
              (s['must_visit'] == true ? 1000 : 0) +
              (s['priority'] as int? ?? 0) * 100;
          final rank = importance(b).compareTo(importance(a));
          return rank != 0
              ? rank
              : (a['custom_order'] as int).compareTo(b['custom_order'] as int);
        });
    final schedules = <int, List<Map<String, dynamic>>>{};
    final endTimes = <int, int>{};
    final cursors = <int, int>{};
    final origins = <int, List<double>>{};
    for (final day in days) {
      final number = day['day_number'] as int;
      if (affectedDays != null && !affectedDays.contains(number) ||
          day['day_type'] == 'REST') {
        continue;
      }
      final start = minute(day['start_time'] as String?, 540),
          end = minute(day['end_time'] as String?, 1140);
      if (end <= start) continue;
      schedules[number] = route
          .where((s) => s['day_number'] == number)
          .toList();
      endTimes[number] = end;
      cursors[number] = start;
      origins[number] = [
        (trip['start_latitude'] ??
                trip['arrival_latitude'] ??
                trip['city']['latitude'] as num)
            .toDouble(),
        (trip['start_longitude'] ??
                trip['arrival_longitude'] ??
                trip['city']['longitude'] as num)
            .toDouble(),
      ];
      final completed = schedules[number]!
          .where((p) => p['status'] == 'COMPLETED')
          .toList();
      if (completed.isNotEmpty) {
        completed.sort(
          (a, b) =>
              (a['visit_order'] as int).compareTo(b['visit_order'] as int),
        );
        final last = completed.last;
        cursors[number] = math.max(
          start,
          minute(last['planned_departure_time'] as String?, start),
        );
        final place = saved
            .where((s) => s['place_id'] == last['place_id'])
            .firstOrNull?['place'];
        if (place != null) {
          origins[number] = [
            (place['latitude'] as num).toDouble(),
            (place['longitude'] as num).toDouble(),
          ];
        }
      }
    }
    for (final selection in candidates) {
      final place = selection['place'] as Map<String, dynamic>;
      Map<String, dynamic>? best;
      double bestCost = double.infinity;
      for (final day in days) {
        final number = day['day_number'] as int;
        if (!cursors.containsKey(number)) continue;
        if (selection['assignment_mode'] == 'LOCKED' &&
            selection['assigned_day_id'] != day['id']) {
          continue;
        }
        final origin = origins[number]!;
        final distance =
            CityPackRepository.distanceMeters(
              origin[0],
              origin[1],
              (place['latitude'] as num).toDouble(),
              (place['longitude'] as num).toDouble(),
            ) *
            1.3;
        final travel = distance == 0 ? 0 : math.max(1, (distance / 500).ceil());
        final duration = (place['recommended_visit_minutes'] as int? ?? 60)
            .clamp(10, 480);
        var arrival = cursors[number]! + travel;
        var lunch = false;
        // Same 60-minute midday break as the online planner, when it fits the day.
        if (cursors[number]! <= 780 &&
            arrival + duration > 750 &&
            endTimes[number]! >= 810) {
          arrival = math.max(arrival, 810);
          lunch = true;
        }
        final date = DateTime.parse(day['date'] as String);
        const names = [
          'monday',
          'tuesday',
          'wednesday',
          'thursday',
          'friday',
          'saturday',
          'sunday',
        ];
        final hours = place['opening_hours'] as Map? ?? {};
        final intervals = hours[names[date.weekday - 1]] as List? ?? [];
        final verified =
            place['hours_verification'] == 'VERIFIED' &&
            hours.containsKey(names[date.weekday - 1]);
        int? fit;
        for (final raw in intervals) {
          final open = minute(raw['open'] as String?, 0),
              close = minute(raw['close'] as String?, 1440);
          final proposed = math.max(arrival, open);
          if (proposed + duration <= close &&
              proposed + duration <= endTimes[number]!) {
            if (fit == null || proposed < fit) fit = proposed;
          }
        }
        if (verified && fit == null) continue;
        if (fit != null) arrival = fit;
        if (arrival + duration > endTimes[number]!) continue;
        final load =
            (cursors[number]! - minute(day['start_time'] as String?, 540)) /
            math.max(
              1,
              endTimes[number]! - minute(day['start_time'] as String?, 540),
            );
        final cost = load * 300 + travel + (arrival - cursors[number]!) * .1;
        if (cost >= bestCost) continue;
        bestCost = cost;
        best = {
          'day_number': number,
          'arrival': arrival,
          'departure': arrival + duration,
          'duration': duration,
          'distance': distance,
          'travel': travel,
          'known': verified,
          'lunch': lunch,
        };
      }
      if (best == null) {
        unscheduled.add({
          'place_id': place['id'],
          'name': place['name'],
          'assigned_day_id': selection['assigned_day_id'],
          'reason': selection['assignment_mode'] == 'LOCKED'
              ? 'LOCKED_DAY_INFEASIBLE'
              : 'NO_FEASIBLE_DAY',
        });
        continue;
      }
      final number = best['day_number'] as int;
      final stop = <String, dynamic>{
        'id': '${trip['trip_id']}:${place['id']}',
        'place_id': place['id'],
        'name': place['name'],
        'day_number': number,
        'visit_order': schedules[number]!.length + 1,
        'distance_from_previous': (best['distance'] as num) / 1000,
        'travel_time_minutes': best['travel'],
        'planned_arrival_time': clock(best['arrival'] as int),
        'planned_departure_time': clock(best['departure'] as int),
        'visit_duration_minutes': best['duration'],
        'is_opening_hours_known': best['known'],
        'status': 'PLANNED',
        'category': place['category'],
        'normalized_category': place['normalized_category'],
        'image': place['image'],
      };
      route.add(stop);
      schedules[number]!.add(stop);
      if (best['lunch'] == true &&
          !breaks.any((b) => b['day_number'] == number)) {
        breaks.add({
          'day_number': number,
          'start_time': '12:30',
          'end_time': '13:30',
          'duration_minutes': 60,
          'label': 'Midday Break',
        });
      }
      cursors[number] = best['departure'] as int;
      origins[number] = [
        (place['latitude'] as num).toDouble(),
        (place['longitude'] as num).toDouble(),
      ];
      if (place['hours_verification'] != 'VERIFIED') {
        conflicts.add('${place['name']}: check opening hours before visiting.');
      }
    }
    route.sort((a, b) {
      final d = (a['day_number'] as int).compareTo(b['day_number'] as int);
      return d != 0
          ? d
          : (a['visit_order'] as int).compareTo(b['visit_order'] as int);
    });
    final result = <String, dynamic>{
      'trip_id': trip['trip_id'],
      'optimized_places': route,
      'total_days': days.length,
      'breaks': breaks,
      'conflicts': conflicts,
      'unscheduled_places': unscheduled,
      'total_distance': route.fold<double>(
        0,
        (n, p) => n + (p['distance_from_previous'] as num).toDouble(),
      ),
      'total_travel_time_minutes': route.fold<int>(
        0,
        (n, p) => n + (p['travel_time_minutes'] as int),
      ),
    };
    result['route_geometry'] = geometry(state, route: result);
    return result;
  }
}
