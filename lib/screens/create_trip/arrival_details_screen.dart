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
import '../../widgets/create_trip_scaffold.dart';
import 'trip_purpose_screen.dart';

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
    _startLatitude = widget.draft.startLatitude;
    _startLongitude = widget.draft.startLongitude;
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
    if (_suppressArrivalSearch || query.length < 3) return;
    _arrivalSearchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _searchArrivalPoint(query, revision),
    );
  }

  Future<void> _searchArrivalPoint(String query, int revision) async {
    setState(() {
      _isSearchingArrival = true;
      _arrivalError = null;
    });
    try {
      final suggestions = await _locationService.autocomplete(
        _arrivalProviderQuery(query),
        hotelOnly: false,
        latitude: widget.draft.destination?.latitude,
        longitude: widget.draft.destination?.longitude,
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

  void _selectMethod(String method) {
    if (_method == method) return;
    setState(() => _method = method);
    if (_arrivalPoint.isNotEmpty) _refreshPoint();
  }

  String _arrivalProviderQuery(String query) {
    final normalized = query.toLowerCase();
    return switch (_method) {
      'Train'
          when !normalized.contains('railway') &&
              !normalized.contains('station') =>
        '$query railway station',
      'Flight' when !normalized.contains('airport') => '$query airport',
      'Bus'
          when !normalized.contains('bus') &&
              !normalized.contains('terminal') =>
        '$query bus station',
      _ => query,
    };
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

  bool get _canContinue {
    if (_arrivalPoint.isEmpty || _isSavingStart) return false;
    if (_startType == TripStartLocationType.arrival) {
      return _arrivalLatitude != null &&
          _arrivalLongitude != null &&
          !_isSearchingArrival;
    }
    return _startName != null &&
        _startLatitude != null &&
        _startLongitude != null &&
        !_isResolvingLocation &&
        !_isGettingCurrentLocation;
  }

  void _selectStartType(TripStartLocationType type) {
    _searchDebounce?.cancel();
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
    if (query.length < 3 ||
        (_startType != TripStartLocationType.hotel &&
            _startType != TripStartLocationType.custom)) {
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
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
        );
        if (!mounted ||
            revision != _searchRevision ||
            query != _startSearchController.text.trim()) {
          return;
        }
        setState(() => _locationSuggestions = suggestions);
      } on Object catch (error) {
        if (!mounted) return;
        setState(() => _startError = _locationError(error));
      } finally {
        if (mounted && revision == _searchRevision) {
          setState(() => _isSearchingLocation = false);
        }
      }
    });
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
    setState(() {
      _isGettingCurrentLocation = true;
      _startError = null;
    });
    try {
      final position = await _deviceLocationService.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _startName = 'Current location';
        _startLatitude = position.latitude;
        _startLongitude = position.longitude;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _startError = _locationError(error));
    } finally {
      if (mounted) setState(() => _isGettingCurrentLocation = false);
    }
  }

  String _locationError(Object error) {
    if (error is DeviceLocationException) return error.message;
    if (error is LocationServiceException) return error.message;
    if (error is TimeoutException) return 'Location lookup took too long.';
    return 'Could not select this start location.';
  }

  Future<void> _continue() async {
    widget.draft
      ..arrivalMethod = _method
      ..arrivalPoint = _arrivalPoint
      ..arrivalLatitude = _arrivalLatitude
      ..arrivalLongitude = _arrivalLongitude
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
    if (_startType == TripStartLocationType.arrival) {
      return _StartLocationStatus(
        key: const ValueKey('arrival-start'),
        icon: Icons.flag_outlined,
        message: _arrivalPoint.isEmpty
            ? 'Choose your arrival point above.'
            : 'Sightseeing will begin at $_arrivalPoint.',
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
                  'Powered by Geoapify • © OpenStreetMap contributors',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
      title: 'How are you\nreaching $city?',
      subtitle: 'Set your arrival, then choose where sightseeing begins.',
      continueEnabled: _canContinue,
      onContinue: _continue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Arrival method', style: AppTextStyles.sectionTitle),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _methods
                .map(
                  (method) => _TransportCard(
                    label: method.$1,
                    icon: method.$2,
                    selected: _method == method.$1,
                    onTap: () => _selectMethod(method.$1),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 30),
          const Text(
            'Where will you arrive?',
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pointController,
            focusNode: _pointFocus,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Search arrival points in $city',
              prefixIcon: const Icon(Icons.location_on_outlined),
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
                children: _arrivalSuggestions
                    .map(
                      (suggestion) => ListTile(
                        dense: true,
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
                    )
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 6),
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
          ] else if (_arrivalError != null) ...[
            const SizedBox(height: 8),
            Text(
              _arrivalError!,
              style: AppTextStyles.caption.copyWith(color: AppColors.error),
            ),
          ] else if (_hasSearchedArrival &&
              !_isSearchingArrival &&
              _arrivalPoint.isNotEmpty &&
              _arrivalLatitude == null) ...[
            const SizedBox(height: 8),
            Text(
              'No matching arrival point found. Try a station, airport, or terminal name.',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ] else if (_arrivalPoint.isNotEmpty &&
              _arrivalLatitude == null &&
              _startType == TripStartLocationType.arrival) ...[
            const SizedBox(height: 8),
            Text(
              'Select a search result so route planning has an exact starting point.',
              style: AppTextStyles.caption.copyWith(color: AppColors.error),
            ),
          ] else if (_arrivalLatitude != null && _arrivalLongitude != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 18,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Route starting point confirmed',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 26),
          const Text(
            'Approximate arrival time',
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: 12),
          _TimeField(value: _formatTime(_arrivalTime), onTap: _pickTime),
          const SizedBox(height: 26),
          const Text('Start your trip from', style: AppTextStyles.sectionTitle),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final type in TripStartLocationType.values)
                    SizedBox(
                      width: width,
                      child: _StartOptionCard(
                        type: type,
                        selected: _startType == type,
                        onTap: () => _selectStartType(type),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _buildStartLocationDetails(),
          ),
          if (_startError case final error?) ...[
            const SizedBox(height: 10),
            _StartLocationError(
              message: error,
              onRetry: _startType == TripStartLocationType.currentLocation
                  ? _useCurrentLocation
                  : null,
            ),
          ],
          const SizedBox(height: 20),
          _StartCard(
            locationName: _startName ?? 'Choose a start location',
            locationType: _startType.label,
            arrivalTime: _formatTime(_arrivalTime),
          ),
        ],
      ),
    );
  }
}

class _TransportCard extends StatelessWidget {
  const _TransportCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 94,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.tealLight : AppColors.surface,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected ? AppColors.teal : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? AppColors.teal : AppColors.textSecondary,
              ),
              const SizedBox(height: 7),
              Text(label, style: AppTextStyles.label),
            ],
          ),
        ),
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
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
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
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (type) {
      TripStartLocationType.arrival => Icons.flag_outlined,
      TripStartLocationType.hotel => Icons.hotel_rounded,
      TripStartLocationType.currentLocation => Icons.my_location_rounded,
      TripStartLocationType.custom => Icons.add_location_alt_outlined,
    };
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: selected ? AppColors.tealLight : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.teal : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: selected ? AppColors.teal : AppColors.textSecondary,
                size: 22,
              ),
              const SizedBox(height: 8),
              Text(type.label, style: AppTextStyles.label),
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

class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.locationName,
    required this.locationType,
    required this.arrivalTime,
  });

  final String locationName;
  final String locationType;
  final String arrivalTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.tealDark,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.marigold,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.flag_rounded, color: AppColors.charcoal),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'START  •  ${locationType.toUpperCase()}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.marigold,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .7,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  locationName,
                  style: AppTextStyles.cardTitle.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 5),
                Text(
                  'Route planning begins here after your $arrivalTime arrival.',
                  style: AppTextStyles.body.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
