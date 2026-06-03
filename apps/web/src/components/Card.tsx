'use client';

import { tokens } from '@1wallet/ui';
import type { ReactElement, ReactNode, CSSProperties } from 'react';

export function Card({
  title,
  children,
  style,
}: {
  title?: ReactNode;
  children: ReactNode;
  style?: CSSProperties;
}): ReactElement {
  return (
    <section
      className="glass"
      style={{
        borderRadius: tokens.radius.xl,
        padding: tokens.space.xl,
        display: 'flex',
        flexDirection: 'column',
        gap: tokens.space.md,
        transition: 'var(--transition-normal)',
        ...style,
      }}
    >
      {title && (
        <h3
          style={{
            margin: 0,
            fontSize: tokens.font.size.lg,
            color: 'var(--color-on-surface)',
            fontWeight: tokens.font.weight.bold,
          }}
        >
          {title}
        </h3>
      )}
      {children}
    </section>
  );
}
