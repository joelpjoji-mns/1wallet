import re

with open('lib/src/features/transactions/transactions_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add import
if 'liquid_glass_widgets.dart' not in content:
    content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:liquid_glass_widgets/liquid_glass_widgets.dart';")

# 2. Find the AppScreen definition and replace it
# The AppScreen goes from `return AppScreen(` up to the closing `);` before `bool _hasActiveFilters`
# Let's use regex to find `return AppScreen(` and matching parenthesis.
def find_matching_paren(text, start_index):
    count = 0
    for i in range(start_index, len(text)):
        if text[i] == '(':
            count += 1
        elif text[i] == ')':
            count -= 1
            if count == 0:
                return i
    return -1

start_idx = content.find('return AppScreen(')
end_idx = find_matching_paren(content, start_idx + 16)

app_screen_content = content[start_idx:end_idx+1]

# Rebuild the UI manually:
# We need to extract the parts of AppScreen and use them in RouteScaffold.
# However, modifying this heavily is risky without parsing. Let's do string replaces on the original block.

app_screen_new = app_screen_content.replace(
    '''return AppScreen(
      title: _selectedTransactionIds.isNotEmpty
          ? '${_selectedTransactionIds.length} selected'
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
      child: Column(''',
    '''return GlassIsolationScope(
      isolated: true,
      child: RouteScaffold(
        appBar: GlassAppBar(
          title: _selectedTransactionIds.isNotEmpty
              ? '${_selectedTransactionIds.length} selected'
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
        body: Column('''
)

# And close GlassIsolationScope instead of AppScreen
if app_screen_new.endswith(')'):
    app_screen_new = app_screen_new[:-1] + ')\n    )'

# Now handle the ListView.builder replacement
listview_idx = app_screen_new.find('return ListView.builder(')
listview_end_idx = find_matching_paren(app_screen_new, listview_idx + 23)

old_list_view = app_screen_new[listview_idx:listview_end_idx+1]

new_list_view = '''
                      final widgets = <Widget>[];
                      String? currentMonth;
                      DateTime? currentDay;
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      final yesterday = today.subtract(const Duration(days: 1));
                      final locale = state.preferences.locale.replaceAll(
                        '_',
                        '-',
                      );
                      
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
                                            '/transaction/${currentDayTransactions[i].id}',
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
                        final monthStr = DateFormat(
                          'MMM yyyy',
                          locale,
                        ).format(t.occurredAt).toUpperCase();
                        
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
                                AppSpacing.sm,
                                widgets.isEmpty ? 0 : AppSpacing.md,
                                AppSpacing.sm,
                                AppSpacing.sm,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    monthStr,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: PrivacyText(
                                          'Balance $balanceStr',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                      PrivacyText(
                                        '∑ $flowStr',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
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
                        padding: const EdgeInsets.only(
                          bottom: AppSizes.bottomBarClearance,
                          left: AppSpacing.md,
                          right: AppSpacing.md,
                        ),
                        itemCount: widgets.length,
                        itemBuilder: (context, index) => widgets[index],
                      );
'''

# We need to replace the old items collection part and the ListView.builder.
# `final items = <Object>[];` is what starts the old list.
items_idx = app_screen_new.find('final items = <Object>[];')
# The block ends after `return ListView.builder(...)`
if items_idx != -1 and listview_idx != -1:
    app_screen_new = app_screen_new[:items_idx] + new_list_view.strip() + '\n' + app_screen_new[listview_end_idx+1:]

content = content[:start_idx] + app_screen_new + content[end_idx+1:]

with open('lib/src/features/transactions/transactions_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("Done")
