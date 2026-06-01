'use client';

import { tokens } from '@1wallet/ui';
import type { ReactElement } from 'react';

const scheme = tokens.color.md3.light;

export function Bar({ share, over }: { share: number; over?: boolean }): ReactElement {
  return (
    <div
      style={{
        height: 8,
        background: scheme.surfaceContainerHigh,
        borderRadius: tokens.radius.pill,
        marginTop: tokens.space.xs,
        overflow: 'hidden',
      }}
    >
      <div
        style={{
          height: '100%',
          width: `${Math.min(100, Math.max(0, share * 100))}%`,
          background: over ? scheme.error : scheme.primary,
        }}
      />
    </div>
  );
}
