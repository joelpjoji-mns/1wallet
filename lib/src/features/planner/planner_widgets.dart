import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../transactions/transaction_row.dart';

enum TimePeriod { d7, d30, w12, m6, y1 }

extension TimePeriodExtension on TimePeriod {
  String get label {
    switch (this) {
      case TimePeriod.d7: return '7D';
      case TimePeriod.d30: return '30D';
      case TimePeriod.w12: return '12W';
      case TimePeriod.m6: return '6M';
      case TimePeriod.y1: return '1Y';
    }
  }

  Duration get duration {
    switch (this) {
      case TimePeriod.d7: return const Duration(days: 7);
      case TimePeriod.d30: return const Duration(days: 30);
      case TimePeriod.w12: return const Duration(days: 84);
      case TimePeriod.m6: return const Duration(days: 180);
      case TimePeriod.y1: return const Duration(days: 365);
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

Widget _buildTimeSelector(TimePeriod current, ValueChanged<TimePeriod> onChanged) {
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
               Text(current.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
               const SizedBox(width: 4),
               const Icon(Icons.arrow_drop_down, size: 16),
            ],
         ),
      ),
      itemBuilder: (context) => TimePeriod.values.map((p) => PopupMenuItem(
         value: p,
         child: Text(p.label),
      )).toList(),
   );
}

// ---------------------------------------------------------
// WIDGETS
// ---------------------------------------------------------

class BalanceTrendWidget extends StatefulWidget {
  const BalanceTrendWidget({required this.state, super.key});
  final LedgerState state;

  @override
  State<BalanceTrendWidget> createState() => _BalanceTrendWidgetState();
}

class _BalanceTrendWidgetState extends State<BalanceTrendWidget> {
  TimePeriod _period = TimePeriod.d30;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = now.subtract(_period.duration);
    
    int totalCash = 0;
    final balances = accountBalanceMap(widget.state);
    final bankAccountIds = <String>{};
    for (final acc in widget.state.accounts) {
      if (acc.type == 'cash' || acc.type == 'bank') {
         totalCash += convertMoneyForDisplay(widget.state, accountBalanceFromMap(balances, acc), widget.state.preferences.displayCurrency).amountMinor;
         bankAccountIds.add(acc.id);
      }
    }
    
    final daysToPlot = _period.duration.inDays;
    final dailyBalances = List<double>.filled(daysToPlot + 1, 0);
    
    int currentBal = totalCash;
    dailyBalances[daysToPlot] = currentBal.toDouble();
    
    final sortedTxs = widget.state.transactions.toList()..sort((a,b) => b.occurredAt.compareTo(a.occurredAt));
    int txIdx = 0;
    
    for (int i = daysToPlot - 1; i >= 0; i--) {
        final dayStart = start.add(Duration(days: i));
        
        while (txIdx < sortedTxs.length && sortedTxs[txIdx].occurredAt.isAfter(dayStart)) {
            final tx = sortedTxs[txIdx];
            if (tx.status != 'void' && tx.status != 'scheduled' && tx.status != 'paused') {
                if (bankAccountIds.contains(tx.accountId)) {
                    final delta = convertMoneyForDisplay(widget.state, Money(amountMinor: sourceDelta(tx), currency: tx.amount.currency), widget.state.preferences.displayCurrency).amountMinor;
                    currentBal -= delta;
                }
                if (tx.counterAccountId != null && bankAccountIds.contains(tx.counterAccountId)) {
                    final delta = convertMoneyForDisplay(widget.state, Money(amountMinor: counterDelta(tx), currency: tx.counterAmount?.currency ?? tx.amount.currency), widget.state.preferences.displayCurrency).amountMinor;
                    currentBal -= delta;
                }
            }
            txIdx++;
        }
        dailyBalances[i] = currentBal.toDouble();
    }
    
    final pastCash = dailyBalances[0].toInt();
    double percentChange = 0;
    if (pastCash > 0) percentChange = ((totalCash - pastCash) / pastCash) * 100;
    final scheme = Theme.of(context).colorScheme;
    
    final spots = <FlSpot>[];
    double minBal = double.infinity;
    double maxBal = double.negativeInfinity;
    for (int i = 0; i <= daysToPlot; i++) {
        final val = dailyBalances[i];
        if (val < minBal) minBal = val;
        if (val > maxBal) maxBal = val;
        spots.add(FlSpot(i.toDouble(), val));
    }
    
    if (minBal == maxBal) {
       minBal -= 1000;
       maxBal += 1000;
    }
    
    final spanChart = maxBal - minBal;
    double niceInterval = 1.0;
    if (spanChart > 0) {
      final roughStep = spanChart / 4;
      final magnitude = math.pow(10, (math.log(roughStep > 0 ? roughStep : 1) / math.ln10).floor()).toDouble();
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
    
    return DashboardCard(
       child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   const Text('Balance Trend', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                   _buildTimeSelector(_period, (p) => setState(() => _period = p)),
                ],
             ),
             Text('Do I have more money than before?', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
             const SizedBox(height: 24),
             Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         Text('TODAY', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                         Text(formatMoney(Money(amountMinor: totalCash, currency: widget.state.preferences.displayCurrency), widget.state.preferences.locale), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                      ],
                   ),
                   Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                         Text('vs past period', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                         Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                               color: (percentChange >= 0 ? scheme.primary : scheme.error).withAlphaFactor(0.1),
                               borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('${percentChange >= 0 ? '+' : ''}${percentChange.toStringAsFixed(1)}%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: percentChange >= 0 ? scheme.primary : scheme.error)),
                         ),
                      ],
                   ),
                ],
             ),
             const SizedBox(height: 24),
             SizedBox(
                height: 200,
                width: double.infinity,
                child: LineChart(
                   LineChartData(
                      gridData: FlGridData(
                         show: true,
                         drawVerticalLine: false,
                         horizontalInterval: niceInterval,
                             getDrawingHorizontalLine: (value) => FlLine(
                                color: Theme.of(context).colorScheme.outlineVariant.withAlphaFactor(0.3),
                                strokeWidth: 1,
                                dashArray: [4, 4],
                             ),
                      ),
                      titlesData: FlTitlesData(
                         show: true,
                         topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                         rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                         leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                               showTitles: true,
                               reservedSize: 40,
                               interval: niceInterval,
                               getTitlesWidget: (value, meta) {
                                  if (value == 0) return const Text('0', style: TextStyle(fontSize: 10));
                                  final absVal = (value / 100.0).abs();
                                  final sign = value < 0 ? '-' : '';
                                  String text = '$sign${absVal.toInt()}';
                                  
                                  if (niceInterval >= 100000) {
                                    if (absVal >= 100000) {
                                      text = '$sign${(absVal / 100000).round()}L';
                                    } else if (absVal >= 1000) {
                                      text = '$sign${(absVal / 1000).round()}K';
                                    }
                                  } else if (niceInterval >= 1000) {
                                    if (absVal >= 1000) {
                                      text = '$sign${(absVal / 1000).round()}K';
                                    }
                                  }
                                  return Text(text, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant));
                               },
                            ),
                         ),
                         bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                               showTitles: true,
                               reservedSize: 22,
                               getTitlesWidget: (value, meta) {
                                  final intValue = value.toInt();
                                  final middle = daysToPlot ~/ 2;
                                  if (intValue == 0) {
                                     return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text('${start.day}/${start.month}', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)));
                                  } else if (intValue == daysToPlot && daysToPlot > 0) {
                                     final date = start.add(Duration(days: intValue));
                                     return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text('${date.day}/${date.month}', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)));
                                  } else if (intValue == middle && middle > 0 && middle < daysToPlot) {
                                     final date = start.add(Duration(days: intValue));
                                     return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text('${date.day}/${date.month}', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)));
                                  }
                                  return const SizedBox.shrink();
                               },
                            ),
                         ),
                      ),
                      borderData: FlBorderData(show: false),
                      minX: 0,
                      maxX: daysToPlot.toDouble(),
                      minY: minBal - (maxBal - minBal) * 0.1,
                      maxY: maxBal + (maxBal - minBal) * 0.1,
                      lineBarsData: [
                         LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: scheme.primary,
                            barWidth: 4,
                            isStrokeCapRound: true,
                            shadow: Shadow(
                               color: scheme.primary.withAlphaFactor(0.3),
                               blurRadius: 8,
                               offset: const Offset(0, 4),
                            ),
                            dotData: FlDotData(
                               show: true,
                               checkToShowDot: (spot, barData) => spot.x == barData.spots.last.x,
                               getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                                  radius: 5,
                                  color: scheme.primary,
                                  strokeWidth: 2,
                                  strokeColor: scheme.surface,
                               ),
                            ),
                            belowBarData: BarAreaData(
                               show: true,
                               gradient: LinearGradient(
                                  colors: [
                                     scheme.primary.withAlphaFactor(0.4),
                                     scheme.primary.withAlphaFactor(0.0),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                               ),
                            ),
                         ),
                      ],
                      lineTouchData: LineTouchData(
                         enabled: true,
                         getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                            return spotIndexes.map((index) {
                               return TouchedSpotIndicatorData(
                                  FlLine(color: scheme.primary.withAlphaFactor(0.5), strokeWidth: 2, dashArray: [4, 4]),
                                  FlDotData(
                                     getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                                        radius: 5,
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
                               return touchedSpots.map((spot) => LineTooltipItem(
                                  formatMoney(
                                     Money(amountMinor: spot.y.toInt(), currency: widget.state.preferences.displayCurrency),
                                     widget.state.preferences.locale,
                                  ),
                                  TextStyle(color: scheme.surface, fontWeight: FontWeight.bold, fontSize: 12),
                               )).toList();
                            },
                         ),
                      ),
                   ),
                ),
             ),
          ],
       ),
    );
  }
}

class TopCategoriesWidget extends StatefulWidget {
  const TopCategoriesWidget({required this.state, super.key});
  final LedgerState state;

  @override
  State<TopCategoriesWidget> createState() => _TopCategoriesWidgetState();
}

class _TopCategoriesWidgetState extends State<TopCategoriesWidget> {
  TimePeriod _period = TimePeriod.d30;

  void _showCategoryRecords(BuildContext context, String categoryId, List<TransactionRecord> records) {
     records.sort((a,b) => b.occurredAt.compareTo(a.occurredAt));
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
                       style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
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
       if (tx.status == 'void' || tx.status == 'scheduled' || tx.status == 'paused') continue;
       if (expenseTypes.contains(tx.type) && tx.occurredAt.isAfter(start)) {
          final amt = convertMoneyForDisplay(widget.state, tx.amount, widget.state.preferences.displayCurrency).amountMinor;
          if (tx.categoryId != null) {
             catTotals[tx.categoryId!] = (catTotals[tx.categoryId!] ?? 0) + amt;
             catRecords.putIfAbsent(tx.categoryId!, () => []).add(tx);
          }
          totalExp += amt;
       }
    }
    
    final sorted = catTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final scheme = Theme.of(context).colorScheme;
    
    return DashboardCard(
       child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   const Text('Top Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                   _buildTimeSelector(_period, (p) => setState(() => _period = p)),
                ],
             ),
             Text('Where is my money going?', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
             const SizedBox(height: 24),
             if (sorted.isEmpty)
                const Text('No spending in this period.'),
             ...sorted.map((entry) {
                final cat = categoryById(widget.state, entry.key);
                final pct = totalExp > 0 ? entry.value / totalExp : 0.0;
                return InkWell(
                   onTap: () => _showCategoryRecords(context, entry.key, catRecords[entry.key] ?? []),
                   borderRadius: BorderRadius.circular(8),
                   child: Padding(
                      padding: const EdgeInsets.only(bottom: 20, top: 4, left: 4, right: 4),
                      child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                            Row(
                               mainAxisAlignment: MainAxisAlignment.spaceBetween,
                               children: [
                                  Text(cat?.name ?? 'Unknown', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                  Text(formatMoney(Money(amountMinor: entry.value, currency: widget.state.preferences.displayCurrency), widget.state.preferences.locale), style: const TextStyle(fontWeight: FontWeight.bold)),
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
             }).toList(),
          ],
       ),
    );
  }
}

class CreditUtilizationWidget extends StatefulWidget {
  const CreditUtilizationWidget({required this.state, super.key});
  final LedgerState state;

  @override
  State<CreditUtilizationWidget> createState() => _CreditUtilizationWidgetState();
}

class _CreditUtilizationWidgetState extends State<CreditUtilizationWidget> {
  TimePeriod _period = TimePeriod.d30;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Exclude loans as requested
    final creditAccounts = widget.state.accounts.where((a) => a.type == 'card').toList();
    final balances = accountBalanceMap(widget.state);
    
    return DashboardCard(
       child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   const Flexible(child: Text('Utilization by Credit Cards', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                   _buildTimeSelector(_period, (p) => setState(() => _period = p)),
                ],
             ),
             Text('Which credit cards am I using the most?', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
             const SizedBox(height: 24),
             if (creditAccounts.isEmpty)
                const Text('No credit accounts.'),
             ...creditAccounts.map((acc) {
                final bal = convertMoneyForDisplay(widget.state, accountBalanceFromMap(balances, acc), widget.state.preferences.displayCurrency).amountMinor.abs();
                final limit = acc.creditLimit != null ? convertMoneyForDisplay(widget.state, acc.creditLimit!, widget.state.preferences.displayCurrency).amountMinor : 0;
                final util = limit > 0 ? (bal / limit) : 0.0;
                
                return Padding(
                   padding: const EdgeInsets.only(bottom: 24),
                   child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                               Expanded(child: Text(acc.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                               if (limit > 0)
                                  Text('${(util * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))
                               else
                                  const Text('N/A', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                            ],
                         ),
                         const SizedBox(height: 8),
                         LinearProgressIndicator(
                            value: limit > 0 ? util : 0.0,
                            color: acc.color ?? scheme.primary,
                            backgroundColor: scheme.surfaceContainerHighest,
                            minHeight: 16,
                            borderRadius: BorderRadius.circular(4),
                         ),
                         const SizedBox(height: 6),
                         Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                               Text('Balance ${formatMoney(Money(amountMinor: bal, currency: widget.state.preferences.displayCurrency), widget.state.preferences.locale)}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                               Text('Limit ${limit > 0 ? formatMoney(Money(amountMinor: limit, currency: widget.state.preferences.displayCurrency), widget.state.preferences.locale) : 'Not Set'}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                            ],
                         ),
                      ],
                   ),
                );
             }).toList(),
          ],
       ),
    );
  }
}
