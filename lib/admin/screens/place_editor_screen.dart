import 'package:flutter/material.dart';

import '../../theme/yc_style.dart';
import '../data/admin_repository.dart';
import '../widgets/admin_components.dart';

class PlaceEditorScreen extends StatelessWidget {
  const PlaceEditorScreen({
    required this.repository,
    required this.cityKey,
    required this.placeId,
    super.key,
  });
  final AdminRepository repository;
  final String cityKey, placeId;
  @override
  Widget build(BuildContext context) => AdminAsyncScreen(
    title: 'Place review',
    load: () => repository.get('city-lab/cities/$cityKey/places/$placeId'),
    builder: (context, data, refresh) => PlaceEditor(
      key: ValueKey('${data['fingerprint']}-${data['review']?['updated_at']}'),
      repository: repository,
      cityKey: cityKey,
      placeId: placeId,
      data: data,
      refresh: refresh,
    ),
  );
}

class PlaceEditor extends StatefulWidget {
  const PlaceEditor({
    required this.repository,
    required this.cityKey,
    required this.placeId,
    required this.data,
    required this.refresh,
    super.key,
  });
  final AdminRepository repository;
  final String cityKey, placeId;
  final Map<String, dynamic> data;
  final VoidCallback refresh;
  @override
  State<PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends State<PlaceEditor> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  final _evidence = TextEditingController(), _notes = TextEditingController();
  late Map<String, dynamic> _original;
  String _status = 'NEEDS_RESEARCH';
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    final s = widget.data['source'] as Map;
    _original = {
      'name': s['name'],
      'name_hi': s['name_hi'],
      'aliases': (s['alternate_names'] as List? ?? []).join(', '),
      'category': s['classification']['category'],
      'subcategory': s['classification']['subcategory'],
      'description': s['description'],
      'latitude': s['location']['latitude'],
      'longitude': s['location']['longitude'],
      'address': s['location']['address'],
      'website': s['contact']['website'],
      'phone': s['contact']['phone'],
      'opening_hours':
          s['opening_hours']['raw'] ?? s['opening_hours']['normalized'],
    };
    final review = widget.data['review'] as Map?;
    final edits = (review?['changes'] as Map?) ?? {};
    for (final field in _original.keys) {
      final value = edits.containsKey(field) ? edits[field] : _original[field];
      _fields[field] = TextEditingController(
        text: field == 'opening_hours' && value is Map
            ? '${value['raw'] ?? ''}'
            : field == 'aliases' && value is List
            ? value.join(', ')
            : '${value ?? ''}',
      );
    }
    _status = '${review?['status'] ?? 'NEEDS_RESEARCH'}';
    _evidence.text = '${review?['evidence_url'] ?? ''}';
    _notes.text = '${review?['notes'] ?? ''}';
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _evidence.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_status == 'EXCLUDE' &&
        !await confirmAction(
          context,
          'Exclude this record from review?',
          'The decision will be audited. Canonical records are preserved until a reviewed release workflow applies it.',
        )) {
      return;
    }
    final changes = <String, dynamic>{};
    for (final entry in _fields.entries) {
      final text = entry.value.text.trim();
      if (text == '${_original[entry.key] ?? ''}') continue;
      dynamic value = text.isEmpty ? null : text;
      if (entry.key == 'latitude' || entry.key == 'longitude') {
        value = double.parse(text);
      }
      if (entry.key == 'aliases') {
        value = text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (entry.key == 'opening_hours') {
        value = {
          ...Map<String, dynamic>.from(
            widget.data['source']['opening_hours'] as Map,
          ),
          'raw': text.isEmpty ? null : text,
          'normalized': text.isEmpty ? null : text,
          'verified': false,
          'confidence': 0,
          'source': 'admin_review',
        };
      }
      changes[entry.key] = value;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.mutate(
        'city-lab/cities/${widget.cityKey}/places/${widget.placeId}',
        {
          'fingerprint': widget.data['fingerprint'],
          'expected_updated_at': widget.data['review']?['updated_at'],
          'status': _status,
          'changes': changes,
          'notes': _notes.text.trim(),
          'evidence_url': _evidence.text.trim().isEmpty
              ? null
              : _evidence.text.trim(),
        },
        patch: true,
      );
      if (mounted) {
        widget.refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Review saved. Canonical release preserved.'),
          ),
        );
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
  Widget build(BuildContext context) {
    final source = Map<String, dynamic>.from(widget.data['source'] as Map),
        primary = source['images']['primary'] as Map?;
    final issues = (widget.data['issues'] as List).cast<String>();
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('${source['name']}', style: YCStyle.sectionTitle),
          const SizedBox(height: 16),
          if (primary?['local_path'] != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AdminImage(
                repository: widget.repository,
                cityKey: widget.cityKey,
                path: '${primary!['local_path']}',
              ),
            ),
          if (primary == null)
            const AdminEmpty('No primary image is recorded.'),
          if (primary != null)
            RecordSection(
              'Image provenance',
              Map<String, dynamic>.from(primary),
            ),
          if (issues.isNotEmpty)
            RecordSection('Quality issues', {'issues': issues}),
          RecordSection('Gallery references', {
            'gallery': source['images']['gallery'],
            'integrity': issues.contains('broken_gallery')
                ? 'Missing referenced files'
                : 'No broken local gallery references detected',
          }),
          for (final image in (source['images']['gallery'] as List? ?? []).take(
            12,
          ))
            if (image['local_path'] != null)
              AdminCard(
                child: Column(
                  children: [
                    AdminImage(
                      repository: widget.repository,
                      cityKey: widget.cityKey,
                      path: '${image['local_path']}',
                      height: 120,
                    ),
                    Text(
                      '${image['attribution'] ?? image['source'] ?? 'Attribution not recorded'}',
                      style: YCStyle.caption,
                    ),
                  ],
                ),
              ),
          const RecordSection('Image correction workflow', {
            'availability': 'Use City Lab image import to replace a photo with validated identity and licensing. Mark this place NEEDS_RESEARCH here; unverified remote URLs are not accepted as real photos.',
          }),
          for (final entry in _fields.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: TextFormField(
                controller: entry.value,
                maxLines: entry.key == 'description' ? 4 : 1,
                keyboardType: {'latitude', 'longitude'}.contains(entry.key)
                    ? const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      )
                    : TextInputType.text,
                decoration: InputDecoration(labelText: label(entry.key)),
                validator: (value) {
                  if (['name', 'category'].contains(entry.key) &&
                      (value == null || value.trim().isEmpty)) {
                    return 'This field is required.';
                  }
                  if (['latitude', 'longitude'].contains(entry.key)) {
                    final n = double.tryParse(value ?? ''),
                        bound = entry.key == 'latitude' ? 90 : 180;
                    if (n == null || !n.isFinite || n < -bound || n > bound) {
                      return 'Enter valid coordinates.';
                    }
                  }
                  return null;
                },
              ),
            ),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'QA decision'),
            items: [
              for (final status in [
                'KEEP',
                'NEEDS_RESEARCH',
                'EXCLUDE',
                'KEEP_BOTH',
              ])
                DropdownMenuItem(value: status, child: Text(label(status))),
            ],
            onChanged: (s) => setState(() => _status = s!),
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _evidence,
            decoration: const InputDecoration(
              labelText: 'Source evidence URL',
              helperText: 'Required for field corrections.',
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Review notes'),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Save review'),
          ),
          const SizedBox(height: 24),
          RecordSection('Provider identities and provenance', {
            'external_ids': source['external_ids'],
            'sources': source['sources'],
            'provenance_records': source['provenance_records'],
            'quality': source['quality'],
          }),
        ],
      ),
    );
  }
}
