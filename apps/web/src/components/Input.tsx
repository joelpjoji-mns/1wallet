'use client';

import { tokens } from '@1wallet/ui';
import type { InputHTMLAttributes, ReactElement } from 'react';
import { useState } from 'react';

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
}

export function Input({ label, error, style, ...props }: InputProps): ReactElement {
  const [focused, setFocused] = useState(false);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.xs, flex: 1, ...style }}>
      {label && (
        <label 
          style={{ 
            fontSize: tokens.font.size.sm, 
            fontWeight: tokens.font.weight.semibold,
            color: focused ? 'var(--color-primary)' : 'var(--color-on-surface)',
            transition: 'var(--transition-fast)'
          }}
        >
          {label}
        </label>
      )}
      <input
        onFocus={(e) => { setFocused(true); props.onFocus?.(e); }}
        onBlur={(e) => { setFocused(false); props.onBlur?.(e); }}
        style={{
          padding: `${tokens.space.md}px ${tokens.space.lg}px`,
          fontSize: tokens.font.size.md,
          borderRadius: tokens.radius.lg,
          border: `2px solid ${error ? 'var(--color-error)' : focused ? 'var(--color-primary)' : 'var(--color-outline-variant)'}`,
          backgroundColor: 'var(--color-surface)',
          color: 'var(--color-on-surface)',
          outline: 'none',
          boxShadow: focused ? `0 0 0 4px ${error ? 'var(--color-error)' : 'var(--color-primary)'}20` : 'none',
        }}
        {...props}
      />
      {error && <span style={{ color: 'var(--color-error)', fontSize: tokens.font.size.sm }}>{error}</span>}
    </div>
  );
}

interface SelectProps extends InputHTMLAttributes<HTMLSelectElement> {
  label?: string;
  error?: string;
  children: React.ReactNode;
}

export function Select({ label, error, style, children, ...props }: SelectProps): ReactElement {
  const [focused, setFocused] = useState(false);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.xs, flex: 1, ...style }}>
      {label && (
        <label 
          style={{ 
            fontSize: tokens.font.size.sm, 
            fontWeight: tokens.font.weight.semibold,
            color: focused ? 'var(--color-primary)' : 'var(--color-on-surface)',
            transition: 'var(--transition-fast)'
          }}
        >
          {label}
        </label>
      )}
      <select
        onFocus={(e) => { setFocused(true); props.onFocus?.(e); }}
        onBlur={(e) => { setFocused(false); props.onBlur?.(e); }}
        style={{
          padding: `${tokens.space.md}px ${tokens.space.lg}px`,
          fontSize: tokens.font.size.md,
          borderRadius: tokens.radius.lg,
          border: `2px solid ${error ? 'var(--color-error)' : focused ? 'var(--color-primary)' : 'var(--color-outline-variant)'}`,
          backgroundColor: 'var(--color-surface)',
          color: 'var(--color-on-surface)',
          outline: 'none',
          appearance: 'none', // typically we'd add a custom chevron SVG background
          boxShadow: focused ? `0 0 0 4px ${error ? 'var(--color-error)' : 'var(--color-primary)'}20` : 'none',
          cursor: 'pointer',
        }}
        {...props}
      >
        {children}
      </select>
      {error && <span style={{ color: 'var(--color-error)', fontSize: tokens.font.size.sm }}>{error}</span>}
    </div>
  );
}
