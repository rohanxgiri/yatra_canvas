import 'package:flutter/material.dart';

import '../../models/trip_draft.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/create_trip_scaffold.dart';
import '../../widgets/selection_chip.dart';
import 'arrival_details_screen.dart';

class SelectDatesScreen extends StatefulWidget {
  const SelectDatesScreen({required this.draft, super.key});

  final TripDraft draft;

  @override
  State<SelectDatesScreen> createState() => _SelectDatesScreenState();
}

class _SelectDatesScreenState extends State<SelectDatesScreen> {
  late DateTime _startDate;
  DateTime? _endDate;
  late bool _datesFlexible;
  late int _durationDays;
  bool _selectingEnd = false;

  @override
  void initState() {
    super.initState();
    _startDate = widget.draft.startDate;
    _endDate = widget.draft.endDate;
    _datesFlexible = widget.draft.datesFlexible;
    _durationDays = widget.draft.durationDays;
  }

  int get _selectedDays {
    final end = _endDate ?? _startDate;
    return end.difference(_startDate).inDays + 1;
  }

  void _selectDate(DateTime date) {
    setState(() {
      if (!_selectingEnd || date.isBefore(_startDate)) {
        _startDate = date;
        _endDate = null;
        _selectingEnd = true;
      } else {
        _endDate = date;
        _selectingEnd = false;
      }
    });
  }

  void _continue() {
    widget.draft
      ..datesFlexible = _datesFlexible
      ..durationDays = _datesFlexible ? _durationDays : _selectedDays
      ..startDate = _startDate
      ..endDate =
          _endDate ??
          _startDate.add(
            Duration(days: _datesFlexible ? _durationDays - 1 : 0),
          );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArrivalDetailsScreen(draft: widget.draft),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CreateTripScaffold(
      step: 2,
      title: 'When are you\ntravelling?',
      subtitle:
          "Choose your trip dates and we'll plan around the time you have.",
      onContinue: _continue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FlexibleDateToggle(
            selected: _datesFlexible,
            onTap: () => setState(() => _datesFlexible = !_datesFlexible),
          ),
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _datesFlexible
                ? _DurationPicker(
                    key: const ValueKey('duration'),
                    selectedDays: _durationDays,
                    onSelected: (days) => setState(() => _durationDays = days),
                  )
                : _CalendarCard(
                    key: const ValueKey('calendar'),
                    startDate: _startDate,
                    endDate: _endDate,
                    onSelected: _selectDate,
                  ),
          ),
          const SizedBox(height: 22),
          _DateSummary(
            flexible: _datesFlexible,
            startDate: _startDate,
            endDate: _endDate,
            durationDays: _datesFlexible ? _durationDays : _selectedDays,
          ),
        ],
      ),
    );
  }
}

class _FlexibleDateToggle extends StatelessWidget {
  const _FlexibleDateToggle({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.tealLight : AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.teal : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.event_busy_outlined,
                color: selected ? AppColors.teal : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "I don't know my exact dates yet",
                  style: AppTextStyles.label,
                ),
              ),
              Switch.adaptive(value: selected, onChanged: (_) => onTap()),
            ],
          ),
        ),
      ),
    );
  }
}

class _DurationPicker extends StatelessWidget {
  const _DurationPicker({
    required this.selectedDays,
    required this.onSelected,
    super.key,
  });

  final int selectedDays;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('How long is your trip?', style: AppTextStyles.sectionTitle),
        const SizedBox(height: 14),
        Wrap(
          spacing: 9,
          runSpacing: 10,
          children: List.generate(5, (index) {
            final days = index + 1;
            return SelectionChip(
              label: days == 5
                  ? '5+ Days'
                  : '$days ${days == 1 ? 'Day' : 'Days'}',
              selected: selectedDays == days,
              onSelected: (_) => onSelected(days),
            );
          }),
        ),
      ],
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.startDate,
    required this.endDate,
    required this.onSelected,
    super.key,
  });

  final DateTime startDate;
  final DateTime? endDate;
  final ValueChanged<DateTime> onSelected;

  static const _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  bool _isSelected(int day) {
    final date = DateTime(2026, 8, day);
    final end = endDate ?? startDate;
    return !date.isBefore(startDate) && !date.isAfter(end);
  }

  @override
  Widget build(BuildContext context) {
    const leadingEmptyDays = 6;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded, color: AppColors.teal),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('August 2026', style: AppTextStyles.sectionTitle),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.tealLight,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  endDate == null ? 'Select end' : 'Dates selected',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.tealDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: _weekdays
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(day, style: AppTextStyles.caption),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 37,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 2,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              if (index < leadingEmptyDays) return const SizedBox.shrink();
              final day = index - leadingEmptyDays + 1;
              final selected = _isSelected(day);
              final isEdge = day == startDate.day || day == endDate?.day;
              return Semantics(
                button: true,
                selected: selected,
                label: '$day August 2026',
                child: InkWell(
                  onTap: () => onSelected(DateTime(2026, 8, day)),
                  customBorder: const CircleBorder(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    decoration: BoxDecoration(
                      color: isEdge
                          ? AppColors.teal
                          : selected
                          ? AppColors.tealLight
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$day',
                      style: AppTextStyles.label.copyWith(
                        color: isEdge ? Colors.white : AppColors.charcoal,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DateSummary extends StatelessWidget {
  const _DateSummary({
    required this.flexible,
    required this.startDate,
    required this.endDate,
    required this.durationDays,
  });

  final bool flexible;
  final DateTime startDate;
  final DateTime? endDate;
  final int durationDays;

  @override
  Widget build(BuildContext context) {
    final end = endDate ?? startDate;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.tealDark,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.event_available_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  flexible
                      ? 'Flexible dates'
                      : '${startDate.day} Aug — ${end.day} Aug',
                  style: AppTextStyles.cardTitle.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  '$durationDays ${durationDays == 1 ? 'Day' : 'Days'}',
                  style: AppTextStyles.body.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: AppColors.marigold),
        ],
      ),
    );
  }
}
