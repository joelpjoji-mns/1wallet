import 'dart:io';

void main() {
  final file = File('lib/src/features/transactions/transactions_screen.dart');
  var content = file.readAsStringSync();

  if (!content.contains('liquid_glass_widgets.dart')) {
    content = content.replaceFirst(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport 'package:liquid_glass_widgets/liquid_glass_widgets.dart';");
  }

  // Find AppScreen
  final startIdx = content.indexOf('return AppScreen(');
  if (startIdx == -1) return;

  var count = 0;
  var endIdx = -1;
  for (var i = startIdx + 16; i < content.length; i++) {
    if (content[i] == '(') count++;
    else if (content[i] == ')') {
      count--;
      if (count == 0) {
        endIdx = i;
        break;
      }
    }
  }

  var appScreenContent = content.substring(startIdx, endIdx + 1);

  // Replace AppScreen signature with GlassIsolationScope and RouteScaffold
  final oldAppScreen = '''return AppScreen(
      title: _selectedTransactionIds.isNotEmpty
          ? '\${_selectedTransactionIds.length} selected'
          : 'Transactions',
      maxWidth: 1400,
      onMenuPressed: widget.onMenuPressed,
      floatingActionButton: IslandFloatingActionButton(
        icon: Icons.add_rounded,
        tooltip: 'Add record',
        onPressed: () => context.push('/add'),
      ),
      scrollable: false,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      actions: _selectedTransactionIds.isNotEmpty
          ? [
              HeaderIconButton(
                icon: Icons.delete_outline_rounded,
                onPressed: _confirmDeleteSelected,
                semanticLabel: 'Delete selected transactions',
              ),
              HeaderIconButton(
                icon: Icons.close_rounded,
                onPressed: () =>
                    setState(() => _selectedTransactionIds.clear()),
                semanticLabel: 'Clear selection',
              ),
            ]
          : [
              HeaderIconButton(
                icon: Icons.currency_exchange_rounded,
                onPressed: () => _showDisplayCurrencyPicker(state),
                semanticLabel: 'Choose display currency',
              ),
              HeaderIconButton(
                icon: Icons.add_rounded,
                onPressed: () => context.push('/add'),
                semanticLabel: 'Add record',
              ),
              HeaderIconButton(
                icon: Icons.dashboard_customize_outlined,
                onPressed: () => context.push('/widgets'),
                semanticLabel: 'Customize widgets',
              ),
            ],
      child: Column(''';
      
  final newAppScreen = '''return GlassIsolationScope(
      isolated: true,
      child: RouteScaffold(
        appBar: GlassAppBar(
          title: _selectedTransactionIds.isNotEmpty
              ? '\${_selectedTransactionIds.length} selected'
              : 'Transactions',
          leading: HeaderIconButton(
            icon: Icons.menu_rounded,
            onPressed: widget.onMenuPressed,
            semanticLabel: 'Menu',
          ),
          actions: _selectedTransactionIds.isNotEmpty
              ? [
                  HeaderIconButton(
                    icon: Icons.delete_outline_rounded,
                    onPressed: _confirmDeleteSelected,
                    semanticLabel: 'Delete selected transactions',
                  ),
                  HeaderIconButton(
                    icon: Icons.close_rounded,
                    onPressed: () =>
                        setState(() => _selectedTransactionIds.clear()),
                    semanticLabel: 'Clear selection',
                  ),
                ]
              : [
                  HeaderIconButton(
                    icon: Icons.currency_exchange_rounded,
                    onPressed: () => _showDisplayCurrencyPicker(state),
                    semanticLabel: 'Choose display currency',
                  ),
                  HeaderIconButton(
                    icon: Icons.add_rounded,
                    onPressed: () => context.push('/add'),
                    semanticLabel: 'Add record',
                  ),
                ],
        ),
        floatingActionButton: IslandFloatingActionButton(
          icon: Icons.add_rounded,
          tooltip: 'Add record',
          onPressed: () => context.push('/add'),
        ),
        body: Column''';

  appScreenContent = appScreenContent.replaceFirst(oldAppScreen, newAppScreen);
  if (appScreenContent.endsWith(')')) {
    appScreenContent = appScreenContent.substring(0, appScreenContent.length - 1) + ')\n    )';
  }

  final itemsStart = appScreenContent.indexOf('final items = <Object>[];');
  final listviewStart = appScreenContent.indexOf('return ListView.builder(');
  var listviewEnd = -1;
  count = 0;
  for (var i = listviewStart + 23; i < appScreenContent.length; i++) {
    if (appScreenContent[i] == '(') count++;
    else if (appScreenContent[i] == ')') {
      count--;
      if (count == 0) {
        listviewEnd = i;
        break;
      }
    }
  }

  final newListView = '''
                      final widgets = <Widget>[];
                      String? currentMonth;
                      DateTime? currentDay;
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      final yesterday = today.subtract(const Duration(days: 1));
                      final locale = state.preferences.locale.replaceAll('_', '-');
                      
                      String? currentDayLabel;
                      List<TransactionRecord> currentDayTransactions = [];

                      void flushDay() {
                        if (currentDayTransactions.isNotEmpty && currentDayLabel != null) {
                          widgets.add(
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.md),
                              child: GlassGroupedSection(
                                header: Text(currentDayLabel!),
                                children: [
                                  for (var i = 0; i < currentDayTransactions.length; i++) ...[
                                    if (i > 0) const GlassDivider(),
                                    TransactionRow(
                                      glass: true,
                                      state: state,
                                      transaction: currentDayTransactions[i],
                                      selectedAccountId: accountFilter,
                                      selected: _selectedTransactionIds.contains(
                                        currentDayTransactions[i].id,
                                      ),
                                      onLongPress: () {
                                        setState(() {
                                          if (_selectedTransactionIds.contains(
                                            currentDayTransactions[i].id,
                                          )) {
                                            _selectedTransactionIds.remove(
                                              currentDayTransactions[i].id,
                                            );
                                          } else {
                                            _selectedTransactionIds.add(currentDayTransactions[i].id);
                                          }
                                        });
                                      },
                                      onTap: () {
                                        if (_selectedTransactionIds.isNotEmpty) {
                                          setState(() {
                                            if (_selectedTransactionIds.contains(
                                              currentDayTransactions[i].id,
                                            )) {
                                              _selectedTransactionIds.remove(
                                                currentDayTransactions[i].id,
                                              );
                                            } else {
                                              _selectedTransactionIds.add(
                                                currentDayTransactions[i].id,
                                              );
                                            }
                                          });
                                        } else {
                                          context.push(
                                            '/transaction/\${currentDayTransactions[i].id}',
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                          currentDayTransactions = [];
                        }
                      }

                      for (final t in transactions) {
                        final monthStr = DateFormat('MMM yyyy', locale).format(t.occurredAt).toUpperCase();
                        
                        final isNewMonth = currentMonth != monthStr;
                        if (isNewMonth) {
                          flushDay();
                          currentMonth = monthStr;
                          
                          final balanceStr = formatMoney(
                            Money(
                              amountMinor: monthlyBalances[monthStr] ?? 0,
                              currency: state.preferences.displayCurrency,
                            ),
                            state.preferences.locale,
                          );
                          final flowStr = formatMoney(
                            Money(
                              amountMinor: monthlyFlows[monthStr] ?? 0,
                              currency: state.preferences.displayCurrency,
                            ),
                            state.preferences.locale,
                          );
                          
                          widgets.add(
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                0,
                                widgets.isEmpty ? 0 : AppSpacing.md,
                                0,
                                AppSpacing.sm,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    monthStr,
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: PrivacyText(
                                          'Balance \$balanceStr',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                      PrivacyText(
                                        '∑ \$flowStr',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        
                        final occurredAt = t.occurredAt;
                        final day = DateTime(occurredAt.year, occurredAt.month, occurredAt.day);
                        if (isNewMonth || currentDay != day) {
                          flushDay();
                          currentDay = day;
                          if (day == today) {
                            currentDayLabel = 'Today';
                          } else if (day == yesterday) {
                            currentDayLabel = 'Yesterday';
                          } else {
                            currentDayLabel = DateFormat('EEE, d MMM', locale).format(day);
                          }
                        }
                        
                        currentDayTransactions.add(t);
                      }
                      flushDay();

                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: AppSizes.bottomBarClearance),
                        itemCount: widgets.length,
                        itemBuilder: (context, index) => widgets[index],
                      );
''';

  if (itemsStart != -1 && listviewStart != -1) {
    appScreenContent = appScreenContent.substring(0, itemsStart) + newListView.trim() + '\n' + appScreenContent.substring(listviewEnd + 1);
  }

  content = content.substring(0, startIdx) + appScreenContent + content.substring(endIdx + 1);
  file.writeAsStringSync(content);
}
