import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/city.dart';
import '../../models/optimized_route.dart';
import '../../models/place.dart';
import '../../models/recommendation.dart';
import '../../models/saved_place.dart';
import '../../models/trip_start_location.dart';
import '../../services/place_service.dart';
import '../../services/recommendation_service.dart';
import '../../services/route_optimization_service.dart';
import '../../services/saved_place_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../models/weather_advisory.dart';
import '../../models/smart_replanning.dart';
import '../../services/weather_advisory_service.dart';
import '../../services/smart_replanning_service.dart';
import '../../widgets/place_card.dart';
import '../../widgets/selection_chip.dart';
import '../trip_map/trip_map_screen.dart';
import 'widgets/weather_advisory_card.dart';

class PlaceDiscoveryScreen extends StatefulWidget {
  const PlaceDiscoveryScreen({
    required this.city,
    this.tripId,
    this.tripPurposes = const <String>{},
    this.routeStartReady,
    this.durationDays,
    this.startLocation,
    this.recommendationService,
    this.savedPlaceService,
    this.routeOptimizationService,
    this.weatherAdvisoryService,
    this.smartReplanningService,
    this.placeService,
    super.key,
  });

  final City city;
  final String? tripId;
  final Set<String> tripPurposes;
  final bool? routeStartReady;
  final int? durationDays;
  final TripStartLocation? startLocation;
  final RecommendationService? recommendationService;
  final SavedPlaceService? savedPlaceService;
  final RouteOptimizationService? routeOptimizationService;
  final WeatherAdvisoryService? weatherAdvisoryService;
  final SmartReplanningService? smartReplanningService;
  final PlaceService? placeService;

  @override
  State<PlaceDiscoveryScreen> createState() => _PlaceDiscoveryScreenState();
}

class _PlaceDiscoveryScreenState extends State<PlaceDiscoveryScreen> {
  late final RecommendationService _recommendationService;
  late final bool _ownsRecommendationService;
  late final SavedPlaceService _savedPlaceService;
  late final bool _ownsSavedPlaceService;
  late final RouteOptimizationService _routeOptimizationService;
  late final bool _ownsRouteOptimizationService;
  late final WeatherAdvisoryService _weatherAdvisoryService;
  late final bool _ownsWeatherAdvisoryService;
  late final SmartReplanningService _smartReplanningService;
  late final bool _ownsSmartReplanningService;
  late final PlaceService _placeService;
  late final bool _ownsPlaceService;

  late final Set<PlaceCategory> _purposeCategories;
  final Set<PlaceCategory> _refinementCategories = {};
  PlaceCategory? _activeCategoryFilter;
  List<Recommendation> _recommendations = const [];
  List<SavedPlace> _savedPlaces = const [];
  List<WeatherAdvisory> _weatherAdvisories = const [];
  final Set<String> _dismissedAdvisoryIds = {};
  OptimizedRoute? _optimizedRoute;
  TripReplanImpact? _replanImpact;
  bool _isLoadingReplanPreview = false;
  final Set<String> _mutatingPlaceIds = {};
  String? _error;
  String? _savedError;
  String? _routeError;
  bool _isLoading = false;
  bool _isLoadingSavedPlaces = false;
  bool _isReordering = false;
  bool _isOptimizingRoute = false;
  bool _hasRequested = false;
  bool _showRefinements = false;
  bool _refinementsDirty = false;
  int _requestGeneration = 0;

  // Manual place search state
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  bool _isSearchOpen = false;
  bool _isSearching = false;
  String? _searchError;
  List<PlaceSearchResult> _searchResults = const [];
  final Set<String> _resolvingResultIds = {};

  @override
  void initState() {
    super.initState();
    _purposeCategories = _categoriesForPurposes(widget.tripPurposes);
    _showRefinements = _purposeCategories.isEmpty;
    _ownsRecommendationService = widget.recommendationService == null;
    _recommendationService =
        widget.recommendationService ?? RecommendationService();
    _ownsSavedPlaceService = widget.savedPlaceService == null;
    _savedPlaceService = widget.savedPlaceService ?? SavedPlaceService();
    _ownsRouteOptimizationService = widget.routeOptimizationService == null;
    _routeOptimizationService =
        widget.routeOptimizationService ?? RouteOptimizationService();
    _ownsWeatherAdvisoryService = widget.weatherAdvisoryService == null;
    _weatherAdvisoryService =
        widget.weatherAdvisoryService ?? WeatherAdvisoryService();
    _ownsSmartReplanningService = widget.smartReplanningService == null;
    _smartReplanningService =
        widget.smartReplanningService ?? SmartReplanningService();
    _ownsPlaceService = widget.placeService == null;
    _placeService = widget.placeService ?? PlaceService();
    if (_tripId != null) {
      _loadSavedPlaces();
      _loadWeatherAdvisories();
    }
    if (_purposeCategories.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadRecommendations();
      });
    }
  }

  static Set<PlaceCategory> _categoriesForPurposes(Set<String> purposes) {
    final categories = <PlaceCategory>{};
    for (final purpose in purposes) {
      switch (purpose) {
        case 'Religious / Spiritual':
          categories.add(PlaceCategory.religious);
          break;
        case 'Culture & Heritage':
          categories.add(PlaceCategory.heritage);
          break;
        case 'Food Exploration':
          categories.add(PlaceCategory.food);
          break;
        case 'Photography':
          categories.addAll([PlaceCategory.tourism, PlaceCategory.heritage]);
          break;
        case 'Mixed Trip':
          categories.addAll(PlaceCategory.values);
          break;
        case 'Sightseeing':
        case 'Nature':
        case 'Relaxation':
        case 'Family Trip':
        case 'Shopping':
          categories.add(PlaceCategory.tourism);
          break;
      }
    }
    return categories;
  }

  Set<PlaceCategory> get _effectiveCategories => {
    ..._purposeCategories,
    ..._refinementCategories,
  };

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    if (_ownsPlaceService) _placeService.close();
    if (_ownsRecommendationService) _recommendationService.close();
    if (_ownsSavedPlaceService) _savedPlaceService.close();
    if (_ownsRouteOptimizationService) _routeOptimizationService.close();
    if (_ownsWeatherAdvisoryService) _weatherAdvisoryService.close();
    if (_ownsSmartReplanningService) _smartReplanningService.dispose();
    super.dispose();
  }

  String? get _tripId {
    final value = widget.tripId?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> _loadRecommendations() async {
    final cityId = widget.city.id;
    if (cityId == null || cityId.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Resolve this city before discovering nearby places.';
      });
      return;
    }

    final requestGeneration = ++_requestGeneration;
    final categories = PlaceCategory.values
        .where(_effectiveCategories.contains)
        .toList(growable: false);
    if (categories.isEmpty) {
      setState(() {
        _isLoading = false;
        _hasRequested = false;
        _error = 'Choose at least one interest to discover places.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _hasRequested = true;
      _error = null;
    });

    try {
      final recommendations = await _recommendationService.getRecommendations(
        cityId,
        categories,
        tripId: _tripId,
        purposes: widget.tripPurposes,
        interests: _refinementCategories.map((c) => c.apiValue),
        categoryFilter: _activeCategoryFilter,
      );
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _recommendations = recommendations;
        _isLoading = false;
        _refinementsDirty = false;
        if (_purposeCategories.isNotEmpty) _showRefinements = false;
      });
    } on Object catch (error) {
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        final friendlyMsg = _friendlyError(error);
        if (_recommendations.isEmpty) {
          _error = friendlyMsg;
        } else {
          _showSavedMessage(friendlyMsg, isError: true);
        }
        _isLoading = false;
      });
    }
  }

  void _setCategoryFilter(PlaceCategory? category) {
    setState(() {
      if (_activeCategoryFilter == category) {
        _activeCategoryFilter = null;
      } else {
        _activeCategoryFilter = category;
      }
    });
    _loadRecommendations();
  }

  void _toggleCategory(PlaceCategory category) {
    setState(() {
      if (_refinementCategories.contains(category)) {
        _refinementCategories.remove(category);
      } else {
        _refinementCategories.add(category);
      }
      _refinementsDirty = true;
      _error = null;
    });
  }

  Future<void> _loadSavedPlaces() async {
    final tripId = _tripId;
    if (tripId == null) return;
    setState(() {
      _isLoadingSavedPlaces = true;
      _savedError = null;
    });
    try {
      final savedPlaces = await _savedPlaceService.getSavedPlaces(tripId);
      if (!mounted) return;
      setState(() {
        _savedPlaces = savedPlaces;
        _isLoadingSavedPlaces = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingSavedPlaces = false;
        _savedError = _savedPlaceError(error);
      });
    }
  }

  Future<void> _loadWeatherAdvisories() async {
    final tripId = _tripId;
    if (tripId == null) return;
    try {
      final res = await _weatherAdvisoryService.getAdvisories(tripId);
      if (!mounted || res == null) return;
      setState(() {
        _weatherAdvisories = res.advisories;
      });
    } catch (_) {
      // Safe degradation: never block trip planning on weather errors
    }
  }

  Future<void> _checkReplanImpact() async {
    final tripId = _tripId;
    if (tripId == null || _optimizedRoute == null) return;
    try {
      final impact = await _smartReplanningService.getReplanImpact(tripId);
      if (!mounted) return;
      setState(() {
        _replanImpact = impact.isStale ? impact : null;
      });
    } catch (_) {
      // Safe degradation: never block trip planning
    }
  }

  Future<void> _showReplanPreviewDialog() async {
    final tripId = _tripId;
    if (tripId == null) return;
    setState(() => _isLoadingReplanPreview = true);

    try {
      final preview = await _smartReplanningService.getReplanPreview(tripId);
      if (!mounted) return;
      setState(() => _isLoadingReplanPreview = false);

      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.auto_fix_high_rounded, color: AppColors.teal),
              SizedBox(width: 8),
              Expanded(child: Text('Proposed Re-plan')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview.summary,
                  style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700),
                ),
                if (preview.addedPlaces.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Added to itinerary:',
                    style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
                  ),
                  for (final place in preview.addedPlaces)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Text('• $place', style: AppTextStyles.caption.copyWith(color: AppColors.tealDark)),
                    ),
                ],
                if (preview.removedPlaces.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Removed from itinerary:',
                    style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
                  ),
                  for (final place in preview.removedPlaces)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Text('• $place', style: AppTextStyles.caption.copyWith(color: AppColors.error)),
                    ),
                ],
                if (preview.movedPlaces.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Rescheduled stops:',
                    style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
                  ),
                  for (final moved in preview.movedPlaces)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Text('• ${moved.name}: ${moved.moveDescription}', style: AppTextStyles.caption),
                    ),
                ],
                if (preview.travelTimeDeltaMinutes != 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timelapse_rounded, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          'Estimated travel change: ${preview.travelTimeDeltaMinutes > 0 ? "+${preview.travelTimeDeltaMinutes}" : "${preview.travelTimeDeltaMinutes}"} min',
                          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
                if (preview.conflicts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Planning Advisory',
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        for (final conflict in preview.conflicts)
                          Text('• $conflict', style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                setState(() => _replanImpact = null);
              },
              child: const Text('Keep current plan'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                try {
                  final applied = await _smartReplanningService.applyReplan(tripId);
                  if (!mounted) return;
                  setState(() {
                    _optimizedRoute = applied;
                    _replanImpact = null;
                  });
                  _showSavedMessage('New itinerary applied.');
                  _loadWeatherAdvisories();
                } catch (e) {
                  _showSavedMessage('Failed to apply re-plan: $e', isError: true);
                }
              },
              child: const Text('Apply new plan'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingReplanPreview = false);
      _showSavedMessage('Could not generate re-plan preview: $error', isError: true);
    }
  }

  SavedPlace? _savedPlaceFor(String placeId) {
    for (final savedPlace in _savedPlaces) {
      if (savedPlace.placeId == placeId) return savedPlace;
    }
    return null;
  }

  Future<void> _toggleSavedPlace(Recommendation recommendation) async {
    final tripId = _tripId;
    if (tripId == null || _mutatingPlaceIds.contains(recommendation.id)) {
      return;
    }
    final existing = _savedPlaceFor(recommendation.id);
    setState(() {
      _mutatingPlaceIds.add(recommendation.id);
      _savedError = null;
      _routeError = null;
    });
    try {
      if (existing == null) {
        final savedPlace = await _savedPlaceService.addSavedPlace(
          tripId,
          recommendation.id,
          customOrder: _savedPlaces.length + 1,
        );
        if (!mounted) return;
        setState(() {
          _savedPlaces = [..._savedPlaces, savedPlace];
          _optimizedRoute = null;
        });
        _showSavedMessage('${recommendation.name} added to your trip.');
      } else {
        await _savedPlaceService.removeSavedPlace(tripId, recommendation.id);
        if (!mounted) return;
        setState(() {
          _optimizedRoute = null;
        });
        await _loadSavedPlaces();
        if (!mounted) return;
        _showSavedMessage('${recommendation.name} removed from your trip.');
      }
      await _checkReplanImpact();
    } on Object catch (error) {
      if (!mounted) return;
      if (existing == null &&
          error is SavedPlaceServiceException &&
          error.isConflict) {
        try {
          final authoritative = await _savedPlaceService.getSavedPlaces(tripId);
          if (!mounted) return;
          final isSaved = authoritative.any(
            (item) => item.placeId == recommendation.id,
          );
          if (isSaved) {
            setState(() {
              _savedPlaces = authoritative;
              _savedError = null;
            });
            _showSavedMessage('${recommendation.name} is already saved.');
            return;
          }
        } on Object {
          // Keep the original conflict as the actionable error.
        }
      }
      final message = _savedPlaceError(error);
      setState(() => _savedError = message);
      _showSavedMessage(message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _mutatingPlaceIds.remove(recommendation.id));
      }
    }
  }

  Future<void> _removeSavedPlace(SavedPlace savedPlace) async {
    final tripId = _tripId;
    if (tripId == null || _mutatingPlaceIds.contains(savedPlace.placeId)) {
      return;
    }
    setState(() {
      _mutatingPlaceIds.add(savedPlace.placeId);
      _routeError = null;
    });
    try {
      await _savedPlaceService.removeSavedPlace(tripId, savedPlace.placeId);
      if (!mounted) return;
      setState(() {
        _savedPlaces = [
          for (final item in _savedPlaces)
            if (item.placeId != savedPlace.placeId) item,
        ];
        _optimizedRoute = null;
        _savedError = null;
      });
      await _loadSavedPlaces();
      await _checkReplanImpact();
    } on Object catch (error) {
      if (!mounted) return;
      final message = _savedPlaceError(error);
      setState(() => _savedError = message);
      _showSavedMessage(message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _mutatingPlaceIds.remove(savedPlace.placeId));
      }
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searchError = null;
        _isSearching = false;
      });
      return;
    }
    _searchDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      _performSearch(trimmed);
    });
  }

  Future<void> _performSearch(String query) async {
    final cityId = widget.city.id;
    if (cityId == null) return;
    setState(() {
      _isSearching = true;
      _searchError = null;
    });
    try {
      final results = await _placeService.searchPlaces(cityId, query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = error is PlaceServiceException
            ? error.message
            : 'Could not search places. Please try again.';
      });
    }
  }

  Future<void> _addManualPlace(PlaceSearchResult result) async {
    final tripId = _tripId;
    if (tripId == null) return;
    final cityId = widget.city.id;
    if (cityId == null) return;

    final resultKey = result.externalPlaceId ?? result.placeId ?? result.name;
    if (_resolvingResultIds.contains(resultKey)) return;

    // Fast client-side duplicate check
    final alreadySaved = _savedPlaces.any(
      (sp) =>
          (result.placeId != null && sp.placeId == result.placeId) ||
          sp.place.name.trim().toLowerCase() == result.name.trim().toLowerCase(),
    );
    if (alreadySaved) {
      _showSavedMessage('${result.name} is already in your selected places.');
      return;
    }

    setState(() {
      _resolvingResultIds.add(resultKey);
      _savedError = null;
      _routeError = null;
    });

    try {
      final place = await _placeService.resolvePlace(cityId, result);
      if (!mounted) return;

      if (_savedPlaces.any((sp) => sp.placeId == place.id)) {
        _showSavedMessage('${place.name} is already in your selected places.');
        return;
      }

      final savedPlace = await _savedPlaceService.addSavedPlace(
        tripId,
        place.id,
        customOrder: _savedPlaces.length + 1,
      );
      if (!mounted) return;

      setState(() {
        _savedPlaces = [..._savedPlaces, savedPlace];
        _optimizedRoute = null;
      });
      _showSavedMessage('${place.name} added to your trip.');
      await _checkReplanImpact();
    } on Object catch (error) {
      if (!mounted) return;
      final message = _savedPlaceError(error);
      setState(() => _savedError = message);
      _showSavedMessage(message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _resolvingResultIds.remove(resultKey));
      }
    }
  }

  Widget _buildSearchResultTile(PlaceSearchResult result) {
    final isAlreadySaved = _savedPlaces.any((sp) =>
        (result.placeId != null && sp.placeId == result.placeId) ||
        sp.place.name.trim().toLowerCase() == result.name.trim().toLowerCase());
    final resultKey = result.externalPlaceId ?? result.placeId ?? result.name;
    final isAdding = _resolvingResultIds.contains(resultKey);

    return ListTile(
      dense: true,
      title: Text(result.name, style: AppTextStyles.cardTitle),
      subtitle: Text(
        [
          result.category,
          if (result.distanceMeters != null)
            '${(result.distanceMeters! / 1000).toStringAsFixed(1)} km away',
          if (result.address != null && result.address!.isNotEmpty)
            result.address!,
        ].join(' · '),
        style: AppTextStyles.caption,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isAlreadySaved
          ? const Tooltip(
              message: 'Already in trip',
              child: Icon(Icons.check_circle_rounded, color: AppColors.success),
            )
          : isAdding
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.tonal(
                  key: ValueKey('add-search-result-${result.placeId ?? result.externalPlaceId ?? result.name}'),
                  onPressed: _tripId == null ? null : () => _addManualPlace(result),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Add to trip'),
                ),
    );
  }

  Future<void> _editSavedPlace(SavedPlace savedPlace) async {
    var draftNotes = savedPlace.notes ?? '';
    var priority = savedPlace.priority;
    var isLocked = savedPlace.isLocked;
    var mustVisit = savedPlace.mustVisit;
    final settings =
        await showDialog<
          ({String notes, int priority, bool isLocked, bool mustVisit})
        >(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text('Customize ${savedPlace.place.name}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      initialValue: draftNotes,
                      autofocus: true,
                      maxLength: 1000,
                      maxLines: 3,
                      onChanged: (value) => draftNotes = value,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        hintText: 'Opening hours, must-try food, or a reminder',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Priority $priority', style: AppTextStyles.label),
                    Slider(
                      value: priority.toDouble(),
                      min: 0,
                      max: 10,
                      divisions: 10,
                      label: '$priority',
                      onChanged: (value) =>
                          setDialogState(() => priority = value.round()),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Must visit'),
                      subtitle: const Text(
                        'Keep this place in the final route',
                      ),
                      value: mustVisit,
                      onChanged: (value) =>
                          setDialogState(() => mustVisit = value),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Lock this position'),
                      subtitle: Text(
                        'Keep it at position ${savedPlace.customOrder}',
                      ),
                      value: isLocked,
                      onChanged: (value) =>
                          setDialogState(() => isLocked = value),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop((
                    notes: draftNotes,
                    priority: priority,
                    isLocked: isLocked,
                    mustVisit: mustVisit,
                  )),
                  child: const Text('Save preferences'),
                ),
              ],
            ),
          ),
        );
    if (settings == null || !mounted || _tripId == null) return;

    setState(() {
      _mutatingPlaceIds.add(savedPlace.placeId);
      _routeError = null;
    });
    try {
      final updated = await _savedPlaceService.updateSettings(
        _tripId!,
        savedPlace.placeId,
        notes: settings.notes,
        priority: settings.priority,
        isLocked: settings.isLocked,
        mustVisit: settings.mustVisit,
        customOrder: savedPlace.customOrder,
      );
      if (!mounted) return;
      setState(() {
        _savedPlaces = [
          for (final item in _savedPlaces)
            if (item.placeId == updated.placeId) updated else item,
        ];
      });
      final constraintsChanged = settings.priority != savedPlace.priority ||
          settings.isLocked != savedPlace.isLocked ||
          settings.mustVisit != savedPlace.mustVisit;
      if (constraintsChanged) {
        await _checkReplanImpact();
      }
    } on Object catch (error) {
      if (!mounted) return;
      final message = _savedPlaceError(error);
      setState(() => _savedError = message);
      _showSavedMessage(message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _mutatingPlaceIds.remove(savedPlace.placeId));
      }
    }
  }

  Future<void> _reorderSavedPlaces(int oldIndex, int newIndex) async {
    final tripId = _tripId;
    if (tripId == null || _isReordering) return;
    if (newIndex == oldIndex) return;

    final previous = List<SavedPlace>.of(_savedPlaces);
    final reordered = List<SavedPlace>.of(_savedPlaces);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    setState(() {
      _savedPlaces = reordered;
      _isReordering = true;
      _savedError = null;
      _routeError = null;
    });

    try {
      final saved = await _savedPlaceService.reorderSavedPlaces(
        tripId,
        reordered.map((item) => item.placeId).toList(growable: false),
      );
      if (!mounted) return;
      setState(() => _savedPlaces = saved);
      await _checkReplanImpact();
    } on Object catch (error) {
      if (!mounted) return;
      final message = _savedPlaceError(error);
      try {
        final authoritative = await _savedPlaceService.getSavedPlaces(tripId);
        if (!mounted) return;
        setState(() {
          _savedPlaces = authoritative;
          _savedError = message;
        });
      } on Object {
        if (!mounted) return;
        setState(() {
          _savedPlaces = previous;
          _savedError = message;
        });
      }
      _showSavedMessage(message, isError: true);
    } finally {
      if (mounted) setState(() => _isReordering = false);
    }
  }

  Future<void> _optimizeRoute() async {
    final tripId = _tripId;
    if (tripId == null || _savedPlaces.length < 2 || _isOptimizingRoute) {
      return;
    }
    setState(() {
      _isOptimizingRoute = true;
      _routeError = null;
    });
    try {
      final route = await _routeOptimizationService.optimizeRoute(tripId);
      if (!mounted) return;
      setState(() {
        _optimizedRoute = route;
        _replanImpact = null;
      });
      _loadWeatherAdvisories();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _routeError = _routeOptimizationError(error));
    } finally {
      if (mounted) setState(() => _isOptimizingRoute = false);
    }
  }

  String _routeOptimizationError(Object error) {
    if (error is TimeoutException) {
      return 'Route optimization took too long. Please try again.';
    }
    if (error is RouteOptimizationServiceException) return error.message;
    return 'Could not optimize this route. Please try again.';
  }

  String _savedPlaceError(Object error) {
    if (error is TimeoutException) {
      return 'Saving places took too long. Please try again.';
    }
    if (error is SavedPlaceServiceException) return error.message;
    return 'Could not update your selected places.';
  }

  void _showSavedMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.charcoal,
      ),
    );
  }

  String _friendlyError(Object error) {
    if (error is TimeoutException) {
      return 'Place data took longer than expected. Your trip choices are safe—try again.';
    }
    if (error is RecommendationServiceException) return error.message;
    return 'Could not load nearby places. Check your connection and try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover places')),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _hasRequested ? _loadRecommendations : () async {},
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _CityContext(city: widget.city),
              const SizedBox(height: 22),
              _buildSavedPlacesSection(),
              const SizedBox(height: 24),
              if (_purposeCategories.isNotEmpty) ...[
                Text(
                  'Recommended for your trip',
                  style: AppTextStyles.sectionTitle,
                ),
                const SizedBox(height: 6),
                Text(
                  'Based on why you chose to visit ${widget.city.name}.',
                  style: AppTextStyles.bodyMuted,
                ),
                const SizedBox(height: 12),
                _TripPreferenceContext(purposes: widget.tripPurposes),
              ] else ...[
                Text(
                  'Choose what you’d like to see',
                  style: AppTextStyles.sectionTitle,
                ),
                const SizedBox(height: 6),
                Text(
                  'Select one or more interests for ${widget.city.name}.',
                  style: AppTextStyles.bodyMuted,
                ),
              ],
              if (_purposeCategories.length < PlaceCategory.values.length) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => setState(
                            () => _showRefinements = !_showRefinements,
                          ),
                    icon: Icon(
                      _showRefinements
                          ? Icons.expand_less_rounded
                          : Icons.tune_rounded,
                    ),
                    label: Text(
                      _showRefinements
                          ? 'Hide extra interests'
                          : _refinementCategories.isEmpty
                          ? 'Add another interest'
                          : '${_refinementCategories.length} extra ${_refinementCategories.length == 1 ? 'interest' : 'interests'}',
                    ),
                  ),
                ),
              ],
              if (_showRefinements) ...[
                const SizedBox(height: 4),
                _RefinementPanel(
                  categories: PlaceCategory.values
                      .where(
                        (category) => !_purposeCategories.contains(category),
                      )
                      .toList(growable: false),
                  selectedCategories: _refinementCategories,
                  enabled: !_isLoading,
                  onToggle: _toggleCategory,
                  onApply:
                      _effectiveCategories.isEmpty ||
                          _isLoading ||
                          (_hasRequested && !_refinementsDirty)
                      ? null
                      : _loadRecommendations,
                  applyLabel: _hasRequested
                      ? 'Update recommendations'
                      : 'Show matching places',
                ),
              ],
              if (_hasRequested && _effectiveCategories.length > 1) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CategoryFilterChip(
                      label: 'All',
                      selected: _activeCategoryFilter == null,
                      enabled: !_isLoading,
                      onSelected: () => _setCategoryFilter(null),
                    ),
                    for (final cat in _effectiveCategories)
                      _CategoryFilterChip(
                        key: ValueKey('filter_${cat.apiValue}'),
                        label: cat.label,
                        selected: _activeCategoryFilter == cat,
                        enabled: !_isLoading,
                        onSelected: () => _setCategoryFilter(cat),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _buildResults(),
              ),
              const SizedBox(height: 12),
              Text(
                'Place data © OpenStreetMap contributors • ODbL\n'
                'https://www.openstreetmap.org/copyright',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSavedPlacesSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Selected places',
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              if (_tripId != null)
                Text(
                  '${_savedPlaces.length} saved',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _tripId == null
                ? 'Recommendations are available now; saving unlocks after the trip has a UUID.'
                : 'Changes save automatically. Drag the handle to reorder.',
            style: AppTextStyles.bodyMuted,
          ),
          const SizedBox(height: 16),
          if (!_isSearchOpen)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('open-place-search-button'),
                onPressed: () => setState(() => _isSearchOpen = true),
                icon: const Icon(Icons.search_rounded),
                label: const Text('Search another place'),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('manual-place-search-field'),
                    controller: _searchController,
                    autofocus: true,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search places in ${widget.city.name}…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearchChanged('');
                                  },
                                )
                              : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const ValueKey('close-place-search-button'),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close search',
                  onPressed: () {
                    setState(() {
                      _isSearchOpen = false;
                      _searchController.clear();
                      _searchResults = const [];
                      _searchError = null;
                      _isSearching = false;
                    });
                  },
                ),
              ],
            ),
            if (_searchError != null) ...[
              const SizedBox(height: 8),
              Text(
                _searchError!,
                style: AppTextStyles.caption.copyWith(color: AppColors.error),
              ),
            ],
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < _searchResults.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _buildSearchResultTile(_searchResults[i]),
                    ],
                  ],
                ),
              ),
            ] else if (_searchController.text.trim().isNotEmpty && !_isSearching) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'No matching places found near ${widget.city.name}.',
                  style: AppTextStyles.caption,
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          if (_tripId == null)
            const _PersistenceNotice()
          else if (_isLoadingSavedPlaces && _savedPlaces.isEmpty)
            const LinearProgressIndicator(minHeight: 3)
          else if (_savedError != null && _savedPlaces.isEmpty)
            _InlineSavedError(message: _savedError!, onRetry: _loadSavedPlaces)
          else if (_savedPlaces.isEmpty)
            const _EmptySavedPlaces()
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _savedPlaces.length,
              onReorderItem: _reorderSavedPlaces,
              proxyDecorator: (child, _, animation) => AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, child) => Material(
                  color: Colors.transparent,
                  elevation: 3 * animation.value,
                  borderRadius: BorderRadius.circular(16),
                  child: child,
                ),
              ),
              itemBuilder: (context, index) {
                final savedPlace = _savedPlaces[index];
                return Padding(
                  key: ValueKey(savedPlace.placeId),
                  padding: EdgeInsets.only(
                    bottom: index == _savedPlaces.length - 1 ? 0 : 9,
                  ),
                  child: _SavedPlaceTile(
                    savedPlace: savedPlace,
                    index: index,
                    busy: _mutatingPlaceIds.contains(savedPlace.placeId),
                    dragEnabled: !_isReordering,
                    onNotes: () => _editSavedPlace(savedPlace),
                    onRemove: () => _removeSavedPlace(savedPlace),
                  ),
                );
              },
            ),
          if (_tripId != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    _savedPlaces.length < 2 ||
                        widget.routeStartReady == false ||
                        _isLoadingSavedPlaces ||
                        _isReordering ||
                        _mutatingPlaceIds.isNotEmpty ||
                        _isOptimizingRoute
                    ? null
                    : _optimizeRoute,
                icon: _isOptimizingRoute
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.alt_route_rounded),
                label: Text(
                  _isOptimizingRoute ? 'Optimizing…' : 'Optimize Route',
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Route order uses offline distance estimates; times are approximate.',
              style: AppTextStyles.caption,
            ),
            if (_savedPlaces.length < 2) ...[
              const SizedBox(height: 7),
              Text(
                'Add at least 2 places to calculate a practical route.',
                style: AppTextStyles.caption,
              ),
            ],
            if (widget.routeStartReady == false) ...[
              const SizedBox(height: 7),
              Text(
                'Choose a precise trip start location before optimizing.',
                style: AppTextStyles.caption.copyWith(color: AppColors.error),
              ),
            ],
            if (_routeError case final routeError?) ...[
              const SizedBox(height: 10),
              _RouteError(message: routeError, onRetry: _optimizeRoute),
            ],
            if (_weatherAdvisories.isNotEmpty && _tripId != null) ...[
              for (final advisory in _weatherAdvisories)
                if (!_dismissedAdvisoryIds.contains(advisory.id)) ...[
                  const SizedBox(height: 12),
                  WeatherAdvisoryCard(
                    tripId: _tripId!,
                    advisory: advisory,
                    weatherService: _weatherAdvisoryService,
                    onDismiss: () {
                      setState(() {
                        _dismissedAdvisoryIds.add(advisory.id);
                      });
                    },
                    onApplied: () {
                      _loadSavedPlaces();
                      _optimizeRoute();
                      _loadWeatherAdvisories();
                    },
                  ),
                ],
            ],
            if (_replanImpact case final impact?) ...[
              const SizedBox(height: 12),
              _ReplanAdvisoryCard(
                impact: impact,
                isLoading: _isLoadingReplanPreview,
                onReview: _showReplanPreviewDialog,
                onDismiss: () => setState(() => _replanImpact = null),
              ),
            ],
            if (_optimizedRoute case final route?) ...[
              const SizedBox(height: 12),
              _OptimizedRouteCard(route: route),
            ],
            const SizedBox(height: 12),
            if (_tripId != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TripMapScreen(
                          tripId: _tripId!,
                          initialStartLocation: widget.startLocation,
                          initialSavedPlaces: _savedPlaces,
                          initialOptimizedRoute: _optimizedRoute,
                          initialRouteGeometry: _optimizedRoute?.routeGeometry,
                          initialDurationDays: widget.durationDays ?? _optimizedRoute?.totalDays,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map_rounded),
                  label: const Text('Open Interactive Map'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading && _recommendations.isEmpty) {
      final categoryCount = _effectiveCategories.length;
      return _DiscoveryStatus(
        key: const ValueKey('loading-recommendations'),
        icon: Icons.radar_rounded,
        title: 'Ranking places for your trip',
        message:
            'Checking $categoryCount ${categoryCount == 1 ? 'interest' : 'interests'}, saved results, and nearby places…',
        showProgress: true,
      );
    }
    if (_error case final error?) {
      if (_recommendations.isEmpty) {
        return _DiscoveryError(
          key: const ValueKey('error'),
          message: error,
          onRetry: _loadRecommendations,
        );
      }
    }
    if (!_hasRequested) {
      return const _DiscoveryStatus(
        key: ValueKey('choose-interests'),
        icon: Icons.tune_rounded,
        title: 'Build your recommendation mix',
        message:
            'Choose interests, then ask YatraCanvas to rank nearby places.',
      );
    }
    if (_recommendations.isEmpty) {
      return const _DiscoveryStatus(
        key: ValueKey('empty-recommendations'),
        icon: Icons.explore_off_outlined,
        title: 'No matching places found',
        message: 'Try a different interest mix or pull down to check again.',
      );
    }

    return Column(
      key: const ValueKey('ranked-recommendations'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isLoading) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.tealLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.teal,
                  ),
                ),
                SizedBox(width: 8),
                Text('Updating nearby places…', style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                '${_recommendations.length} ranked ${_recommendations.length == 1 ? 'place' : 'places'}',
                style: AppTextStyles.sectionTitle,
              ),
            ),
            const Icon(
              Icons.swipe_down_rounded,
              size: 18,
              color: AppColors.textTertiary,
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (var index = 0; index < _recommendations.length; index++) ...[
          Builder(
            builder: (context) {
              final recommendation = _recommendations[index];
              final selected =
                  recommendation.isSaved || _savedPlaceFor(recommendation.id) != null;
              final busy = _mutatingPlaceIds.contains(recommendation.id);
              return PlaceCard(
                name: recommendation.name,
                category: _categoryLabel(recommendation.category),
                description: _matchDescription(recommendation),
                meta: _recommendationMeta(recommendation),
                selected: selected,
                actionLabel: _tripId == null
                    ? 'Save trip first'
                    : selected
                    ? 'Remove'
                    : 'Add',
                actionIcon: selected
                    ? Icons.remove_circle_outline_rounded
                    : Icons.add_circle_outline_rounded,
                actionBusy: busy,
                onAction: _tripId == null || busy
                    ? null
                    : () => _toggleSavedPlace(recommendation),
              );
            },
          ),
          if (index != _recommendations.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  String _matchDescription(Recommendation recommendation) {
    if (recommendation.recommendationReason != null &&
        recommendation.recommendationReason!.isNotEmpty) {
      return recommendation.recommendationReason!;
    }
    final matches = recommendation.matchedCategories
        .map((category) => category.label)
        .join(' + ');
    return 'Matches $matches';
  }

  String _recommendationMeta(Recommendation recommendation) {
    final reviews =
        '${recommendation.reviewCount} ${recommendation.reviewCount == 1 ? 'review' : 'reviews'}';
    final score =
        'Score ${recommendation.recommendationScore.toStringAsFixed(1)}';
    if (recommendation.rating == null) return '$reviews  ·  $score';
    return '★ ${recommendation.rating!.toStringAsFixed(1)}  ·  $reviews  ·  $score';
  }

  String _categoryLabel(String category) {
    try {
      return PlaceCategory.values.byName(category).label;
    } on ArgumentError {
      return category;
    }
  }
}

class _RefinementPanel extends StatelessWidget {
  const _RefinementPanel({
    required this.categories,
    required this.selectedCategories,
    required this.enabled,
    required this.onToggle,
    required this.onApply,
    required this.applyLabel,
  });

  final List<PlaceCategory> categories;
  final Set<PlaceCategory> selectedCategories;
  final bool enabled;
  final ValueChanged<PlaceCategory> onToggle;
  final VoidCallback? onApply;
  final String applyLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Optional extras', style: AppTextStyles.label),
          const SizedBox(height: 4),
          Text(
            'Add interests beyond the reasons from your trip setup.',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 9,
            runSpacing: 10,
            children: [
              for (final category in categories)
                SelectionChip(
                  label: category.label,
                  icon: _categoryIcon(category),
                  selected: selectedCategories.contains(category),
                  enabled: enabled,
                  onSelected: (_) => onToggle(category),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onApply,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(applyLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripPreferenceContext extends StatelessWidget {
  const _TripPreferenceContext({required this.purposes});

  final Set<String> purposes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tealLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.teal.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.teal,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From your trip setup',
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.tealDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  purposes.join(' • '),
                  style: AppTextStyles.bodyMuted.copyWith(
                    color: AppColors.tealDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CityContext extends StatelessWidget {
  const _CityContext({required this.city});

  final City city;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppColors.tealLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.explore_rounded, color: AppColors.teal),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EXPLORING',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.tealDark,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .7,
                  ),
                ),
                const SizedBox(height: 4),
                Text(city.name, style: AppTextStyles.sectionTitle),
                const SizedBox(height: 2),
                Text(city.locationLabel, style: AppTextStyles.bodyMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedPlaceTile extends StatelessWidget {
  const _SavedPlaceTile({
    required this.savedPlace,
    required this.index,
    required this.busy,
    required this.dragEnabled,
    required this.onNotes,
    required this.onRemove,
  });

  final SavedPlace savedPlace;
  final int index;
  final bool busy;
  final bool dragEnabled;
  final VoidCallback onNotes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08142033),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: AppColors.tealGradient,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: AppTextStyles.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  savedPlace.place.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.label,
                ),
                if (savedPlace.notes case final notes?) ...[
                  const SizedBox(height: 2),
                  Text(
                    notes,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption,
                  ),
                ],
                if (savedPlace.priority > 0 ||
                    savedPlace.isLocked ||
                    savedPlace.mustVisit) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      if (savedPlace.priority > 0)
                        _PreferenceBadge(
                          label: 'Priority ${savedPlace.priority}',
                        ),
                      if (savedPlace.mustVisit)
                        const _PreferenceBadge(label: 'Must visit'),
                      if (savedPlace.isLocked)
                        const _PreferenceBadge(label: 'Locked'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: savedPlace.notes == null
                ? 'Add notes'
                : 'Edit notes and preferences',
            onPressed: busy ? null : onNotes,
            icon: const Icon(Icons.tune_rounded, size: 20),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: 'Remove place',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ReorderableDragStartListener(
            index: index,
            enabled: dragEnabled && !busy,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.drag_handle_rounded,
                color: dragEnabled
                    ? AppColors.textSecondary
                    : AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceBadge extends StatelessWidget {
  const _PreferenceBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.tealLight,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.tealDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OptimizedRouteCard extends StatelessWidget {
  const _OptimizedRouteCard({required this.route});

  final OptimizedRoute route;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.tealLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.teal.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_rounded, color: AppColors.teal, size: 22),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Optimized route',
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.tealDark,
                  ),
                ),
              ),
              Text(
                '${_formatDistance(route.totalDistance)} · ${route.totalTravelTimeMinutes} min',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.tealDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (route.conflicts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Planning Advisory',
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final conflict in route.conflicts)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '• $conflict',
                        style: AppTextStyles.caption.copyWith(color: AppColors.charcoal),
                      ),
                    ),
                ],
              ),
            ),
          ],
          for (var dayIndex = 0; dayIndex < route.logicalDays.length; dayIndex++) ...[
            if (dayIndex > 0) const SizedBox(height: 16),
            _buildDaySchedule(
              route.logicalDays[dayIndex],
              route.placesByDay[route.logicalDays[dayIndex]] ?? const <OptimizedRoutePlace>[],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.access_time_rounded, size: 13, color: AppColors.textTertiary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Timings are planning estimates based on category heuristics and route durations.',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDaySchedule(int day, List<OptimizedRoutePlace> dayPlaces) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.wb_sunny_rounded,
              color: AppColors.teal,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              'Day $day',
              style: AppTextStyles.label.copyWith(
                color: AppColors.tealDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (dayPlaces.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No places scheduled yet. Add a place or optimize your itinerary.',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          )
        else
          for (var placeIdx = 0; placeIdx < dayPlaces.length; placeIdx++) ...[
            _RouteConnector(
              place: dayPlaces[placeIdx],
              fromArrival: placeIdx == 0,
            ),
            const SizedBox(height: 7),
            _RouteStop(place: dayPlaces[placeIdx]),
            for (final b in route.breaks.where(
              (brk) =>
                  brk.dayNumber == day &&
                  (placeIdx < dayPlaces.length - 1 &&
                      dayPlaces[placeIdx].plannedDepartureTime != null &&
                      dayPlaces[placeIdx + 1].plannedArrivalTime != null &&
                      brk.startTime.compareTo(dayPlaces[placeIdx].plannedDepartureTime!) >= 0 &&
                      brk.endTime.compareTo(dayPlaces[placeIdx + 1].plannedArrivalTime!) <= 0),
            ))
              _MiddayBreakCard(breakItem: b),
          ],
      ],
    );
  }
}

class _MiddayBreakCard extends StatelessWidget {
  const _MiddayBreakCard({required this.breakItem});

  final ItineraryBreak breakItem;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textTertiary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 34,
            child: Icon(Icons.coffee_rounded, color: AppColors.textSecondary, size: 18),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  breakItem.label,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.charcoal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${breakItem.formattedTimeWindow} · ${breakItem.durationMinutes} min rest & meals',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteConnector extends StatelessWidget {
  const _RouteConnector({required this.place, required this.fromArrival});

  final OptimizedRoutePlace place;
  final bool fromArrival;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Icon(
            fromArrival ? Icons.trip_origin_rounded : Icons.south_rounded,
            size: fromArrival ? 16 : 18,
            color: AppColors.teal,
          ),
        ),
        Expanded(
          child: Text(
            '${fromArrival ? 'From arrival · ' : ''}${_formatDistance(place.distanceFromPrevious)} · ${place.travelTimeMinutes} min',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _RouteStop extends StatelessWidget {
  const _RouteStop({required this.place});

  final OptimizedRoutePlace place;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.teal,
            shape: BoxShape.circle,
          ),
          child: Text(
            '${place.visitOrder}',
            style: AppTextStyles.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                place.name,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.charcoal,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (place.formattedTimeWindow != null) ...[
                const SizedBox(height: 2),
                Text(
                  '${place.formattedTimeWindow} · ~${place.visitDurationMinutes} min visit',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.tealDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteError extends StatelessWidget {
  const _RouteError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.route_outlined, color: AppColors.error, size: 20),
          const SizedBox(width: 9),
          Expanded(child: Text(message, style: AppTextStyles.caption)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

String _formatDistance(double distanceKm) {
  if (distanceKm < 10) return '${distanceKm.toStringAsFixed(1)} km';
  return '${distanceKm.toStringAsFixed(0)} km';
}

class _PersistenceNotice extends StatelessWidget {
  const _PersistenceNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.canvasPeach,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.teal, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Create or load the trip first to add and reorder places.',
              style: AppTextStyles.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySavedPlaces extends StatelessWidget {
  const _EmptySavedPlaces();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.playlist_add_rounded, color: AppColors.teal),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Add recommendations below to build your custom place list.',
              style: AppTextStyles.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineSavedError extends StatelessWidget {
  const _InlineSavedError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.error),
        const SizedBox(width: 9),
        Expanded(child: Text(message, style: AppTextStyles.caption)),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

class _DiscoveryStatus extends StatelessWidget {
  const _DiscoveryStatus({
    required this.icon,
    required this.title,
    required this.message,
    this.showProgress = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.teal, size: 28),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.cardTitle,
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMuted,
          ),
          if (showProgress) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
    );
  }
}

class _DiscoveryError extends StatelessWidget {
  const _DiscoveryError({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.error.withValues(alpha: .35)),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.error, size: 28),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMuted,
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

IconData _categoryIcon(PlaceCategory category) => switch (category) {
  PlaceCategory.religious => Icons.temple_hindu_rounded,
  PlaceCategory.food => Icons.restaurant_rounded,
  PlaceCategory.tourism => Icons.photo_camera_outlined,
  PlaceCategory.cafes => Icons.local_cafe_rounded,
  PlaceCategory.heritage => Icons.account_balance_rounded,
};

class _ReplanAdvisoryCard extends StatelessWidget {
  const _ReplanAdvisoryCard({
    required this.impact,
    required this.onReview,
    required this.onDismiss,
    this.isLoading = false,
  });

  final TripReplanImpact impact;
  final VoidCallback onReview;
  final VoidCallback onDismiss;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_fix_high_rounded, color: Colors.amber.shade900, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Trip Changes Detected',
                  style: AppTextStyles.label.copyWith(
                    color: Colors.amber.shade900,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            impact.summary,
            style: AppTextStyles.caption.copyWith(color: AppColors.charcoal),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: isLoading ? null : onReview,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Review proposed plan'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Keep current plan'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryFilterChip extends StatelessWidget {
  const _CategoryFilterChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    super.key,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onSelected : null,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.tealLight : AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.teal : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: enabled
                  ? (selected ? AppColors.tealDark : AppColors.charcoal)
                  : AppColors.textTertiary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
