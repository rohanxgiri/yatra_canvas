import 'package:flutter/material.dart';

import '../../theme/yc_style.dart';
import '../data/admin_repository.dart';
import '../widgets/admin_components.dart';
import 'catalog_screens.dart';
import 'city_lab_screens.dart';
import 'operational_screens.dart';
import 'people_trip_screens.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({required this.repository, super.key});
  final AdminRepository repository;
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const _paths = {
    'operations': 'dashboard',
    'health': 'system-health',
    'cities': 'city-lab/cities',
    'canonical': 'city-lab/summary',
  };
  final _data = <String, Map<String, dynamic>>{};
  final _errors = <String, Object>{};
  final _refreshed = <String, DateTime>{};
  final _pending = <String>{};
  int _sequence = 0;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final sequence = ++_sequence;
    setState(() {
      _pending.addAll(_paths.keys);
      _errors.clear();
    });
    await Future.wait(
      _paths.entries.map((entry) async {
        try {
          final result = await widget.repository.get(entry.value);
          if (!mounted || sequence != _sequence) return;
          setState(() {
            _data[entry.key] = result;
            _refreshed[entry.key] = DateTime.now();
            _pending.remove(entry.key);
          });
        } catch (error) {
          if (!mounted || sequence != _sequence) return;
          setState(() {
            _errors[entry.key] = error;
            _pending.remove(entry.key);
          });
        }
      }),
    );
  }

  void _open(Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));
  String _time(DateTime value) => MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(value), alwaysUse24HourFormat: true);
  Widget _metrics(List<Widget> cards) => LayoutBuilder(
    builder: (context, box) {
      final minWidth = MediaQuery.textScalerOf(context).scale(180);
      final columns = ((box.maxWidth + 12) / (minWidth + 12)).floor().clamp(
        1,
        4,
      );
      final width = (box.maxWidth - 12 * (columns - 1)) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final card in cards) SizedBox(width: width, child: card),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final metrics = _data['operations'];
    final canonical = _data['canonical'];
    final health = _data['health'];
    final cities = ((_data['cities']?['items'] as List?) ?? []).cast<Map>();
    final reports = (metrics?['recent_reports'] as List? ?? []).cast<Map>();
    final trips = (metrics?['recent_trips'] as List? ?? []).cast<Map>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _pending.isEmpty ? _reload : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width >= 1050 ? 32 : 20,
          ),
          children: [
            Text(
              'Your operational overview',
              style: YCStyle.title.copyWith(
                fontSize: 30,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Review urgent issues, inspect records, and prepare safer city releases.',
              style: YCStyle.secondary,
            ),
            const SizedBox(height: 16),
            if (_refreshed['operations'] case final time?)
              Text(
                'Backend counts · Last refreshed ${_time(time)} (local time)',
                style: YCStyle.caption,
              ),
            if (_pending.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(
                  semanticsLabel: 'Refreshing admin sources',
                ),
              ),
            for (final error in _errors.entries)
              AdminNotice(
                '${label(error.key)} could not refresh. '
                '${_data.containsKey(error.key) ? 'Showing the last successful result from ${_time(_refreshed[error.key]!)}. ' : ''}'
                '${error.value}',
                error: true,
                retry: _pending.isEmpty ? _reload : null,
              ),
            const SizedBox(height: 16),
            if (metrics != null) ...[
              _metrics([
                AdminMetricCard(
                  title: 'Registered users',
                  value: metrics['total_users'],
                  scope: 'Backend accounts',
                  icon: Icons.people_outline,
                  onTap: () =>
                      _open(UserListScreen(repository: widget.repository)),
                ),
                AdminMetricCard(
                  title: 'Recorded trips',
                  value: metrics['total_trips'],
                  scope: 'Backend records only',
                  icon: Icons.route_outlined,
                  onTap: () =>
                      _open(TripListScreen(repository: widget.repository)),
                ),
                AdminMetricCard(
                  title: 'Online catalog places',
                  value: metrics['total_places'],
                  scope: 'Backend place catalog',
                  icon: Icons.place_outlined,
                  onTap: () => _open(
                    OnlinePlaceListScreen(repository: widget.repository),
                  ),
                ),
                AdminMetricCard(
                  title: 'Enabled destinations',
                  value: metrics['active_destinations'],
                  scope: 'Backend city catalog',
                  icon: Icons.location_city_outlined,
                ),
                AdminMetricCard(
                  title: 'Open reports',
                  value: metrics['open_reports_count'],
                  scope: 'Open or under review',
                  icon: Icons.flag_outlined,
                  onTap: () =>
                      _open(ReportListScreen(repository: widget.repository)),
                ),
              ]),
              const SizedBox(height: 16),
              const AdminNotice(
                'Local offline trips are stored on the traveler’s device. They are excluded from backend trip counts. Online catalog places and canonical release records are separate sources.',
              ),
            ],
            if (canonical?['configured'] == true) ...[
              if (canonical?['inventory_complete'] == false)
                AdminNotice(
                  '${(canonical?['inventory_problems'] as List? ?? []).length} source releases have unreadable or invalid metadata. Canonical counts include readable releases only; this inventory is incomplete.',
                  error: true,
                ),
              Text('Connected canonical releases', style: YCStyle.cardTitle),
              const SizedBox(height: 6),
              Text(
                'DataFactory records for the selected release of each connected city. These counts do not establish app pack certification.',
                style: YCStyle.secondary,
              ),
              const SizedBox(height: 12),
              _metrics([
                AdminMetricCard(
                  title: 'Connected cities',
                  value: canonical!['city_count'],
                  scope: 'Configured release root',
                  icon: Icons.location_city_outlined,
                  onTap: () =>
                      _open(CityListScreen(repository: widget.repository)),
                ),
                AdminMetricCard(
                  title: 'Release place records',
                  value: canonical['published_places'],
                  scope: 'Canonical source releases',
                  icon: Icons.dataset_outlined,
                ),
                AdminMetricCard(
                  title: 'Missing image references',
                  value: canonical['quality']?['missing_image'],
                  scope: 'Completeness check only',
                  icon: Icons.image_outlined,
                  onTap: () => _open(
                    CityListScreen(
                      repository: widget.repository,
                      qualityMode: true,
                    ),
                  ),
                ),
                AdminMetricCard(
                  title: 'Unknown hours',
                  value: canonical['quality']?['missing_hours'],
                  scope: 'Recorded source hours',
                  icon: Icons.schedule_outlined,
                  onTap: () => _open(
                    CityListScreen(
                      repository: widget.repository,
                      qualityMode: true,
                    ),
                  ),
                ),
              ]),
              if (_refreshed['canonical'] case final time?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Canonical counts refreshed ${_time(time)} (local time)',
                    style: YCStyle.caption,
                  ),
                ),
            ],
            const SizedBox(height: 20),
            Text('Requires attention', style: YCStyle.cardTitle),
            const SizedBox(height: 12),
            if ((health?['jobs']?['failed'] as num? ?? 0) > 0)
              AdminCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.error_outline),
                  title: const Text('Refresh jobs require attention'),
                  subtitle: Text(
                    '${health!['jobs']['failed']} recorded failed jobs',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      _open(SystemHealthScreen(repository: widget.repository)),
                ),
              ),
            if (metrics != null &&
                metrics['open_reports_count'] is num &&
                metrics['open_reports_count'] > 0)
              AdminCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Review traveler reports'),
                  subtitle: Text(
                    '${metrics['open_reports_count']} unresolved reports',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      _open(ReportListScreen(repository: widget.repository)),
                ),
              ),
            if (_data.containsKey('cities') && cities.isEmpty)
              const AdminNotice(
                'No canonical city releases are connected. City quality and certification evidence are unavailable.',
              ),
            for (final city in cities.where(
              (city) => city['status'] != 'READY',
            ))
              AdminCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${city['name']}', style: YCStyle.cardTitle),
                  subtitle: Text(
                    'Source release ${city['pack_version']} · ${label('${city['status']}')}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(
                    CityDetailScreen(
                      repository: widget.repository,
                      cityKey: '${city['id']}',
                    ),
                  ),
                ),
              ),
            if (_data['cities']?['has_more'] == true)
              TextButton(
                onPressed: () =>
                    _open(CityListScreen(repository: widget.repository)),
                child: const Text('View all connected cities'),
              ),
            if (metrics != null) ...[
              const SizedBox(height: 20),
              Text('Recent backend trips', style: YCStyle.cardTitle),
              const SizedBox(height: 12),
              if (trips.isEmpty)
                const AdminNotice(
                  'No trips have been recorded in the backend.',
                ),
              for (final trip in trips)
                AdminCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${trip['trip_name']}'),
                    subtitle: Text(
                      '${trip['city_name']} · ${trip['days']} days',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(
                      TripDetailScreen(
                        repository: widget.repository,
                        tripId: '${trip['id']}',
                      ),
                    ),
                  ),
                ),
              Text('Recent place reports', style: YCStyle.cardTitle),
              const SizedBox(height: 12),
              if (reports.isEmpty)
                const AdminNotice('No place reports have been submitted.'),
              for (final report in reports)
                AdminCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${report['place_name']}'),
                    subtitle: Text(
                      '${label('${report['reason']}')} · ${label('${report['status']}')}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(
                      ReportDetailScreen(
                        repository: widget.repository,
                        id: '${report['id']}',
                      ),
                    ),
                  ),
                ),
              RecordSection(
                'Online place moderation',
                Map<String, dynamic>.from(
                  metrics['places_by_status'] as Map? ?? {},
                ),
              ),
              const AdminNotice(
                'Provider configuration does not prove availability. System Health shows recorded diagnostics without making external probes.',
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _open(SystemHealthScreen(repository: widget.repository)),
                icon: const Icon(Icons.monitor_heart_outlined),
                label: const Text('View system health'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
