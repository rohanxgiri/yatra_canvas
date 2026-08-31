class CreatedTrip {
  const CreatedTrip({required this.tripId});

  final String tripId;

  factory CreatedTrip.fromJson(Map<String, dynamic> json) {
    final tripId = json['trip_id'];
    if (tripId is! String || tripId.trim().isEmpty) {
      throw const FormatException('Missing trip_id.');
    }
    return CreatedTrip(tripId: tripId.trim());
  }
}
