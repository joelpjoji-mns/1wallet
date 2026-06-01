import {
    exportOneWalletArchive,
    ledgerStateFromOneWalletArchive,
    parseOneWalletArchive,
    summarizeLedgerState,
    validateOneWalletArchive,
    type OneWalletArchiveV1,
    type OneWalletArchiveValidation,
} from '@1wallet/ledger';
import { useLedger } from '@1wallet/state';
import * as DocumentPicker from 'expo-document-picker';
import * as FileSystem from 'expo-file-system/legacy';
import * as Sharing from 'expo-sharing';
import { useMemo, useState } from 'react';
import { Share, StyleSheet, View } from 'react-native';
import { Button, Dialog, Portal, Snackbar, Text, useTheme } from 'react-native-paper';
import { useAuth } from '../src/auth';
import { AppScreen, EmptyState, InfoRow, InlineMeta, SectionCard } from '../src/components/AppKit';

type ArchivePreview = {
  fileName: string;
  archive: OneWalletArchiveV1;
  validation: OneWalletArchiveValidation;
};

export default function DataBackup() {
  const theme = useTheme();
  const { user } = useAuth();
  const { state, flushSaves, replaceLedgerState } = useLedger();
  const currentSummary = useMemo(() => summarizeLedgerState(state), [state]);
  const [exportBusy, setExportBusy] = useState(false);
  const [importBusy, setImportBusy] = useState(false);
  const [restoreBusy, setRestoreBusy] = useState(false);
  const [preview, setPreview] = useState<ArchivePreview | null>(null);
  const [restoreVisible, setRestoreVisible] = useState(false);
  const [importError, setImportError] = useState<string | null>(null);
  const [snackbar, setSnackbar] = useState<string | null>(null);

  const exportArchive = async () => {
    if (exportBusy) return;
    setExportBusy(true);
    setImportError(null);
    try {
      await flushSaves();
      const archive = exportOneWalletArchive(state, { source: 'mobile' });
      const fileName = `1wallet-backup-${safeDateStamp(archive.exportedAt)}.onewallet.json`;
      const directory = FileSystem.cacheDirectory ?? FileSystem.documentDirectory;
      if (!directory) throw new Error('No writable export folder is available on this device.');
      const uri = `${directory}${fileName}`;
      await FileSystem.writeAsStringAsync(uri, JSON.stringify(archive, null, 2));
      if (await Sharing.isAvailableAsync()) {
        await Sharing.shareAsync(uri, {
          dialogTitle: fileName,
          mimeType: 'application/json',
          UTI: 'public.json',
        });
      } else {
        await Share.share({ title: fileName, message: `1wallet backup saved at ${uri}` });
      }
      setSnackbar('Backup archive ready to share');
    } catch (error) {
      setSnackbar(`Export failed: ${(error as Error).message}`);
    } finally {
      setExportBusy(false);
    }
  };

  const pickArchive = async () => {
    if (importBusy) return;
    setImportBusy(true);
    setImportError(null);
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: '*/*',
        multiple: false,
        copyToCacheDirectory: true,
      });
      if (result.canceled) {
        setSnackbar('Backup selection cancelled');
        return;
      }
      const asset = result.assets[0];
      if (!asset) throw new Error('The file picker did not return a backup file.');
      const content = await FileSystem.readAsStringAsync(asset.uri);
      const archive = parseOneWalletArchive(content);
      const validation = validateOneWalletArchive(archive);
      setPreview({ fileName: asset.name || '1wallet backup', archive, validation });
      setSnackbar(validation.ok ? 'Backup preview ready' : 'Backup needs attention');
    } catch (error) {
      setPreview(null);
      setImportError((error as Error).message);
      setSnackbar(`Could not read backup: ${(error as Error).message}`);
    } finally {
      setImportBusy(false);
    }
  };

  const restoreArchive = async () => {
    if (!preview || restoreBusy) return;
    setRestoreBusy(true);
    try {
      const restoredState = ledgerStateFromOneWalletArchive(preview.archive, {
        userId: user?.id,
      });
      await replaceLedgerState(restoredState);
      setRestoreVisible(false);
      setPreview(null);
      setSnackbar('Backup restored');
    } catch (error) {
      setSnackbar(`Restore failed: ${(error as Error).message}`);
    } finally {
      setRestoreBusy(false);
    }
  };

  return (
    <>
      <AppScreen
        title="Backup & restore"
        subtitle="Export and restore a native 1wallet archive for safe testing."
      >
        <SectionCard title="Current wallet" subtitle="This is what your next archive will contain.">
          <SummaryRows summary={currentSummary} />
        </SectionCard>

        <SectionCard
          title="Export"
          subtitle="Creates a native backup that can be imported back into 1wallet exactly."
        >
          <Button
            mode="contained"
            icon="database-export-outline"
            loading={exportBusy}
            disabled={exportBusy}
            onPress={() => void exportArchive()}
          >
            Export 1wallet archive
          </Button>
        </SectionCard>

        <SectionCard
          title="Restore"
          subtitle="Pick a 1wallet backup, preview it, then replace this local ledger."
        >
          <Button
            mode="contained-tonal"
            icon="file-search-outline"
            loading={importBusy}
            disabled={importBusy || restoreBusy}
            onPress={() => void pickArchive()}
          >
            Pick backup file
          </Button>
          {importError ? (
            <Text variant="bodySmall" style={{ color: theme.colors.error }}>
              {importError}
            </Text>
          ) : null}
          {preview ? <ArchivePreviewCard preview={preview} /> : null}
          {preview?.validation.ok ? (
            <Button
              mode="contained"
              icon="backup-restore"
              loading={restoreBusy}
              disabled={restoreBusy}
              onPress={() => setRestoreVisible(true)}
            >
              Restore this backup
            </Button>
          ) : preview ? null : (
            <EmptyState
              icon="database-search-outline"
              title="No backup selected"
              body="Choose a .onewallet.json file to preview before restoring."
            />
          )}
        </SectionCard>
      </AppScreen>

      <Portal>
        <Dialog visible={restoreVisible} onDismiss={() => setRestoreVisible(false)}>
          <Dialog.Title>Restore this 1wallet backup?</Dialog.Title>
          <Dialog.Content>
            <Text variant="bodyMedium">
              This replaces the local ledger on this device with the selected backup. Auth and
              device permissions are not part of the backup.
            </Text>
            {preview ? (
              <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                {preview.validation.summary.accounts} accounts,{' '}
                {preview.validation.summary.transactions} records, and{' '}
                {preview.validation.summary.plannedPayments} planned payments will be restored.
              </Text>
            ) : null}
          </Dialog.Content>
          <Dialog.Actions>
            <Button onPress={() => setRestoreVisible(false)}>Cancel</Button>
            <Button
              loading={restoreBusy}
              disabled={restoreBusy}
              textColor={theme.colors.error}
              onPress={() => void restoreArchive()}
            >
              Restore
            </Button>
          </Dialog.Actions>
        </Dialog>
      </Portal>
      <Snackbar visible={Boolean(snackbar)} onDismiss={() => setSnackbar(null)} duration={2600}>
        {snackbar}
      </Snackbar>
    </>
  );
}

function ArchivePreviewCard({ preview }: { preview: ArchivePreview }) {
  const theme = useTheme();
  const { validation } = preview;
  return (
    <View style={styles.previewCard}>
      <InfoRow
        icon={validation.ok ? 'file-check-outline' : 'file-alert-outline'}
        label="Backup"
        value={preview.fileName}
        tone={validation.ok ? 'positive' : 'danger'}
      />
      <InfoRow
        icon="calendar-clock-outline"
        label="Exported"
        value={formatDateTime(preview.archive.exportedAt)}
      />
      <SummaryRows summary={validation.summary} compact />
      {validation.errors.length > 0 ? (
        <View style={styles.messageList}>
          {validation.errors.map((error) => (
            <Text key={error} variant="bodySmall" style={{ color: theme.colors.error }}>
              {error}
            </Text>
          ))}
        </View>
      ) : null}
      {validation.warnings.length > 0 ? (
        <View style={styles.messageList}>
          {validation.warnings.slice(0, 4).map((warning) => (
            <Text
              key={warning}
              variant="bodySmall"
              style={{ color: theme.colors.onSurfaceVariant }}
            >
              {warning}
            </Text>
          ))}
        </View>
      ) : null}
    </View>
  );
}

function SummaryRows({
  summary,
  compact = false,
}: {
  summary: ReturnType<typeof summarizeLedgerState>;
  compact?: boolean;
}) {
  return (
    <View style={styles.summaryRows}>
      <InfoRow icon="wallet-outline" label="Accounts" value={String(summary.accounts)} />
      <InfoRow icon="format-list-bulleted" label="Records" value={String(summary.transactions)} />
      <InfoRow
        icon="calendar-sync-outline"
        label="Planned payments"
        value={String(summary.plannedPayments)}
      />
      <InfoRow icon="bank-outline" label="Loan accounts" value={String(summary.loanAccounts)} />
      {!compact ? (
        <InfoRow
          icon="calendar-range"
          label="Date range"
          value={formatDateRange(summary.dateRange)}
        />
      ) : null}
      <InlineMeta
        numberOfLines={2}
        items={[
          ...summary.currencies.slice(0, 8),
          summary.currencies.length > 8 ? `+${summary.currencies.length - 8}` : null,
        ]}
      />
    </View>
  );
}

function safeDateStamp(value: string): string {
  return value
    .replace(/[-:]/g, '')
    .replace(/\.\d{3}Z$/, 'Z')
    .replace(/[TZ]/g, '-')
    .replace(/-$/, '');
}

function formatDateTime(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString();
}

function formatDateRange(range: ReturnType<typeof summarizeLedgerState>['dateRange']): string {
  if (!range) return 'No records yet';
  return range.start === range.end ? range.start : `${range.start} - ${range.end}`;
}

const styles = StyleSheet.create({
  summaryRows: {
    gap: 2,
  },
  previewCard: {
    gap: 4,
  },
  messageList: {
    gap: 4,
    paddingTop: 6,
  },
});
