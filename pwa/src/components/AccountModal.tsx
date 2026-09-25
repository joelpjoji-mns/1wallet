import { X } from 'lucide-react';
import { useState } from 'react';
import type { Account } from '../lib/ledgerTypes';

export interface AccountFormValue {
  id?: string;
  name: string;
  type: string;
  currency: string;
  openingBalanceMajor: string;
  institution: string;
  groupName: string;
  includeInTotals: boolean;
  includeInReports: boolean;
  includeInNetWorth: boolean;
  showOnHome: boolean;
}

export function accountToFormValue(a?: Account): AccountFormValue {
  if (!a) {
    return {
      name: '',
      type: 'bank',
      currency: 'USD',
      openingBalanceMajor: '0',
      institution: '',
      groupName: '',
      includeInTotals: true,
      includeInReports: true,
      includeInNetWorth: true,
      showOnHome: true,
    };
  }
  return {
    id: a.id,
    name: a.name,
    type: a.type,
    currency: a.currency,
    openingBalanceMajor: (a.openingBalance.amountMinor / 100).toString(),
    institution: a.institution ?? '',
    groupName: a.groupName ?? '',
    includeInTotals: a.includeInTotals,
    includeInReports: a.includeInReports,
    includeInNetWorth: a.includeInNetWorth,
    showOnHome: a.showOnHome,
  };
}

const ACCOUNT_TYPES = ['bank', 'cash', 'card', 'wallet', 'investment', 'loan', 'other'];

interface Props {
  initial: AccountFormValue;
  isEditing: boolean;
  hasEncryptedDetails: boolean;
  onCancel: () => void;
  onSubmit: (value: AccountFormValue) => void;
  onArchiveToggle?: () => void;
  isArchived?: boolean;
  onDelete?: () => void;
}

export function AccountModal({
  initial,
  isEditing,
  hasEncryptedDetails,
  onCancel,
  onSubmit,
  onArchiveToggle,
  isArchived,
  onDelete,
}: Props) {
  const [value, setValue] = useState<AccountFormValue>(initial);
  const set = <K extends keyof AccountFormValue>(key: K, v: AccountFormValue[K]) =>
    setValue((prev) => ({ ...prev, [key]: v }));

  return (
    <div className="modal-backdrop" role="dialog" aria-modal="true">
      <form
        className="glass-card modal-card"
        onSubmit={(e) => {
          e.preventDefault();
          onSubmit(value);
        }}
      >
        <div className="modal-header">
          <h2>{isEditing ? 'Edit account' : 'Add account'}</h2>
          <button type="button" className="icon-btn" onClick={onCancel} aria-label="Close">
            <X size={18} />
          </button>
        </div>

        {hasEncryptedDetails && (
          <p className="hint-banner">
            🔒 This account has device-encrypted details (e.g. card number) that were added on a
            phone. They can't be read or edited from the web for security reasons, and are kept
            unchanged when you save.
          </p>
        )}

        <label className="field">
          <span>Name</span>
          <input required type="text" value={value.name} onChange={(e) => set('name', e.target.value)} />
        </label>

        <label className="field">
          <span>Type</span>
          <select value={value.type} onChange={(e) => set('type', e.target.value)}>
            {ACCOUNT_TYPES.map((t) => (
              <option key={t} value={t}>
                {t[0]!.toUpperCase() + t.slice(1)}
              </option>
            ))}
          </select>
        </label>

        <label className="field">
          <span>Currency</span>
          <input
            required
            type="text"
            maxLength={3}
            style={{ textTransform: 'uppercase' }}
            value={value.currency}
            onChange={(e) => set('currency', e.target.value.toUpperCase())}
          />
        </label>

        <label className="field">
          <span>Opening balance</span>
          <input
            required
            type="number"
            step="0.01"
            value={value.openingBalanceMajor}
            onChange={(e) => set('openingBalanceMajor', e.target.value)}
          />
        </label>

        <label className="field">
          <span>Institution</span>
          <input type="text" value={value.institution} onChange={(e) => set('institution', e.target.value)} />
        </label>

        <label className="field">
          <span>Group</span>
          <input type="text" value={value.groupName} onChange={(e) => set('groupName', e.target.value)} />
        </label>

        <div className="checkbox-grid">
          <label className="checkbox-field">
            <input
              type="checkbox"
              checked={value.includeInTotals}
              onChange={(e) => set('includeInTotals', e.target.checked)}
            />
            Include in totals
          </label>
          <label className="checkbox-field">
            <input
              type="checkbox"
              checked={value.includeInNetWorth}
              onChange={(e) => set('includeInNetWorth', e.target.checked)}
            />
            Include in net worth
          </label>
          <label className="checkbox-field">
            <input
              type="checkbox"
              checked={value.includeInReports}
              onChange={(e) => set('includeInReports', e.target.checked)}
            />
            Include in reports
          </label>
          <label className="checkbox-field">
            <input
              type="checkbox"
              checked={value.showOnHome}
              onChange={(e) => set('showOnHome', e.target.checked)}
            />
            Show on home
          </label>
        </div>

        <div className="modal-actions">
          {isEditing && onDelete && (
            <button type="button" className="btn-danger" onClick={onDelete}>
              Delete
            </button>
          )}
          {isEditing && onArchiveToggle && (
            <button type="button" className="btn-secondary" onClick={onArchiveToggle}>
              {isArchived ? 'Unarchive' : 'Archive'}
            </button>
          )}
          <div style={{ flex: 1 }} />
          <button type="button" className="btn-secondary" onClick={onCancel}>
            Cancel
          </button>
          <button type="submit" className="btn-primary">
            Save
          </button>
        </div>
      </form>
    </div>
  );
}
