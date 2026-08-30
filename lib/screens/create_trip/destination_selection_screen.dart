import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/city.dart';
import '../../models/trip_draft.dart';
import '../../services/city_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/create_trip_scaffold.dart';
import '../../widgets/search_field.dart';
import 'select_dates_screen.dart';

class DestinationSelectionScreen extends StatefulWidget {
  const DestinationSelectionScreen({this.draft, this.cityService, super.key});

  final TripDraft? draft;
  final CityService? cityService;

  @override
  State<DestinationSelectionScreen> createState() =>
      _DestinationSelectionScreenState();
}

class _DestinationSelectionScreenState
    extends State<DestinationSelectionScreen> {
  static const _debounceDuration = Duration(milliseconds: 400);

  late final TripDraft _draft;
  late final CityService _cityService;
  late final bool _ownsCityService;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  Timer? _debounce;
  List<City> _suggestions = const [];
  City? _pendingResolution;
  String _query = '';
  String? _searchError;
  String? _resolveError;
  bool _isSearching = false;
  bool _isResolving = false;
  int _searchGeneration = 0;
  int _resolveGeneration = 0;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft ?? TripDraft();
    _ownsCityService = widget.cityService == null;
    _cityService = widget.cityService ?? CityService();

    final selectedCity = _draft.destination;
    if (selectedCity != null) {
      _query = selectedCity.displayName;
      _searchController.text = selectedCity.displayName;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    if (_ownsCityService) _cityService.close();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _searchGeneration++;
    _resolveGeneration++;

    final normalizedQuery = value.trim();
    setState(() {
      _query = value;
      _suggestions = const [];
      _searchError = null;
      _resolveError = null;
      _pendingResolution = null;
      _isResolving = false;
      _isSearching = normalizedQuery.length >= 2;

      final selectedCity = _draft.destination;
      if (selectedCity != null && value != selectedCity.displayName) {
        _draft.destination = null;
      }
    });

    if (normalizedQuery.length < 2) return;

    final requestGeneration = _searchGeneration;
    _debounce = Timer(
      _debounceDuration,
      () => _search(normalizedQuery, requestGeneration),
    );
  }

  Future<void> _search(String query, int requestGeneration) async {
    try {
      final cities = await _cityService.searchCities(query);
      if (!mounted || requestGeneration != _searchGeneration) return;
      setState(() {
        _suggestions = cities;
        _isSearching = false;
      });
    } on Object catch (error) {
      if (!mounted || requestGeneration != _searchGeneration) return;
      setState(() {
        _isSearching = false;
        _searchError = _friendlyError(error);
      });
    }
  }

  void _retrySearch() {
    final normalizedQuery = _query.trim();
    if (normalizedQuery.length < 2) return;

    final requestGeneration = ++_searchGeneration;
    setState(() {
      _searchError = null;
      _isSearching = true;
    });
    _search(normalizedQuery, requestGeneration);
  }

  Future<void> _selectCity(City city) async {
    _debounce?.cancel();
    _searchGeneration++;
    _searchFocusNode.unfocus();
    _searchController.text = city.displayName;
    _searchController.selection = TextSelection.collapsed(
      offset: _searchController.text.length,
    );

    final requestGeneration = ++_resolveGeneration;
    setState(() {
      _query = city.displayName;
      _suggestions = const [];
      _searchError = null;
      _resolveError = null;
      _pendingResolution = city;
      _draft.destination = null;
      _isSearching = false;
      _isResolving = true;
    });

    try {
      final resolvedCity = await _cityService.resolveCity(city);
      if (!mounted || requestGeneration != _resolveGeneration) return;
      setState(() {
        _draft.destination = resolvedCity;
        _pendingResolution = null;
        _isResolving = false;
        _query = resolvedCity.displayName;
        _searchController.text = resolvedCity.displayName;
      });
    } on Object catch (error) {
      if (!mounted || requestGeneration != _resolveGeneration) return;
      setState(() {
        _isResolving = false;
        _resolveError = _friendlyError(error);
      });
    }
  }

  void _retryResolve() {
    final city = _pendingResolution;
    if (city != null) _selectCity(city);
  }

  String _friendlyError(Object error) {
    if (error is TimeoutException) {
      return 'The server took too long to respond. Check that FastAPI is running.';
    }
    if (error is CityServiceException) return error.message;
    return 'Could not reach the city service. Check your connection and try again.';
  }

  void _continue() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SelectDatesScreen(draft: _draft)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CreateTripScaffold(
      step: 1,
      title: 'Where are you\ngoing?',
      subtitle: 'Search cities already available in YatraCanvas.',
      continueEnabled: _draft.destination != null && !_isResolving,
      onContinue: _continue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            hintText: 'Search by city or state',
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _buildSearchState(),
          ),
          if (_draft.destination case final city?) ...[
            const SizedBox(height: 22),
            _SelectedCityCard(city: city),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchState() {
    if (_isResolving) {
      return const _StatusCard(
        key: ValueKey('resolving'),
        icon: Icons.sync_rounded,
        title: 'Confirming your city',
        message: 'Saving the city to your trip…',
        showProgress: true,
      );
    }
    if (_resolveError != null) {
      return _ErrorCard(
        key: const ValueKey('resolve-error'),
        message: _resolveError!,
        onRetry: _retryResolve,
      );
    }
    if (_draft.destination != null) {
      return const SizedBox.shrink(key: ValueKey('selected'));
    }
    if (_query.trim().length < 2) {
      return const _StatusCard(
        key: ValueKey('hint'),
        icon: Icons.travel_explore_rounded,
        title: 'Find your destination',
        message: 'Type at least 2 characters to search saved cities.',
      );
    }
    if (_isSearching) {
      return const _StatusCard(
        key: ValueKey('searching'),
        icon: Icons.location_searching_rounded,
        title: 'Searching cities',
        message: 'Looking through destinations in YatraCanvas…',
        showProgress: true,
      );
    }
    if (_searchError != null) {
      return _ErrorCard(
        key: const ValueKey('search-error'),
        message: _searchError!,
        onRetry: _retrySearch,
      );
    }
    if (_suggestions.isEmpty) {
      return const _StatusCard(
        key: ValueKey('empty'),
        icon: Icons.location_off_outlined,
        title: 'No cities found',
        message: 'Try another city name or search by state.',
      );
    }
    return _SuggestionsPanel(
      key: const ValueKey('suggestions'),
      cities: _suggestions,
      onSelected: _selectCity,
    );
  }
}

class _SuggestionsPanel extends StatelessWidget {
  const _SuggestionsPanel({
    required this.cities,
    required this.onSelected,
    super.key,
  });

  final List<City> cities;
  final ValueChanged<City> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderStrong),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1214294E),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 9),
            child: Text(
              '${cities.length} ${cities.length == 1 ? 'city' : 'cities'} found',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.tealDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(),
          for (var index = 0; index < cities.length; index++) ...[
            _CitySuggestion(
              city: cities[index],
              onTap: () => onSelected(cities[index]),
            ),
            if (index != cities.length - 1)
              const Divider(indent: 64, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _CitySuggestion extends StatelessWidget {
  const _CitySuggestion({required this.city, required this.onTap});

  final City city;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AppColors.tealLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: AppColors.teal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(city.name, style: AppTextStyles.cardTitle),
                    const SizedBox(height: 2),
                    Text(city.locationLabel, style: AppTextStyles.bodyMuted),
                  ],
                ),
              ),
              const Icon(
                Icons.north_west_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.surfaceSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.teal, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.label),
                const SizedBox(height: 2),
                Text(message, style: AppTextStyles.caption),
                if (showProgress) ...[
                  const SizedBox(height: 9),
                  const LinearProgressIndicator(minHeight: 2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.error.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: AppTextStyles.bodyMuted)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _SelectedCityCard extends StatelessWidget {
  const _SelectedCityCard({required this.city});

  final City city;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.tealGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -8,
            bottom: -18,
            child: Icon(
              Icons.route_rounded,
              size: 96,
              color: Colors.white.withValues(alpha: .10),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.marigold,
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'CITY ADDED TO YOUR TRIP',
                      maxLines: 2,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.marigold,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .7,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                city.name,
                style: AppTextStyles.pageTitle.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 5),
              Text(
                city.locationLabel,
                style: AppTextStyles.body.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
