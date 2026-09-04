import 'package:flutter/material.dart';

import '../../models/trip_draft.dart';
import '../../services/trip_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/create_trip_scaffold.dart';
import '../../widgets/selection_chip.dart';
import 'arrival_details_screen.dart';

class SelectDatesScreen extends StatefulWidget {
  const SelectDatesScreen({required this.draft, this.tripService, super.key});

  final TripDraft draft;
  final TripService? tripService;

  @override
  State<SelectDatesScreen> createState() => _SelectDatesScreenState();
}

class _SelectDatesScreenState extends State<SelectDatesScreen> {
  late DateTime _startDate;
  DateTime? _endDate;
  late bool _datesFlexible;
  late int _durationDays;
  bool _selectingEnd = false;
  late DateTime _displayedMonth;

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
  DateTime get _today => _dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    final today = _today;
    var start = _dateOnly(widget.draft.startDate);
    if (start.isBefore(today)) {
      start = today;
    }
    _startDate = start;
    if (widget.draft.endDate.isBefore(_startDate)) {
      _endDate = _startDate.add(Duration(days: widget.draft.durationDays > 0 ? widget.draft.durationDays - 1 : 1));
    } else {
      _endDate = _dateOnly(widget.draft.endDate);
    }
    _datesFlexible = widget.draft.datesFlexible;
    _durationDays = widget.draft.durationDays;
    _displayedMonth = DateTime(_startDate.year, _startDate.month, 1);
  }

  int get _selectedDays {
    final end = _endDate ?? _startDate;
    return end.difference(_startDate).inDays + 1;
  }

  void _selectDate(DateTime date) {
    final normalized = _dateOnly(date);
    if (normalized.isBefore(_today)) return;

    setState(() {
      if (!_selectingEnd || normalized.isBefore(_startDate)) {
        _startDate = normalized;
        _endDate = null;
        _selectingEnd = true;
      } else {
        _endDate = normalized;
        _selectingEnd = false;
      }
    });
  }

  void _previousMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 1);
    });
  }

  bool get _canGoPrevious {
    final todayMonth = DateTime(_today.year, _today.month, 1);
    return _displayedMonth.isAfter(todayMonth);
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
        builder: (_) => ArrivalDetailsScreen(
          draft: widget.draft,
          tripService: widget.tripService,
        ),
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
                    displayedMonth: _displayedMonth,
                    startDate: _startDate,
                    endDate: _endDate,
                    today: _today,
                    canGoPrevious: _canGoPrevious,
                    onPreviousMonth: _previousMonth,
                    onNextMonth: _nextMonth,
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
    required this.displayedMonth,
    required this.startDate,
    required this.endDate,
    required this.today,
    required this.canGoPrevious,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onSelected,
    super.key,
  });

  final DateTime displayedMonth;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime today;
  final bool canGoPrevious;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onSelected;

  static const _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  bool _isSelected(DateTime date) {
    final end = endDate ?? startDate;
    return !date.isBefore(startDate) && !date.isAfter(end);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final year = displayedMonth.year;
    final month = displayedMonth.month;
    final firstDayOfMonth = DateTime(year, month, 1);
    final leadingEmptyDays = firstDayOfMonth.weekday % 7;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final totalGridCount = leadingEmptyDays + daysInMonth;

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
              const Icon(Icons.calendar_month_rounded, color: AppColors.teal, size: 20),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: canGoPrevious ? onPreviousMonth : null,
                tooltip: 'Previous month',
                color: canGoPrevious ? AppColors.teal : AppColors.textTertiary,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_monthNames[month - 1]} $year',
                    style: AppTextStyles.sectionTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: onNextMonth,
                tooltip: 'Next month',
                color: AppColors.teal,
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.tealLight,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  endDate == null ? 'Select end' : 'Selected',
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
            itemCount: totalGridCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 2,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              if (index < leadingEmptyDays) return const SizedBox.shrink();
              final day = index - leadingEmptyDays + 1;
              final date = DateTime(year, month, day);
              final isPast = date.isBefore(today);
              final selected = _isSelected(date);
              final isEdge = _isSameDay(date, startDate) ||
                  (endDate != null && _isSameDay(date, endDate!));

              return Semantics(
                button: !isPast,
                selected: selected,
                label: isPast
                    ? '$day ${_monthNames[month - 1]} $year (past)'
                    : '$day ${_monthNames[month - 1]} $year',
                child: InkWell(
                  onTap: isPast ? null : () => onSelected(date),
                  customBorder: const CircleBorder(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    decoration: BoxDecoration(
                      color: isPast
                          ? Colors.transparent
                          : isEdge
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
                        color: isPast
                            ? AppColors.textTertiary
                            : isEdge
                                ? Colors.white
                                : AppColors.charcoal,
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

  static const _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _formatDateRange() {
    final end = endDate ?? startDate;
    if (startDate.year == end.year && startDate.month == end.month) {
      if (startDate.day == end.day) {
        return '${startDate.day} ${_monthAbbr[startDate.month - 1]} ${startDate.year}';
      }
      return '${startDate.day} — ${end.day} ${_monthAbbr[startDate.month - 1]}';
    } else if (startDate.year == end.year) {
      return '${startDate.day} ${_monthAbbr[startDate.month - 1]} — ${end.day} ${_monthAbbr[end.month - 1]}';
    } else {
      return '${startDate.day} ${_monthAbbr[startDate.month - 1]} ${startDate.year} — ${end.day} ${_monthAbbr[end.month - 1]} ${end.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  flexible ? 'Flexible dates' : _formatDateRange(),
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
