import { router } from 'expo-router';

export type AddRecordEntryOrigin = 'center' | 'fab' | 'top';

type OpenAddRecordOptions = {
  accountId?: string;
  entryOrigin?: AddRecordEntryOrigin;
};

export function openAddRecord(options: OpenAddRecordOptions = {}) {
  const params: Record<string, string> = {
    entryOrigin: options.entryOrigin ?? 'center',
  };
  if (options.accountId) params.accountId = options.accountId;

  router.push({ pathname: '/add', params });
}

export function isAddRecordEntryOrigin(value: string | undefined): value is AddRecordEntryOrigin {
  return value === 'center' || value === 'fab' || value === 'top';
}
