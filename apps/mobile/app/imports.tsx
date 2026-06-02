import { useLedger } from '@1wallet/state';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useMemo } from 'react';
import { Button, Divider, Text } from 'react-native-paper';
import { AppScreen, InfoRow, QuickLink, SectionCard } from '../src/components/AppKit';

export default function Imports() {
  const { indexes, reload } = useLedger();
  const { pending, approved, rejected } = useMemo(
    () => ({
      pending: indexes.captureCandidatesByStatus.get('pending') ?? [],
      approved: indexes.captureCandidatesByStatus.get('approved') ?? [],
      rejected: indexes.captureCandidatesByStatus.get('rejected') ?? [],
    }),
    [indexes.captureCandidatesByStatus],
  );

  useFocusEffect(
    useCallback(() => {
      void reload().catch(() => undefined);
    }, [reload]),
  );
  return (
    <AppScreen
      title="Import & backup"
      back={false}
      drawer
      subtitle="Imports, capture review, and native backup tools live together here."
      actions={[{ icon: 'robot-outline', label: 'Review', onPress: () => router.push('/review') }]}
    >
      <SectionCard
        title="Queue health"
        subtitle="Everything imported or captured should pass through review first."
      >
        <InfoRow
          icon="clock-outline"
          label="Pending"
          value={String(pending.length)}
          tone={pending.length ? 'warning' : 'positive'}
        />
        <InfoRow
          icon="check-circle-outline"
          label="Approved"
          value={String(approved.length)}
          tone="positive"
        />
        <InfoRow
          icon="close-circle-outline"
          label="Rejected"
          value={String(rejected.length)}
          tone="danger"
        />
        <Button mode="contained-tonal" icon="robot-outline" onPress={() => router.push('/review')}>
          Open review queue
        </Button>
      </SectionCard>

      <SectionCard
        title="Import & backup workflows"
        subtitle="Move data in and out without bypassing Review."
      >
        <QuickLink
          icon="backup-restore"
          title="Backup & restore"
          body="Export or restore a native 1wallet archive for safe round-trip testing."
          badge="Native"
          onPress={() => router.push('/data-backup' as never)}
        />
        <Divider />
        <QuickLink
          icon="file-table-outline"
          title="Wallet CSV reset and import"
          body="Pick one Wallet export, preview summaries, reset local data if confirmed, and queue safe rows for Review."
          badge="Ready"
          onPress={() => router.push('/import-wallet-csv')}
        />
        <Divider />
        <QuickLink
          icon="bell-badge-outline"
          title="Notification capture"
          body="Per-app trust, local parsing, and candidate scoring belong here."
          badge="Android"
          onPress={() => router.push('/settings')}
        />
        <Divider />
        <QuickLink
          icon="message-text-lock-outline"
          title="Auto Capture"
          body="Read transaction-looking SMS alerts locally, auto-post safe matches, and queue uncertain ones for Review."
          badge="Android"
          onPress={() => router.push('/auto-capture' as never)}
        />
      </SectionCard>

      <Text variant="bodySmall">
        Direct bank sync is intentionally outside this MVP slice. The safe path is manual ledger
        first, imports second, notification capture third, and SMS only with explicit permission.
      </Text>
    </AppScreen>
  );
}
