import 'package:flutter/material.dart';

import '../data/admin_repository.dart';
import '../widgets/admin_components.dart';
import 'admin_collection_screen.dart';
import 'people_trip_screens.dart';

class SystemHealthScreen extends StatelessWidget {
  const SystemHealthScreen({required this.repository, super.key});
  final AdminRepository repository;
  @override
  Widget build(BuildContext context) => AdminAsyncScreen(
    title: 'System Health',
    load: () async => {
      'health': await repository.get('system-health'),
      'provider_configuration': await repository.get('provider-status'),
    },
    builder: (context, data, refresh) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        RecordSection(
          'Recorded backend state',
          Map<String, dynamic>.from(data['health'] as Map),
        ),
        FilledButton(
          onPressed: () => openAdminPage(
            context,
            AdminCollectionScreen(
              title: 'Refresh jobs',
              path: 'jobs',
              repository: repository,
              filters: const {
                'state': ['queued', 'running', 'completed', 'failed'],
              },
              titleFor: (r) => '${r['versioned_category']}',
              subtitleFor: (r) =>
                  '${r['state']} • ${r['attempt_count']} attempts\n${r['city_id']}',
              emptyMessage: 'No refresh jobs match this state.',
              onOpen: (context, job) => openAdminPage(
                context,
                Scaffold(
                  appBar: AppBar(title: const Text('Job diagnostics')),
                  body: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [RecordSection('Recorded job', job)],
                  ),
                ),
              ),
            ),
          ),
          child: const Text('Inspect background jobs'),
        ),
        const SizedBox(height: 24),
        RecordSection(
          'Provider configuration, no connectivity probes',
          Map<String, dynamic>.from(data['provider_configuration'] as Map),
        ),
      ],
    ),
  );
}

class AuditDetailScreen extends StatelessWidget {
  const AuditDetailScreen({required this.row, super.key});
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Audit event')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        RecordSection('Actor and operation', {
          for (final k in [
            'timestamp',
            'admin_user_id',
            'action',
            'entity_type',
            'entity_id',
            'city_id',
            'reason',
          ])
            k: row[k],
        }),
        RecordSection(
          'Before',
          Map<String, dynamic>.from(row['before'] as Map? ?? {}),
        ),
        RecordSection(
          'After',
          Map<String, dynamic>.from(row['after'] as Map? ?? {}),
        ),
      ],
    ),
  );
}

class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({required this.repository, super.key});
  final AdminRepository repository;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        RecordSection('Session', {
          'name': repository.auth.session?.user.name,
          'email': repository.auth.session?.user.email,
          'role': repository.auth.session?.user.role.value,
        }),
        const RecordSection('Operational boundaries', {
          'city_data':
              'Immutable canonical releases and backend review overlays.',
          'publishing': 'Remote deployment is not configured.',
          'identity': 'Local backend JWT accounts. Production identity provider and reset email delivery remain deployment work.',
          'sessions': 'Native credentials use secure storage. Web sessions last only while this app page remains open.',
        }),
        OutlinedButton.icon(
          onPressed: repository.auth.logout,
          icon: const Icon(Icons.logout),
          label: const Text('Logout'),
        ),
      ],
    ),
  );
}
