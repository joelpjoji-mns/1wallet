import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { Button, ProgressBar, Snackbar, Text, useTheme } from 'react-native-paper';
import { AppScreen, InfoRow, SectionCard } from '../src/components/AppKit';
import {
  OptionListOverlay,
  OptionSelectorRow,
  type OptionListItem,
} from '../src/components/OptionListOverlay';
import { APP_ICONS } from '../src/iconSystem';
import { useAppUpdate } from '../src/updates/AppUpdateProvider';
import type { AppUpdateRelease, UpdateChannel } from '../src/updates/types';
import { formatBytes, formatEta, formatReleaseType, progressPercent } from '../src/updates/version';

const UPDATE_CHANNEL_OPTIONS: OptionListItem<UpdateChannel>[] = [
  {
    value: 'stable',
    label: 'Stable',
    description: 'Regular releases after PR merge',
    icon: 'shield-check-outline',
  },
  {
    value: 'beta',
    label: 'Beta',
    description: 'Test releases before they merge to main',
    icon: 'flask-outline',
  },
];

export default function UpdatesScreen() {
  const theme = useTheme();
  const updates = useAppUpdate();
  const { state } = updates;
  const [channelPickerVisible, setChannelPickerVisible] = useState(false);
  const release = state.release;
  const progress = state.download?.progress ?? 0;
  const hasNativeUpdate = Boolean(release);
  const isBusy =
    state.status === 'checking' || state.status === 'downloading' || state.status === 'installing';

  return (
    <>
      <AppScreen
        title="Updates"
        subtitle=""
        contentStyle={styles.content}
        actions={[
          {
            label: 'Check updates',
            icon: 'refresh',
            onPress: () => void updates.checkForUpdates(true),
          },
        ]}
      >
        <SectionCard title="Update channel" compact>
          <OptionSelectorRow
            label="Channel"
            value={channelLabel(state.channel)}
            description={channelDescription(state.channel)}
            icon={state.channel === 'beta' ? 'flask-outline' : 'shield-check-outline'}
            disabled={isBusy}
            onPress={() => setChannelPickerVisible(true)}
          />
        </SectionCard>

        <SectionCard title="Status" compact>
          <View style={styles.heroRow}>
            <View
              style={[
                styles.statusIcon,
                {
                  backgroundColor: hasNativeUpdate
                    ? theme.colors.secondaryContainer
                    : theme.colors.primaryContainer,
                },
              ]}
            >
              <MaterialCommunityIcons
                name={hasNativeUpdate ? 'download-circle-outline' : 'check-circle-outline'}
                size={24}
                color={
                  hasNativeUpdate
                    ? theme.colors.onSecondaryContainer
                    : theme.colors.onPrimaryContainer
                }
              />
            </View>
            <View style={styles.fill}>
              <Text variant="titleMedium" style={styles.strongText}>
                {statusTitle(state.status, hasNativeUpdate)}
              </Text>
              <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                {statusBody(state.status, hasNativeUpdate, state.message, state.error)}
              </Text>
            </View>
          </View>
          <InfoRow
            icon="source-branch"
            label="Checking channel"
            value={channelLabel(state.channel)}
          />
          <InfoRow icon="cellphone" label="Current version" value={state.current.versionName} />
          <InfoRow icon="counter" label="Current build" value={String(state.current.versionCode)} />
          {release ? (
            <>
              <InfoRow
                icon="tag-outline"
                label="New version"
                value={release.versionName}
                tone="positive"
              />
              <InfoRow
                icon="source-branch"
                label="Release channel"
                value={channelLabel(release.channel)}
              />
              <InfoRow icon="counter" label="New build" value={String(release.versionCode)} />
              <InfoRow
                icon={release.mandatory ? 'alert-circle-outline' : 'information-outline'}
                label="Update type"
                value={`${formatReleaseType(release.releaseType)} / ${release.mandatory ? 'Mandatory' : 'Optional'}`}
                tone={release.mandatory ? 'warning' : 'default'}
              />
              <InfoRow
                icon="database-arrow-down-outline"
                label="Download size"
                value={formatBytes(release.apk.sizeBytes)}
              />
              <InfoRow
                icon="timer-outline"
                label="Estimated time"
                value={formatEta(
                  state.download?.etaSeconds ?? release.apk.estimatedDownloadSeconds,
                )}
              />
            </>
          ) : null}
          <InfoRow
            icon="clock-outline"
            label="Last checked"
            value={dateValue(state.lastCheckedAt)}
          />
        </SectionCard>

        {state.status === 'downloading' ? (
          <SectionCard title="Download" compact>
            <View style={styles.progressHeader}>
              <Text variant="labelLarge">Downloading update...</Text>
              <Text variant="labelMedium" style={{ color: theme.colors.onSurfaceVariant }}>
                {progressPercent(progress)}
              </Text>
            </View>
            <ProgressBar progress={progress} style={styles.progress} />
            <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
              {formatBytes(state.download?.bytesWritten ?? 0)} of{' '}
              {formatBytes(state.download?.bytesExpected ?? release?.apk.sizeBytes ?? 0)} /{' '}
              {formatEta(state.download?.etaSeconds)} left
            </Text>
            <Button mode="outlined" icon="close" onPress={() => void updates.cancelDownload()}>
              Cancel
            </Button>
          </SectionCard>
        ) : null}

        {release ? <ChangelogCard release={release} /> : null}

        {state.jsUpdate.available && !release ? (
          <SectionCard title="JavaScript update" compact>
            <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
              {state.jsUpdate.downloaded
                ? 'Update downloaded successfully'
                : 'A compatible app update is available.'}
            </Text>
            <View style={styles.actionRow}>
              {state.jsUpdate.downloaded ? (
                <Button
                  mode="contained"
                  icon="restart"
                  onPress={() => void updates.applyJsUpdate()}
                >
                  Restart app
                </Button>
              ) : (
                <Button
                  mode="contained"
                  icon="download"
                  onPress={() => void updates.downloadJsUpdate()}
                >
                  Update app
                </Button>
              )}
            </View>
          </SectionCard>
        ) : null}

        <View style={styles.actionRow}>
          {release && state.status !== 'downloading' && state.status !== 'downloaded' ? (
            <Button
              mode="contained"
              icon="download"
              disabled={isBusy}
              onPress={() => void updates.downloadUpdate()}
            >
              Update app
            </Button>
          ) : null}
          {release && state.status === 'downloaded' ? (
            <Button
              mode="contained"
              icon="package-up"
              onPress={() => void updates.installDownloadedUpdate()}
            >
              Install update
            </Button>
          ) : null}
          <Button
            mode={release ? 'outlined' : 'contained-tonal'}
            icon={APP_ICONS.navigation.sync}
            disabled={isBusy}
            onPress={() => void updates.checkForUpdates(true)}
          >
            Check again
          </Button>
        </View>

        <Snackbar visible={Boolean(state.message)} onDismiss={updates.clearMessage} duration={2600}>
          {state.message}
        </Snackbar>
      </AppScreen>

      <OptionListOverlay
        visible={channelPickerVisible}
        title="Update channel"
        options={UPDATE_CHANNEL_OPTIONS}
        selectedValue={state.channel}
        searchable={false}
        onDismiss={() => setChannelPickerVisible(false)}
        onSelect={(option) => {
          setChannelPickerVisible(false);
          void updates.setUpdateChannel(option.value);
        }}
      />
    </>
  );
}

function ChangelogCard({ release }: { release: AppUpdateRelease }) {
  return (
    <SectionCard title="Changelog" compact>
      <ChangelogGroup title="New features" items={release.changelog.newFeatures} />
      <ChangelogGroup title="Bug fixes" items={release.changelog.bugFixes} />
      <ChangelogGroup title="Notes" items={release.changelog.notes} />
    </SectionCard>
  );
}

function ChangelogGroup({ title, items }: { title: string; items: string[] }) {
  const theme = useTheme();
  if (items.length === 0) return null;
  return (
    <View style={styles.changelogGroup}>
      <Text variant="labelLarge" style={styles.strongText}>
        {title}
      </Text>
      {items.map((item) => (
        <View key={item} style={styles.changelogItem}>
          <MaterialCommunityIcons name="circle-small" size={18} color={theme.colors.primary} />
          <Text variant="bodyMedium" style={styles.fill}>
            {item}
          </Text>
        </View>
      ))}
    </View>
  );
}

function statusTitle(status: string, hasUpdate: boolean): string {
  if (status === 'checking') return 'Checking for updates';
  if (status === 'downloading') return 'Downloading update...';
  if (status === 'downloaded') return 'Update downloaded successfully';
  if (status === 'installing') return 'Installing update...';
  if (status === 'cancelled') return 'Update cancelled';
  if (status === 'error') return 'Update needs attention';
  if (hasUpdate) return 'Update available';
  return 'Your app is up to date';
}

function statusBody(status: string, hasUpdate: boolean, message?: string, error?: string): string {
  if (error) return error;
  if (message) return message;
  if (status === 'checking') return 'Checking the latest published release.';
  if (status === 'downloading') return 'Downloading update...';
  if (status === 'downloaded') return 'Install the downloaded update when ready.';
  if (status === 'installing') return 'Android will ask you to confirm the installation.';
  if (status === 'cancelled') return 'Update cancelled';
  if (hasUpdate) return 'A newer 1wallet release is ready for this device.';
  return 'Your app is up to date';
}

function dateValue(value?: string): string {
  if (!value) return 'Never';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
}

function channelLabel(channel: UpdateChannel): string {
  return UPDATE_CHANNEL_OPTIONS.find((option) => option.value === channel)?.label ?? channel;
}

function channelDescription(channel: UpdateChannel): string {
  return (
    UPDATE_CHANNEL_OPTIONS.find((option) => option.value === channel)?.description ??
    'Choose which update channel this device checks'
  );
}

const styles = StyleSheet.create({
  content: { gap: 10, paddingHorizontal: 14, paddingTop: 6, paddingBottom: 88 },
  fill: { flex: 1, minWidth: 0 },
  heroRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  statusIcon: {
    width: 46,
    height: 46,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  strongText: { fontWeight: '800' },
  progressHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  progress: { height: 8, borderRadius: 999 },
  actionRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 10, alignItems: 'center' },
  changelogGroup: { gap: 6 },
  changelogItem: { flexDirection: 'row', alignItems: 'flex-start', gap: 2 },
});
