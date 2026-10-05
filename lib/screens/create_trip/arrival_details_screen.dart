import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/trip_draft.dart';
import '../../models/trip_start_location.dart';
import '../../services/device_location_service.dart';
import '../../services/location_service.dart';
import '../../services/place_prefetch_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/yc_motion.dart';
import '../../widgets/create_trip_scaffold.dart';
import '../../widgets/yc_pressable.dart';
import 'trip_purpose_screen.dart';
import 'start_point_picker.dart';

class ArrivalDetailsScreen extends StatefulWidget {
  const ArrivalDetailsScreen({
    required this.draft,
    this.locationService,
    this.tripService,
    this.deviceLocationService,
    this.prefetchService,
    super.key,
  });

  final TripDraft draft;
  final LocationService? locationService;
  final TripService? tripService;
  final DeviceLocationService? deviceLocationService;
  final PlacePrefetchService? prefetchService;

  @override
  State<ArrivalDetailsScreen> createState() => _ArrivalDetailsScreenState();
}

class _ArrivalDetailsScreenState extends State<ArrivalDetailsScreen> {
  late String _method;
  late String _arrivalPoint;
  double? _arrivalLatitude;
  double? _arrivalLongitude;
  late TimeOfDay _arrivalTime;
  late final TextEditingController _pointController;
  late final TextEditingController _startSearchController;
  final _pointFocus = FocusNode();
  late final LocationService _locationService;
  late final TripService _tripService;
  late final DeviceLocationService _deviceLocationService;
  late final bool _ownsLocationService;
  late final bool _ownsTripService;
  Timer? _searchDebounce;
  Timer? _arrivalSearchDebounce;
  late TripStartLocationType _startType;
  String? _startName;
  double? _startLatitude;
  double? _startLongitude;
  String? _startProvider;
  String? _startProviderPlaceId;
  List<LocationSuggestion> _locationSuggestions = const [];
  List<LocationSuggestion> _arrivalSuggestions = const [];
  String? _arrivalError;
  String? _startError;
  bool _isSearchingLocation = false;
  bool _isSearchingArrival = false;
  bool _hasSearchedArrival = false;
  bool _isResolvingLocation = false;
  bool _isGettingCurrentLocation = false;
  bool _isSavingStart = false;
  bool _suppressStartSearch = false;
  bool _suppressArrivalSearch = false;
  int _searchRevision = 0;
  int _arrivalSearchRevision = 0;
  String? _lastArrivalQuery;

  static const _methods = <(String, IconData)>[
    ('Train', Icons.train_rounded),
    ('Flight', Icons.flight_rounded),
    ('Bus', Icons.directions_bus_rounded),
    ('Car', Icons.directions_car_rounded),
    ('Other', Icons.more_horiz_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _method = widget.draft.arrivalMethod;
    _arrivalPoint = widget.draft.arrivalPoint;
    _arrivalLatitude = widget.draft.arrivalLatitude;
    _arrivalLongitude = widget.draft.arrivalLongitude;
    _arrivalTime = TimeOfDay(
      hour: widget.draft.arrivalTime.hour,
      minute: widget.draft.arrivalTime.minute,
    );
    _pointController = TextEditingController(text: _arrivalPoint);
    _startSearchController = TextEditingController();
    _startType = widget.draft.startLocationType;
    _startName =
        widget.draft.startLocationName ??
        (_startType == TripStartLocationType.arrival ? _arrivalPoint : null);
    _startLatitude =
        widget.draft.startLatitude ??
        (_startType == TripStartLocationType.arrival ? _arrivalLatitude : null);
    _startLongitude =
        widget.draft.startLongitude ??
        (_startType == TripStartLocationType.arrival
            ? _arrivalLongitude
            : null);
    _startProvider = widget.draft.startLocationProvider;
    _startProviderPlaceId = widget.draft.startLocationProviderPlaceId;
    _ownsLocationService = widget.locationService == null;
    _locationService = widget.locationService ?? LocationService();
    _ownsTripService = widget.tripService == null;
    _tripService = widget.tripService ?? TripService();
    _deviceLocationService =
        widget.deviceLocationService ?? DeviceLocationService();
    _pointController.addListener(_refreshPoint);
    _startSearchController.addListener(_onStartSearchChanged);
    _pointFocus.addListener(_refresh);
    unawaited(_loadBundledStarts());
  }

  @override
  void dispose() {
    _pointController
      ..removeListener(_refreshPoint)
      ..dispose();
    _startSearchController
      ..removeListener(_onStartSearchChanged)
      ..dispose();
    _searchDebounce?.cancel();
    _arrivalSearchDebounce?.cancel();
    if (_ownsLocationService) _locationService.close();
    if (_ownsTripService) _tripService.close();
    _pointFocus
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<void> _loadBundledStarts() async {
    if (!await _locationService.hasOfflineCity(widget.draft.destination?.id) ||
        !mounted) {
      return;
    }
    if (_pointController.text.isEmpty &&
        _startType == TripStartLocationType.arrival) {
      await _searchArrivalPoint('', ++_arrivalSearchRevision);
    }
  }

  Future<void> _choosePoint() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final city = widget.draft.destination;
    final point = await Navigator.of(context).push<SelectedStartPoint>(
      MaterialPageRoute(
        builder: (_) => StartPointPicker(
          cityName: city?.name ?? 'your destination',
          latitude: city?.latitude ?? _startLatitude ?? 0,
          longitude: city?.longitude ?? _startLongitude ?? 0,
          cityId: city?.id,
          locationService: _locationService,
        ),
      ),
    );
    if (!mounted || point == null) return;
    setState(() {
      _startType = TripStartLocationType.custom;
      _startName = point.name;
      _startLatitude = point.latitude;
      _startLongitude = point.longitude;
      _startProvider = null;
      _startProviderPlaceId = null;
      _startError = null;
    });
  }

  void _refreshPoint() {
    final query = _pointController.text.trim();
    _arrivalSearchDebounce?.cancel();
    final revision = ++_arrivalSearchRevision;
    setState(() {
      _arrivalPoint = query;
      _arrivalError = null;
      _arrivalSuggestions = const [];
      _isSearchingArrival = false;
      _hasSearchedArrival = false;
      if (!_suppressArrivalSearch) {
        _arrivalLatitude = null;
        _arrivalLongitude = null;
      }
      if (_startType == TripStartLocationType.arrival) {
        _startName = _arrivalPoint;
        _startLatitude = _arrivalLatitude;
        _startLongitude = _arrivalLongitude;
        if (!_suppressArrivalSearch) {
          _startProvider = null;
          _startProviderPlaceId = null;
        }
      }
    });
    if (_suppressArrivalSearch) return;
    _arrivalSearchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _searchArrivalPoint(query, revision),
    );
  }

  Future<void> _searchArrivalPoint(String query, int revision) async {
    _lastArrivalQuery = query;
    setState(() {
      _isSearchingArrival = true;
      _arrivalError = null;
    });
    try {
      final suggestions = await _locationService.autocomplete(
        query,
        hotelOnly: false,
        locationKind: _method == 'Train'
            ? 'station'
            : _method == 'Flight'
            ? 'airport'
            : null,
        latitude: widget.draft.destination?.latitude,
        longitude: widget.draft.destination?.longitude,
        cityId: widget.draft.destination?.id,
      );
      if (!mounted ||
          revision != _arrivalSearchRevision ||
          query != _pointController.text.trim()) {
        return;
      }
      setState(() {
        _arrivalSuggestions = suggestions;
        _hasSearchedArrival = true;
      });
    } on Object catch (error) {
      if (!mounted || revision != _arrivalSearchRevision) return;
      setState(() => _arrivalError = _locationError(error));
    } finally {
      if (mounted && revision == _arrivalSearchRevision) {
        setState(() => _isSearchingArrival = false);
      }
    }
  }

  void _retryArrivalSearch() {
    final query = _lastArrivalQuery ?? _pointController.text.trim();
    final revision = ++_arrivalSearchRevision;
    _searchArrivalPoint(query, revision);
  }

  void _selectMethod(String method) {
    setState(() => _method = _method == method ? '' : method);
    if (_startType == TripStartLocationType.arrival &&
        _arrivalLatitude == null) {
      _suppressArrivalSearch = true;
      _pointController.clear();
      _suppressArrivalSearch = false;
      unawaited(_searchArrivalPoint('', ++_arrivalSearchRevision));
      final fieldContext = _pointFocus.context;
      if (fieldContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            fieldContext,
            alignment: .1,
            duration: const Duration(milliseconds: 250),
          ),
        );
      }
    }
  }

  void _selectPoint(LocationSuggestion suggestion) {
    _arrivalSearchRevision++;
    _suppressArrivalSearch = true;
    _pointController.text = suggestion.formattedAddress;
    _pointController.selection = TextSelection.collapsed(
      offset: suggestion.formattedAddress.length,
    );
    _suppressArrivalSearch = false;
    setState(() {
      _arrivalPoint = suggestion.formattedAddress;
      _arrivalLatitude = suggestion.latitude;
      _arrivalLongitude = suggestion.longitude;
      _arrivalSuggestions = const [];
      _arrivalError = null;
      _hasSearchedArrival = true;
      if (_startType == TripStartLocationType.arrival) {
        _startName = suggestion.formattedAddress;
        _startLatitude = suggestion.latitude;
        _startLongitude = suggestion.longitude;
        _startProvider = suggestion.provider;
        _startProviderPlaceId = suggestion.providerPlaceId;
      }
    });
    _pointFocus.unfocus();
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _arrivalTime,
      helpText: 'Approximate arrival time',
    );
    if (selected != null && mounted) setState(() => _arrivalTime = selected);
  }

  bool get _canContinue =>
      !_isSavingStart &&
      _startName?.trim().isNotEmpty == true &&
      _startLatitude != null &&
      _startLongitude != null &&
      _startLatitude!.isFinite &&
      _startLongitude!.isFinite &&
      _startLatitude!.abs() <= 90 &&
      _startLongitude!.abs() <= 180 &&
      !_isResolvingLocation &&
      !_isGettingCurrentLocation;

  void _selectStartType(TripStartLocationType type) {
    if (_startType == type) return;
    _searchRevision++;
    _searchDebounce?.cancel();
    _isGettingCurrentLocation = false;
    _isSearchingLocation = false;
    _suppressStartSearch = true;
    _startSearchController.clear();
    _suppressStartSearch = false;
    setState(() {
      _startType = type;
      _startError = null;
      _locationSuggestions = const [];
      if (type == TripStartLocationType.arrival) {
        _startName = _arrivalPoint;
        _startLatitude = _arrivalLatitude;
        _startLongitude = _arrivalLongitude;
        _startProvider = null;
        _startProviderPlaceId = null;
      } else {
        _startName = null;
        _startLatitude = null;
        _startLongitude = null;
        _startProvider = null;
        _startProviderPlaceId = null;
      }
    });
    if (type == TripStartLocationType.currentLocation) {
      _useCurrentLocation();
    } else if (type == TripStartLocationType.custom) {
      _choosePoint();
    } else if (type == TripStartLocationType.hotel) {
      unawaited(_searchStartPoint('', ++_searchRevision));
    } else if (type == TripStartLocationType.arrival) {
      unawaited(_loadBundledStarts());
    }
  }

  void _onStartSearchChanged() {
    if (_suppressStartSearch) return;
    _searchDebounce?.cancel();
    final revision = ++_searchRevision;
    final query = _startSearchController.text.trim();
    setState(() {
      // Editing after a selection makes the value raw text again. Coordinates
      // and provider identity return only when a suggestion is selected.
      _startName = null;
      _startLatitude = null;
      _startLongitude = null;
      _startProvider = null;
      _startProviderPlaceId = null;
      _locationSuggestions = const [];
      _isSearchingLocation = false;
    });
    if (_startType != TripStartLocationType.hotel &&
        _startType != TripStartLocationType.custom) {
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _searchStartPoint(query, revision),
    );
  }

  Future<void> _searchStartPoint(String query, int revision) async {
    setState(() {
      _isSearchingLocation = true;
      _startError = null;
    });
    try {
      final suggestions = await _locationService.autocomplete(
        query,
        hotelOnly: _startType == TripStartLocationType.hotel,
        latitude: widget.draft.destination?.latitude,
        longitude: widget.draft.destination?.longitude,
        cityId: widget.draft.destination?.id,
      );
      if (!mounted ||
          revision != _searchRevision ||
          query != _startSearchController.text.trim()) {
        return;
      }
      setState(() => _locationSuggestions = suggestions);
    } on Object catch (error) {
      if (!mounted || revision != _searchRevision) return;
      setState(() => _startError = _locationError(error));
    } finally {
      if (mounted && revision == _searchRevision) {
        setState(() => _isSearchingLocation = false);
      }
    }
  }

  void _selectLocationSuggestion(LocationSuggestion suggestion) {
    _searchRevision++;
    setState(() {
      _isResolvingLocation = false;
      _startError = null;
      _locationSuggestions = const [];
      _suppressStartSearch = true;
      _startSearchController.text = suggestion.formattedAddress;
      _suppressStartSearch = false;
      _startName = suggestion.formattedAddress;
      _startLatitude = suggestion.latitude;
      _startLongitude = suggestion.longitude;
      _startProvider = suggestion.provider;
      _startProviderPlaceId = suggestion.providerPlaceId;
    });
  }

  Future<void> _useCurrentLocation() async {
    final revision = ++_searchRevision;
    setState(() {
      _isGettingCurrentLocation = true;
      _startError = null;
    });
    try {
      final position = await _deviceLocationService.getCurrentPosition();
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _startName = 'Current location';
        _startLatitude = position.latitude;
        _startLongitude = position.longitude;
      });
    } on Object catch (error) {
      if (!mounted || revision != _searchRevision) return;
      setState(() => _startError = _locationError(error));
    } finally {
      if (mounted && revision == _searchRevision) {
        setState(() => _isGettingCurrentLocation = false);
      }
    }
  }

  String _locationError(Object error) {
    if (error is DeviceLocationException) return error.message;
    if (error is LocationServiceException) return error.message;
    if (error is TimeoutException) {
      return 'Location lookup timed out. Try again.';
    }
    return 'Could not select this start location.';
  }

  Future<void> _continue() async {
    if (!_canContinue) return;
    // The existing API requires arrival_place. With no separate arrival selected,
    // the user-confirmed origin supplies that field rather than an invented venue.
    widget.draft
      ..arrivalMethod = _method
      ..arrivalPoint = _startType == TripStartLocationType.arrival
          ? _arrivalPoint
          : _startName!
      ..arrivalLatitude = _startLatitude
      ..arrivalLongitude = _startLongitude
      ..arrivalTime = TimeOfDayValue(
        hour: _arrivalTime.hour,
        minute: _arrivalTime.minute,
      )
      ..startLocationType = _startType
      ..startLocationName = _startName
      ..startLatitude = _startLatitude
      ..startLongitude = _startLongitude;
    widget.draft
      ..startLocationProvider = _startProvider
      ..startLocationProviderPlaceId = _startProviderPlaceId;
    final cityId = widget.draft.destination?.id;
    if (cityId != null && cityId.isNotEmpty) {
      unawaited(
        (widget.prefetchService ?? PlacePrefetchService.shared).prefetchCity(
          cityId,
          stage: PrefetchStage.startLocationConfirmed,
          requestId: widget.draft.creationRequestId,
          startLatitude: _startLatitude,
          startLongitude: _startLongitude,
        ),
      );
    }
    final tripId = widget.draft.tripId?.trim();
    if (tripId != null && tripId.isNotEmpty) {
      setState(() {
        _isSavingStart = true;
        _startError = null;
      });
      try {
        final saved = await _tripService.updateStartLocation(
          tripId,
          type: _startType,
          name: _startName,
          latitude: _startLatitude,
          longitude: _startLongitude,
          provider: _startProvider,
          providerPlaceId: _startProviderPlaceId,
        );
        widget.draft
          ..startLocationName = saved.name
          ..startLatitude = saved.latitude
          ..startLongitude = saved.longitude;
        widget.draft
          ..startLocationProvider = saved.provider
          ..startLocationProviderPlaceId = saved.providerPlaceId;
      } on Object catch (error) {
        if (!mounted) return;
        setState(() {
          _startError = error is TripServiceException
              ? error.message
              : 'Could not save the trip start.';
          _isSavingStart = false;
        });
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripPurposeScreen(
          draft: widget.draft,
          tripService: widget.tripService,
          prefetchService: widget.prefetchService,
        ),
      ),
    );
  }

  Widget _buildStartLocationDetails() {
    if (_startType == TripStartLocationType.custom) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _choosePoint,
            icon: const Icon(Icons.map_outlined),
            label: const Text('Choose a point or enter coordinates'),
          ),
          if (_startName != null)
            _StartLocationStatus(
              icon: Icons.check_circle_outline,
              message:
                  '$_startName (${_startLatitude!.toStringAsFixed(5)}, ${_startLongitude!.toStringAsFixed(5)})',
            ),
        ],
      );
    }
    if (_startType == TripStartLocationType.currentLocation) {
      return _StartLocationStatus(
        key: const ValueKey('current-start'),
        icon: Icons.my_location_rounded,
        loading: _isGettingCurrentLocation,
        message: _isGettingCurrentLocation
            ? 'Getting your current position…'
            : _startLatitude == null
            ? 'Allow location access to use your current position.'
            : 'Current position ready: ${_startLatitude!.toStringAsFixed(5)}, ${_startLongitude!.toStringAsFixed(5)}',
      );
    }
    return Material(
      key: ValueKey(_startType),
      color: AppColors.surfaceSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _startSearchController,
              enabled: !_isResolvingLocation,
              decoration: InputDecoration(
                hintText: _startType == TripStartLocationType.hotel
                    ? 'Search hotels in your city'
                    : 'Search a landmark or address',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _isSearchingLocation || _isResolvingLocation
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
            if (_locationSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final suggestion in _locationSuggestions)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: const Icon(
                    Icons.place_outlined,
                    color: AppColors.teal,
                  ),
                  title: Text(suggestion.name, style: AppTextStyles.label),
                  subtitle: Text(
                    suggestion.formattedAddress,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _selectLocationSuggestion(suggestion),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _locationSuggestions.every((s) => s.provider == 'city_pack')
                      ? 'Bundled city places • Available offline'
                      : 'Powered by Geoapify • © OpenStreetMap contributors',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ] else if (!_isSearchingLocation &&
                _startSearchController.text.length >= 3 &&
                _startName == null &&
                _startError == null) ...[
              const SizedBox(height: 8),
              const Text('No hotel found. Choose a point on the map instead.'),
              TextButton(
                onPressed: _choosePoint,
                child: const Text('Choose on map'),
              ),
            ] else if (_startName != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_startName!, style: AppTextStyles.label),
                  ),
                ],
              ),
              if (_startProvider == 'geoapify') ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Powered by Geoapify • © OpenStreetMap contributors',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay value) {
    final hour = value.hourOfPeriod == 0 ? 12 : value.hourOfPeriod;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final city = widget.draft.destination?.name ?? 'Ujjain';
    return CreateTripScaffold(
      step: 3,
      title: 'Where will you start in $city?',
      subtitle:
          'Choose a place or your own point. How you get there is optional.',
      continueEnabled: _canContinue,
      onContinue: _continue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Starting point', style: AppTextStyles.sectionTitle),
          const SizedBox(height: 12),
          if (_startType == TripStartLocationType.arrival) ...[
            TextField(
              key: const ValueKey('start-place-search'),
              controller: _pointController,
              focusNode: _pointFocus,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Place, hotel or station',
                hintText: 'Search places in $city',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _isSearchingArrival
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
            if (_arrivalSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Material(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    for (final suggestion in _arrivalSuggestions)
                      ListTile(
                        leading: const Icon(
                          Icons.place_outlined,
                          color: AppColors.teal,
                        ),
                        title: Text(
                          suggestion.name,
                          style: AppTextStyles.label,
                        ),
                        subtitle: Text(
                          suggestion.formattedAddress,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectPoint(suggestion),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _arrivalSuggestions.every((s) => s.provider == 'city_pack')
                    ? 'Bundled city places • Available offline'
                    : 'Powered by Geoapify • © OpenStreetMap contributors',
                style: AppTextStyles.caption,
              ),
            ] else if (_arrivalError != null) ...[
              const SizedBox(height: 8),
              _StartLocationError(
                message: _arrivalError!,
                onRetry: _retryArrivalSearch,
              ),
              TextButton(
                onPressed: _choosePoint,
                child: const Text('Choose a point instead'),
              ),
            ] else if (_hasSearchedArrival &&
                !_isSearchingArrival &&
                _arrivalLatitude == null) ...[
              const SizedBox(height: 8),
              const Text(
                'No matching place. You can choose any point on the map.',
              ),
              TextButton(
                onPressed: _choosePoint,
                child: const Text('Choose on map'),
              ),
            ],
          ],
          const SizedBox(height: 16),
          // Full-width rows remain usable with larger phone text settings.
          for (final type in TripStartLocationType.values) ...[
            _StartOptionCard(
              type: type,
              selected: _startType == type,
              onTap: () => _selectStartType(type),
            ),
            const SizedBox(height: 8),
          ],
          if (_startType != TripStartLocationType.arrival) ...[
            const SizedBox(height: 4),
            _buildStartLocationDetails(),
          ],
          if (_startError != null) ...[
            const SizedBox(height: 10),
            _StartLocationError(
              message: _startError!,
              onRetry: _startType == TripStartLocationType.currentLocation
                  ? _useCurrentLocation
                  : null,
            ),
          ],
          if (_canContinue) ...[
            const SizedBox(height: 12),
            _StartLocationStatus(
              icon: Icons.check_circle_outline,
              message: 'Start confirmed: $_startName',
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Approximate arrival time',
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: 12),
          _TimeField(value: _formatTime(_arrivalTime), onTap: _pickTime),
          const SizedBox(height: 24),
          Text('Travel method (optional)', style: AppTextStyles.sectionTitle),
          const SizedBox(height: 6),
          const Text('Skip this if you are already in the city.'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final method in _methods)
                FilterChip(
                  avatar: Icon(method.$2, size: 18),
                  label: Text(method.$1),
                  selected: _method == method.$1,
                  onSelected: (_) => _selectMethod(method.$1),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return YCPressable(
      onTap: onTap,
      semanticLabel: 'Arrival time $value',
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule_rounded, color: AppColors.teal),
            const SizedBox(width: 12),
            Expanded(child: Text(value, style: AppTextStyles.cardTitle)),
            const Icon(
              Icons.expand_more_rounded,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _StartOptionCard extends StatelessWidget {
  const _StartOptionCard({
    required this.type,
    required this.selected,
    required this.onTap,
  });
  final TripStartLocationType type;
  String get _label => switch (type) {
    TripStartLocationType.arrival => 'Search places',
    TripStartLocationType.hotel => 'Hotel',
    TripStartLocationType.currentLocation => 'Current location',
    TripStartLocationType.custom => 'Choose on map',
  };
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final icon = switch (type) {
      TripStartLocationType.arrival => Icons.flag_outlined,
      TripStartLocationType.hotel => Icons.hotel_outlined,
      TripStartLocationType.currentLocation => Icons.my_location_rounded,
      TripStartLocationType.custom => Icons.add_location_alt_outlined,
    };
    return YCPressable(
      onTap: onTap,
      semanticLabel: _label,
      selected: selected,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: YCMotion.duration(context, YCMotion.component),
        curve: YCMotion.standard,
        decoration: BoxDecoration(
          color: selected ? AppColors.tealLight : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.teal : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.teal),
              const SizedBox(width: 12),
              Expanded(child: Text(_label, style: AppTextStyles.bodyLarge)),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? AppColors.teal : AppColors.borderStrong,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartLocationStatus extends StatelessWidget {
  const _StartLocationStatus({
    required this.icon,
    required this.message,
    this.loading = false,
    super.key,
  });

  final IconData icon;
  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          if (loading)
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, color: AppColors.teal, size: 21),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: AppTextStyles.caption)),
        ],
      ),
    );
  }
}

class _StartLocationError extends StatelessWidget {
  const _StartLocationError({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: 9),
          Expanded(child: Text(message, style: AppTextStyles.caption)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
