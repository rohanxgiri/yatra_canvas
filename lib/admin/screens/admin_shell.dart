import 'package:flutter/material.dart';

import '../../models/auth_controller.dart';
import '../../theme/yc_style.dart';
import '../data/admin_repository.dart';
import '../admin_theme.dart';
import 'admin_collection_screen.dart';
import 'admin_dashboard_screen.dart';
import 'catalog_screens.dart';
import 'city_lab_screens.dart';
import 'operational_screens.dart';
import 'people_trip_screens.dart';

enum AdminSection {
  dashboard('Overview', Icons.dashboard_outlined),
  cityLab('City Quality', Icons.location_city_outlined),
  trips('Trips', Icons.route_outlined),
  users('Users', Icons.people_outline),
  more('Operations', Icons.more_horiz);

  const AdminSection(this.title, this.icon);
  final String title;
  final IconData icon;
}

class AdminShell extends StatefulWidget {
  const AdminShell({required this.auth, this.repository, super.key});
  final AuthController auth;
  final AdminRepository? repository;
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  late final AdminRepository _repository;
  late final List<Widget> _screens;
  final _navigators = List.generate(5, (_) => GlobalKey<NavigatorState>());
  final _canHandlePop = List.filled(5, false);
  int _index = 0;
  final _visited = <int>{0};
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AdminRepository(auth: widget.auth);
    _screens = [
      AdminDashboardScreen(repository: _repository),
      CityListScreen(repository: _repository),
      TripListScreen(repository: _repository),
      UserListScreen(repository: _repository),
      AdminMoreScreen(repository: _repository, auth: widget.auth),
    ];
  }

  @override
  void dispose() {
    if (widget.repository == null) _repository.close();
    super.dispose();
  }

  void _select(int index) {
    if (_index == index) {
      _navigators[index].currentState?.popUntil((r) => r.isFirst);
    }
    setState(() {
      _visited.add(index);
      _index = index;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.auth,
    builder: (context, _) {
      if (!widget.auth.isAdmin) {
        return const Scaffold(
          body: Center(child: Text('Administrator access required.')),
        );
      }
      return Theme(
        data: AdminTheme.of(context),
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 700;
            return PopScope(
              canPop: !_canHandlePop[_index],
              onPopInvokedWithResult: (didPop, result) async {
                if (!didPop) await _navigators[_index].currentState?.maybePop();
              },
              child: Scaffold(
                body: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      if (wide)
                        NavigationRail(
                          extended: box.maxWidth >= 1050,
                          minWidth: 88,
                          minExtendedWidth: 248,
                          useIndicator: true,
                          selectedIndex: _index,
                          onDestinationSelected: _select,
                          leading: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AdminTheme.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.travel_explore,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                if (box.maxWidth >= 1050) ...[
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'YatraCanvas',
                                        style: YCStyle.cardTitle,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Admin Studio',
                                        style: YCStyle.caption,
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          trailing: Padding(
                            padding: const EdgeInsets.only(top: 32),
                            child: box.maxWidth >= 1050
                                ? OutlinedButton.icon(
                                    onPressed: widget.auth.logout,
                                    icon: const Icon(Icons.logout, size: 18),
                                    label: const Text('Logout'),
                                  )
                                : IconButton(
                                    tooltip: 'Logout',
                                    onPressed: widget.auth.logout,
                                    icon: const Icon(Icons.logout),
                                  ),
                          ),
                          destinations: [
                            for (final section in AdminSection.values)
                              NavigationRailDestination(
                                icon: Icon(section.icon),
                                label: Text(section.title),
                              ),
                          ],
                        ),
                      if (wide) const VerticalDivider(width: 1),
                      Expanded(
                        // Route barriers must not remove the sibling rail from
                        // the accessibility tree.
                        child: Semantics(
                          container: true,
                          child: IndexedStack(
                            index: _index,
                            children: [
                              for (var i = 0; i < _screens.length; i++)
                                if (!_visited.contains(i))
                                  const SizedBox.shrink()
                                else
                                  NotificationListener<NavigationNotification>(
                                    onNotification: (notification) {
                                      if (mounted &&
                                          _canHandlePop[i] !=
                                              notification.canHandlePop) {
                                        setState(
                                          () => _canHandlePop[i] =
                                              notification.canHandlePop,
                                        );
                                      }
                                      return false;
                                    },
                                    child: Navigator(
                                      key: _navigators[i],
                                      onGenerateRoute: (_) =>
                                          MaterialPageRoute<void>(
                                            builder: (_) => _screens[i],
                                          ),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                bottomNavigationBar: wide
                    ? null
                    : NavigationBar(
                        selectedIndex: _index,
                        onDestinationSelected: _select,
                        destinations: [
                          for (final section in AdminSection.values)
                            NavigationDestination(
                              icon: Icon(section.icon),
                              label: section.title,
                            ),
                        ],
                      ),
              ),
            );
          },
        ),
      );
    },
  );
}

class AdminMoreScreen extends StatelessWidget {
  const AdminMoreScreen({
    required this.repository,
    required this.auth,
    super.key,
  });
  final AdminRepository repository;
  final AuthController auth;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Operations')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final entry in <(String, IconData, Widget)>[
          (
            'Online Place Manager',
            Icons.place_outlined,
            OnlinePlaceListScreen(repository: repository),
          ),
          (
            'Place Reports',
            Icons.flag_outlined,
            ReportListScreen(repository: repository),
          ),
          (
            'Fix Center',
            Icons.fact_check_outlined,
            CityListScreen(repository: repository, qualityMode: true),
          ),
          (
            'Review Queue',
            Icons.science_outlined,
            CityListScreen(repository: repository, researchMode: true),
          ),
          (
            'City Releases',
            Icons.inventory_2_outlined,
            PackListScreen(repository: repository),
          ),
          (
            'System Health',
            Icons.monitor_heart_outlined,
            SystemHealthScreen(repository: repository),
          ),
          ('Audit Log', Icons.history, AuditListScreen(repository: repository)),
          (
            'Settings',
            Icons.settings_outlined,
            AdminSettingsScreen(repository: repository),
          ),
        ])
          Card(
            elevation: 0,
            child: ListTile(
              leading: Icon(entry.$2),
              title: Text(entry.$1),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => entry.$3)),
            ),
          ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: auth.logout,
          icon: const Icon(Icons.logout),
          label: const Text('Logout'),
        ),
      ],
    ),
  );
}

class AuditListScreen extends StatelessWidget {
  const AuditListScreen({required this.repository, super.key});
  final AdminRepository repository;
  @override
  Widget build(BuildContext context) => AdminCollectionScreen(
    title: 'Audit Log',
    path: 'audit-log',
    repository: repository,
    advancedFilters: const {
      'admin_user_id': 'Admin user ID',
      'action': 'Action',
      'city': 'City ID',
      'since': 'From date (UTC)',
    },
    filters: const {
      'entity_type': [
        'user',
        'place',
        'city',
        'research',
        'pack',
        'patch',
        'report',
      ],
    },
    titleFor: (row) => labelAction(row['action']),
    subtitleFor: (row) =>
        '${row['timestamp']}\n${row['entity_id']}\nActor ${row['admin_user_id']}',
    emptyMessage: 'No privileged actions have been recorded for this filter.',
    onOpen: (context, row) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AuditDetailScreen(row: row)),
    ),
  );
  String labelAction(dynamic value) => '$value'.replaceAll('_', ' ');
}
