'use client';

import { tokens } from '@1wallet/ui';
import type { ReactElement, ReactNode, CSSProperties, ButtonHTMLAttributes } from 'react';

type ButtonVariant = 'primary' | 'secondary' | 'danger' | 'ghost';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  children: ReactNode;
}

export function Button({ variant = 'primary', children, style, ...props }: ButtonProps): ReactElement {
  const getVariantStyles = (): CSSProperties => {
    switch (variant) {
      case 'primary':
        return {
          backgroundColor: 'var(--color-primary)',
          color: 'var(--color-on-primary)',
          border: '1px solid transparent',
          boxShadow: '0 4px 12px rgba(0, 0, 0, 0.15)',
        };
      case 'secondary':
        return {
          backgroundColor: 'var(--color-surface-high)',
          color: 'var(--color-on-surface)',
          border: '1px solid var(--color-outline-variant)',
        };
      case 'danger':
        return {
          backgroundColor: 'var(--color-error)',
          color: 'var(--color-on-error)',
          border: '1px solid transparent',
        };
      case 'ghost':
        return {
          backgroundColor: 'transparent',
          color: 'var(--color-primary)',
          border: '1px solid transparent',
        };
    }
  };

  return (
    <button
      style={{
        padding: `${tokens.space.md}px ${tokens.space.xl}px`,
        borderRadius: tokens.radius.pill,
        fontWeight: tokens.font.weight.bold,
        cursor: 'pointer',
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: tokens.space.sm,
        ...getVariantStyles(),
        ...style,
      }}
      {...props}
    >
      {children}
    </button>
  );
}
