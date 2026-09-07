import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/itinerary_stop_status.dart';
import '../../models/optimized_route.dart';
import '../../models/route_geometry.dart';
import '../../models/saved_place.dart';
import '../../models/trip_draft.dart';
import '../../models/trip_start_location.dart';
import '../../services/route_geometry_service.dart';
import '../../services/route_optimization_service.dart';
import '../../services/saved_place_service.dart';
import '../../services/smart_replanning_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/poi_bottom_sheet.dart';

class TripMapScreen extends StatefulWidget {
  const TripMapScreen({
    required this.tripId,
    this.initialStartLocation,
    this.initialSavedPlaces,
    this.initialOptimizedRoute,
    this.initialRouteGeometry,
    this.initialDurationDays,
    this.tripService,
    this.savedPlaceService,
    this.routeOptimizationService,
    this.routeGeometryService,
    this.smartReplanningService,
    super.key,
  });

  final String tripId;
  final TripStartLocation? initialStartLocation;
  final List<SavedPlace>? initialSavedPlaces;
  final OptimizedRoute? initialOptimizedRoute;
  final TripRouteGeometry? initialRouteGeometry;
  final int? initialDurationDays;
  final TripService? tripService;
  final SavedPlaceService? savedPlaceService;
  final RouteOptimizationService? routeOptimizationService;
  final RouteGeometryService? routeGeometryService;
  final SmartReplanningService? smartReplanningService;

  @override
  State<TripMapScreen> createState() => _TripMapScreenState();
}

class _TripMapScreenState extends State<TripMapScreen> {
  late final TripService _tripService;
  late final bool _ownsTripService;
  late final SavedPlaceService _savedPlaceService;
  late final bool _ownsSavedPlaceService;
  late final RouteOptimizationService _routeOptimizationService;
  late final bool _ownsRouteOptimizationService;
  late final RouteGeometryService _routeGeometryService;
  late final bool _ownsRouteGeometryService;
  late final SmartReplanningService _replanningService;
  late final bool _ownsReplanningService;

  final MapController _mapController = MapController();
  final Stopwatch _perfWatch = Stopwatch();

  /// Tracks stop IDs with in-flight status-update requests.
  final Set<String> _updatingStopIds = {};

  bool _isLoading = true;
  bool _isRouteLoading = false;
  String? _error;

  TripStartLocation? _startLocation;
  List<SavedPlace> _savedPlaces = [];
  OptimizedRoute? _optimizedRoute;
  TripRouteGeometry? _routeGeometry;
  int? _selectedDay;
  int? _durationDays;

  List<int> get _logicalDays {
    final total = _durationDays ?? _optimizedRoute?.totalDays ?? 1;
    return List.generate(total < 1 ? 1 : total, (i) => i + 1);
  }

  @override
  void initState() {
    super.initState();
    _perfWatch.start();
    _ownsTripService = widget.tripService == null;
    _tripService = widget.tripService ?? TripService();

    _ownsSavedPlaceService = widget.savedPlaceService == null;
    _savedPlaceService = widget.savedPlaceService ?? SavedPlaceService();

    _ownsRouteOptimizationService = widget.routeOptimizationService == null;
    _routeOptimizationService =
        widget.routeOptimizationService ?? RouteOptimizationService();

    _ownsRouteGeometryService = widget.routeGeometryService == null;
    _routeGeometryService =
        widget.routeGeometryService ?? RouteGeometryService();

    _ownsReplanningService = widget.smartReplanningService == null;
    _replanningService =
        widget.smartReplanningService ?? SmartReplanningService();

    _durationDays = widget.initialDurationDays ?? widget.initialOptimizedRoute?.totalDays;

    if (widget.initialStartLocation != null ||
        (widget.initialSavedPlaces != null && widget.initialSavedPlaces!.isNotEmpty)) {
      _startLocation = widget.initialStartLocation;
      _savedPlaces = widget.initialSavedPlaces ?? [];
      _optimizedRoute = widget.initialOptimizedRoute;
      _routeGeometry = widget.initialRouteGeometry ?? widget.initialOptimizedRoute?.routeGeometry;
      _isLoading = false;

      developer.log(
        '[MapPerformance] Screen created and initialized with pre-passed state in ${_perfWatch.elapsedMilliseconds}ms. Markers: ${_savedPlaces.length}',
        name: 'TripMap',
      );

      if (_routeGeometry == null && _optimizedRoute != null) {
        _fetchRouteGeometryAsync();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitMapBounds();
      });
    } else {
      _loadMapData();
    }
  }

  @override
  void dispose() {
    if (_ownsTripService) _tripService.close();
    if (_ownsSavedPlaceService) _savedPlaceService.close();
    if (_ownsRouteOptimizationService) _routeOptimizationService.close();
    if (_ownsRouteGeometryService) _routeGeometryService.close();
    if (_ownsReplanningService) _replanningService.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _fetchRouteGeometryAsync() async {
    if (!mounted) return;
    setState(() => _isRouteLoading = true);
    try {
      final geom = await _routeGeometryService.getRouteGeometry(widget.tripId);
      if (!mounted) return;
      setState(() {
        _routeGeometry = geom;
        _isRouteLoading = false;
      });
      developer.log(
        '[MapPerformance] Route geometry ready in ${_perfWatch.elapsedMilliseconds}ms',
        name: 'TripMap',
      );
      _fitMapBounds();
    } catch (_) {
      if (mounted) setState(() => _isRouteLoading = false);
    }
  }

  Future<void> _loadMapData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _tripService.getTrip(widget.tripId),
        _savedPlaceService.getSavedPlaces(widget.tripId),
      ]);

      final tripDraft = results[0] as TripDraft;
      final savedPlacesResult = results[1] as List<SavedPlace>;

      if (!mounted) return;

      final stType = tripDraft.startLocationType;
      final name = tripDraft.startLocationName ?? tripDraft.arrivalPoint;
      final lat = tripDraft.startLatitude ?? tripDraft.arrivalLatitude ?? 0.0;
      final lng =
          tripDraft.startLongitude ?? tripDraft.arrivalLongitude ?? 0.0;

      TripStartLocation? start;
      if (lat != 0.0 && lng != 0.0) {
        start = TripStartLocation(
          tripId: widget.tripId,
          type: stType,
          name: name,
          latitude: lat,
          longitude: lng,
        );
      }

      setState(() {
        _startLocation = start;
        _savedPlaces = savedPlacesResult;
        _durationDays = tripDraft.durationDays;
        _isLoading = false;
      });

      developer.log(
        '[MapPerformance] Base map and ${_savedPlaces.length} markers ready in ${_perfWatch.elapsedMilliseconds}ms',
        name: 'TripMap',
      );

      _fitMapBounds();

      _fetchRouteAsync();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load map data. Please try again.';
      });
    }
  }

  Future<void> _fetchRouteAsync() async {
    if (!mounted) return;
    setState(() => _isRouteLoading = true);

    OptimizedRoute? routeResult;
    try {
      routeResult = await _routeOptimizationService.optimizeRoute(widget.tripId);
    } catch (_) {
      // Route optimization optional
    }

    TripRouteGeometry? geometryResult = routeResult?.routeGeometry;
    if (geometryResult == null) {
      try {
        geometryResult =
            await _routeGeometryService.getRouteGeometry(widget.tripId);
      } catch (_) {
        // Safe degradation: if geometry cannot be fetched, map still shows markers.
      }
    }

    if (!mounted) return;
    setState(() {
      _optimizedRoute = routeResult;
      _routeGeometry = geometryResult;
      if (routeResult != null && _durationDays == null) {
        _durationDays = routeResult.totalDays;
      }
      _isRouteLoading = false;
    });

    developer.log(
      '[MapPerformance] Route ready in ${_perfWatch.elapsedMilliseconds}ms',
      name: 'TripMap',
    );
    _fitMapBounds();
  }

  void _fitMapBounds() {
    try {
      final points = _getVisiblePoints();
      if (points.isEmpty) return;

      if (points.length == 1) {
        _mapController.move(points.first, 14.0);
        return;
      }

      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50.0)),
      );
    } catch (_) {
      // MapController not ready yet, will be called again in onMapReady
    }
  }

  List<LatLng> _getVisiblePoints() {
    final points = <LatLng>[];

    if (_startLocation != null) {
      points.add(LatLng(_startLocation!.latitude, _startLocation!.longitude));
    }

    // Include road-route geometry points if available for accurate camera framing
    if (_routeGeometry != null) {
      final geometryPoints = _routeGeometry!.pointsForDay(_selectedDay);
      points.addAll(geometryPoints);
    }

    if (_optimizedRoute != null) {
      final filteredPlaces = _selectedDay == null
          ? _optimizedRoute!.places
          : _optimizedRoute!.places.where((p) => p.dayNumber == _selectedDay);

      for (final place in filteredPlaces) {
        final saved = _savedPlaces
            .where((s) => s.placeId == place.placeId)
            .firstOrNull;
        if (saved != null) {
          points.add(LatLng(saved.place.latitude, saved.place.longitude));
        }
      }
    } else {
      for (final saved in _savedPlaces) {
        points.add(LatLng(saved.place.latitude, saved.place.longitude));
      }
    }

    return points;
  }

  List<Polyline> _buildPolylines() {
    if (_routeGeometry == null) return const [];
    final polylines = <Polyline>[];

    final filteredDays = _selectedDay == null
        ? _routeGeometry!.days
        : _routeGeometry!.days.where((d) => d.dayNumber == _selectedDay);

    for (final day in filteredDays) {
      if (day.points.isNotEmpty) {
        polylines.add(
          Polyline(
            points: day.points,
            color: AppColors.teal,
            strokeWidth: 4.5,
          ),
        );
      }
    }
    return polylines;
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    if (_startLocation != null) {
      markers.add(
        Marker(
          point: LatLng(_startLocation!.latitude, _startLocation!.longitude),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showStartLocationSheet(),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.teal,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: Icon(Icons.home_rounded, color: Colors.white, size: 24),
            ),
          ),
        ),
      );
    }

    if (_optimizedRoute != null) {
      final filteredPlaces = _selectedDay == null
          ? _optimizedRoute!.places
          : _optimizedRoute!.places.where((p) => p.dayNumber == _selectedDay);

      for (final place in filteredPlaces) {
        final saved = _savedPlaces
            .where((s) => s.placeId == place.placeId)
            .firstOrNull;
        if (saved != null) {
          markers.add(
            Marker(
              point: LatLng(saved.place.latitude, saved.place.longitude),
              width: 36,
              height: 36,
              child: GestureDetector(
                onTap: () => _showPoiBottomSheet(saved, place),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppColors.teal,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 4),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${place.visitOrder}',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      }
    } else {
      for (final saved in _savedPlaces) {
        markers.add(
          Marker(
            point: LatLng(saved.place.latitude, saved.place.longitude),
            width: 32,
            height: 32,
            child: GestureDetector(
              onTap: () => _showPoiBottomSheet(saved, null),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.teal,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        );
      }
    }

    return markers;
  }

  /// Opens the rich POI detail bottom sheet for a saved place marker.
  void _showPoiBottomSheet(SavedPlace saved, OptimizedRoutePlace? stop) {
    // Available days for the "Move" picker: all logical days except the
    // current stop's day. REST filtering is handled server-side.
    final availableDays = _optimizedRoute?.logicalDays
            .where((d) => d != stop?.dayNumber)
            .toList() ??
        [];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (_, scrollController) => PoiBottomSheet(
          savedPlace: saved,
          routeStop: stop,
          availableDays: availableDays,
          onStatusChange: stop == null
              ? null
              : (status) => _handleStopStatusChange(stop, status),
          onMoveToDay: stop == null
              ? null
              : (targetDay) => _handleMoveToDay(stop, targetDay),
        ),
      ),
    );
  }


  /// Shows a minimal bottom sheet for the trip start-location marker.
  void _showStartLocationSheet() {
    final name = _startLocation?.name ?? 'Start Location';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.tealLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Start Location',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.teal,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(name, style: AppTextStyles.sectionTitle),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Calls the replanning service to update a stop's status, then patches
  /// [_optimizedRoute] in place without a full reload.
  Future<void> _handleStopStatusChange(
    OptimizedRoutePlace stop,
    ItineraryStopStatus status,
  ) async {
    final stopId = stop.id ?? stop.placeId;
    if (_updatingStopIds.contains(stopId)) return;
    _updatingStopIds.add(stopId);

    try {
      final updated = await _replanningService.updateStopStatus(
        tripId: widget.tripId,
        stopOrPlaceId: stop.id != null ? stop.id! : stop.placeId,
        status: status,
        isPlaceId: stop.id == null,
      );

      if (!mounted) return;
      setState(() {
        if (_optimizedRoute != null) {
          final places = _optimizedRoute!.places.map((p) {
            if (p.placeId == updated.placeId) {
              return OptimizedRoutePlace(
                id: updated.id,
                placeId: updated.placeId,
                name: updated.name,
                dayNumber: updated.dayNumber,
                visitOrder: updated.visitOrder,
                distanceFromPrevious: updated.distanceFromPrevious,
                travelTimeMinutes: updated.travelTimeMinutes,
                plannedArrivalTime: updated.plannedArrivalTime,
                plannedDepartureTime: updated.plannedDepartureTime,
                visitDurationMinutes: updated.visitDurationMinutes,
                isOpeningHoursKnown: updated.isOpeningHoursKnown,
                status: updated.status,
              );
            }
            return p;
          }).toList();
          _optimizedRoute = OptimizedRoute(
            tripId: _optimizedRoute!.tripId,
            places: places,
            totalDistance: _optimizedRoute!.totalDistance,
            totalTravelTimeMinutes: _optimizedRoute!.totalTravelTimeMinutes,
            totalDays: _optimizedRoute!.totalDays,
            breaks: _optimizedRoute!.breaks,
            conflicts: _optimizedRoute!.conflicts,
            unscheduledPlaces: _optimizedRoute!.unscheduledPlaces,
            routeGeometry: _optimizedRoute!.routeGeometry,
          );
        }
      });
    } finally {
      _updatingStopIds.remove(stopId);
    }
  }

  /// Calls the replanning service to move a missed stop to another day, then
  /// merges the server response back into [_optimizedRoute].
  Future<void> _handleMoveToDay(
    OptimizedRoutePlace stop,
    int targetDay,
  ) async {
    final stopId = stop.id ?? stop.placeId;
    if (_updatingStopIds.contains(stopId)) return;
    _updatingStopIds.add(stopId);

    try {
      final response = await _replanningService.movePlaceToDay(
        tripId: widget.tripId,
        placeId: stop.placeId,
        targetDayNumber: targetDay,
      );

      if (!mounted) return;

      if (!response.success) {
        throw SmartReplanningException(
          response.reason ?? 'TARGET_DAY_INFEASIBLE',
        );
      }

      setState(() {
        final merged = response.updatedItinerary;
        if (merged != null) {
          _optimizedRoute = merged;
        } else {
          // Patch source and target day stops from response.
          final newPlaces = <OptimizedRoutePlace>[
            ..._optimizedRoute!.places.where(
              (p) =>
                  p.dayNumber != stop.dayNumber &&
                  p.dayNumber != targetDay,
            ),
            ...response.sourceItinerary,
            ...response.targetItinerary,
          ];
          newPlaces.sort((a, b) {
            final dc = a.dayNumber.compareTo(b.dayNumber);
            return dc != 0 ? dc : a.visitOrder.compareTo(b.visitOrder);
          });
          _optimizedRoute = OptimizedRoute(
            tripId: _optimizedRoute!.tripId,
            places: newPlaces,
            totalDistance: _optimizedRoute!.totalDistance,
            totalTravelTimeMinutes: _optimizedRoute!.totalTravelTimeMinutes,
            totalDays: _optimizedRoute!.totalDays,
            breaks: _optimizedRoute!.breaks,
            conflicts: _optimizedRoute!.conflicts,
            unscheduledPlaces: _optimizedRoute!.unscheduledPlaces,
            routeGeometry: _optimizedRoute!.routeGeometry,
          );
        }
      });
    } finally {
      _updatingStopIds.remove(stopId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Map'),
        actions: [
          if (_logicalDays.isNotEmpty)
            PopupMenuButton<int?>(
              icon: const Icon(Icons.filter_list_rounded),
              onSelected: (day) {
                setState(() {
                  _selectedDay = day;
                });
                _fitMapBounds();
              },
              itemBuilder: (context) {
                final days = _logicalDays;
                return [
                  const PopupMenuItem(value: null, child: Text('All Days')),
                  for (final day in days)
                    PopupMenuItem(value: day, child: Text('Day $day')),
                ];
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.error,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTextStyles.body,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loadMapData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final points = _getVisiblePoints();
    final center = points.isNotEmpty ? points.first : const LatLng(0, 0);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13.0,
            onMapReady: _fitMapBounds,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.yatracanvas.app',
            ),
            PolylineLayer(polylines: _buildPolylines()),
            MarkerLayer(markers: _buildMarkers()),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
        if (_selectedDay != null &&
            _optimizedRoute != null &&
            !_optimizedRoute!.places.any((p) => p.dayNumber == _selectedDay))
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              color: AppColors.surface,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 18, color: AppColors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Day $_selectedDay · No places scheduled yet.',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.charcoal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_isRouteLoading)
          Positioned(
            bottom: 24,
            left: 24,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(20),
              color: AppColors.surface,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Calculating route…',
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
