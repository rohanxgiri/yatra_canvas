import 'package:flutter/foundation.dart';

import 'trip_draft.dart';

/// Session-only UI state. Backend records remain authoritative; this is not
/// account storage and does not claim to restore trips after an app restart.
class YatraSession extends ChangeNotifier {
  YatraSession._();
  static final instance = YatraSession._();
  final List<TripDraft> _trips = [];
  List<TripDraft> get trips => List.unmodifiable(_trips);
  String name = 'Traveller';
  String pace = 'Balanced';
  void remember(TripDraft trip) {
    if (trip.tripId == null) return;
    _trips.removeWhere((item) => item.tripId == trip.tripId);
    _trips.insert(
      0,
      TripDraft(
        tripId: trip.tripId,
        creationRequestId: trip.creationRequestId,
        destination: trip.destination,
        startDate: trip.startDate,
        endDate: trip.endDate,
        datesFlexible: trip.datesFlexible,
        durationDays: trip.durationDays,
        arrivalMethod: trip.arrivalMethod,
        arrivalPoint: trip.arrivalPoint,
        arrivalLatitude: trip.arrivalLatitude,
        arrivalLongitude: trip.arrivalLongitude,
        startLocationType: trip.startLocationType,
        startLocationName: trip.startLocationName,
        startLatitude: trip.startLatitude,
        startLongitude: trip.startLongitude,
        startLocationProvider: trip.startLocationProvider,
        startLocationProviderPlaceId: trip.startLocationProviderPlaceId,
        arrivalTime: trip.arrivalTime,
        purposes: {...trip.purposes},
        travelPace: trip.travelPace,
        budget: trip.budget,
        transportPreferences: {...trip.transportPreferences},
      ),
    );
    notifyListeners();
  }

  void setName(String value) {
    name = value.trim().isEmpty ? 'Traveller' : value.trim();
    notifyListeners();
  }

  void setPace(String value) {
    pace = value;
    notifyListeners();
  }

  void clearRecentTrips() {
    _trips.clear();
    notifyListeners();
  }
}
