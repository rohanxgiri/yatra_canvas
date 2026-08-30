import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/city.dart';
import '../../models/optimized_route.dart';
import '../../models/place.dart';
import '../../models/recommendation.dart';
import '../../models/saved_place.dart';
import '../../services/recommendation_service.dart';
import '../../services/route_optimization_service.dart';
import '../../services/saved_place_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/place_card.dart';
import '../../widgets/selection_chip.dart';

class PlaceDiscoveryScreen extends StatefulWidget {
  const PlaceDiscoveryScreen({
    required this.city,
    this.tripId,
    this.recommendationService,
    this.savedPlaceService,
    this.routeOptimizationService,
    super.key,
  });

  final City city;
  final String? tripId;
  final RecommendationService? recommendationService;
  final SavedPlaceService? savedPlaceService;
  final RouteOptimizationService? routeOptimizationService;

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

  final Set<PlaceCategory> _selectedCategories = {PlaceCategory.religious};
  List<Recommendation> _recommendations = const [];
  List<SavedPlace> _savedPlaces = const [];
  OptimizedRoute? _optimizedRoute;
  final Set<String> _mutatingPlaceIds = {};
  String? _error;
  String? _savedError;
  String? _routeError;
  bool _isLoading = false;
  bool _isLoadingSavedPlaces = false;
  bool _isReordering = false;
  bool _isOptimizingRoute = false;
  bool _hasRequested = false;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _ownsRecommendationService = widget.recommendationService == null;
    _recommendationService =
        widget.recommendationService ?? RecommendationService();
    _ownsSavedPlaceService = widget.savedPlaceService == null;
    _savedPlaceService = widget.savedPlaceService ?? SavedPlaceService();
    _ownsRouteOptimizationService = widget.routeOptimizationService == null;
    _routeOptimizationService =
        widget.routeOptimizationService ?? RouteOptimizationService();
    if (_tripId != null) _loadSavedPlaces();
  }

  @override
  void dispose() {
    if (_ownsRecommendationService) _recommendationService.close();
    if (_ownsSavedPlaceService) _savedPlaceService.close();
    if (_ownsRouteOptimizationService) _routeOptimizationService.close();
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
        .where(_selectedCategories.contains)
        .toList(growable: false);
    setState(() {
      _isLoading = true;
      _hasRequested = true;
      _error = null;
    });

    try {
      final recommendations = await _recommendationService.getRecommendations(
        cityId,
        categories,
      );
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _recommendations = recommendations;
        _isLoading = false;
      });
    } on Object catch (error) {
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _recommendations = const [];
        _isLoading = false;
        _error = _friendlyError(error);
      });
    }
  }

  void _toggleCategory(PlaceCategory category) {
    setState(() {
      if (_selectedCategories.contains(category)) {
        _selectedCategories.remove(category);
      } else {
        _selectedCategories.add(category);
      }
      _recommendations = const [];
      _hasRequested = false;
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
      _optimizedRoute = null;
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
        });
        _showSavedMessage('${recommendation.name} added to your trip.');
      } else {
        await _savedPlaceService.removeSavedPlace(tripId, recommendation.id);
        if (!mounted) return;
        await _loadSavedPlaces();
        if (!mounted) return;
        _showSavedMessage('${recommendation.name} removed from your trip.');
      }
    } on Object catch (error) {
      if (!mounted) return;
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
      _optimizedRoute = null;
      _routeError = null;
    });
    try {
      await _savedPlaceService.removeSavedPlace(tripId, savedPlace.placeId);
      if (!mounted) return;
      await _loadSavedPlaces();
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
      _optimizedRoute = null;
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
      _optimizedRoute = null;
      _routeError = null;
    });

    try {
      final saved = await _savedPlaceService.reorderSavedPlaces(
        tripId,
        reordered.map((item) => item.placeId).toList(growable: false),
      );
      if (!mounted) return;
      setState(() => _savedPlaces = saved);
    } on Object catch (error) {
      if (!mounted) return;
      final message = _savedPlaceError(error);
      setState(() {
        _savedPlaces = previous;
        _savedError = message;
      });
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
      setState(() => _optimizedRoute = route);
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
      return 'Place discovery took too long. Check FastAPI and try again.';
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
              const SizedBox(height: 26),
              Text('Choose your interests', style: AppTextStyles.sectionTitle),
              const SizedBox(height: 6),
              Text(
                'Select one or more categories for ${widget.city.name}.',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 9,
                runSpacing: 10,
                children: [
                  for (final category in PlaceCategory.values)
                    SelectionChip(
                      label: category.label,
                      icon: _categoryIcon(category),
                      selected: _selectedCategories.contains(category),
                      enabled: !_isLoading,
                      onSelected: (_) => _toggleCategory(category),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selectedCategories.isEmpty || _isLoading
                      ? null
                      : _loadRecommendations,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Get Recommendations'),
                ),
              ),
              const SizedBox(height: 24),
              _buildSavedPlacesSection(),
              const SizedBox(height: 28),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _buildResults(),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
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
          const SizedBox(height: 14),
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
            if (_savedPlaces.length < 2) ...[
              const SizedBox(height: 7),
              Text(
                'Add at least 2 places to calculate a practical route.',
                style: AppTextStyles.caption,
              ),
            ],
            if (_routeError case final routeError?) ...[
              const SizedBox(height: 10),
              _RouteError(message: routeError, onRetry: _optimizeRoute),
            ],
            if (_optimizedRoute case final route?) ...[
              const SizedBox(height: 12),
              _OptimizedRouteCard(route: route),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.search_rounded),
                label: const Text('Search another place — coming later'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading) {
      return _DiscoveryStatus(
        key: const ValueKey('loading-recommendations'),
        icon: Icons.radar_rounded,
        title: 'Ranking places for your trip',
        message:
            'Checking ${_selectedCategories.length} ${_selectedCategories.length == 1 ? 'category' : 'categories'}, saved results, and nearby places…',
        showProgress: true,
      );
    }
    if (_error case final error?) {
      return _DiscoveryError(
        key: const ValueKey('error'),
        message: error,
        onRetry: _loadRecommendations,
      );
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
              final selected = _savedPlaceFor(recommendation.id) != null;
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
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.teal,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
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
          const SizedBox(height: 14),
          for (var index = 0; index < route.places.length; index++) ...[
            _RouteConnector(
              place: route.places[index],
              fromArrival: index == 0,
            ),
            const SizedBox(height: 7),
            _RouteStop(place: route.places[index]),
          ],
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
          child: Text(
            place.name,
            style: AppTextStyles.label.copyWith(color: AppColors.charcoal),
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
