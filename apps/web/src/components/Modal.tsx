'use client';

import { tokens } from '@1wallet/ui';
import type { ReactElement, ReactNode } from 'react';
import { useEffect, useRef } from 'react';
import { Button } from './Button';

interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  actions?: ReactNode;
}

export function Modal({ isOpen, onClose, title, children, actions }: ModalProps): ReactElement | null {
  const dialogRef = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;

    if (isOpen && !dialog.open) {
      dialog.showModal();
    } else if (!isOpen && dialog.open) {
      dialog.close();
    }
  }, [isOpen]);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    
    // Close on backdrop click
    const handleLightDismiss = (e: MouseEvent) => {
      if (e.target === dialog) {
        onClose();
      }
    };
    
    dialog.addEventListener('click', handleLightDismiss);
    return () => dialog.removeEventListener('click', handleLightDismiss);
  }, [onClose]);

  if (!isOpen) return null;

  return (
    <dialog
      ref={dialogRef}
      style={{
        padding: 0,
        border: 'none',
        borderRadius: tokens.radius.xl,
        backgroundColor: 'transparent',
        maxWidth: 500,
        width: '100%',
      }}
      className="animate-fade-in"
      onClose={onClose}
    >
      <div
        className="glass"
        style={{
          display: 'flex',
          flexDirection: 'column',
          backgroundColor: 'var(--color-surface)', // override glass if needed, but glass is nice
        }}
      >
        <div 
          style={{ 
            padding: `${tokens.space.lg}px ${tokens.space.xl}px`,
            borderBottom: '1px solid var(--color-outline-variant)',
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
          }}
        >
          <h2 style={{ margin: 0, fontSize: 20, color: 'var(--color-on-surface)' }}>{title}</h2>
          <button
            onClick={onClose}
            style={{
              background: 'transparent',
              border: 'none',
              fontSize: 24,
              color: 'var(--color-on-surface)',
              cursor: 'pointer',
              lineHeight: 1,
            }}
          >
            &times;
          </button>
        </div>
        
        <div style={{ padding: tokens.space.xl }}>
          {children}
        </div>

        {actions && (
          <div 
            style={{ 
              padding: `${tokens.space.md}px ${tokens.space.xl}px`,
              borderTop: '1px solid var(--color-outline-variant)',
              display: 'flex',
              justifyContent: 'flex-end',
              gap: tokens.space.sm,
              backgroundColor: 'var(--color-surface-low)',
            }}
          >
            {actions}
          </div>
        )}
      </div>
    </dialog>
  );
}
