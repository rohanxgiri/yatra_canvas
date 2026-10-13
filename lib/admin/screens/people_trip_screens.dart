import 'package:flutter/material.dart';

import '../../theme/yc_style.dart';
import '../data/admin_repository.dart';
import '../widgets/admin_components.dart';
import 'admin_collection_screen.dart';

void openAdminPage(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

class TripListScreen extends StatelessWidget {
  const TripListScreen({required this.repository, this.userId, super.key});
  final AdminRepository repository;
  final String? userId;
  @override
  Widget build(BuildContext context) => AdminCollectionScreen(
    title: 'Trips',
    path: 'trips',
    filters: const {
      'date_state': ['UPCOMING', 'ACTIVE', 'PAST', 'UNDATED'],
    },
    repository: repository,
    query: {'user_id': ?userId},
    titleFor: (r) => '${r['trip_name']}',
    subtitleFor: (r) =>
        '${r['city_name'] ?? 'Unknown destination'} • ${r['days']} days\n${r['user_name'] ?? 'Legacy development traveller'}\n${r['saved_places_count']} selected • ${r['itinerary_stops_count']} scheduled\n${r['id']}',
    onOpen: (context, row) => openAdminPage(
      context,
      TripDetailScreen(repository: repository, tripId: '${row['id']}'),
    ),
  );
}

class TripDetailScreen extends StatelessWidget {
  const TripDetailScreen({
    required this.repository,
    required this.tripId,
    super.key,
  });
  final AdminRepository repository;
  final String tripId;
  @override
  Widget build(BuildContext context) => AdminAsyncScreen(
    title: 'Trip inspection',
    load: () => repository.get('trips/$tripId'),
    builder: (context, data, refresh) {
      final saved = (data['saved_places'] as List).cast<Map>();
      final itinerary = (data['itinerary'] as List).cast<Map>();
      final scheduled = itinerary.map((r) => r['place_id']).toSet();
      final unscheduled = saved
          .where((r) => !scheduled.contains(r['place_id']))
          .toList();
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('${data['trip_name']}', style: YCStyle.sectionTitle),
          const SizedBox(height: 12),
          const StatusBadge('READ_ONLY'),
          const SizedBox(height: 20),
          RecordSection('Trip', {
            for (final k in [
              'id',
              'user_id',
              'user_name',
              'city_name',
              'start_date',
              'days',
              'arrival_place',
              'start_location_type',
              'start_location_name',
              'created_at',
            ])
              k: data[k],
          }),
          RecordSection('Selected preferences', {
            'preferences': data['preferences'],
          }),
          for (final day in (data['trip_days'] as List).cast<Map>())
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Day ${day['day_number']} • ${day['date']}',
                    style: YCStyle.cardTitle,
                  ),
                  const SizedBox(height: 8),
                  StatusBadge('${day['day_type']}'),
                  const SizedBox(height: 12),
                  if (day['day_type'] != 'REST')
                    Text(
                      '${day['start_time']}–${day['end_time']}',
                      style: YCStyle.secondary,
                    ),
                  for (final stop in itinerary.where(
                    (stop) => stop['day_number'] == day['day_number'],
                  ))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${stop['visit_order']}. ${stop['place_name']}',
                      ),
                      subtitle: Text(
                        '${stop['planned_arrival_time']}–${stop['planned_departure_time']}\n${stop['travel_time_minutes'] ?? 'Unknown'} travel minutes • ${stop['status']}',
                      ),
                    ),
                  if (day['day_type'] == 'REST') const Text('Rest day'),
                  if (day['day_type'] != 'REST' &&
                      !itinerary.any(
                        (stop) => stop['day_number'] == day['day_number'],
                      ))
                    const Text('No persisted stops for this day.'),
                ],
              ),
            ),
          RecordSection('Saved selections and scheduling locks', {
            'places': saved,
          }),
          if (unscheduled.isEmpty)
            const AdminEmpty(
              'All saved selections appear in the persisted itinerary.',
            )
          else
            RecordSection('Unscheduled selections', {
              'places': unscheduled
                  .map(
                    (p) => {
                      'name': p['place_name'],
                      'place_id': p['place_id'],
                      'reason': 'UNKNOWN, planner reasons are not persisted',
                    },
                  )
                  .toList(),
            }),
          const RecordSection('Planner evidence', {
            'availability': 'Recommendation score breakdowns and historical unscheduled reasons are not persisted by the current planner. This inspector never replans or changes the trip.',
          }),
        ],
      );
    },
  );
}

class UserListScreen extends StatelessWidget {
  const UserListScreen({required this.repository, super.key});
  final AdminRepository repository;
  @override
  Widget build(BuildContext context) => AdminCollectionScreen(
    title: 'Users',
    path: 'users',
    repository: repository,
    filters: const {
      'role': ['USER', 'ADMIN'],
    },
    subtitleFor: (r) =>
        '${r['email']}\n${r['role']} • ${r['is_active'] == true ? 'Enabled' : 'Disabled'} • ${r['trip_count']} trips',
    onOpen: (context, row) => openAdminPage(
      context,
      UserDetailScreen(repository: repository, userId: '${row['id']}'),
    ),
  );
}

class UserDetailScreen extends StatefulWidget {
  const UserDetailScreen({
    required this.repository,
    required this.userId,
    super.key,
  });
  final AdminRepository repository;
  final String userId;
  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  bool _busy = false;
  Future<void> _change(
    Map<String, dynamic> changes,
    VoidCallback refresh,
    String title,
  ) async {
    if (_busy ||
        !await confirmAction(
          context,
          title,
          'Confirm this account change. It will be recorded in audit history.',
        )) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.mutate('users/${widget.userId}', {
        ...changes,
        'reason': title,
      }, patch: true);
      if (mounted) refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdminAsyncScreen(
    title: 'User account',
    load: () => widget.repository.get('users/${widget.userId}'),
    builder: (context, data, refresh) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        RecordSection('Profile', data),
        const RecordSection('Activity availability', {
          'last_active': 'Not collected',
          'preferences': 'Available on individual trips only',
        }),
        FilledButton(
          onPressed: () => openAdminPage(
            context,
            TripListScreen(
              repository: widget.repository,
              userId: widget.userId,
            ),
          ),
          child: const Text('View trips'),
        ),
        const SizedBox(height: 12),
        if (widget.userId != widget.repository.auth.session?.user.id) ...[
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _change(
                    {'is_active': data['is_active'] != true},
                    refresh,
                    data['is_active'] == true
                        ? 'Disable account'
                        : 'Enable account',
                  ),
            child: Text(
              data['is_active'] == true ? 'Disable account' : 'Enable account',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _change(
                    {'role': data['role'] == 'ADMIN' ? 'USER' : 'ADMIN'},
                    refresh,
                    'Change role to ${data['role'] == 'ADMIN' ? 'USER' : 'ADMIN'}',
                  ),
            child: const Text('Change role'),
          ),
        ],
        if (_busy) const Center(child: CircularProgressIndicator()),
      ],
    ),
  );
}
