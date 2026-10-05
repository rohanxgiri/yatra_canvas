import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/trip_start_location.dart';
import '../../services/location_service.dart';
import '../../theme/app_colors.dart';

class SelectedStartPoint {
  const SelectedStartPoint(this.name, this.latitude, this.longitude);
  final String name;
  final double latitude;
  final double longitude;
}

/// A coordinate view of bundled landmarks, with no tile or geocoder dependency.
/// Roads are deliberately not drawn: the city pack does not contain a basemap.
class StartPointPicker extends StatefulWidget {
  const StartPointPicker({
    required this.cityName,
    required this.latitude,
    required this.longitude,
    required this.locationService,
    this.cityId,
    super.key,
  });
  final String cityName;
  final String? cityId;
  final double latitude;
  final double longitude;
  final LocationService locationService;

  @override
  State<StartPointPicker> createState() => _StartPointPickerState();
}

class _StartPointPickerState extends State<StartPointPicker> {
  final _mapController = MapController();
  List<LocationSuggestion> _places = const [];
  SelectedStartPoint? _selected;

  @override
  void initState() {
    super.initState();
    _loadPlaces();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadPlaces() async {
    try {
      if (!await widget.locationService.hasOfflineCity(widget.cityId)) return;
      final places = await widget.locationService.autocomplete(
        '',
        hotelOnly: false,
        cityId: widget.cityId,
        latitude: widget.latitude,
        longitude: widget.longitude,
        limit: 80,
      );
      if (mounted) setState(() => _places = places);
    } on Object {
      // A missing pack still permits direct coordinate selection.
    }
  }

  Future<void> _enterCoordinates() async {
    final name = TextEditingController(
      text: _selected?.name ?? 'My starting point',
    );
    final lat = TextEditingController(
      text: (_selected?.latitude ?? widget.latitude).toStringAsFixed(6),
    );
    final lon = TextEditingController(
      text: (_selected?.longitude ?? widget.longitude).toStringAsFixed(6),
    );
    final form = GlobalKey<FormState>();
    final route = DialogRoute<SelectedStartPoint>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter starting coordinates'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Point name'),
                  maxLength: 255,
                  validator: (value) => value?.trim().isEmpty != false
                      ? 'Name this point.'
                      : null,
                ),
                TextFormField(
                  key: const ValueKey('point-latitude'),
                  controller: lat,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Latitude'),
                  validator: (value) => _coordinateError(value, 90),
                ),
                TextFormField(
                  key: const ValueKey('point-longitude'),
                  controller: lon,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Longitude'),
                  validator: (value) => _coordinateError(value, 180),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(
                context,
                SelectedStartPoint(
                  name.text.trim(),
                  double.parse(lat.text.trim()),
                  double.parse(lon.text.trim()),
                ),
              );
            },
            child: const Text('Use coordinates'),
          ),
        ],
      ),
    );
    final point = await Navigator.of(context).push(route);
    await route.completed;
    name.dispose();
    lat.dispose();
    lon.dispose();
    if (mounted && point != null) {
      setState(() => _selected = point);
      _mapController.move(LatLng(point.latitude, point.longitude), 12);
    }
  }

  String? _coordinateError(String? value, double bound) {
    final coordinate = double.tryParse(value?.trim() ?? '');
    return coordinate == null ||
            !coordinate.isFinite ||
            coordinate.abs() > bound
        ? 'Enter a number from -${bound.toInt()} to ${bound.toInt()}.'
        : null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose starting point')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Tap anywhere or select a bundled landmark. This offline view shows locations, without roads or map imagery.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: const Color(0xFFF0F4F8),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  backgroundColor: const Color(0xFFF0F4F8),
                  initialCenter: LatLng(widget.latitude, widget.longitude),
                  initialZoom: 12,
                  minZoom: 3,
                  maxZoom: 19,
                  onTap: (_, point) => setState(
                    () => _selected = SelectedStartPoint(
                      'Chosen point in ${widget.cityName}',
                      point.latitude,
                      point.longitude,
                    ),
                  ),
                ),
                children: [
                  MarkerLayer(
                    markers: [
                      for (final place in _places)
                        Marker(
                          point: LatLng(place.latitude, place.longitude),
                          width: 44,
                          height: 44,
                          child: Semantics(
                            label: place.name,
                            button: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(
                                () => _selected = SelectedStartPoint(
                                  place.name,
                                  place.latitude,
                                  place.longitude,
                                ),
                              ),
                              child: Center(
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: AppColors.teal,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_selected != null)
                        Marker(
                          point: LatLng(
                            _selected!.latitude,
                            _selected!.longitude,
                          ),
                          width: 48,
                          height: 48,
                          child: const Icon(
                            Icons.location_pin,
                            color: AppColors.tealDark,
                            size: 44,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_selected != null) ...[
                      Text(
                        _selected!.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${_selected!.latitude.toStringAsFixed(5)}, ${_selected!.longitude.toStringAsFixed(5)}',
                      ),
                      const SizedBox(height: 8),
                    ],
                    TextButton.icon(
                      onPressed: _enterCoordinates,
                      icon: const Icon(Icons.edit_location_alt_outlined),
                      label: const Text('Enter coordinates'),
                    ),
                    OutlinedButton(
                      onPressed: () => setState(
                        () => _selected = SelectedStartPoint(
                          '${widget.cityName} city centre',
                          widget.latitude,
                          widget.longitude,
                        ),
                      ),
                      child: const Text('Use city centre'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _selected == null
                          ? null
                          : () => Navigator.pop(context, _selected),
                      child: const Text('Use this starting point'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
