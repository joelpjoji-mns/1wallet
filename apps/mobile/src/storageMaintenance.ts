import { compactCloudSyncStorage } from './cloudSync/storage';
import { compactLedgerStorage } from './storage';
import { clearUpdateDownloadCache } from './updates/downloadManager';

export type MobileStorageMaintenanceSummary = {
  cloudRemovedBytes: number;
  cloudRemovedFiles: number;
  ledgerActiveBytes: number;
  ledgerActiveFiles: number;
  ledgerRemovedBytes: number;
  ledgerRemovedFiles: number;
  ledgerTotalBytesBefore: number;
  ledgerTotalFilesBefore: number;
};

export async function runMobileStorageMaintenance(): Promise<MobileStorageMaintenanceSummary> {
  await clearUpdateDownloadCache();
  const ledger = await compactLedgerStorage();
  const cloud = await compactCloudSyncStorage();
  return {
    cloudRemovedBytes: cloud.removedBytes,
    cloudRemovedFiles: cloud.removedFiles,
    ledgerActiveBytes: ledger.activeBytes,
    ledgerActiveFiles: ledger.activeFiles,
    ledgerRemovedBytes: ledger.removedBytes,
    ledgerRemovedFiles: ledger.removedFiles,
    ledgerTotalBytesBefore: ledger.totalBytesBefore,
    ledgerTotalFilesBefore: ledger.totalFilesBefore,
  };
}
