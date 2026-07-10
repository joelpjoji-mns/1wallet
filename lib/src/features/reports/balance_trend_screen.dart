import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../home/home_async_providers.dart';
import '../home/home_dashboard_selectors.dart';

class BalanceTrendScreen extends ConsumerStatefulWidget {
  const BalanceTrendScreen({super.key});

  @override
  ConsumerState<BalanceTrendScreen> createState() => _BalanceTrendScreenState();
}

class _BalanceTrendScreenState extends ConsumerState<BalanceTrendScreen> {
  String _period = 'This year';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final scheme = Theme.of(context).colorScheme;

    final now = DateTime.now();
    DateTime? start;
    switch (_period) {
      case 'This week':
        start = now.subtract(const Duration(days: 7));
        break;
      case 'This month':
        start = now.subtract(const Duration(days: 30));
        break;
      case 'This year':
        start = DateTime(now.year);
        break;
      case 'All time':
        start = null;
        break;
    }

    final nowRounded = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final trend = ref.watch(
      homeBalanceTrendProvider((start: start, end: nowRounded)),
    );
    final current = ref.watch(
      homeTotalBalanceProvider((accountId: null, targetCurrency: null)),
    );

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: const Text('Balance Trend'), centerTitle: true),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'This week', label: Text('Week')),
                ButtonSegment(value: 'This month', label: Text('Month')),
                ButtonSegment(value: 'This year', label: Text('Year')),
                ButtonSegment(value: 'All time', label: Text('All')),
              ],
              selected: {_period},
              onSelectionChanged: (set) => setState(() => _period = set.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'CURRENT BALANCE',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatMoney(current, state.preferences.locale),
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: current.amountMinor >= 0
                          ? const Color(0xff22c55e)
                          : const Color(0xffef4444),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '(Included accounts only)',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BALANCE TREND',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Expanded(
                      child: _buildChart(
                        trend,
                        scheme,
                        state.preferences.locale,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  String _formatMoney(Money money, String locale) {
    final amount = money.amountMinor / 100.0;
    return NumberFormat.simpleCurrency(
      name: money.currency,
      locale: locale,
    ).format(amount);
  }

  String _formatYAxisLabel(double value) {
    if (value == 0) return '0';
    final absVal = value.abs();
    final sign = value < 0 ? '-' : '';
    if (absVal >= 100000) {
      final l = absVal / 100000;
      return '$sign${l.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}L';
    } else if (absVal >= 1000) {
      final k = absVal / 1000;
      return '$sign${k.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}K';
    }
    return '$sign${absVal.toInt()}';
  }

  Widget _buildChart(
    List<BalanceTrendPoint> trend,
    ColorScheme scheme,
    String locale,
  ) {
    if (trend.isEmpty) {
      return const Center(child: Text('No data for this period'));
    }

    final spots = <FlSpot>[];
    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (final point in trend) {
      final x = point.date.millisecondsSinceEpoch.toDouble();
      final y = point.balance.amountMinor / 100.0;
      spots.add(FlSpot(x, y));

      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    if (maxY == minY) {
      maxY += 100000;
      minY -= 100000;
    } else {
      final span = maxY - minY;
      maxY += span * 0.2;
      minY -= span * 0.2;
    }

    if (spots.isNotEmpty) {
      final finalValue = spots.last.y;
      final span = maxY - minY;
      final percentile = (finalValue - minY) / span;

      if (percentile > 0.8) {
        maxY = (finalValue - 0.2 * minY) / 0.8;
      } else if (percentile < 0.2) {
        minY = (finalValue - 0.2 * maxY) / 0.8;
      }
    }

    if (spots.length == 1) {
      final single = spots.first;
      spots.add(FlSpot(single.x + 86400000, single.y));
      maxX += 86400000;
    }

    // Calculate rounded bounds and intervals
    double interval = 1000;
    final yRange = (maxY - minY).abs();
    if (yRange > 1000000) {
      interval = 500000;
    } else if (yRange > 500000) {
      interval = 200000;
    } else if (yRange > 200000) {
      interval = 100000;
    } else if (yRange > 100000) {
      interval = 50000;
    } else if (yRange > 50000) {
      interval = 20000;
    } else if (yRange > 10000) {
      interval = 5000;
    } else if (yRange > 0) {
      interval = 1000;
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          drawHorizontalLine: true,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (value) {
            if (value == 0) {
              return FlLine(color: scheme.onSurfaceVariant, strokeWidth: 2);
            }
            return FlLine(color: scheme.outlineVariant, strokeWidth: 1);
          },
          getDrawingVerticalLine: (value) =>
              FlLine(color: scheme.outlineVariant, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                if (value == minX || value == maxX)
                  return const SizedBox.shrink();
                final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    DateFormat.yMMMd().format(date),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: interval,
              getTitlesWidget: (value, meta) {
                if (value == minY || value == maxY)
                  return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(
                    _formatYAxisLabel(value),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant, width: 1),
            left: BorderSide(color: scheme.outlineVariant, width: 1),
          ),
        ),
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.1,
            color: const Color(0xff3b82f6),
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0x1a3b82f6),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xff1e293b),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final date = DateTime.fromMillisecondsSinceEpoch(
                  spot.x.toInt(),
                );
                return LineTooltipItem(
                  '${DateFormat.yMMMd().format(date)}\n',
                  const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  children: [
                    TextSpan(
                      text: NumberFormat.simpleCurrency(
                        name: trend.first.balance.currency,
                        locale: locale,
                      ).format(spot.y),
                      style: const TextStyle(fontWeight: FontWeight.normal),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}
