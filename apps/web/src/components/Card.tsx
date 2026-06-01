'use client';

import { tokens } from '@1wallet/ui';
import type { ReactElement, ReactNode } from 'react';

const scheme = tokens.color.md3.light;

export function Card({ title, children }: { title: string; children: ReactNode }): ReactElement {
  return (
    <section
      style={{
        background: scheme.surfaceContainerLowest,
        border: `1px solid ${scheme.outlineVariant}`,
        borderRadius: tokens.radius.md,
        padding: tokens.space.lg,
        boxShadow: '0 1px 2px rgba(0,0,0,0.08)',
      }}
    >
      <h3
        style={{
          margin: 0,
          marginBottom: tokens.space.sm,
          fontSize: tokens.font.size.md,
          color: scheme.onSurfaceVariant,
          fontWeight: tokens.font.weight.semibold,
        }}
      >
        {title}
      </h3>
      {children}
    </section>
  );
}
