import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/trip_draft.dart';
import '../../models/trip_day.dart';
import '../../models/saved_place.dart';
import '../../models/trip_start_location.dart';
import '../../models/yatra_session.dart';
import '../../services/trip_service.dart';
import '../../services/saved_place_service.dart';
import '../../theme/yc_style.dart';
import '../../widgets/yc_scaffold.dart';
import '../../widgets/selection_chip.dart';
import '../../widgets/place_card.dart';
import '../home/widgets/home_destination_card.dart';
import '../create_trip/destination_selection_screen.dart';
import '../create_trip/plan_days_screen.dart';
import '../place_discovery/place_discovery_screen.dart';
import '../trip_map/trip_map_screen.dart';

void _open(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    required this.favorites,
    required this.onFavorite,
    super.key,
  });
  final Set<String> favorites;
  final ValueChanged<String> onFavorite;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: YatraSession.instance,
    builder: (context, _) => YCScaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('A little about you.', style: YCStyle.title),
            const SizedBox(height: 24),
            _Surface(
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: YCStyle.selected,
                    child: Icon(Icons.person_outline, color: YCStyle.blue),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          YatraSession.instance.name,
                          style: YCStyle.sectionTitle,
                        ),
                        const SizedBox(height: 4),
                        Text('Exploring as a guest', style: YCStyle.secondary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _Surface(
              child: Column(
                children: [
                  _NavigationRow(
                    icon: Icons.favorite_border,
                    title: 'Saved destinations',
                    subtitle: '${favorites.length} places to dream about',
                    onTap: () => _open(
                      context,
                      SavedScreen(favorites: favorites, onFavorite: onFavorite),
                    ),
                  ),
                  const Divider(),
                  _NavigationRow(
                    icon: Icons.luggage_outlined,
                    title: 'Your trips',
                    subtitle: 'Plans from this session',
                    onTap: () => _open(context, const TripHistoryScreen()),
                  ),
                  const Divider(),
                  _NavigationRow(
                    icon: Icons.tune,
                    title: 'Preferences & settings',
                    subtitle: 'Make planning feel like you',
                    onTap: () => _open(context, const SettingsScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Guest preferences and recent trips are available during this app session. Account sync is not available yet.',
              style: YCStyle.secondary,
            ),
          ],
        ),
      ),
    ),
  );
}

class SavedScreen extends StatefulWidget {
  const SavedScreen({
    required this.favorites,
    required this.onFavorite,
    super.key,
  });
  final Set<String> favorites;
  final ValueChanged<String> onFavorite;
  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  @override
  Widget build(BuildContext context) {
    final names = widget.favorites.toList()..sort();
    return YCScaffold(
      appBar: AppBar(title: const Text('Saved')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Places for another day.', style: YCStyle.title),
            const SizedBox(height: 12),
            Text(
              'Keep your inspiration close. Choose a destination when you are ready to plan.',
              style: YCStyle.secondary,
            ),
            const SizedBox(height: 28),
            if (names.isEmpty)
              YCStateCard(
                title: 'A little inspiration goes a long way',
                message: 'Tap the heart on Home or Explore to keep a destination here.',
                icon: Icons.favorite_border,
                actionLabel: 'Back to exploring',
                onAction: () => Navigator.maybePop(context),
              ),
            for (final name in names) ...[
              HomeDestinationCard(
                name: name,
                region: name == 'Jaipur'
                    ? 'Rajasthan'
                    : name == 'Varanasi'
                    ? 'Uttar Pradesh'
                    : 'Madhya Pradesh',
                image: name.toLowerCase(),
                favorite: true,
                onFavorite: () => setState(() => widget.onFavorite(name)),
                onTap: () => _open(
                  context,
                  DestinationSelectionScreen(initialQuery: name),
                ),
              ),
              const SizedBox(height: 20),
            ],
            _Surface(
              child: _NavigationRow(
                icon: Icons.bookmark_border,
                title: 'Places in your trips',
                subtitle: 'View and edit the places you selected for a plan',
                onTap: () => _open(context, const TripHistoryScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});
  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  String _filter = 'Upcoming';
  String _status(TripDraft trip) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (trip.startDate.isAfter(today)) return 'Upcoming';
    if (trip.endDate.isBefore(today)) return 'Past';
    return 'Ongoing';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: YatraSession.instance,
    builder: (context, _) {
      final trips = YatraSession.instance.trips
          .where((trip) => _status(trip) == _filter)
          .toList();
      return YCScaffold(
        appBar: AppBar(title: const Text('Your trips')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Every journey has a story.', style: YCStyle.title),
              const SizedBox(height: 12),
              Text(
                'Trips opened or created during this session.',
                style: YCStyle.secondary,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in ['Upcoming', 'Ongoing', 'Past'])
                    SelectionChip(
                      label: label,
                      selected: _filter == label,
                      onSelected: (_) => setState(() => _filter = label),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (trips.isEmpty)
                YCStateCard(
                  title: _filter == 'Past'
                      ? 'Memories start with a plan'
                      : 'Room for your next journey',
                  message: 'No ${_filter.toLowerCase()} trips in this session.',
                  actionLabel: 'Plan a trip',
                  onAction: () =>
                      _open(context, const DestinationSelectionScreen()),
                ),
              for (final trip in trips) ...[
                _Surface(
                  child: _NavigationRow(
                    icon: Icons.route_outlined,
                    title: trip.destination?.name ?? 'Your trip',
                    subtitle:
                        '${MaterialLocalizations.of(context).formatMediumDate(trip.startDate)} · ${trip.durationDays} days',
                    onTap: () => _open(context, TripSummaryScreen(draft: trip)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class TripSummaryScreen extends StatefulWidget {
  const TripSummaryScreen({required this.draft, this.tripService, this.savedPlaceService, super.key});
  final TripDraft draft;
  final TripService? tripService;
  final SavedPlaceService? savedPlaceService;
  @override
  State<TripSummaryScreen> createState() => _TripSummaryScreenState();
}

class _TripSummaryScreenState extends State<TripSummaryScreen> {
  late final _trips = widget.tripService ?? TripService();
  late final _saved = widget.savedPlaceService ?? SavedPlaceService();
  List<TripDay> _days = [];
  List<SavedPlace> _places = [];
  bool _loading = true;
  String? _error;
  final Set<String> _removing = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.draft.tripId;
    if (id == null) {
      setState(() {
        _loading = false;
        _error = 'Save this trip before opening its places.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait<Object>([
        _trips.getTripDays(id),
        _saved.getSavedPlaces(id),
      ]);
      if (!mounted) return;
      setState(() {
        _days = result[0] as List<TripDay>;
        _places = result[1] as List<SavedPlace>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Your saved plan could not be loaded. Check your connection and try again.';
        });
      }
    }
  }

  Future<void> _remove(SavedPlace place) async {
    if (_removing.contains(place.placeId)) return;
    setState(() => _removing.add(place.placeId));
    try {
      await _saved.removeSavedPlace(widget.draft.tripId!, place.placeId);
      if (mounted) {
        setState(() => _places.removeWhere((p) => p.placeId == place.placeId));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not remove this place. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _removing.remove(place.placeId));
    }
  }

  @override
  void dispose() {
    if (widget.tripService == null) _trips.close();
    if (widget.savedPlaceService == null) _saved.close();
    super.dispose();
  }

  void _continue() {
    final draft = widget.draft;
    if (draft.destination == null) return;
    final hasStart =
        draft.startLatitude != null && draft.startLongitude != null;
    _open(
      context,
      PlaceDiscoveryScreen(
        city: draft.destination!,
        tripId: draft.tripId,
        tripPurposes: draft.purposes,
        durationDays: draft.durationDays,
        routeStartReady: hasStart,
        startLocation: hasStart
            ? TripStartLocation(
                tripId: draft.tripId!,
                type: draft.startLocationType,
                name: draft.startLocationName ?? 'Trip start',
                latitude: draft.startLatitude!,
                longitude: draft.startLongitude!,
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.draft;
    return YCScaffold(
      appBar: AppBar(title: const Text('Trip details')),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                trip.destination?.name ?? 'Your journey',
                style: YCStyle.title,
              ),
              const SizedBox(height: 10),
              Text(
                '${MaterialLocalizations.of(context).formatMediumDate(trip.startDate)} – ${MaterialLocalizations.of(context).formatMediumDate(trip.endDate)}',
                style: YCStyle.secondary,
              ),
              const SizedBox(height: 24),
              _Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${trip.durationDays} days away',
                      style: YCStyle.sectionTitle,
                    ),
                    const SizedBox(height: 12),
                    Text(trip.purposes.join(' · '), style: YCStyle.body),
                    const SizedBox(height: 12),
                    Text(
                      'Starting from ${trip.startLocationName ?? trip.arrivalPoint}',
                      style: YCStyle.secondary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${trip.travelPace} pace · ${trip.transportPreferences.join(', ')}',
                      style: YCStyle.secondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _continue,
                child: const Text('Continue planning'),
              ),
              const SizedBox(height: 8),
              if (trip.tripId != null)
                OutlinedButton.icon(
                  onPressed: () =>
                      _open(context, TripMapScreen(tripId: trip.tripId!)),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('View itinerary on map'),
                ),
              const SizedBox(height: 24),
              if (_loading)
                const YCStateCard(
                  title: 'Opening your plan',
                  message: 'Loading saved places and day settings.',
                  loading: true,
                )
              else if (_error != null)
                YCStateCard(
                  title: 'Your plan is still saved',
                  message: _error!,
                  onAction: _load,
                )
              else ...[
                _Surface(
                  child: _NavigationRow(
                    icon: Icons.calendar_month_outlined,
                    title:
                        '${_days.where((d) => d.dayType == DayType.rest).length} rest days',
                    subtitle: 'Adjust sightseeing hours and days off',
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlanDaysScreen(tripId: trip.tripId!),
                        ),
                      );
                      if (mounted) _load();
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '${_places.length} selected places',
                  style: YCStyle.sectionTitle,
                ),
                const SizedBox(height: 16),
                if (_places.isEmpty)
                  YCStateCard(
                    title: 'What would you like to see?',
                    message:
                        'Choose a few places to begin shaping your itinerary.',
                    actionLabel: 'Find places',
                    onAction: _continue,
                  ),
                for (final saved in _places) ...[
                  PlaceCard(
                    name: saved.place.name,
                    description: saved.notes ?? 'Included in this trip',
                    category: saved.place.category,
                    selected: true,
                    actionLabel: 'Remove',
                    actionBusy: _removing.contains(saved.placeId),
                    onAction: () => _remove(saved),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _name = TextEditingController(text: YatraSession.instance.name);
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _locationSettings() async {
    try {
      final opened = await Geolocator.openAppSettings();
      if (!opened && mounted) {
        _notice('Open your device settings to manage location access.');
      }
    } catch (_) {
      if (mounted) {
        _notice(
          'Use your device or browser settings to manage location access.',
        );
      }
    }
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  @override
  Widget build(BuildContext context) => YCScaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Make yourself at home.', style: YCStyle.title),
          const SizedBox(height: 24),
          Text('Your profile', style: YCStyle.sectionTitle),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'Preferred name'),
            onSubmitted: (value) {
              YatraSession.instance.setName(value);
              _notice('Name updated for this session.');
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                YatraSession.instance.setName(_name.text);
                _notice('Name updated for this session.');
              },
              child: const Text('Save name'),
            ),
          ),
          const SizedBox(height: 20),
          Text('Travel preferences', style: YCStyle.sectionTitle),
          const SizedBox(height: 8),
          Text('Default pace for new trips', style: YCStyle.secondary),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final pace in ['Relaxed', 'Balanced', 'Packed'])
                SelectionChip(
                  label: pace,
                  selected: YatraSession.instance.pace == pace,
                  onSelected: (_) =>
                      setState(() => YatraSession.instance.setPace(pace)),
                ),
            ],
          ),
          const SizedBox(height: 24),
          _Surface(
            child: Column(
              children: [
                _NavigationRow(
                  icon: Icons.location_on_outlined,
                  title: 'Location permissions',
                  subtitle: 'Used only when you choose your current location',
                  onTap: _locationSettings,
                ),
                const Divider(),
                const _NavigationRow(
                  icon: Icons.light_mode_outlined,
                  title: 'Appearance',
                  subtitle: 'YatraCanvas light appearance',
                ),
                const Divider(),
                const _NavigationRow(
                  icon: Icons.notifications_none,
                  title: 'Notifications',
                  subtitle: 'Trip notifications are not available yet',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _Surface(
            child: Column(
              children: [
                _NavigationRow(
                  icon: Icons.history,
                  title: 'Clear recent trip list',
                  subtitle: 'Keeps your saved trip data intact',
                  onTap: () {
                    YatraSession.instance.clearRecentTrips();
                    _notice(
                      'Recent trip list cleared. Saved trip data was not deleted.',
                    );
                  },
                ),
                const Divider(),
                const _NavigationRow(
                  icon: Icons.info_outline,
                  title: 'About YatraCanvas',
                  subtitle: 'Thoughtful journeys, at your pace. Version 0.1.0',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Preferences are kept for this session. Account sign-in and cloud sync are not available yet.',
            style: YCStyle.secondary,
          ),
        ],
      ),
    ),
  );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: YCStyle.border),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class _NavigationRow extends StatelessWidget {
  const _NavigationRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: YCStyle.blue, size: 24),
    title: Text(title, style: YCStyle.body),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(subtitle, style: YCStyle.secondary),
    ),
    trailing: onTap == null ? null : const Icon(Icons.chevron_right, size: 20),
    onTap: onTap,
  );
}
