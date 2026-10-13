import 'package:flutter/material.dart';

import '../data/admin_repository.dart';
import '../widgets/admin_components.dart';
import 'admin_collection_screen.dart';
import 'people_trip_screens.dart';

class ResearchListScreen extends StatelessWidget {
  const ResearchListScreen({
    required this.repository,
    required this.cityKey,
    super.key,
  });
  final AdminRepository repository;
  final String cityKey;
  @override
  Widget build(BuildContext context) => AdminCollectionScreen(
    title: 'Research Queue',
    path: 'research/tasks',
    query: {'city': cityKey},
    repository: repository,
    filters: const {
      'priority': ['P0', 'P1', 'P2', 'P3', 'P4'],
      'type': [
        'REAL_PRIMARY_IMAGE',
        'OPENING_HOURS',
        'DESCRIPTION',
        'WEBSITE',
        'COORDINATE_RESEARCH',
        'IDENTITY_RESEARCH',
      ],
      'status': ['OPEN', 'ACCEPTED', 'REJECTED', 'MANUAL_REVIEW'],
    },
    subtitleFor: (r) =>
        '${r['priority']} • ${r['type']}\n${r['priority_reason']}\n${r['status']}',
    emptyMessage: 'No research tasks require attention for these filters.',
    onOpen: (context, r) => openAdminPage(
      context,
      ResearchDetailScreen(repository: repository, cityKey: cityKey, task: r),
    ),
  );
}

class ResearchDetailScreen extends StatefulWidget {
  const ResearchDetailScreen({
    required this.repository,
    required this.cityKey,
    required this.task,
    super.key,
  });
  final AdminRepository repository;
  final String cityKey;
  final Map<String, dynamic> task;
  @override
  State<ResearchDetailScreen> createState() => _ResearchDetailScreenState();
}

class _ResearchDetailScreenState extends State<ResearchDetailScreen> {
  final _suggested = TextEditingController(),
      _evidence = TextEditingController(),
      _notes = TextEditingController();
  final _latitude = TextEditingController(),
      _longitude = TextEditingController(),
      _extra = TextEditingController();
  bool _busy = false;
  String get _type => '${widget.task['type']}';
  @override
  void initState() {
    super.initState();
    final changes = widget.task['review']?['changes'] as Map? ?? {};
    final field = switch (_type) {
      'DESCRIPTION' => 'description',
      'WEBSITE' => 'website',
      'IDENTITY_RESEARCH' => 'name',
      _ => 'opening_hours',
    };
    final value = changes[field];
    _suggested.text = value is Map
        ? '${value['raw'] ?? value['normalized'] ?? ''}'
        : '${value ?? ''}';
    _latitude.text = '${changes['latitude'] ?? ''}';
    _longitude.text = '${changes['longitude'] ?? ''}';
    _extra.text = _type == 'IDENTITY_RESEARCH'
        ? (changes['aliases'] as List? ?? []).join(', ')
        : '${changes['address'] ?? ''}';
    _evidence.text = '${widget.task['review']?['evidence_url'] ?? ''}';
    _notes.text = '${widget.task['review']?['notes'] ?? ''}';
  }

  @override
  void dispose() {
    _suggested.dispose();
    _evidence.dispose();
    _notes.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _extra.dispose();
    super.dispose();
  }

  Future<void> _review(String status) async {
    if (_busy) return;
    final changes = <String, dynamic>{};
    if (status == 'ACCEPTED') {
      final value = _suggested.text.trim();
      String? error;
      if (!RegExp(r'^https?://[^\s/]+').hasMatch(_evidence.text.trim())) {
        error = 'Enter a source evidence URL.';
      }
      switch (_type) {
        case 'DESCRIPTION':
          changes['description'] = value;
        case 'WEBSITE':
          changes['website'] = value;
        case 'OPENING_HOURS':
          changes['opening_hours'] = {
            'raw': value,
            'normalized': value,
            'source': 'admin_review',
            'verified': false,
            'confidence': 0,
          };
        case 'IDENTITY_RESEARCH':
          changes['name'] = value;
          if (_extra.text.trim().isNotEmpty) {
            changes['aliases'] = _extra.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
        case 'COORDINATE_RESEARCH':
          final lat = double.tryParse(_latitude.text),
              lon = double.tryParse(_longitude.text);
          if (lat == null ||
              lon == null ||
              !lat.isFinite ||
              !lon.isFinite ||
              lat.abs() > 90 ||
              lon.abs() > 180) {
            error = 'Enter valid latitude and longitude.';
          } else {
            changes.addAll({'latitude': lat, 'longitude': lon});
            if (_extra.text.trim().isNotEmpty) {
              changes['address'] = _extra.text.trim();
            }
          }
        default:
          error =
              'Use the existing City Lab image import workflow for this task.';
      }
      if (_type != 'COORDINATE_RESEARCH' && value.isEmpty) {
        error = 'Enter a suggested value.';
      }
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
        return;
      }
    }
    if (status != 'MANUAL_REVIEW' &&
        !await confirmAction(
          context,
          '${label(status)} research?',
          'This records a human decision. It does not automatically publish the suggested value.',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final city = await widget.repository.get(
        'city-lab/cities/${widget.cityKey}',
      );
      await widget.repository.mutate(
        'research/${widget.task['task_id']}/review',
        {
          'fingerprint': city['fingerprint'],
          'expected_updated_at': widget.task['review']?['updated_at'],
          'status': status,
          'changes': changes,
          'evidence_url': _evidence.text.trim().isEmpty
              ? null
              : _evidence.text.trim(),
          'notes': _notes.text.trim(),
        },
        query: {'city': widget.cityKey},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Research decision recorded.')),
        );
        Navigator.pop(context);
      }
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.task['name']}')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        RecordSection('Research task', {
          for (final k in [
            'task_id',
            'type',
            'priority',
            'priority_reason',
            'status',
            'place',
            'known_evidence',
            'requested_output',
            'review',
          ])
            k: widget.task[k],
        }),
        const RecordSection('Evidence policy', {
          'review': 'Low confidence external research is never accepted automatically. Human acceptance needs a proposed value and source evidence. Canonical application uses the existing DataFactory import validation.',
        }),
        if (_type == 'REAL_PRIMARY_IMAGE')
          const RecordSection('Image research', {
            'next_step': 'Import a replacement in City Lab with identity, licensing and source evidence. You can record rejection or manual review here.',
          })
        else if (_type == 'COORDINATE_RESEARCH') ...[
          TextField(
            controller: _latitude,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(labelText: 'Suggested latitude'),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _longitude,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(labelText: 'Suggested longitude'),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _extra,
            decoration: const InputDecoration(
              labelText: 'Reviewed address (optional)',
            ),
          ),
        ] else
          TextField(
            controller: _suggested,
            maxLines: _type == 'DESCRIPTION' ? 4 : 1,
            keyboardType: _type == 'WEBSITE'
                ? TextInputType.url
                : TextInputType.text,
            decoration: InputDecoration(
              labelText: switch (_type) {
                'WEBSITE' => 'Suggested official website',
                'OPENING_HOURS' => 'Suggested opening hours',
                'IDENTITY_RESEARCH' => 'Reviewed name',
                _ => 'Suggested description',
              },
              helperText: _type == 'OPENING_HOURS'
                  ? 'Use the source schedule, for example Mo-Su 09:00-17:00.'
                  : null,
            ),
          ),
        if (_type == 'IDENTITY_RESEARCH')
          TextField(
            controller: _extra,
            decoration: const InputDecoration(
              labelText: 'Reviewed aliases, separated by commas',
            ),
          ),
        const SizedBox(height: 18),
        TextField(
          controller: _evidence,
          decoration: const InputDecoration(labelText: 'Source evidence URL'),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Research notes'),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: _busy || _type == 'REAL_PRIMARY_IMAGE'
                  ? null
                  : () => _review('ACCEPTED'),
              child: const Text('Accept for review'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _review('REJECTED'),
              child: const Text('Reject'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _review('MANUAL_REVIEW'),
              child: const Text('Needs manual review'),
            ),
          ],
        ),
        if (_busy) const Center(child: CircularProgressIndicator()),
      ],
    ),
  );
}
