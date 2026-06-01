import { MaterialCommunityIcons } from '@expo/vector-icons';
import { StyleSheet, View } from 'react-native';
import { Text, useTheme } from 'react-native-paper';
import { useCloudSync } from '../src/cloudSync/LedgerCloudSyncProvider';
import { AppScreen, InfoRow, SectionCard } from '../src/components/AppKit';

export default function SyncScreen() {
  const theme = useTheme();
  const sync = useCloudSync();

  return (
    <AppScreen
      title="Sync"
      subtitle="Google sign-in, cloud restore, and automatic wallet upload."
      contentStyle={styles.content}
    >
      <SectionCard title="Status" compact>
        <View style={styles.headerRow}>
          <View
            style={[
              styles.statusIcon,
              {
                backgroundColor: sync.enabled
                  ? theme.colors.primaryContainer
                  : theme.colors.surfaceVariant,
              },
            ]}
          >
            <MaterialCommunityIcons
              name={sync.enabled ? 'cloud-check-outline' : 'cloud-off-outline'}
              size={22}
              color={sync.enabled ? theme.colors.onPrimaryContainer : theme.colors.onSurfaceVariant}
            />
          </View>
          <View style={styles.headerCopy}>
            <Text variant="titleMedium" style={styles.strongText}>
              {sync.enabled ? phaseLabel(sync.phase) : 'Not syncing'}
            </Text>
            <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
              {sync.enabled
                ? 'Cloud sync is connected for this Google account.'
                : sync.disabledReason}
            </Text>
          </View>
        </View>
        <InfoRow icon="cloud-outline" label="Mode" value={sync.enabled ? 'Cloud' : 'Local'} />
        <InfoRow
          icon="clock-outline"
          label="Last upload"
          value={dateValue(sync.metadata?.lastPushedAt)}
        />
        <InfoRow
          icon="cloud-download-outline"
          label="Last restore"
          value={dateValue(sync.metadata?.lastPulledAt)}
        />
        <InfoRow
          icon="source-branch"
          label="Cloud revision"
          value={
            sync.metadata?.lastCloudRevision ? String(sync.metadata.lastCloudRevision) : 'None'
          }
        />
        <InfoRow
          icon="timer-sand"
          label="Pending upload"
          value={sync.pendingUpload ? 'Yes' : 'No'}
          tone={sync.pendingUpload ? 'warning' : 'positive'}
        />
        {sync.error ? (
          <InfoRow
            icon="alert-circle-outline"
            label="Sync error"
            value={sync.error}
            tone="warning"
          />
        ) : null}
        {sync.metadata?.lastRestoreBackupUri ? (
          <InfoRow
            icon="archive-outline"
            label="Local pre-restore backup"
            value="Saved on this device"
            tone="positive"
          />
        ) : null}
      </SectionCard>
    </AppScreen>
  );
}

function phaseLabel(phase: string): string {
  switch (phase) {
    case 'checking':
      return 'Checking cloud wallet';
    case 'restoring':
      return 'Restoring from cloud';
    case 'uploading':
      return 'Uploading to cloud';
    case 'error':
      return 'Needs attention';
    default:
      return 'Synced locally';
  }
}

function dateValue(value?: string): string {
  if (!value) return 'Never';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
}

const styles = StyleSheet.create({
  content: { gap: 10, paddingHorizontal: 14, paddingTop: 6, paddingBottom: 88 },
  headerRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  statusIcon: {
    width: 44,
    height: 44,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  headerCopy: { flex: 1, minWidth: 0, gap: 2 },
  strongText: { fontWeight: '800' },
});
