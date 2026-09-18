import 'package:flutter/foundation.dart';

import 'trip_draft.dart';

/// UI-only authentication state.
///
/// This is a presentation-layer signal only. It does not implement or claim
/// real authentication, token management, or backend account binding.
/// Supabase Auth integration (ADR-001) is the planned production path.
enum YatraAuthMode { guest, signedIn }

/// Session-only UI state. Backend records remain authoritative; this is not
/// account storage and does not claim to restore trips after an app restart.
class YatraSession extends ChangeNotifier {
  YatraSession._();
  static final instance = YatraSession._();
  final List<TripDraft> _trips = [];
  List<TripDraft> get trips => List.unmodifiable(_trips);
  String name = 'Traveller';
  String pace = 'Balanced';

  // ── Auth-mode UI state ──────────────────────────────────────────────────
  // [PARTIAL] UI-only. Does NOT perform real authentication or account sync.
  // Real auth (Supabase JWT) is planned — see ADR-001 and PROJECT_CONTEXT.md.
  YatraAuthMode authMode = YatraAuthMode.guest;

  /// Display email shown in the profile header when a sign-in UI has been used.
  /// This is a presentational value; it carries no verified identity claim.
  String? displayEmail;

  bool get isGuest => authMode == YatraAuthMode.guest;

  /// Mark session as guest mode. Clears any display email.
  void enterAsGuest() {
    authMode = YatraAuthMode.guest;
    displayEmail = null;
    notifyListeners();
  }

  /// Record a UI-level sign-in state. Does NOT call any backend or verify identity.
  /// Only use after a real auth provider (Supabase/Google) has returned a verified token.
  /// [PARTIAL] — backend token binding not yet implemented.
  void markSignedIn({required String email, required String displayName}) {
    authMode = YatraAuthMode.signedIn;
    displayEmail = email;
    if (displayName.trim().isNotEmpty) name = displayName.trim();
    notifyListeners();
  }

  /// Sign out: revert to guest mode and clear display email.
  void signOut() {
    authMode = YatraAuthMode.guest;
    displayEmail = null;
    notifyListeners();
  }

  // ── Trip session ────────────────────────────────────────────────────────

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
