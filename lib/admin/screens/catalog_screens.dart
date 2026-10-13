import 'package:flutter/material.dart';

import '../../theme/yc_style.dart';
import '../data/admin_repository.dart';
import '../widgets/admin_components.dart';
import 'admin_collection_screen.dart';

class OnlinePlaceListScreen extends StatelessWidget {
  const OnlinePlaceListScreen({required this.repository, super.key});
  final AdminRepository repository;
  @override
  Widget build(BuildContext context) => AdminCollectionScreen(
    title: 'Online Place Manager',
    path: 'places',
    repository: repository,
    filters: const {
      'moderation_status': [
        'ACTIVE',
        'HIDDEN',
        'RESTRICTED',
        'DUPLICATE',
        'INVALID',
      ],
    },
    advancedFilters: const {
      'city_id': 'Backend city ID',
      'category': 'Category',
    },
    titleFor: (row) => '${row['name']}',
    subtitleFor: (row) =>
        '${row['city_name'] ?? 'City not recorded'} · ${row['category']}\n${label('${row['moderation_status']}')} · ${row['reports_count']} reports',
    emptyMessage: 'No online catalog places match. Canonical pack records are in City Lab.',
    onOpen: (context, row) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OnlinePlaceDetailScreen(repository: repository, id: '${row['id']}'),
      ),
    ),
  );
}

class OnlinePlaceDetailScreen extends StatelessWidget {
  const OnlinePlaceDetailScreen({
    required this.repository,
    required this.id,
    super.key,
  });
  final AdminRepository repository;
  final String id;
  @override
  Widget build(BuildContext context) => AdminAsyncScreen(
    title: 'Online place record',
    load: () => repository.get('places/$id'),
    builder: (context, row, refresh) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('${row['name']}', style: YCStyle.sectionTitle),
        const SizedBox(height: 12),
        const AdminNotice(
          'This is a backend catalog record. Moderation changes affect online discovery. Offline packs require the separate City Lab review and immutable release workflow.',
        ),
        RecordSection('Identity and location', {
          for (final key in [
            'id',
            'city_id',
            'city_name',
            'category',
            'wikidata_id',
            'latitude',
            'longitude',
          ])
            key: row[key],
        }),
        RecordSection('Visiting information', {
          'opening_hours_status': row['opening_hours_status'],
          'raw_opening_hours': row['raw_opening_hours'],
          'recorded_intervals': row['opening_hours'],
          'verification': 'Parsing an opening schedule does not establish human verification.',
        }),
        Text('Source evidence', style: YCStyle.cardTitle),
        const SizedBox(height: 12),
        if ((row['sources'] as List? ?? []).isEmpty)
          const AdminNotice(
            'No provider provenance is recorded for this place.',
          ),
        for (final source in row['sources'] as List? ?? [])
          RecordSection(
            '${source['source'] ?? 'Recorded source'}',
            Map<String, dynamic>.from(source as Map),
          ),
        const AdminNotice(
          'This endpoint does not supply verified photographs or media integrity evidence. A displayed traveler fallback image is not proof of authentic media.',
        ),
        if ((row['reports_count'] as num? ?? 0) > 0)
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ReportListScreen(repository: repository, placeId: id),
              ),
            ),
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Review this place’s reports'),
          ),
        const SizedBox(height: 16),
        _DecisionForm(
          key: ValueKey('${row['moderation_status']}'),
          title: 'Online moderation',
          initialStatus: '${row['moderation_status']}',
          initialNotes: '',
          statuses: const [
            'ACTIVE',
            'HIDDEN',
            'RESTRICTED',
            'DUPLICATE',
            'INVALID',
          ],
          notesLabel: 'Reason and supporting evidence',
          confirmation: 'Apply this moderation decision to the online catalog? The action records your account and reason in the audit log. Offline packs are unchanged.',
          save: (status, notes) async {
            await repository.mutate('places/$id', {
              'moderation_status': status,
              'reason': notes,
              'expected_moderation_status': row['moderation_status'],
            }, patch: true);
          },
          refresh: refresh,
        ),
      ],
    ),
  );
}

class ReportListScreen extends StatelessWidget {
  const ReportListScreen({required this.repository, this.placeId, super.key});
  final AdminRepository repository;
  final String? placeId;
  @override
  Widget build(BuildContext context) => AdminCollectionScreen(
    title: 'Place Reports',
    path: 'reports',
    repository: repository,
    query: {'place_id': ?placeId},
    filters: const {
      'status': ['OPEN', 'REVIEWING', 'RESOLVED', 'REJECTED'],
    },
    advancedFilters: const {
      'city_id': 'Backend city ID',
      'reason': 'Issue type',
    },
    titleFor: (row) => '${row['place_name'] ?? 'Place not available'}',
    subtitleFor: (row) =>
        '${row['city_name'] ?? 'City not recorded'} · ${label('${row['status']}')}\n${label('${row['reason']}')}',
    emptyMessage: 'No submitted reports match these filters.',
    onOpen: (context, row) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ReportDetailScreen(repository: repository, id: '${row['id']}'),
      ),
    ),
  );
}

class ReportDetailScreen extends StatelessWidget {
  const ReportDetailScreen({
    required this.repository,
    required this.id,
    super.key,
  });
  final AdminRepository repository;
  final String id;
  @override
  Widget build(BuildContext context) => AdminAsyncScreen(
    title: 'Review place report',
    load: () => repository.get('reports/$id'),
    builder: (context, row, refresh) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '${row['place_name'] ?? 'Place not available'}',
          style: YCStyle.sectionTitle,
        ),
        const SizedBox(height: 12),
        RecordSection('Submitted evidence', {
          'issue': label('${row['reason']}'),
          'details': row['details'],
          'city': row['city_name'],
          'submitted_at': row['created_at'],
          'report_id': row['id'],
        }),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => OnlinePlaceDetailScreen(
                repository: repository,
                id: '${row['place_id']}',
              ),
            ),
          ),
          icon: const Icon(Icons.place_outlined),
          label: const Text('Inspect affected place'),
        ),
        const SizedBox(height: 16),
        const AdminNotice(
          'Resolving a report records a review decision. It does not modify the affected place or publish an offline correction.',
        ),
        _DecisionForm(
          key: ValueKey('${row['updated_at']}'),
          title: 'Review decision',
          initialStatus: '${row['status']}',
          initialNotes: '${row['admin_notes'] ?? ''}',
          statuses: const ['OPEN', 'REVIEWING', 'RESOLVED', 'REJECTED'],
          notesLabel: 'Review notes and evidence',
          confirmation: 'Save this report decision and notes? Your account and changes will be recorded in the audit log.',
          save: (status, notes) async {
            await repository.mutate('reports/$id', {
              'status': status,
              'admin_notes': notes,
              'expected_updated_at': row['updated_at'],
            }, patch: true);
          },
          refresh: refresh,
        ),
      ],
    ),
  );
}

class _DecisionForm extends StatefulWidget {
  const _DecisionForm({
    required this.title,
    required this.initialStatus,
    required this.initialNotes,
    required this.statuses,
    required this.notesLabel,
    required this.confirmation,
    required this.save,
    required this.refresh,
    super.key,
  });
  final String title, initialStatus, initialNotes, notesLabel, confirmation;
  final List<String> statuses;
  final Future<void> Function(String, String) save;
  final VoidCallback refresh;
  @override
  State<_DecisionForm> createState() => _DecisionFormState();
}

class _DecisionFormState extends State<_DecisionForm> {
  final _form = GlobalKey<FormState>();
  late final _notes = TextEditingController(text: widget.initialNotes);
  late String _status = widget.initialStatus;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (!await confirmAction(
      context,
      'Confirm decision',
      widget.confirmation,
    )) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    try {
      await widget.save(_status, _notes.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Decision saved to the backend audit log.'),
        ),
      );
      widget.refresh();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AdminCard(
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: YCStyle.cardTitle),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _status,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              for (final status in widget.statuses)
                DropdownMenuItem(value: status, child: Text(label(status))),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _status = value!),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _notes,
            enabled: !_busy,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            decoration: InputDecoration(labelText: widget.notesLabel),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Add a reason or evidence for your decision.'
                : null,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.check),
            label: Text(_busy ? 'Saving decision…' : 'Save decision'),
          ),
        ],
      ),
    ),
  );
}
