import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/trip_draft.dart';
import '../../models/trip_day.dart';
import '../../models/saved_place.dart';
import '../../models/trip_start_location.dart';
import '../../models/yatra_session.dart';
import '../../services/trip_service.dart';
import '../../services/saved_place_service.dart';
import '../../theme/yc_motion.dart';
import '../../theme/yc_style.dart';
import '../../widgets/yc_scaffold.dart';
import '../../widgets/selection_chip.dart';
import '../../widgets/place_card.dart';
import '../auth/account_entry_screen.dart';
import '../home/widgets/home_destination_card.dart';
import '../home/widgets/yatra_refractive_glass.dart';
import '../create_trip/destination_selection_screen.dart';
import '../create_trip/plan_days_screen.dart';
import '../place_discovery/place_discovery_screen.dart';
import '../trip_map/trip_map_screen.dart';

void _open(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

// ─────────────────────────────────────────────────────────────────────────────
// ProfileScreen
// ─────────────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.favorites,
    required this.onFavorite,
    this.embedded = false,
    super.key,
  });
  final Set<String> favorites;
  final ValueChanged<String> onFavorite;
  final bool embedded;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  Set<String> get favorites => widget.favorites;
  void onFavorite(String name) {
    widget.onFavorite(name);
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: YCMotion.navigation,
    );
    final curved = CurvedAnimation(
      parent: _entryController,
      curve: YCMotion.standard,
    );
    _fade = curved;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(curved);
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  void _openAccountEntry() {
    Navigator.of(
      context,
    ).push(YCRoutes.standard<void>(builder: (_) => const AccountEntryScreen()));
  }

  void _signOut() {
    YatraSession.instance.signOut();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: YatraSession.instance,
      builder: (context, _) {
        final session = YatraSession.instance;
        final isGuest = session.isGuest;
        final tripCount = session.trips.length;
        final savedCount = favorites.length;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: DecoratedBox(
            decoration: const BoxDecoration(gradient: YCStyle.canvas),
            child: SafeArea(
              top: !widget.embedded,
              bottom: false,
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          widget.embedded ? 20 : 12,
                          24,
                          widget.embedded ? 150 : 32,
                        ),
                        sliver: SliverList.list(
                          children: [
                            // ── Header ─────────────────────────────────────
                            _ProfileHeader(
                              name: session.name,
                              email: session.displayEmail,
                              isGuest: isGuest,
                              onCreateAccount: _openAccountEntry,
                            ),
                            const SizedBox(height: 20),

                            // ── Stats ──────────────────────────────────────
                            _StatsRow(trips: tripCount, saved: savedCount),
                            const SizedBox(height: 20),

                            // ── My Travel section ──────────────────────────
                            _SectionLabel(label: 'MY TRAVEL'),
                            const SizedBox(height: 12),
                            _YCRow(
                              icon: Icons.luggage_outlined,
                              title: 'My Trips',
                              trailing: tripCount > 0 ? '$tripCount' : null,
                              onTap: () =>
                                  _open(context, const TripHistoryScreen()),
                            ),
                            _YCRowDivider(),
                            _YCRow(
                              icon: Icons.favorite_border_rounded,
                              title: 'Saved Destinations',
                              trailing: savedCount > 0 ? '$savedCount' : null,
                              onTap: () => _open(
                                context,
                                SavedScreen(
                                  favorites: favorites,
                                  onFavorite: onFavorite,
                                ),
                              ),
                            ),
                            _YCRowDivider(),
                            _YCRow(
                              icon: Icons.tune_rounded,
                              title: 'Travel Preferences',
                              onTap: () =>
                                  _open(context, const SettingsScreen()),
                            ),
                            const SizedBox(height: 28),

                            // ── Travel style section ───────────────────────
                            _SectionLabel(label: 'YOUR TRAVEL STYLE'),
                            const SizedBox(height: 14),
                            _TravelStylePanel(
                              pace: session.pace,
                              onEdit: () =>
                                  _open(context, const SettingsScreen()),
                            ),
                            const SizedBox(height: 28),

                            // ── App section ────────────────────────────────
                            _SectionLabel(label: 'APP'),
                            const SizedBox(height: 12),
                            _YCRow(
                              icon: Icons.settings_outlined,
                              title: 'Settings',
                              onTap: () =>
                                  _open(context, const SettingsScreen()),
                            ),
                            _YCRowDivider(),
                            const _YCRow(
                              icon: Icons.info_outline_rounded,
                              title: 'About YatraCanvas',
                              subtitle:
                                  'Thoughtful journeys, at your pace · v0.1.0',
                            ),
                            const SizedBox(height: 28),

                            // ── Account section ────────────────────────────
                            _SectionLabel(label: 'ACCOUNT'),
                            const SizedBox(height: 12),
                            if (isGuest) ...[
                              _YCRow(
                                icon: Icons.login_rounded,
                                title: 'Sign in',
                                onTap: _openAccountEntry,
                              ),
                              _YCRowDivider(),
                              _YCRow(
                                icon: Icons.person_add_outlined,
                                title: 'Create account',
                                onTap: _openAccountEntry,
                              ),
                            ] else ...[
                              _YCRow(
                                icon: Icons.mail_outline_rounded,
                                title: 'Account',
                                subtitle: session.displayEmail ?? '',
                              ),
                              _YCRowDivider(),
                              _YCRow(
                                icon: Icons.logout_rounded,
                                title: 'Sign out',
                                onTap: _signOut,
                                destructive: true,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ProfileHeader
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.email,
    required this.isGuest,
    required this.onCreateAccount,
  });

  final String name;
  final String? email;
  final bool isGuest;
  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isNotEmpty
        ? name
              .trim()
              .split(' ')
              .map((w) => w.isNotEmpty ? w[0] : '')
              .take(2)
              .join()
              .toUpperCase()
        : 'T';

    return Semantics(
      label: '$name, ${isGuest ? 'Guest Traveller' : (email ?? 'Signed in')}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 236),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          image: const DecorationImage(
            image: AssetImage('lib/assets/home/journey_editorial.png'),
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18142C53),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x10000000), Color(0xD4141B34)],
              stops: [.3, 1],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .92),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initials,
                        style: YCStyle.cardTitle.copyWith(color: YCStyle.blue),
                      ),
                    ),
                    const Spacer(),
                    if (isGuest)
                      IconButton(
                        onPressed: onCreateAccount,
                        tooltip: 'Account options',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: .88),
                          foregroundColor: YCStyle.blue,
                        ),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                      ),
                  ],
                ),
                const SizedBox(height: 48),
                Text(
                  'YOUR TRAVEL CANVAS',
                  style: YCStyle.caption.copyWith(
                    color: YCStyle.saffron,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 7),
                Text(name, style: YCStyle.title.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  isGuest
                      ? 'Guest traveller · planning this session'
                      : (email ?? 'Signed in'),
                  style: YCStyle.secondary.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatsRow
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.trips, required this.saved});
  final int trips;
  final int saved;

  @override
  Widget build(BuildContext context) {
    return YatraRefractiveGlass(
      radius: 18,
      blur: 5,
      fill: const Color(0x44FFFFFF),
      borderColor: const Color(0x99FFFFFF),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Stat(
              value: '$trips',
              label: trips == 1 ? 'Trip' : 'Trips',
              valueKey: const ValueKey('profile-trip-count'),
            ),
            _StatDivider(),
            _Stat(
              value: '$saved',
              label: 'Saved',
              valueKey: const ValueKey('profile-saved-count'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.valueKey});
  final String value;
  final String label;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label == 'Saved'
        ? '$value saved destinations'
        : '$value ${label.toLowerCase()}',
    child: ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            key: valueKey,
            style: const TextStyle(
              fontFamily: 'HomeInter',
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Color(0xFF141B34),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'HomeInter',
              fontSize: 12,
              color: Color(0xFF526077),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    ),
  );
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(height: 28, width: 1, color: const Color(0x33526077));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TravelStylePanel
// ─────────────────────────────────────────────────────────────────────────────

class _TravelStylePanel extends StatelessWidget {
  const _TravelStylePanel({required this.pace, required this.onEdit});
  final String pace;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    const paces = ['Relaxed', 'Balanced', 'Packed'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in paces) _StyleChip(label: p, selected: pace == p),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Edit travel style',
              style: const TextStyle(
                fontFamily: 'HomeInter',
                fontSize: 13,
                color: Color(0xFF1A4FC4),
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.underline,
                decorationColor: Color(0xFF1A4FC4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StyleChip extends StatelessWidget {
  const _StyleChip({required this.label, required this.selected});
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: YCMotion.component,
      curve: YCMotion.standard,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFF1A4FC4).withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? const Color(0xFF1A4FC4).withValues(alpha: 0.50)
              : const Color(0xFFD7E2EF),
          width: selected ? 1.5 : 1.0,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'HomeInter',
          fontSize: 14,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? const Color(0xFF1A4FC4) : const Color(0xFF526077),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label + row components
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: 'HomeInter',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.6,
        color: Color(0xFF8A9AB8),
      ),
    );
  }
}

class _YCRow extends StatelessWidget {
  const _YCRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final foreground = destructive
        ? const Color(0xFFCC3333)
        : const Color(0xFF141B34);
    final iconColor = destructive
        ? const Color(0xFFCC3333)
        : const Color(0xFF1A4FC4);

    Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'HomeInter',
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: foreground,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontFamily: 'HomeInter',
                      fontSize: 12,
                      color: Color(0xFF8A9AB8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFE7F0FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                trailing!,
                style: const TextStyle(
                  fontFamily: 'HomeInter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A4FC4),
                ),
              ),
            ),
          if (onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: const Color(0xFFB8C8DC),
            ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: const Color(0x08055EC8),
        borderRadius: BorderRadius.circular(8),
        child: row,
      );
    }
    return row;
  }
}

class _YCRowDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: Color(0xFFEEF3FA));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SavedScreen
// ─────────────────────────────────────────────────────────────────────────────

class SavedScreen extends StatefulWidget {
  const SavedScreen({
    required this.favorites,
    required this.onFavorite,
    this.embedded = false,
    this.onExplore,
    super.key,
  });
  final Set<String> favorites;
  final ValueChanged<String> onFavorite;
  final bool embedded;
  final VoidCallback? onExplore;
  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  @override
  Widget build(BuildContext context) {
    final names = widget.favorites.toList()..sort();
    return YCScaffold(
      appBar: AppBar(
        title: const Text('Saved'),
        automaticallyImplyLeading: !widget.embedded,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, widget.embedded ? 150 : 24),
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
                onAction: widget.onExplore ?? () => Navigator.maybePop(context),
              ),
            for (final name in names) ...[
              HomeDestinationCard(
                name: name,
                region: switch (name) {
                  'Jaipur' || 'Udaipur' => 'Rajasthan',
                  'Varanasi' => 'Uttar Pradesh',
                  'Manali' => 'Himachal Pradesh',
                  'Goa' => 'Goa',
                  'Rishikesh' => 'Uttarakhand',
                  _ => 'Madhya Pradesh',
                },
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
            _LightCard(
              child: _YCRow(
                icon: Icons.bookmark_border_rounded,
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

// ─────────────────────────────────────────────────────────────────────────────
// TripHistoryScreen
// ─────────────────────────────────────────────────────────────────────────────

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});
  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  String _filter = 'Upcoming';
  @override
  void initState() {
    super.initState();
    final statuses = YatraSession.instance.trips.map(_status).toSet();
    if (statuses.contains('Ongoing')) {
      _filter = 'Ongoing';
    } else if (!statuses.contains('Upcoming') && statuses.contains('Past')) {
      _filter = 'Past';
    }
  }

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
                _TripHistoryEmpty(
                  title: _filter == 'Past'
                      ? 'Memories start with a plan'
                      : 'Room for your next journey',
                  message: 'No ${_filter.toLowerCase()} trips in this session.',
                  actionLabel: 'Plan a trip',
                  onAction: () =>
                      _open(context, const DestinationSelectionScreen()),
                ),
              for (final trip in trips) ...[
                _LightCard(
                  child: _YCRow(
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

class _TripHistoryEmpty extends StatelessWidget {
  const _TripHistoryEmpty({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: YCStyle.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Image.asset(
            'lib/assets/home/journey_editorial.png',
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: YCStyle.sectionTitle),
              const SizedBox(height: 8),
              Text(message, style: YCStyle.secondary),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TripSummaryScreen
// ─────────────────────────────────────────────────────────────────────────────

class TripSummaryScreen extends StatefulWidget {
  const TripSummaryScreen({
    required this.draft,
    this.tripService,
    this.savedPlaceService,
    super.key,
  });
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
  bool _daysLoaded = false;
  bool _placesLoaded = false;
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
    var failed = false;
    await Future.wait([
      () async {
        try {
          final days = await _trips.getTripDays(id);
          if (!mounted) return;
          _days = days;
          _daysLoaded = true;
        } catch (_) {
          failed = true;
        }
      }(),
      () async {
        try {
          final places = await _saved.getSavedPlaces(id);
          if (!mounted) return;
          _places = places;
          _placesLoaded = true;
        } catch (_) {
          failed = true;
        }
      }(),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = failed
          ? 'Some trip details could not refresh. Check your connection and try again.'
          : null;
    });
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
              _TripSummaryHero(trip: trip),
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
              else ...[
                if (_error != null)
                  YCStateCard(
                    title: 'Could not refresh everything',
                    message: _error!,
                    actionLabel: 'Retry',
                    onAction: _load,
                  ),
                if (_daysLoaded)
                  _LightCard(
                    child: _YCRow(
                      icon: Icons.calendar_month_outlined,
                      title:
                          '${_days.where((d) => d.dayType == DayType.rest).length} rest days',
                      subtitle: 'Adjust sightseeing hours and days off',
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                PlanDaysScreen(tripId: trip.tripId!),
                          ),
                        );
                        if (mounted) _load();
                      },
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  _placesLoaded
                      ? '${_places.length} selected places'
                      : 'Places have not loaded yet',
                  style: YCStyle.sectionTitle,
                ),
                const SizedBox(height: 16),
                if (_placesLoaded && _places.isEmpty)
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
                    normalizedCategory: saved.place.normalizedCategory,
                    imageData: saved.place.image,
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

class _TripSummaryHero extends StatelessWidget {
  const _TripSummaryHero({required this.trip});

  final TripDraft trip;

  @override
  Widget build(BuildContext context) {
    final destination = trip.destination?.name ?? 'Your journey';
    const bundledCities = <String>{
      'Jaipur',
      'Varanasi',
      'Ujjain',
      'Udaipur',
      'Manali',
      'Goa',
      'Rishikesh',
    };
    return Container(
      height: 300,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: YCStyle.ink,
        borderRadius: BorderRadius.circular(30),
        image: bundledCities.contains(destination)
            ? DecorationImage(
                image: AssetImage(
                  'lib/assets/home/${destination.toLowerCase()}.png',
                ),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x08000000), Color(0xE1141B34)],
            stops: [.28, 1],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${trip.durationDays} DAYS AWAY',
                style: YCStyle.caption.copyWith(
                  color: YCStyle.saffron,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                destination,
                style: YCStyle.display.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 7),
              Text(
                '${MaterialLocalizations.of(context).formatMediumDate(trip.startDate)} – ${MaterialLocalizations.of(context).formatMediumDate(trip.endDate)}',
                style: YCStyle.body.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                trip.purposes.join(' · '),
                style: YCStyle.secondary.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 5),
              Text(
                'Starting from ${trip.startLocationName ?? trip.arrivalPoint}',
                style: YCStyle.secondary.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 5),
              Text(
                '${trip.travelPace} pace · ${trip.transportPreferences.join(', ')}',
                style: YCStyle.secondary.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SettingsScreen
// ─────────────────────────────────────────────────────────────────────────────

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
          _LightCard(
            child: Column(
              children: [
                _YCRow(
                  icon: Icons.location_on_outlined,
                  title: 'Location permissions',
                  subtitle: 'Used only when you choose your current location',
                  onTap: _locationSettings,
                ),
                _YCRowDivider(),
                const _YCRow(
                  icon: Icons.light_mode_outlined,
                  title: 'Appearance',
                  subtitle: 'YatraCanvas light appearance',
                ),
                _YCRowDivider(),
                const _YCRow(
                  icon: Icons.notifications_none,
                  title: 'Notifications',
                  subtitle: 'Trip notifications are not available yet',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _LightCard(
            child: Column(
              children: [
                _YCRow(
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
                _YCRowDivider(),
                const _YCRow(
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

// ─────────────────────────────────────────────────────────────────────────────
// _LightCard (white surface for non-profile screens)
// ─────────────────────────────────────────────────────────────────────────────

class _LightCard extends StatelessWidget {
  const _LightCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: YCStyle.border),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: child,
    ),
  );
}
