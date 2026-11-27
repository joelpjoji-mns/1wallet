import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Compact calendar popup for choosing a custom date range.
///
/// Replaces Flutter's full-screen [showDateRangePicker] on phones while
/// keeping its contract: dates are returned at local midnight, the range is
/// inclusive, a single tapped day yields a one-day range, and `null` means
/// the user cancelled.
Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  DateTimeRange? initialDateRange,
  DateTime? firstDate,
  DateTime? lastDate,
  String? helpText,
}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (_) => AppDateRangePopup(
      initialDateRange: initialDateRange,
      firstDate: firstDate ?? DateTime(2000),
      lastDate: lastDate ?? DateTime(2100),
      helpText: helpText ?? 'Select date range',
    ),
  );
}

class AppDateRangePopup extends StatefulWidget {
  const AppDateRangePopup({
    required this.firstDate,
    required this.lastDate,
    required this.helpText,
    this.initialDateRange,
    super.key,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final String helpText;
  final DateTimeRange? initialDateRange;

  @override
  State<AppDateRangePopup> createState() => _AppDateRangePopupState();
}

class _AppDateRangePopupState extends State<AppDateRangePopup> {
  static const _cellExtent = 40.0;

  late final DateTime _first = DateUtils.dateOnly(widget.firstDate);
  late final DateTime _last = DateUtils.dateOnly(widget.lastDate);
  DateTime? _start;
  DateTime? _end;
  late DateTime _month;
  bool _choosingYear = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDateRange;
    if (initial != null) {
      _start = _clamp(DateUtils.dateOnly(initial.start));
      _end = _clamp(DateUtils.dateOnly(initial.end));
    }
    final anchor = _start ?? _clamp(DateUtils.dateOnly(DateTime.now()));
    _month = DateTime(anchor.year, anchor.month);
  }

  DateTime _clamp(DateTime day) {
    if (day.isBefore(_first)) return _first;
    if (day.isAfter(_last)) return _last;
    return day;
  }

  bool get _canGoBack => DateTime(
    _month.year,
    _month.month - 1,
  ).isAfter(DateTime(_first.year, _first.month - 1));

  bool get _canGoForward => DateTime(
    _month.year,
    _month.month + 1,
  ).isBefore(DateTime(_last.year, _last.month + 1));

  void _shiftMonth(int delta) {
    if (delta < 0 && !_canGoBack) return;
    if (delta > 0 && !_canGoForward) return;
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  void _selectDay(DateTime day) {
    setState(() {
      if (_start == null || _end != null || day.isBefore(_start!)) {
        _start = day;
        _end = null;
      } else {
        _end = day;
      }
    });
  }

  void _apply() {
    final start = _start;
    if (start == null) return;
    Navigator.of(context).pop(DateTimeRange(start: start, end: _end ?? start));
  }

  String _summary(MaterialLocalizations l10n) {
    final start = _start;
    if (start == null) return 'Select start date';
    final end = _end;
    final startText = l10n.formatShortMonthDay(start);
    if (end == null) return '$startText – select end';
    if (DateUtils.isSameDay(start, end)) return l10n.formatMediumDate(start);
    final endText = start.year == end.year
        ? l10n.formatShortMonthDay(end)
        : l10n.formatShortDate(end);
    return '$startText – $endText, ${end.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = MaterialLocalizations.of(context);
    final actionStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
      ),
      textStyle: WidgetStatePropertyAll(
        theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
    return Dialog(
      key: const ValueKey('date-range-popup'),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.helpText.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _summary(l10n),
                key: const ValueKey('date-range-summary'),
                maxLines: 2,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildMonthBar(theme, l10n),
              const SizedBox(height: AppSpacing.xs),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _choosingYear
                    ? _buildYearGrid()
                    : _buildMonthGrid(theme, l10n),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('date-range-clear'),
                      style: actionStyle,
                      onPressed: _start == null
                          ? null
                          : () => setState(() {
                              _start = null;
                              _end = null;
                            }),
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('date-range-cancel'),
                      style: actionStyle,
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.cancelButtonLabel),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('date-range-apply'),
                      style: actionStyle,
                      onPressed: _start == null ? null : _apply,
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthBar(ThemeData theme, MaterialLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('date-range-month-title'),
              onPressed: () => setState(() => _choosingYear = !_choosingYear),
              iconAlignment: IconAlignment.end,
              icon: Icon(
                _choosingYear
                    ? Icons.arrow_drop_up_rounded
                    : Icons.arrow_drop_down_rounded,
              ),
              label: Text(
                l10n.formatMonthYear(_month),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        if (!_choosingYear) ...[
          IconButton(
            key: const ValueKey('date-range-previous-month'),
            tooltip: l10n.previousMonthTooltip,
            onPressed: _canGoBack ? () => _shiftMonth(-1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            key: const ValueKey('date-range-next-month'),
            tooltip: l10n.nextMonthTooltip,
            onPressed: _canGoForward ? () => _shiftMonth(1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ],
    );
  }

  Widget _buildYearGrid() {
    return _YearGrid(
      key: const ValueKey('date-range-year-grid'),
      firstYear: _first.year,
      lastYear: _last.year,
      selectedYear: _month.year,
      height: _cellExtent * 7,
      onSelected: (year) => setState(() {
        final month = DateTime(year, _month.month);
        final firstMonth = DateTime(_first.year, _first.month);
        final lastMonth = DateTime(_last.year, _last.month);
        _month = month.isBefore(firstMonth)
            ? firstMonth
            : month.isAfter(lastMonth)
            ? lastMonth
            : month;
        _choosingYear = false;
      }),
    );
  }

  Widget _buildMonthGrid(ThemeData theme, MaterialLocalizations l10n) {
    final scheme = theme.colorScheme;
    final firstWeekday = l10n.firstDayOfWeekIndex;
    final weekdayLabels = [
      for (var i = 0; i < 7; i++) l10n.narrowWeekdays[(firstWeekday + i) % 7],
    ];
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final leading = DateUtils.firstDayOffset(_month.year, _month.month, l10n);
    final today = DateUtils.dateOnly(DateTime.now());

    Widget dayCell(int index) {
      final dayNumber = index - leading + 1;
      if (dayNumber < 1 || dayNumber > daysInMonth) {
        return const SizedBox.shrink();
      }
      final day = DateTime(_month.year, _month.month, dayNumber);
      final enabled = !day.isBefore(_first) && !day.isAfter(_last);
      final start = _start;
      final end = _end;
      final isStart = start != null && DateUtils.isSameDay(day, start);
      final isEnd = end != null && DateUtils.isSameDay(day, end);
      final isEndpoint = isStart || isEnd;
      final inRange =
          start != null &&
          end != null &&
          !day.isBefore(start) &&
          !day.isAfter(end);
      final bandColor = scheme.primary.withValues(alpha: 0.18);
      final hasRangeEnd = start != null && end != null && start != end;
      final isToday = DateUtils.isSameDay(day, today);

      return Semantics(
        button: true,
        enabled: enabled,
        selected: isEndpoint || inRange,
        label: l10n.formatFullDate(day),
        excludeSemantics: true,
        child: GestureDetector(
          key: ValueKey('date-range-day-${day.year}-${day.month}-${day.day}'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => _selectDay(day) : null,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (inRange && hasRangeEnd)
                Padding(
                  key: ValueKey(
                    'date-range-band-${day.year}-${day.month}-${day.day}',
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ColoredBox(
                          color: isStart ? Colors.transparent : bandColor,
                        ),
                      ),
                      Expanded(
                        child: ColoredBox(
                          color: isEnd ? Colors.transparent : bandColor,
                        ),
                      ),
                    ],
                  ),
                ),
              Center(
                child: Container(
                  width: _cellExtent - 4,
                  height: _cellExtent - 4,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isEndpoint ? scheme.primary : null,
                    border: isToday && !isEndpoint
                        ? Border.all(color: scheme.primary)
                        : null,
                  ),
                  child: Text(
                    '$dayNumber',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isEndpoint || isToday
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: !enabled
                          ? scheme.onSurface.withValues(alpha: 0.3)
                          : isEndpoint
                          ? scheme.onPrimary
                          : scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      key: ValueKey('date-range-month-${_month.year}-${_month.month}'),
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 200) return;
        _shiftMonth(velocity < 0 ? 1 : -1);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (final label in weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          for (var row = 0; row < 6; row++)
            SizedBox(
              height: _cellExtent,
              child: Row(
                children: [
                  for (var column = 0; column < 7; column++)
                    Expanded(child: dayCell(row * 7 + column)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _YearGrid extends StatefulWidget {
  const _YearGrid({
    required this.firstYear,
    required this.lastYear,
    required this.selectedYear,
    required this.height,
    required this.onSelected,
    super.key,
  });

  final int firstYear;
  final int lastYear;
  final int selectedYear;
  final double height;
  final ValueChanged<int> onSelected;

  @override
  State<_YearGrid> createState() => _YearGridState();
}

class _YearGridState extends State<_YearGrid> {
  static const _rowExtent = 44.0;
  late final ScrollController _controller = ScrollController(
    initialScrollOffset:
        ((widget.selectedYear - widget.firstYear) ~/ 3 - 2).clamp(0, 1 << 20) *
        (_rowExtent + AppSpacing.xs),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: widget.height,
      child: GridView.builder(
        controller: _controller,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisExtent: _rowExtent,
          mainAxisSpacing: AppSpacing.xs,
          crossAxisSpacing: AppSpacing.xs,
        ),
        itemCount: widget.lastYear - widget.firstYear + 1,
        itemBuilder: (context, index) {
          final year = widget.firstYear + index;
          final selected = year == widget.selectedYear;
          return Material(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: InkWell(
              key: ValueKey('date-range-year-$year'),
              borderRadius: BorderRadius.circular(AppRadii.pill),
              onTap: () => widget.onSelected(year),
              child: Center(
                child: Text(
                  '$year',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
