import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../models/trip_draft.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/create_trip_scaffold.dart';
import 'trip_purpose_screen.dart';

class ArrivalDetailsScreen extends StatefulWidget {
  const ArrivalDetailsScreen({required this.draft, super.key});

  final TripDraft draft;

  @override
  State<ArrivalDetailsScreen> createState() => _ArrivalDetailsScreenState();
}

class _ArrivalDetailsScreenState extends State<ArrivalDetailsScreen> {
  late String _method;
  late String _arrivalPoint;
  late TimeOfDay _arrivalTime;
  late final TextEditingController _pointController;
  final _pointFocus = FocusNode();

  static const _methods = <(String, IconData)>[
    ('Train', Icons.train_rounded),
    ('Flight', Icons.flight_rounded),
    ('Bus', Icons.directions_bus_rounded),
    ('Car', Icons.directions_car_rounded),
    ('Other', Icons.more_horiz_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _method = widget.draft.arrivalMethod;
    _arrivalPoint = widget.draft.arrivalPoint;
    _arrivalTime = TimeOfDay(
      hour: widget.draft.arrivalTime.hour,
      minute: widget.draft.arrivalTime.minute,
    );
    _pointController = TextEditingController(text: _arrivalPoint);
    _pointController.addListener(_refreshPoint);
    _pointFocus.addListener(_refresh);
  }

  @override
  void dispose() {
    _pointController
      ..removeListener(_refreshPoint)
      ..dispose();
    _pointFocus
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _refreshPoint() {
    setState(() => _arrivalPoint = _pointController.text.trim());
  }

  List<String> get _suggestions {
    final query = _pointController.text.trim().toLowerCase();
    return MockData.arrivalPoints
        .where((point) {
          return query.isEmpty || point.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  void _selectMethod(String method) {
    setState(() {
      _method = method;
      if (method == 'Train') {
        _pointController.text = 'Ujjain Railway Station';
      }
    });
  }

  void _selectPoint(String point) {
    _pointController.text = point;
    _pointController.selection = TextSelection.collapsed(offset: point.length);
    _pointFocus.unfocus();
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _arrivalTime,
      helpText: 'Approximate arrival time',
    );
    if (selected != null && mounted) setState(() => _arrivalTime = selected);
  }

  void _continue() {
    widget.draft
      ..arrivalMethod = _method
      ..arrivalPoint = _arrivalPoint
      ..arrivalTime = TimeOfDayValue(
        hour: _arrivalTime.hour,
        minute: _arrivalTime.minute,
      );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripPurposeScreen(draft: widget.draft),
      ),
    );
  }

  String _formatTime(TimeOfDay value) {
    final hour = value.hourOfPeriod == 0 ? 12 : value.hourOfPeriod;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final city = widget.draft.destination?.name ?? 'Ujjain';
    return CreateTripScaffold(
      step: 3,
      title: 'How are you\nreaching $city?',
      subtitle: 'Your journey will start from where you arrive.',
      continueEnabled: _arrivalPoint.isNotEmpty,
      onContinue: _continue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Arrival method', style: AppTextStyles.sectionTitle),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _methods
                .map(
                  (method) => _TransportCard(
                    label: method.$1,
                    icon: method.$2,
                    selected: _method == method.$1,
                    onTap: () => _selectMethod(method.$1),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 30),
          const Text(
            'Where will you arrive?',
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pointController,
            focusNode: _pointFocus,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'Search arrival points',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          if (_pointFocus.hasFocus && _suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: _suggestions
                    .map(
                      (point) => ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.place_outlined,
                          color: AppColors.teal,
                        ),
                        title: Text(point, style: AppTextStyles.label),
                        onTap: () => _selectPoint(point),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
          const SizedBox(height: 26),
          const Text(
            'Approximate arrival time',
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: 12),
          _TimeField(value: _formatTime(_arrivalTime), onTap: _pickTime),
          const SizedBox(height: 26),
          _StartCard(
            arrivalPoint: _arrivalPoint.isEmpty
                ? 'Choose an arrival point'
                : _arrivalPoint,
            arrivalTime: _formatTime(_arrivalTime),
          ),
        ],
      ),
    );
  }
}

class _TransportCard extends StatelessWidget {
  const _TransportCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 94,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.tealLight : AppColors.surface,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected ? AppColors.teal : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? AppColors.teal : AppColors.textSecondary,
              ),
              const SizedBox(height: 7),
              Text(label, style: AppTextStyles.label),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule_rounded, color: AppColors.teal),
              const SizedBox(width: 12),
              Expanded(child: Text(value, style: AppTextStyles.cardTitle)),
              const Icon(
                Icons.expand_more_rounded,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({required this.arrivalPoint, required this.arrivalTime});

  final String arrivalPoint;
  final String arrivalTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.tealDark,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.marigold,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.flag_rounded, color: AppColors.charcoal),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'START  •  $arrivalTime',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.marigold,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .7,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  arrivalPoint,
                  style: AppTextStyles.cardTitle.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 5),
                Text(
                  'Your itinerary will begin here.',
                  style: AppTextStyles.body.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
