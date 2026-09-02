class OptimizedRoutePlace {
  const OptimizedRoutePlace({
    required this.placeId,
    required this.name,
    required this.dayNumber,
    required this.visitOrder,
    required this.distanceFromPrevious,
    required this.travelTimeMinutes,
  });

  final String placeId;
  final String name;
  final int dayNumber;
  final int visitOrder;
  final double distanceFromPrevious;
  final int travelTimeMinutes;

  factory OptimizedRoutePlace.fromJson(Map<String, dynamic> json) {
    return OptimizedRoutePlace(
      placeId: json['place_id'] as String,
      name: json['name'] as String,
      dayNumber: json['day_number'] as int,
      visitOrder: json['visit_order'] as int,
      distanceFromPrevious: (json['distance_from_previous'] as num).toDouble(),
      travelTimeMinutes: json['travel_time_minutes'] as int,
    );
  }
}

class OptimizedRoute {
  const OptimizedRoute({
    required this.tripId,
    required this.places,
    required this.totalDistance,
    required this.totalTravelTimeMinutes,
  });

  final String tripId;
  final List<OptimizedRoutePlace> places;
  final double totalDistance;
  final int totalTravelTimeMinutes;

  factory OptimizedRoute.fromJson(Map<String, dynamic> json) {
    final places = json['optimized_places'] as List<dynamic>;
    return OptimizedRoute(
      tripId: json['trip_id'] as String,
      places: places
          .map(
            (item) =>
                OptimizedRoutePlace.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      totalDistance: (json['total_distance'] as num).toDouble(),
      totalTravelTimeMinutes: json['total_travel_time_minutes'] as int,
    );
  }
}
