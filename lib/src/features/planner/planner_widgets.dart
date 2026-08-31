import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/privacy_text.dart';
import '../home/home_async_providers.dart';
import '../transactions/transaction_row.dart';

enum TimePeriod { d7, d30, w12, m6, y1 }

extension TimePeriodExtension on TimePeriod {
  String get label {
    switch (this) {
      case TimePeriod.d7:
        return '7D';
      case TimePeriod.d30:
        return '30D';
      case TimePeriod.w12:
        return '12W';
      case TimePeriod.m6:
        return '6M';
      case TimePeriod.y1:
        return '1Y';
    }
  }

  Duration get duration {
    switch (this) {
      case TimePeriod.d7:
        return const Duration(days: 7);
      case TimePeriod.d30:
        return const Duration(days: 30);
      case TimePeriod.w12:
        return const Duration(days: 84);
      case TimePeriod.m6:
        return const Duration(days: 180);
      case TimePeriod.y1:
        return const Duration(days: 365);
    }
  }
}

class DashboardCard extends StatelessWidget {
  const DashboardCard({required this.child, this.onTap, super.key});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withAlphaFactor(0.3)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withAlphaFactor(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: child,
          ),
        ),
      ),
    );
  }
}

Widget _buildTimeSelector(
  TimePeriod current,
  ValueChanged<TimePeriod> onChanged,
) {
  return PopupMenuButton<TimePeriod>(
    initialValue: current,
    onSelected: onChanged,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.withAlphaFactor(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            current.label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, size: 16),
        ],
      ),
    ),
    itemBuilder: (context) => TimePeriod.values
        .map((p) => PopupMenuItem(value: p, child: Text(p.label)))
        .toList(),
  );
}

// ---------------------------------------------------------
// WIDGETS
// ---------------------------------------------------------

class BalanceTrendWidget extends ConsumerStatefulWidget {
  const BalanceTrendWidget({required this.state, super.key});
  final LedgerState state;

  @override
  ConsumerState<BalanceTrendWidget> createState() => _BalanceTrendWidgetState();
}

class _BalanceTrendWidgetState extends ConsumerState<BalanceTrendWidget> {
  TimePeriod _period = TimePeriod.d30;
  // Past data occupies 80% of the chart canvas; future the remaining 20%
  static const double _pastFraction = 0.8;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowRounded = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final start = nowRounded.subtract(_period.duration);

    // Future window: capped at 60 days, minimum 7
    final futureDays = math.min(_period.duration.inDays, 60).clamp(7, 60);
    final futureEnd = nowRounded.add(Duration(days: futureDays));

    // Past trend from home provider (same data, all included accounts)
    final pastTrend = ref.watch(
      homeBalanceTrendProvider((start: start, end: nowRounded)),
    );
    final futureTrend = ref.watch(
      homeBalanceFutureTrendProvider((start: nowRounded, end: futureEnd)),
    );

    final pastValues = pastTrend.map((p) => p.balance.amountMinor).toList();
    final futureValues = futureTrend.map((p) => p.balance.amountMinor).toList();
    final allValues = [...pastValues, ...futureValues];

    // Also keep cash/bank totals for the summary header
    int totalCash = 0;
    final balances = accountBalanceMap(widget.state);
    final bankAccountIds = <String>{};
    for (final acc in widget.state.accounts) {
      if (acc.type == 'cash' || acc.type == 'bank') {
        totalCash += convertMoneyForDisplay(
          widget.state,
          accountBalanceFromMap(balances, acc),
          widget.state.preferences.displayCurrency,
        ).amountMinor;
        bankAccountIds.add(acc.id);
      }
    }

    final scheme = Theme.of(context).colorScheme;

    // % change vs start of period
    final pastStartBalance = pastValues.isNotEmpty ? pastValues.first : totalCash;
    double percentChange = 0;
    if (pastStartBalance != 0) {
      percentChange = ((totalCash - pastStartBalance) / pastStartBalance.abs()) * 100;
    }

    // Y-axis range
    var minY = allValues.isEmpty ? 0.0 : allValues.reduce(math.min).toDouble();
    var maxY = allValues.isEmpty ? 0.0 : allValues.reduce(math.max).toDouble();
    if (maxY == minY) {
      maxY += 100000;
      minY -= 100000;
    } else {
      final span = maxY - minY;
      maxY += span * 0.2;
      minY -= span * 0.2;
    }

    final spanChart = maxY - minY;
    double niceInterval = 1.0;
    if (spanChart > 0) {
      final roughStep = spanChart / 4;
      final magnitude = math
          .pow(
            10,
            (math.log(roughStep > 0 ? roughStep : 1) / math.ln10).floor(),
          )
          .toDouble();
      final normalizedStep = roughStep / magnitude;
      double niceStep;
      if (normalizedStep < 1.5) {
        niceStep = 1.0;
      } else if (normalizedStep < 3.5) {
        niceStep = 2.0;
      } else if (normalizedStep < 7.5) {
        niceStep = 5.0;
      } else {
        niceStep = 10.0;
      }
      niceInterval = niceStep * magnitude;
      if (spanChart >= 100000 && niceInterval < 100000) {
        niceInterval = 100000.0;
      } else if (spanChart >= 1000 && niceInterval < 1000) {
        niceInterval = 1000.0;
      }
    }

    String formatCompact(num amountMinor) {
      if (amountMinor == 0) return '0';
      final absVal = (amountMinor / 100.0).abs();
      final sign = amountMinor < 0 ? '-' : '';
      if (niceInterval >= 100000) {
        if (absVal >= 100000) return '$sign${(absVal / 100000).round()}L';
        if (absVal >= 1000) return '$sign${(absVal / 1000).round()}K';
      } else if (niceInterval >= 1000) {
        if (absVal >= 1000) return '$sign${(absVal / 1000).round()}K';
      }
      return '$sign${absVal.toInt()}';
    }

    // Unified X-axis: past = [0 .. pastN-1], future continues from nowX
    final pastN = pastTrend.length;
    final futureN = futureTrend.length;
    final totalN = pastN + futureN - 1; // shared "now" point
    final nowX = (pastN - 1).toDouble();

    final pastSpots = <FlSpot>[
      for (int i = 0; i < pastN; i++)
        FlSpot(i.toDouble(), pastValues[i].toDouble()),
    ];
    final futureSpots = <FlSpot>[
      for (int i = 0; i < futureN; i++)
        FlSpot(nowX + i.toDouble(), futureValues[i].toDouble()),
    ];

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Balance Trend',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              _buildTimeSelector(_period, (p) => setState(() => _period = p)),
            ],
          ),
          Text(
            'Do I have more money than before?',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TODAY',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    PrivacyText(
                      formatMoney(
                        Money(
                          amountMinor: totalCash,
                          currency: widget.state.preferences.displayCurrency,
                        ),
                        widget.state.preferences.locale,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'vs past period',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (percentChange >= 0 ? scheme.primary : scheme.error)
                          .withAlphaFactor(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${percentChange >= 0 ? '+' : ''}${percentChange.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: percentChange >= 0 ? scheme.primary : scheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (allValues.isEmpty)
            const SizedBox(
              height: 200,
              child: Center(child: Text('No data')),
            )
          else
            SizedBox(
              height: 200,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Past region = 80% of visible width; total canvas wider
                  final availableWidth = math.max(
                    constraints.maxWidth - 44.0,
                    300.0,
                  );
                  final totalWidth = pastN > 1
                      ? availableWidth / _pastFraction
                      : availableWidth;

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: SizedBox(
                      width: totalWidth,
                      child: LineChart(
                        LineChartData(
                          clipData: FlClipData.none(),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: niceInterval,
                            getDrawingHorizontalLine: (value) => FlLine(
                              color: scheme.outlineVariant.withAlphaFactor(0.25),
                              strokeWidth: 0.5,
                              dashArray: [3, 5],
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            topTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 44,
                                interval: niceInterval,
                                getTitlesWidget: (value, meta) {
                                  return PrivacyText(
                                    formatCompact(value),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  );
                                },
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 22,
                                getTitlesWidget: (value, meta) {
                                  final idx = value.round();
                                  if (idx == 0 && pastTrend.isNotEmpty) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        '${start.day}/${start.month}',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    );
                                  }
                                  if (idx == pastN - 1) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Now',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: scheme.primary,
                                        ),
                                      ),
                                    );
                                  }
                                  if (futureTrend.isNotEmpty && idx == totalN - 1) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        '${futureEnd.day}/${futureEnd.month}',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          minX: 0,
                          maxX: (totalN - 1).toDouble(),
                          minY: minY,
                          maxY: maxY,
                          extraLinesData: ExtraLinesData(
                            verticalLines: [
                              VerticalLine(
                                x: nowX,
                                color: scheme.primary.withAlphaFactor(0.4),
                                strokeWidth: 1.0,
                                dashArray: [4, 4],
                                label: VerticalLineLabel(show: false),
                              ),
                            ],
                          ),
                          lineBarsData: [
                            // Past line — full colour
                            if (pastSpots.length > 1)
                              LineChartBarData(
                                spots: pastSpots,
                                isCurved: true,
                                curveSmoothness: 0.3,
                                color: scheme.primary,
                                barWidth: 1.5,
                                isStrokeCapRound: true,
                                shadow: Shadow(
                                  color: scheme.primary.withAlphaFactor(0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                                dotData: FlDotData(
                                  show: true,
                                  checkToShowDot: (spot, barData) =>
                                      spot.x == barData.spots.last.x,
                                  getDotPainter: (spot, percent, barData, index) =>
                                      FlDotCirclePainter(
                                        radius: 4,
                                        color: scheme.primary,
                                        strokeWidth: 2,
                                        strokeColor: scheme.surface,
                                      ),
                                ),
                                belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                    colors: [
                                      scheme.primary.withAlphaFactor(0.35),
                                      scheme.primary.withAlphaFactor(0.0),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            // Future line — muted/greyed out dashed
                            if (futureSpots.length > 1)
                              LineChartBarData(
                                spots: futureSpots,
                                isCurved: true,
                                curveSmoothness: 0.3,
                                color: scheme.onSurfaceVariant.withAlphaFactor(0.45),
                                barWidth: 1.2,
                                isStrokeCapRound: true,
                                dashArray: [6, 4],
                                dotData: FlDotData(
                                  show: true,
                                  checkToShowDot: (spot, barData) =>
                                      spot.x == barData.spots.last.x,
                                  getDotPainter: (spot, percent, barData, index) =>
                                      FlDotCirclePainter(
                                        radius: 3,
                                        color: scheme.onSurfaceVariant
                                            .withAlphaFactor(0.5),
                                        strokeWidth: 1,
                                        strokeColor: scheme.surface,
                                      ),
                                ),
                                belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                    colors: [
                                      scheme.onSurfaceVariant.withAlphaFactor(0.12),
                                      scheme.onSurfaceVariant.withAlphaFactor(0.0),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                          ],
                          lineTouchData: LineTouchData(
                            enabled: true,
                            getTouchedSpotIndicator: (
                              LineChartBarData barData,
                              List<int> spotIndexes,
                            ) {
                              return spotIndexes.map((index) {
                                return TouchedSpotIndicatorData(
                                  FlLine(
                                    color: scheme.primary.withAlphaFactor(0.4),
                                    strokeWidth: 1.5,
                                    dashArray: [4, 4],
                                  ),
                                  FlDotData(
                                    getDotPainter:
                                        (spot, percent, barData, index) =>
                                            FlDotCirclePainter(
                                              radius: 4,
                                              color: scheme.primary,
                                              strokeWidth: 2,
                                              strokeColor: scheme.surface,
                                            ),
                                  ),
                                );
                              }).toList();
                            },
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (touchedSpot) => scheme.onSurface,
                              getTooltipItems: (touchedSpots) {
                                return touchedSpots
                                    .map(
                                      (spot) => LineTooltipItem(
                                        maskMoneyIfPrivate(
                                          widget.state,
                                          formatMoney(
                                            Money(
                                              amountMinor: spot.y.toInt(),
                                              currency: widget
                                                  .state
                                                  .preferences
                                                  .displayCurrency,
                                            ),
                                            widget.state.preferences.locale,
                                          ),
                                        ),
                                        TextStyle(
                                          color: scheme.surface,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    )
                                    .toList();
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          // Legend
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TrendLegendDot(color: scheme.primary),
                const SizedBox(width: 4),
                Text(
                  'Actual',
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 12),
                _TrendLegendDot(
                  color: scheme.onSurfaceVariant.withAlphaFactor(0.5),
                  dashed: true,
                ),
                const SizedBox(width: 4),
                Text(
                  'Projected',
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendLegendDot extends StatelessWidget {
  const _TrendLegendDot({required this.color, this.dashed = false});

  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 2),
      painter: _TrendLinePainter(color: color, dashed: dashed),
    );
  }
}

class _TrendLinePainter extends CustomPainter {
  const _TrendLinePainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (!dashed) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
    } else {
      double x = 0;
      const dashLen = 4.0;
      const gapLen = 3.0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, size.height / 2),
          Offset(math.min(x + dashLen, size.width), size.height / 2),
          paint,
        );
        x += dashLen + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(_TrendLinePainter old) =>
      old.color != color || old.dashed != dashed;
}

class TopCategoriesWidget extends StatefulWidget {
  const TopCategoriesWidget({required this.state, super.key});
  final LedgerState state;

  @override
  State<TopCategoriesWidget> createState() => _TopCategoriesWidgetState();
}

class _TopCategoriesWidgetState extends State<TopCategoriesWidget> {
  TimePeriod _period = TimePeriod.d30;

  void _showCategoryRecords(
    BuildContext context,
    String categoryId,
    List<TransactionRecord> records,
  ) {
    records.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                categoryById(widget.state, categoryId)?.name ?? 'Unknown',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final transaction in records) ...[
                TransactionRow(
                  state: widget.state,
                  transaction: transaction,
                  onTap: () {
                    context.push('/transaction/${transaction.id}');
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = now.subtract(_period.duration);
    final catTotals = <String, int>{};
    final catRecords = <String, List<TransactionRecord>>{};
    int totalExp = 0;

    for (final tx in widget.state.transactions) {
      if (tx.status == 'void' ||
          tx.status == 'scheduled' ||
          tx.status == 'paused') {
        continue;
      }
      if (expenseTypes.contains(tx.type) && tx.occurredAt.isAfter(start)) {
        final amt = convertMoneyForDisplay(
          widget.state,
          tx.amount,
          widget.state.preferences.displayCurrency,
        ).amountMinor;
        if (tx.categoryId != null) {
          catTotals[tx.categoryId!] = (catTotals[tx.categoryId!] ?? 0) + amt;
          catRecords.putIfAbsent(tx.categoryId!, () => []).add(tx);
        }
        totalExp += amt;
      }
    }

    final sorted = catTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final scheme = Theme.of(context).colorScheme;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Top Categories',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              _buildTimeSelector(_period, (p) => setState(() => _period = p)),
            ],
          ),
          Text(
            'Where is my money going?',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (sorted.isEmpty) const Text('No spending in this period.'),
          ...sorted.map((entry) {
            final cat = categoryById(widget.state, entry.key);
            final pct = totalExp > 0 ? entry.value / totalExp : 0.0;
            return InkWell(
              onTap: () => _showCategoryRecords(
                context,
                entry.key,
                catRecords[entry.key] ?? [],
              ),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.only(
                  bottom: 20,
                  top: 4,
                  left: 4,
                  right: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            cat?.name ?? 'Unknown',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: PrivacyText(
                            formatMoney(
                              Money(
                                amountMinor: entry.value,
                                currency:
                                    widget.state.preferences.displayCurrency,
                              ),
                              widget.state.preferences.locale,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: pct,
                      color: cat?.color ?? scheme.primary,
                      backgroundColor: scheme.surfaceContainerHighest,
                      minHeight: 16,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class CreditUtilizationWidget extends StatelessWidget {
  const CreditUtilizationWidget({required this.state, super.key});
  final LedgerState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Exclude loans as requested
    final creditAccounts = state.accounts
        .where(
          (a) => (a.type == 'credit_card' || a.type == 'card') && !a.isArchived,
        )
        .toList();
    final balances = accountBalanceMap(state);

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Credit Card Utilization',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            'Which credit cards am I using the most?',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (creditAccounts.isEmpty) const Text('No credit accounts.'),
          ...creditAccounts.map((acc) {
            final bal = convertMoneyForDisplay(
              state,
              accountBalanceFromMap(balances, acc),
              state.preferences.displayCurrency,
            ).amountMinor.abs();
            final limit = acc.creditLimit != null
                ? convertMoneyForDisplay(
                    state,
                    acc.creditLimit!,
                    state.preferences.displayCurrency,
                  ).amountMinor
                : 0;
            final util = limit > 0 ? (bal / limit) : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          acc.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (limit > 0)
                        Text(
                          '${(util * 100).round()}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        )
                      else
                        const Text(
                          'N/A',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: limit > 0 ? util.clamp(0.0, 1.0) : 0.0,
                    color: acc.color ?? scheme.primary,
                    backgroundColor: scheme.surfaceContainerHighest,
                    minHeight: 16,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: PrivacyText(
                          'Balance ${formatMoney(Money(amountMinor: bal, currency: state.preferences.displayCurrency), state.preferences.locale)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: PrivacyText(
                          'Limit ${limit > 0 ? formatMoney(Money(amountMinor: limit, currency: state.preferences.displayCurrency), state.preferences.locale) : 'Not Set'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
