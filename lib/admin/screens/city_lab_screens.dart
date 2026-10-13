import 'package:flutter/material.dart';

import '../../theme/yc_style.dart';
import '../data/admin_repository.dart';
import '../widgets/admin_components.dart';
import 'admin_collection_screen.dart';
import 'people_trip_screens.dart';
import 'place_editor_screen.dart';
import 'research_screens.dart';

class CityListScreen extends StatelessWidget {
  const CityListScreen({
    required this.repository,
    this.qualityMode = false,
    this.researchMode = false,
    super.key,
  });
  final AdminRepository repository;
  final bool qualityMode, researchMode;
  @override
  Widget build(BuildContext context) => AdminCollectionScreen(
    title: researchMode
        ? 'Research by city'
        : qualityMode
        ? 'Data Quality by city'
        : 'City Lab',
    path: 'city-lab/cities',
    repository: repository,
    filters: const {
      'status': ['READY', 'REVIEW_REQUIRED', 'BLOCKED', 'NOT_CERTIFIED'],
    },
    subtitleFor: (r) =>
        '${r['state']} • ${r['pack_version']}\n${r['published_places']} canonical places • ${label('${r['status']}')}\n${r['quality']['missing_image']} missing images • ${r['quality']['missing_hours']} missing hours${r['release_selection']?['ambiguous'] == true ? '\nVersions share a timestamp. Choose in City Packs.' : ''}',
    emptyMessage: 'No canonical releases are connected. Configure ADMIN_RELEASE_ROOT on the backend. App offline packs remain independent.',
    onOpen: (context, r) => openAdminPage(
      context,
      researchMode
          ? ResearchListScreen(repository: repository, cityKey: '${r['id']}')
          : CityDetailScreen(
              repository: repository,
              cityKey: '${r['id']}',
              qualityMode: qualityMode,
            ),
    ),
  );
}

class PackListScreen extends StatelessWidget {
  const PackListScreen({required this.repository, super.key});
  final AdminRepository repository;
  @override
  Widget build(BuildContext context) => AdminCollectionScreen(
    title: 'City Packs',
    path: 'city-packs',
    repository: repository,
    subtitleFor: (r) =>
        '${r['pack_version']} • schema ${r['schema_version']}\n${r['published_places']} places • ${label('${r['status']}')}\nBuilt ${r['generated_at'] ?? 'not recorded'}',
    emptyMessage: 'No canonical packs are connected. Configure the backend release root to inspect them.',
    onOpen: (context, r) => openAdminPage(
      context,
      CityDetailScreen(
        repository: repository,
        cityKey: '${r['id']}',
        packMode: true,
      ),
    ),
  );
}

class CityDetailScreen extends StatefulWidget {
  const CityDetailScreen({
    required this.repository,
    required this.cityKey,
    this.qualityMode = false,
    this.packMode = false,
    super.key,
  });
  final AdminRepository repository;
  final String cityKey;
  final bool qualityMode, packMode;
  @override
  State<CityDetailScreen> createState() => _CityDetailScreenState();
}

class _CityDetailScreenState extends State<CityDetailScreen> {
  bool _busy = false;
  Map<String, dynamic>? _result;
  Future<void> _action(
    String path,
    String title, {
    bool confirm = false,
  }) async {
    if (_busy) return;
    if (confirm &&
        !await confirmAction(
          context,
          title,
          'The backend will create an immutable artifact from this canonical release. Existing releases and installed app packs are preserved.',
        )) {
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final result = await widget.repository.mutate(path, {});
      if (mounted) setState(() => _result = result);
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
    title: widget.packMode ? 'Pack workflow' : 'City overview',
    load: () => widget.repository.get('city-lab/cities/${widget.cityKey}'),
    builder: (context, city, refresh) {
      final quality = Map<String, dynamic>.from(city['quality'] as Map);
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('${city['name']}', style: YCStyle.sectionTitle),
          const SizedBox(height: 8),
          Text(
            '${city['state']} • ${city['pack_version']}',
            style: YCStyle.secondary,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge('${city['status']}'),
          ),
          const SizedBox(height: 12),
          AdminNotice(
            '${city['readiness_problem'] ?? city['readiness_scope'] ?? 'Certification evidence is unavailable.'}',
          ),
          LayoutBuilder(
            builder: (context, box) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final item in <(String, Object?, String, IconData)>[
                  (
                    'Data Quality',
                    city['readiness']?['data_quality_score'],
                    'Reported City Lab score / 100',
                    Icons.fact_check_outlined,
                  ),
                  (
                    'Travel Readiness',
                    city['readiness']?['travel_readiness_score'],
                    'Reported City Lab score / 100',
                    Icons.route_outlined,
                  ),
                  (
                    'Manual QA',
                    city['readiness'] == null
                        ? null
                        : '${city['readiness']['manual_qa_reviewed_count']}/${city['readiness']['manual_qa_minimum_required']}',
                    'Human reviews in the Lab export',
                    Icons.person_search_outlined,
                  ),
                ])
                  SizedBox(
                    width: box.maxWidth < 600
                        ? box.maxWidth
                        : (box.maxWidth - 24) / 3,
                    child: AdminMetricCard(
                      title: item.$1,
                      value: item.$2,
                      scope: item.$3,
                      icon: item.$4,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (city['readiness'] != null)
            RecordSection('Evaluation evidence', {
              'evaluated_at': city['readiness']['generated_at'],
              'reported_gate': city['reported_gate_status'],
              'critical_blockers': city['readiness']['criticalIssues'],
              'manual_review_state': city['readiness']['manualQaStatus'],
              'checks': city['readiness']['validation_summary'],
              'certification_scope': city['readiness_scope'],
            }),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: () => openAdminPage(
                  context,
                  PlaceListScreen(
                    repository: widget.repository,
                    cityKey: widget.cityKey,
                  ),
                ),
                child: const Text('Review places'),
              ),
              OutlinedButton(
                onPressed: () => openAdminPage(
                  context,
                  DuplicateScreen(
                    repository: widget.repository,
                    cityKey: widget.cityKey,
                  ),
                ),
                child: const Text('Duplicate review'),
              ),
              OutlinedButton(
                onPressed: () => openAdminPage(
                  context,
                  ResearchListScreen(
                    repository: widget.repository,
                    cityKey: widget.cityKey,
                  ),
                ),
                child: const Text('Research queue'),
              ),
              OutlinedButton(
                onPressed: _busy || city['capabilities']['validate'] != true
                    ? null
                    : () => _action(
                        'city-lab/cities/${widget.cityKey}/validate',
                        'Validate city',
                      ),
                child: const Text('Validate city'),
              ),
              OutlinedButton(
                onPressed: _busy || city['capabilities']['build'] != true
                    ? null
                    : () => _action(
                        'city-packs/${widget.cityKey}/build',
                        'Build city pack',
                        confirm: true,
                      ),
                child: const Text('Build city pack'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _action(
                        'city-lab/cities/${widget.cityKey}/export-patch',
                        'Export reviewed patch',
                        confirm: true,
                      ),
                child: const Text('Export reviewed patch'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (city['readiness'] == null)
            const RecordSection('City Lab certification', {
              'availability': 'No version matched City Lab release report has been exported. Confidence, grade and release gate are unavailable. DataFactory usability below is a separate report.',
            })
          else
            RecordSection(
              'City Lab release evidence',
              Map<String, dynamic>.from(city['readiness'] as Map),
            ),
          RecordSection('Canonical release', {
            for (final k in [
              'canonical_city_id',
              'pack_version',
              'schema_version',
              'published_places',
              'generated_at',
              'pipeline_health',
              'data_quality',
              'source_coverage',
              'research_tasks',
              'duplicate_groups',
            ])
              k: city[k],
            'raw_places': city['raw_counts']?['total_raw_candidates'],
            'last_validation': city['last_validation']?['timestamp'],
            'last_pack_build': city['last_pack_build']?['timestamp'],
            'last_publish': city['last_publish'],
          }),
          RecordSection('Field coverage', {
            for (final key in [
              'missing_image',
              'missing_hours',
              'missing_coordinates',
              'missing_description',
              'missing_website',
            ])
              key.replaceFirst('missing_', ''): city['coverage']?[key] is num
                  ? '${((city['coverage'][key] as num) * 100).toStringAsFixed(1)}%'
                  : null,
          }),
          Text('Data quality inbox', style: YCStyle.cardTitle),
          const SizedBox(height: 12),
          for (final entry in quality.entries)
            AdminCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(label(entry.key)),
                trailing: Text('${entry.value}', style: YCStyle.cardTitle),
                onTap: () => openAdminPage(
                  context,
                  PlaceListScreen(
                    repository: widget.repository,
                    cityKey: widget.cityKey,
                    issue: entry.key,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          const RecordSection('Publishing', {
            'availability': 'This backend can validate releases, export reviewed patches and build app packs when DataFactory is configured. A new canonical release is applied through the existing reviewed DataFactory import. Remote publish and automatic merge are not configured.',
          }),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
          if (_result != null) RecordSection('Action result', _result!),
          if (city['usability'] is Map && (city['usability'] as Map).isNotEmpty)
            RecordSection(
              'DataFactory usability and blockers',
              Map<String, dynamic>.from(city['usability'] as Map),
            ),
        ],
      );
    },
  );
}

class PlaceListScreen extends StatelessWidget {
  const PlaceListScreen({
    required this.repository,
    required this.cityKey,
    this.issue,
    super.key,
  });
  final AdminRepository repository;
  final String cityKey;
  final String? issue;
  @override
  Widget build(BuildContext context) => AdminCollectionScreen(
    title: issue == null ? 'Places' : label(issue!),
    path: 'city-lab/cities/$cityKey/places',
    repository: repository,
    query: {'issue': ?issue},
    filters: const {
      'status': [
        'UNREVIEWED',
        'KEEP',
        'NEEDS_RESEARCH',
        'EXCLUDE',
        'KEEP_BOTH',
      ],
      'sort': ['name', 'priority', 'confidence', 'recent', 'missing_fields'],
    },
    subtitleFor: (r) =>
        '${r['category']} • ${label('${r['qa_status']}')}\n${(r['issues'] as List).map((v) => label('$v')).join(' • ')}',
    emptyMessage: issue == null
        ? 'No places match this review filter.'
        : 'No ${label(issue!).toLowerCase()} issues match this filter.',
    onOpen: (context, r) => openAdminPage(
      context,
      PlaceEditorScreen(
        repository: repository,
        cityKey: cityKey,
        placeId: '${r['id']}',
      ),
    ),
  );
}

class DuplicateScreen extends StatelessWidget {
  const DuplicateScreen({
    required this.repository,
    required this.cityKey,
    super.key,
  });
  final AdminRepository repository;
  final String cityKey;
  @override
  Widget build(BuildContext context) => AdminCollectionScreen(
    title: 'Identity conflicts',
    path: 'city-lab/cities/$cityKey/duplicates',
    repository: repository,
    titleFor: (r) => '${r['kind']} • ${r['key']}',
    subtitleFor: (r) =>
        (r['places'] as List).map((p) => '${p['name']}').join(' vs '),
    emptyMessage:
        'No identity conflicts were found by the existing DataFactory rules.',
    onOpen: (context, group) => openAdminPage(
      context,
      Scaffold(
        appBar: AppBar(title: const Text('Duplicate review')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            RecordSection('Existing conflict evidence', group),
            const RecordSection('Review policy', {
              'actions': 'Review each record to keep both, exclude from review or request research. A canonical merge requires the existing reviewed DataFactory identity workflow. No uncertain records are automatically merged.',
            }),
            for (final p in (group['places'] as List).cast<Map>())
              ListTile(
                title: Text('${p['name']}'),
                subtitle: Text('${p['id']}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openAdminPage(
                  context,
                  PlaceEditorScreen(
                    repository: repository,
                    cityKey: cityKey,
                    placeId: '${p['id']}',
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
