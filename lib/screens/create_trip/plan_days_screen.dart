import '../../widgets/yc_scaffold.dart';
import '../../theme/yc_style.dart';

import 'package:flutter/material.dart';

import '../../models/trip_day.dart';
import '../../services/trip_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/primary_button.dart';

class PlanDaysScreen extends StatefulWidget {
  const PlanDaysScreen({
    required this.tripId,
    this.tripService,
    this.onContinue,
    super.key,
  });

  final String tripId;
  final TripService? tripService;
  final VoidCallback? onContinue;

  static String formatTimeDisplay(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    final parts = timeStr.split(':');
    if (parts.length < 2) return timeStr;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final mStr = minute.toString().padLeft(2, '0');
    return '${h12.toString().padLeft(2, '0')}:$mStr $period';
  }

  @override
  State<PlanDaysScreen> createState() => _PlanDaysScreenState();
}

class _PlanDaysScreenState extends State<PlanDaysScreen> {
  late final TripService _tripService;
  late final bool _ownsTripService;

  List<TripDay> _days = const [];
  bool _isLoading = true;
  String? _error;
  final Set<int> _updatingDayNumbers = {};

  @override
  void initState() {
    super.initState();
    _ownsTripService = widget.tripService == null;
    _tripService = widget.tripService ?? TripService();
    _loadTripDays();
  }

  @override
  void dispose() {
    if (_ownsTripService) _tripService.close();
    super.dispose();
  }

  Future<void> _loadTripDays() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final days = await _tripService.getTripDays(widget.tripId);
      if (!mounted) return;
      setState(() {
        _days = days;
        _isLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error is TripServiceException
            ? error.message
            : 'Could not load trip days. Please check your connection.';
      });
    }
  }

  Future<void> _editDay(TripDay day) async {
    var selectedType = day.dayType;
    var startTime =
        _parseTime(day.startTime) ?? const TimeOfDay(hour: 9, minute: 0);
    var endTime =
        _parseTime(day.endTime) ?? const TimeOfDay(hour: 19, minute: 0);
    String? modalError;
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return Theme(
          data: YCStyle.theme(modalContext),
          child: StatefulBuilder(
          builder: (context, setModalState) {
            final isRest = selectedType == DayType.rest;

            return Container(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 28,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Configure Day ${day.dayNumber}',
                          style: AppTextStyles.sectionTitle,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: isSaving
                              ? null
                              : () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('Day Type', style: AppTextStyles.label),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: DayType.values.map((type) {
                        final selected = selectedType == type;
                        return ChoiceChip(
                          label: Text(type.label),
                          selected: selected,
                          onSelected: isSaving
                              ? null
                              : (val) {
                                  if (val) {
                                    setModalState(() {
                                      selectedType = type;
                                      modalError = null;
                                      if (type == DayType.halfDay &&
                                          startTime.hour >= 14) {
                                        startTime = const TimeOfDay(
                                          hour: 9,
                                          minute: 0,
                                        );
                                        endTime = const TimeOfDay(
                                          hour: 14,
                                          minute: 0,
                                        );
                                      } else if (type == DayType.travel) {
                                        startTime = const TimeOfDay(
                                          hour: 15,
                                          minute: 0,
                                        );
                                        endTime = const TimeOfDay(
                                          hour: 19,
                                          minute: 0,
                                        );
                                      }
                                    });
                                  }
                                },
                          selectedColor: AppColors.tealLight,
                          labelStyle: TextStyle(
                            color: selected
                                ? AppColors.tealDark
                                : AppColors.charcoal,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    if (isRest) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: YCStyle.selected,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: YCStyle.border),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.bedtime_outlined,
                              color: YCStyle.blue,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Rest days do not require a sightseeing time window. Take time to relax or travel freely.',
                                style: AppTextStyles.body.copyWith(
                                  color: AppColors.charcoal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Sightseeing Time Window',
                        style: AppTextStyles.label,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _TimePickerButton(
                              label: 'Start Time',
                              time: startTime,
                              enabled: !isSaving,
                              onTap: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: startTime,
                                );
                                if (picked != null) {
                                  setModalState(() {
                                    startTime = picked;
                                    modalError = null;
                                  });
                                }
                              },
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              '–',
                              style: TextStyle(
                                fontSize: 20,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: _TimePickerButton(
                              label: 'End Time',
                              time: endTime,
                              enabled: !isSaving,
                              onTap: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: endTime,
                                );
                                if (picked != null) {
                                  setModalState(() {
                                    endTime = picked;
                                    modalError = null;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (modalError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        modalError!,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: PrimaryButton(
                        key: const ValueKey('save-day-config'),
                        label: isSaving ? 'Saving…' : 'Save Day Plan',
                        onPressed: isSaving
                            ? null
                            : () async {
                                // Validation
                                if (!isRest) {
                                  final startMin =
                                      startTime.hour * 60 + startTime.minute;
                                  final endMin =
                                      endTime.hour * 60 + endTime.minute;
                                  if (endMin <= startMin) {
                                    setModalState(() {
                                      modalError =
                                          'End time must be after start time.';
                                    });
                                    return;
                                  }
                                }

                                setModalState(() {
                                  isSaving = true;
                                  modalError = null;
                                });

                                try {
                                  final updated = await _tripService
                                      .updateTripDay(
                                        widget.tripId,
                                        day.dayNumber,
                                        dayType: selectedType,
                                        startTime: isRest
                                            ? null
                                            : _toApiTime(startTime),
                                        endTime: isRest
                                            ? null
                                            : _toApiTime(endTime),
                                      );

                                  if (!mounted) return;
                                  if (modalContext.mounted) {
                                    Navigator.of(modalContext).pop();
                                  }
                                  setState(() {
                                    _days = [
                                      for (final d in _days)
                                        if (d.dayNumber == day.dayNumber)
                                          updated
                                        else
                                          d,
                                    ];
                                  });
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Day ${day.dayNumber} updated.',
                                          ),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                } on Object catch (e) {
                                  setModalState(() {
                                    isSaving = false;
                                    modalError = e is TripServiceException
                                        ? e.message
                                        : 'Could not update day. Please try again.';
                                  });
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        );
      },
    );
  }

  static TimeOfDay? _parseTime(String? str) {
    if (str == null || str.isEmpty) return null;
    final parts = str.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  static String _toApiTime(TimeOfDay tod) {
    return '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return YCScaffold(
      appBar: AppBar(
        title: const Text('Plan your days'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: YCStateCard(title: 'Opening your days', message: 'Loading your sightseeing hours and time off.', loading: true),
                    )
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: AppColors.error,
                              size: 36,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMuted,
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: _loadTripDays,
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Make room to explore.',
                            style: YCStyle.title,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Choose your sightseeing hours and leave time to take it slow. Tap a day to adjust it.',
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          for (final day in _days) ...[
                            _DayCard(
                              key: ValueKey('configure-day-${day.dayNumber}'),
                              day: day,
                              isUpdating: _updatingDayNumbers.contains(
                                day.dayNumber,
                              ),
                              onTap: () => _editDay(day),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ),
            ),
            if (!_isLoading && _error == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: 'Continue',
                    onPressed: () {
                      if (widget.onContinue != null) {
                        widget.onContinue!();
                      } else {
                        Navigator.maybePop(context, true);
                      }
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.isUpdating,
    required this.onTap,
    super.key,
  });

  final TripDay day;
  final bool isUpdating;
  final VoidCallback onTap;

  Color get _badgeBg => YCStyle.selected;
  Color get _badgeText => YCStyle.blue;

  IconData get _badgeIcon => switch (day.dayType) {
    DayType.fullDay => Icons.wb_sunny_rounded,
    DayType.halfDay => Icons.wb_twilight_rounded,
    DayType.rest => Icons.bedtime_outlined,
    DayType.travel => Icons.flight_takeoff_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final hasWindow =
        day.dayType != DayType.rest &&
        day.startTime != null &&
        day.endTime != null;

    final windowText = hasWindow
        ? '${PlanDaysScreen.formatTimeDisplay(day.startTime)} – ${PlanDaysScreen.formatTimeDisplay(day.endTime)}'
        : day.dayType == DayType.rest ? 'Rest Day' : 'Choose sightseeing hours';

    return InkWell(
      onTap: isUpdating ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x06142033),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _badgeBg,
                shape: BoxShape.circle,
              ),
              child: Icon(_badgeIcon, color: _badgeText, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Day ${day.dayNumber}',
                        style: AppTextStyles.cardTitle,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _badgeBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          day.dayType.label,
                          style: AppTextStyles.caption.copyWith(
                            color: _badgeText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    windowText,
                    style: AppTextStyles.caption.copyWith(
                      color: day.dayType == DayType.rest
                          ? AppColors.textSecondary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (isUpdating)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}

class _TimePickerButton extends StatelessWidget {
  const _TimePickerButton({
    required this.label,
    required this.time,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final TimeOfDay time;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h12 = time.hour == 0
        ? 12
        : (time.hour > 12 ? time.hour - 12 : time.hour);
    final mStr = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final formatted = '${h12.toString().padLeft(2, '0')}:$mStr $period';

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption),
            const SizedBox(height: 2),
            Text(
              formatted,
              style: AppTextStyles.label.copyWith(
                color: enabled ? AppColors.charcoal : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
