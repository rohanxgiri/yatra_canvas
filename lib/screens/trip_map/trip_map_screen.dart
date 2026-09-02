import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/optimized_route.dart';
import '../../models/route_geometry.dart';
import '../../models/saved_place.dart';
import '../../models/trip_start_location.dart';
import '../../services/route_geometry_service.dart';
import '../../services/route_optimization_service.dart';
import '../../services/saved_place_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

class TripMapScreen extends StatefulWidget {
  const TripMapScreen({
    required this.tripId,
    this.tripService,
    this.savedPlaceService,
    this.routeOptimizationService,
    this.routeGeometryService,
    super.key,
  });

  final String tripId;
  final TripService? tripService;
  final SavedPlaceService? savedPlaceService;
  final RouteOptimizationService? routeOptimizationService;
  final RouteGeometryService? routeGeometryService;

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

  final MapController _mapController = MapController();

  bool _isLoading = true;
  String? _error;

  TripStartLocation? _startLocation;
  List<SavedPlace> _savedPlaces = [];
  OptimizedRoute? _optimizedRoute;
  TripRouteGeometry? _routeGeometry;
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
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

    _loadMapData();
  }

  @override
  void dispose() {
    if (_ownsTripService) _tripService.close();
    if (_ownsSavedPlaceService) _savedPlaceService.close();
    if (_ownsRouteOptimizationService) _routeOptimizationService.close();
    if (_ownsRouteGeometryService) _routeGeometryService.close();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadMapData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tripDraft = await _tripService.getTrip(widget.tripId);
      final savedPlacesResult = await _savedPlaceService.getSavedPlaces(
        widget.tripId,
      );

      OptimizedRoute? routeResult;
      try {
        routeResult = await _routeOptimizationService.optimizeRoute(
          widget.tripId,
        );
      } catch (_) {
        // If optimization fails or doesn't exist, we continue without it.
      }

      TripRouteGeometry? geometryResult;
      try {
        geometryResult = await _routeGeometryService.getRouteGeometry(
          widget.tripId,
        );
      } catch (_) {
        // Safe degradation: if geometry cannot be fetched, map still shows markers.
      }

      if (!mounted) return;

      setState(() {
        final stType = tripDraft.startLocationType;
        final name = tripDraft.startLocationName ?? tripDraft.arrivalPoint;
        final lat = tripDraft.startLatitude ?? tripDraft.arrivalLatitude ?? 0.0;
        final lng =
            tripDraft.startLongitude ?? tripDraft.arrivalLongitude ?? 0.0;

        if (lat != 0.0 && lng != 0.0) {
          _startLocation = TripStartLocation(
            tripId: widget.tripId,
            type: stType,
            name: name,
            latitude: lat,
            longitude: lng,
          );
        }

        _savedPlaces = savedPlacesResult;
        _optimizedRoute = routeResult;
        _routeGeometry = geometryResult;
        _isLoading = false;
      });

      _fitMapBounds();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load map data. Please try again.';
      });
    }
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
            onTap: () =>
                _showPlaceDetails(_startLocation!.name, 'Start Location', null),
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
                onTap: () => _showPlaceDetails(
                  saved.place.name,
                  saved.place.category,
                  place.visitOrder,
                ),
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
              onTap: () => _showPlaceDetails(
                saved.place.name,
                saved.place.category,
                null,
              ),
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

  void _showPlaceDetails(String name, String category, int? visitOrder) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (visitOrder != null) ...[
                Text(
                  'Stop $visitOrder',
                  style: AppTextStyles.caption.copyWith(color: AppColors.teal),
                ),
                const SizedBox(height: 4),
              ],
              Text(name, style: AppTextStyles.sectionTitle),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.category_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(category, style: AppTextStyles.bodyMuted),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Map'),
        actions: [
          if (_optimizedRoute != null)
            PopupMenuButton<int?>(
              icon: const Icon(Icons.filter_list_rounded),
              onSelected: (day) {
                setState(() {
                  _selectedDay = day;
                });
                _fitMapBounds();
              },
              itemBuilder: (context) {
                final days =
                    _optimizedRoute!.places
                        .map((p) => p.dayNumber)
                        .toSet()
                        .toList()
                      ..sort();
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
      ],
    );
  }
}
