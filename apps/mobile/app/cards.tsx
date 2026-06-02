import { formatMoney, toMinor } from '@1wallet/domain/money';
import {
  createFutureGenerationRule,
  forecastFutureRuleOccurrences,
} from '@1wallet/ledger/rules/futureGeneration';
import { indexedAccountBalance } from '@1wallet/ledger/services/indexes';
import { useLedger } from '@1wallet/state';
import { router } from 'expo-router';
import { useMemo, useState } from 'react';
import { View } from 'react-native';
import { Button, Divider, ProgressBar, Snackbar, Text, useTheme } from 'react-native-paper';
import {
  AppScreen,
  EmptyState,
  InfoRow,
  InlineMeta,
  MetricTile,
  SectionCard,
} from '../src/components/AppKit';

export default function Cards() {
  const theme = useTheme();
  const { state, indexes, mutate } = useLedger();
  const [snackbar, setSnackbar] = useState<string | null>(null);
  const cards = useMemo(
    () => state.accounts.filter((account) => account.type === 'credit_card' && !account.isArchived),
    [state.accounts],
  );
  const cardTransactionCount = useMemo(
    () =>
      cards.reduce(
        (count, card) => count + (indexes.transactionsByAccountId.get(card.id)?.length ?? 0),
        0,
      ),
    [cards, indexes.transactionsByAccountId],
  );
  const plannedCardPayments = useMemo(
    () =>
      forecastFutureRuleOccurrences(state, {
        from: startOfDay(new Date()),
        to: daysFromNow(180, 0),
        maxOccurrencesPerRule: 12,
      }).filter((occurrence) => occurrence.type === 'card_payment'),
    [state],
  );
  const nextCardPayment = plannedCardPayments[0];

  const scheduleCardPayment = async () => {
    const card = cards[0];
    if (!card) {
      setSnackbar('Add a credit card account first');
      return;
    }
    const source = state.accounts.find(
      (account) =>
        !account.isArchived &&
        account.currency === card.currency &&
        (account.type === 'bank' || account.type === 'wallet' || account.type === 'cash'),
    );
    if (!source) {
      setSnackbar(`Add a ${card.currency} bank, wallet, or cash account first`);
      return;
    }
    const balance = indexedAccountBalance(indexes, card);
    const amountMinor = Math.max(
      toMinor(5000, card.currency),
      Math.min(Math.abs(balance.amountMinor), toMinor(25000, card.currency)),
    );
    await mutate(
      (draft) => {
        const existingRule = (draft.preferences.futureGenerationRules ?? []).some(
          (rule) =>
            rule.enabled && rule.type === 'card_payment' && rule.counterAccountId === card.id,
        );
        if (existingRule) return;
        const dueAt = daysFromNow(2, 8);
        createFutureGenerationRule(draft, {
          name: `${card.name} payment`,
          type: 'card_payment',
          accountId: source.id,
          counterAccountId: card.id,
          amountMinor,
          currency: card.currency,
          frequency: 'monthly',
          interval: 1,
          dayOfMonth: dueAt.getDate(),
          startsOn: dateOnly(dueAt),
          postMode: 'manual',
          enabled: true,
          paymentMethod: 'Auto debit',
          notes: `${card.name} card payment reminder`,
        });
      },
      { slices: ['preferences'] },
    );
    setSnackbar('Card payment forecast added');
  };

  return (
    <>
      <AppScreen
        title="Cards"
        back={false}
        drawer
        subtitle="Credit cards, statements, due dates, utilization, and payment workflows."
        actions={[{ icon: 'plus', label: 'Add card', onPress: () => router.push('/account/new') }]}
      >
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 12 }}>
          <MetricTile label="Cards" value={String(cards.length)} icon="credit-card-outline" />
          <MetricTile
            label="Card records"
            value={String(cardTransactionCount)}
            icon="format-list-bulleted"
          />
          <MetricTile
            label="Planned pays"
            value={String(plannedCardPayments.length)}
            icon="calendar-clock-outline"
            tone={plannedCardPayments.length ? 'warning' : 'default'}
          />
        </View>

        <SectionCard
          title="Card accounts"
          subtitle="Statement metadata lands after account editing is MD3-complete."
        >
          {cards.length === 0 ? (
            <EmptyState
              icon="credit-card-plus-outline"
              title="No credit cards"
              body="Add an account with type Credit card to start statement and due tracking."
              actionLabel="Add card"
              onAction={() => router.push('/account/new')}
            />
          ) : (
            cards.map((card, index) => {
              const balance = indexedAccountBalance(indexes, card);
              const txns = indexes.transactionsByAccountId.get(card.id) ?? [];
              const utilization = Math.min(
                Math.abs(balance.amountMinor) / Math.max(Math.abs(balance.amountMinor), 1),
                1,
              );
              return (
                <View key={card.id}>
                  <View style={{ gap: 8 }}>
                    <InfoRow
                      icon="credit-card-outline"
                      label={card.name}
                      value={formatMoney(balance, state.preferences.locale)}
                    />
                    <ProgressBar
                      progress={utilization}
                      color={theme.colors.secondary}
                      style={{ height: 8, borderRadius: 4 }}
                    />
                    <InlineMeta
                      items={[
                        card.currency,
                        `${txns.length} records`,
                        !card.includeInNetWorth ? 'net worth excluded' : null,
                      ]}
                    />
                    <Button
                      mode="text"
                      onPress={() =>
                        router.push({ pathname: '/account/[id]', params: { id: card.id } })
                      }
                    >
                      Open card account
                    </Button>
                  </View>
                  {index < cards.length - 1 && <Divider />}
                </View>
              );
            })
          )}
        </SectionCard>

        <SectionCard
          title="Planned card payments"
          subtitle="Forecasts from card payment plans in Planned payments > Card dues."
          actionLabel="Schedule"
          actionIcon="calendar-plus"
          onAction={() => void scheduleCardPayment()}
        >
          {plannedCardPayments.length === 0 ? (
            <EmptyState
              icon="credit-card-clock-outline"
              title="No card dues planned"
              body="Schedule a card payment reminder from your first bank account to your first card."
              actionLabel="Schedule payment"
              onAction={() => void scheduleCardPayment()}
            />
          ) : (
            plannedCardPayments.slice(0, 5).map((payment, index) => {
              const source = indexes.accountsById.get(payment.accountId);
              const card = indexes.accountsById.get(payment.counterAccountId ?? '');
              return (
                <View key={payment.externalRef}>
                  <InfoRow
                    icon="credit-card-check-outline"
                    label={card?.name ?? 'Card payment'}
                    value={formatMoney(
                      { amountMinor: payment.amountMinor, currency: payment.currency },
                      state.preferences.locale,
                    )}
                  />
                  <InlineMeta
                    items={[
                      new Date(payment.occurredAt).toLocaleDateString(),
                      source ? `from ${source.name}` : null,
                    ]}
                    style={{ paddingVertical: 4 }}
                  />
                  {index < Math.min(plannedCardPayments.length, 5) - 1 ? <Divider /> : null}
                </View>
              );
            })
          )}
        </SectionCard>

        <SectionCard
          title="Statement workflow"
          subtitle="Derived from credit card accounts and payment forecasts."
        >
          <InfoRow
            icon="calendar-range-outline"
            label="Cycle close"
            value="Use statement import or manual reminder"
            tone="warning"
          />
          <InfoRow
            icon="calendar-alert"
            label="Payment due"
            value={
              nextCardPayment
                ? new Date(nextCardPayment.occurredAt).toLocaleDateString()
                : 'No planned due'
            }
            tone={nextCardPayment ? 'warning' : 'default'}
          />
          <InfoRow
            icon="cash-check"
            label="Minimum due"
            value={
              nextCardPayment
                ? formatMoney(
                    {
                      amountMinor: nextCardPayment.amountMinor,
                      currency: nextCardPayment.currency,
                    },
                    state.preferences.locale,
                  )
                : 'Schedule a reminder'
            }
          />
          <InfoRow icon="swap-horizontal" label="Payment flow" value="Use Transfer records" />
        </SectionCard>

        <Text variant="bodySmall">
          Upcoming engine: richer statement cycles, billed/unbilled split, utilization limits, and
          automatic matching from imported card statements.
        </Text>
      </AppScreen>
      <Snackbar visible={Boolean(snackbar)} onDismiss={() => setSnackbar(null)} duration={2200}>
        {snackbar}
      </Snackbar>
    </>
  );
}

function daysFromNow(days: number, hour: number) {
  const date = new Date();
  date.setDate(date.getDate() + days);
  date.setHours(hour, 0, 0, 0);
  return date;
}

function startOfDay(date: Date): Date {
  const next = new Date(date);
  next.setHours(0, 0, 0, 0);
  return next;
}

function dateOnly(date: Date): string {
  return date.toISOString().slice(0, 10);
}
