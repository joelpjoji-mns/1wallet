import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../design/tokens.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Shows a compact glass date-range picker dialog.
///
/// Returns [DateTimeRange?] – null if the user cancels.
Future<DateTimeRange?> showGlassDateRangePicker(
  BuildContext context, {
  DateTimeRange? initialRange,
}) {
  return showDialog<DateTimeRange>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (_) => _GlassDateRangePickerDialog(initialRange: initialRange),
  );
}

/// Shows a compact glass single-date picker dialog.
///
/// Returns [DateTime?] – null if the user cancels.
Future<DateTime?> showGlassDatePicker(
  BuildContext context, {
  DateTime? initialDate,
}) async {
  final now = DateTime.now();
  final init = initialDate ?? now;
  final range = await showDialog<DateTimeRange>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (_) => _GlassDateRangePickerDialog(
      initialRange: DateTimeRange(start: init, end: init),
      singleMode: true,
    ),
  );
  return range?.start;
}

// ---------------------------------------------------------------------------
// Internal dialog widget
// ---------------------------------------------------------------------------

class _GlassDateRangePickerDialog extends StatefulWidget {
  const _GlassDateRangePickerDialog({
    this.initialRange,
    this.singleMode = false,
  });

  final DateTimeRange? initialRange;
  final bool singleMode;

  @override
  State<_GlassDateRangePickerDialog> createState() =>
      _GlassDateRangePickerDialogState();
}

class _GlassDateRangePickerDialogState
    extends State<_GlassDateRangePickerDialog> {
  late DateTime _displayMonth;
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    if (widget.initialRange != null) {
      _start = _dateOnly(widget.initialRange!.start);
      _end = _dateOnly(widget.initialRange!.end);
      _displayMonth = DateTime(_start!.year, _start!.month);
    } else {
      _displayMonth = DateTime(now.year, now.month);
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _prevMonth() => setState(
        () => _displayMonth =
            DateTime(_displayMonth.year, _displayMonth.month - 1),
      );

  void _nextMonth() => setState(
        () => _displayMonth =
            DateTime(_displayMonth.year, _displayMonth.month + 1),
      );

  void _onDayTapped(DateTime day) {
    setState(() {
      if (widget.singleMode) {
        _start = day;
        _end = day;
        return;
      }
      if (_start == null || _end != null) {
        // Begin a fresh range
        _start = day;
        _end = null;
      } else {
        // Complete the range; if the user tapped before start, reset
        if (day.isBefore(_start!)) {
          _start = day;
          _end = null;
        } else {
          _end = day;
        }
      }
    });
  }

  bool _inRange(DateTime day) {
    if (_start == null || _end == null) return false;
    return day.isAfter(_start!) && day.isBefore(_end!);
  }

  bool _isStart(DateTime day) => _start != null && day == _start;

  bool _isEnd(DateTime day) =>
      _end != null && day == _end && _end != _start;

  // ── calendar grid ────────────────────────────────────────────────────────

  Widget _buildCalendar(ColorScheme cs) {
    final firstDay = _displayMonth;
    final daysInMonth =
        DateTime(firstDay.year, firstDay.month + 1, 0).day;
    // Monday-first week offset (Mon=0 ... Sun=6)
    final startWeekday = (firstDay.weekday - 1) % 7;

    const dayHeaders = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    // Header row
    final headerCells = dayHeaders
        .map(
          (h) => Center(
            child: Text(
              h,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        )
        .toList();

    // Day cells + leading blanks
    final cells = <Widget>[];
    for (var i = 0; i < startWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(firstDay.year, firstDay.month, d);
      cells.add(_DayCell(
        day: day,
        isStart: _isStart(day),
        isEnd: _isEnd(day),
        inRange: _inRange(day),
        onTap: () => _onDayTapped(day),
        colorScheme: cs,
        isSingleMode: widget.singleMode,
      ));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Day-of-week labels
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.4,
          padding: EdgeInsets.zero,
          children: headerCells,
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1,
          padding: EdgeInsets.zero,
          children: cells,
        ),
      ],
    );
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final monthLabel =
        _monthName(_displayMonth.month, _displayMonth.year);

    final canApply = widget.singleMode
        ? _start != null
        : (_start != null && _end != null);

    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Month navigation row
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: _prevMonth,
                color: cs.onSurface,
              ),
              Expanded(
                child: Text(
                  monthLabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: _nextMonth,
                color: cs.onSurface,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _buildCalendar(cs),
          const SizedBox(height: AppSpacing.sm),
          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSpacing.xs),
              FilledButton(
                onPressed: canApply
                    ? () {
                        final s = _start!;
                        final e = _end ?? _start!;
                        Navigator.of(context)
                            .pop(DateTimeRange(start: s, end: e));
                      }
                    : null,
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: GlassCard(
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
          shape: const LiquidRoundedSuperellipse(borderRadius: AppRadii.xl),
          quality: GlassQuality.standard,
          child: content,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual day cell
// ---------------------------------------------------------------------------

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isStart,
    required this.isEnd,
    required this.inRange,
    required this.onTap,
    required this.colorScheme,
    required this.isSingleMode,
  });

  final DateTime day;
  final bool isStart;
  final bool isEnd;
  final bool inRange;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final bool isSingleMode;

  @override
  Widget build(BuildContext context) {
    final isSelected = isStart || isEnd || (isSingleMode && isStart);
    final primary = colorScheme.primary;

    Color? bg;
    Color textColor = colorScheme.onSurface;
    FontWeight weight = FontWeight.normal;

    if (isSelected) {
      bg = primary;
      textColor = colorScheme.onPrimary;
      weight = FontWeight.w700;
    } else if (inRange) {
      bg = primary.withValues(alpha: 0.18);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 13,
              color: textColor,
              fontWeight: weight,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _monthName(int month, int year) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[month - 1]} $year';
}
