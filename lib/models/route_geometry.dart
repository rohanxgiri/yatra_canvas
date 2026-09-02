import 'package:latlong2/latlong.dart';

class RouteLegGeometry {
  const RouteLegGeometry({
    required this.startLatitude,
    required this.startLongitude,
    required this.endLatitude,
    required this.endLongitude,
    this.distanceMeters,
    this.durationSeconds,
  });

  final double startLatitude;
  final double startLongitude;
  final double endLatitude;
  final double endLongitude;
  final double? distanceMeters;
  final double? durationSeconds;

  factory RouteLegGeometry.fromJson(Map<String, dynamic> json) {
    return RouteLegGeometry(
      startLatitude: (json['start_latitude'] as num).toDouble(),
      startLongitude: (json['start_longitude'] as num).toDouble(),
      endLatitude: (json['end_latitude'] as num).toDouble(),
      endLongitude: (json['end_longitude'] as num).toDouble(),
      distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
    );
  }
}

class DayRouteGeometry {
  const DayRouteGeometry({
    required this.dayNumber,
    required this.points,
    this.distanceMeters,
    this.durationSeconds,
    this.legs = const [],
  });

  final int dayNumber;
  final List<LatLng> points;
  final double? distanceMeters;
  final double? durationSeconds;
  final List<RouteLegGeometry> legs;

  factory DayRouteGeometry.fromJson(Map<String, dynamic> json) {
    final rawCoords = json['coordinates'] as List<dynamic>? ?? [];
    final points = <LatLng>[];
    for (final item in rawCoords) {
      if (item is List && item.length >= 2) {
        final lat = (item[0] as num).toDouble();
        final lon = (item[1] as num).toDouble();
        points.add(LatLng(lat, lon));
      }
    }

    final rawLegs = json['legs'] as List<dynamic>? ?? [];
    final legs = rawLegs
        .map((l) => RouteLegGeometry.fromJson(l as Map<String, dynamic>))
        .toList(growable: false);

    return DayRouteGeometry(
      dayNumber: json['day_number'] as int,
      points: points,
      distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
      legs: legs,
    );
  }
}

class TripRouteGeometry {
  const TripRouteGeometry({
    required this.tripId,
    required this.days,
    this.totalDistanceMeters,
    this.totalDurationSeconds,
  });

  final String tripId;
  final List<DayRouteGeometry> days;
  final double? totalDistanceMeters;
  final double? totalDurationSeconds;

  factory TripRouteGeometry.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'] as List<dynamic>? ?? [];
    return TripRouteGeometry(
      tripId: json['trip_id'] as String,
      days: rawDays
          .map((d) => DayRouteGeometry.fromJson(d as Map<String, dynamic>))
          .toList(growable: false),
      totalDistanceMeters: (json['total_distance_meters'] as num?)?.toDouble(),
      totalDurationSeconds: (json['total_duration_seconds'] as num?)?.toDouble(),
    );
  }

  List<LatLng> pointsForDay(int? dayNumber) {
    if (dayNumber == null) {
      final allPoints = <LatLng>[];
      for (final day in days) {
        allPoints.addAll(day.points);
      }
      return allPoints;
    }
    for (final day in days) {
      if (day.dayNumber == dayNumber) {
        return day.points;
      }
    }
    return const [];
  }
}
