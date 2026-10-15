import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/auth_controller.dart';
import '../../services/city_pack_repository.dart';
import '../../theme/yc_style.dart';
import '../admin_theme.dart';
import '../widgets/admin_components.dart';

class OfflineAdminScreen extends StatefulWidget {
  const OfflineAdminScreen({required this.auth, this.packs, super.key});
  final AuthController auth;
  final CityPackRepository? packs;

  @override
  State<OfflineAdminScreen> createState() => _OfflineAdminScreenState();
}

class _OfflineAdminScreenState extends State<OfflineAdminScreen> {
  CityPackRepository get _packs => widget.packs ?? CityPackRepository.shared;
  late Future<Map<String, dynamic>> _cities = _packs.index;

  @override
  Widget build(BuildContext context) => Theme(
    data: AdminTheme.of(context),
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Offline Admin'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: widget.auth.logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _cities,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AdminError(
              error: snapshot.error!,
              retry: () => setState(() => _cities = _packs.index),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const StatusBadge('OFFLINE'),
              const SizedBox(height: 20),
              Text('Installed city data', style: YCStyle.sectionTitle),
              const SizedBox(height: 12),
              const AdminNotice(
                'You are signed in to offline admin on this device. Browse places, photos and visiting information without internet.',
              ),
              for (final city in snapshot.data!.entries)
                FutureBuilder<Map<String, dynamic>>(
                  future: _packs.diagnostics(city.key),
                  builder: (context, pack) => Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(18),
                      leading: const Icon(Icons.location_city_outlined),
                      title: Text('${city.value['name']}'),
                      subtitle: Text(
                        pack.hasError
                            ? 'Pack could not be opened. Tap to retry.'
                            : pack.hasData
                            ? '${pack.data!['place_count']} places · ${pack.data!['media_count']} bundled photos\n${city.value['pack_version']}'
                            : 'Checking installed data…',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OfflineAdminCityScreen(
                            packs: _packs,
                            cityId: city.key,
                            name: '${city.value['name']}',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (snapshot.data!.isEmpty)
                const AdminEmpty('No offline city datasets are installed.'),
              const SizedBox(height: 20),
              const AdminNotice(
                'User management, server moderation, provider health and publishing require an online administrator sign in. Local city datasets are read only.',
              ),
            ],
          );
        },
      ),
    ),
  );
}

class OfflineAdminCityScreen extends StatefulWidget {
  const OfflineAdminCityScreen({
    required this.packs,
    required this.cityId,
    required this.name,
    super.key,
  });
  final CityPackRepository packs;
  final String cityId, name;

  @override
  State<OfflineAdminCityScreen> createState() => _OfflineAdminCityScreenState();
}

class _OfflineAdminCityScreenState extends State<OfflineAdminCityScreen> {
  String _query = '';
  int _offset = 0;
  Timer? _search;
  late Future<List<Map<String, dynamic>>> _places = _load();

  Future<List<Map<String, dynamic>>> _load() => widget.packs.getCityPlaces(
    widget.cityId,
    query: _query.isEmpty ? null : _query,
    limit: 100,
    offset: _offset,
  );

  void _reload() => setState(() => _places = _load());

  @override
  void dispose() {
    _search?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.name} · Offline')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search installed places',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) {
              _search?.cancel();
              _search = Timer(const Duration(milliseconds: 250), () {
                _query = value.trim();
                _offset = 0;
                _reload();
              });
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _places,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return AdminError(error: snapshot.error!, retry: _reload);
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final places = snapshot.data ?? [];
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  if (places.isEmpty)
                    const AdminEmpty('No installed places match this search.'),
                  for (final place in places)
                    Card(
                      child: ListTile(
                        title: Text('${place['name']}'),
                        subtitle: Text(
                          '${label('${place['category']}')} · Hours: ${label('${place['hours_verification']}')}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                OfflineAdminPlaceScreen(place: place),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: _offset == 0
                            ? null
                            : () {
                                _offset -= 100;
                                _reload();
                              },
                        child: const Text('Previous'),
                      ),
                      Text('Page ${_offset ~/ 100 + 1}'),
                      OutlinedButton(
                        onPressed: places.length < 100
                            ? null
                            : () {
                                _offset += 100;
                                _reload();
                              },
                        child: const Text('Next'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class OfflineAdminPlaceScreen extends StatelessWidget {
  const OfflineAdminPlaceScreen({required this.place, super.key});
  final Map<String, dynamic> place;

  @override
  Widget build(BuildContext context) {
    final asset = (place['image'] as Map?)?['asset_path'];
    return Scaffold(
      appBar: AppBar(title: const Text('Offline place details')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('${place['name']}', style: YCStyle.sectionTitle),
          const SizedBox(height: 16),
          if (asset is String)
            ClipRRect(
              borderRadius: BorderRadius.circular(AdminTheme.radius),
              child: Image.asset(
                asset,
                height: 220,
                fit: BoxFit.cover,
                semanticLabel: '${place['name']} bundled photo',
                errorBuilder: (_, error, trace) =>
                    const AdminEmpty('Bundled photo could not be displayed.'),
              ),
            )
          else
            const AdminNotice('No photo is bundled for this place.'),
          const SizedBox(height: 16),
          RecordSection('Place information', {
            for (final key in [
              'id',
              'city_id',
              'category',
              'normalized_category',
              'latitude',
              'longitude',
              'aliases',
              'description',
              'website',
              'pack_version',
            ])
              key: place[key],
          }),
          RecordSection('Visiting information', {
            'verification': place['hours_verification'],
            'source_schedule': place['raw_opening_hours'],
            'weekly_intervals': place['opening_hours'],
            'visit_duration_minutes': place['visit_duration_minutes'],
          }),
          if (place['image'] is Map)
            RecordSection(
              'Photo source and attribution',
              Map<String, dynamic>.from(place['image'] as Map),
            ),
        ],
      ),
    );
  }
}
