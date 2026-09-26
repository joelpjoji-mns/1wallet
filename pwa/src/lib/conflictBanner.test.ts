// Focused accessibility + destructive-confirmation regression coverage for
// `Workspace.tsx`'s `ConflictBanner` — the explicit escape hatch from the
// `conflict` phase's dead end (see `pendingSaveRaceGuard.test.ts`'s
// `discardConflictAndReload` tests for the pure data-layer half of this).
//
// `ConflictBanner` can't be imported directly outside Vite (it transitively
// pulls in `WalletDataContext.tsx` -> `../lib/firestore`, which reads
// `import.meta.env.VITE_FIREBASE_*` — a Vite-only feature that throws under
// plain `node --test`). Following the same pattern as
// `uidSwitchRender.test.ts`, this file exercises a minimal reproduction of
// the exact same shape (props-driven `phase`/`error`/`onDiscardConfirmed`,
// a native `window.confirm()` gate before invoking it), and separately
// asserts the real `Workspace.tsx` source still contains the specific
// accessibility attributes, the confirmation gate, and the tab-scoped
// (not "kept locally"/durable-sounding) copy, so any of those being
// silently removed or regressed also fails this test.
//
// Run with: node --test src/lib/conflictBanner.test.ts

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { JSDOM } from 'jsdom';

const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', {
  url: 'http://localhost/',
});

function setGlobal(name: string, value: unknown) {
  Object.defineProperty(globalThis, name, {
    value,
    configurable: true,
    writable: true,
  });
}

setGlobal('window', dom.window);
setGlobal('document', dom.window.document);
setGlobal('navigator', dom.window.navigator);
setGlobal('HTMLElement', dom.window.HTMLElement);
setGlobal('IS_REACT_ACT_ENVIRONMENT', true);

const React = await import('react');
const { createRoot } = await import('react-dom/client');

const h = React.createElement;

const DEFAULT_MESSAGE =
  'Your wallet changed on another device or tab. Your edit was not saved — it remains visible only in this browser tab and will be lost if you reload or close it before resolving.';

/**
 * Minimal reproduction of `Workspace.tsx`'s `ConflictBanner`: same
 * `role`/`aria-live` attributes, same message copy, same
 * confirm-then-call-the-discard-callback button behavior. `onDiscardConfirmed`
 * stands in for `discardConflictAndReload()`.
 */
function ConflictBanner(props: {
  phase: 'idle' | 'loading' | 'saving' | 'error' | 'conflict';
  error: string | null;
  onDiscardConfirmed: () => void;
}): React.ReactElement | null {
  if (props.phase !== 'conflict') return null;

  const handleDiscardClick = () => {
    const confirmed = window.confirm(
      'Discard your unsaved edit and load the latest cloud data instead? This cannot be undone — the edit only exists in this tab and will be gone for good.',
    );
    if (!confirmed) return;
    props.onDiscardConfirmed();
  };

  return h(
    'div',
    { className: 'conflict-banner', role: 'alert', 'aria-live': 'assertive' },
    h('p', { className: 'conflict-banner__message' }, props.error ?? DEFAULT_MESSAGE),
    h(
      'button',
      { type: 'button', className: 'btn-danger', onClick: handleDiscardClick },
      'Discard unsaved edit and load cloud',
    ),
  );
}

function render(container: HTMLElement, element: React.ReactElement) {
  const root = createRoot(container);
  root.render(element);
  return root;
}

test('ConflictBanner: renders nothing outside the conflict phase', async () => {
  const container = dom.window.document.createElement('div');
  let discardCalls = 0;
  let root!: ReturnType<typeof createRoot>;
  await React.act(async () => {
    root = render(
      container,
      h(ConflictBanner, { phase: 'idle', error: null, onDiscardConfirmed: () => discardCalls++ }),
    );
  });
  assert.equal(container.textContent, '');
  assert.equal(container.querySelector('[role="alert"]'), null);
  await React.act(async () => { root.unmount(); });
});

test('ConflictBanner: renders an accessible alert with the tab-scoped (not durable-sounding) message', async () => {
  const container = dom.window.document.createElement('div');
  let root!: ReturnType<typeof createRoot>;
  await React.act(async () => {
    root = render(container, h(ConflictBanner, { phase: 'conflict', error: null, onDiscardConfirmed: () => {} }));
  });

  const alert = container.querySelector('[role="alert"]');
  assert.ok(alert, 'must render an element with role="alert" so screen readers announce it immediately');
  assert.equal(alert!.getAttribute('aria-live'), 'assertive');

  const message = container.textContent ?? '';
  assert.match(message, /this (browser )?tab/i, 'must scope the claim to this tab, not "your device"/"locally" in general');
  assert.match(message, /lost|gone/i, 'must warn the edit can be lost, not imply it is safely stored');
  assert.doesNotMatch(
    message,
    /kept locally/i,
    '"kept locally" wrongly implies durable storage — the edit only exists in this tab\'s in-memory state',
  );

  await React.act(async () => { root.unmount(); });
});

test('ConflictBanner: exposes the destructive action as a real, accessibly-named <button>', async () => {
  const container = dom.window.document.createElement('div');
  let root!: ReturnType<typeof createRoot>;
  await React.act(async () => {
    root = render(container, h(ConflictBanner, { phase: 'conflict', error: null, onDiscardConfirmed: () => {} }));
  });

  const button = container.querySelector('button');
  assert.ok(button, 'the discard action must be a real <button>, not a div/span, for default keyboard/AT support');
  assert.equal(button!.getAttribute('type'), 'button', 'must not accidentally submit a form (type="submit")');
  assert.equal(button!.textContent, 'Discard unsaved edit and load cloud');

  await React.act(async () => { root.unmount(); });
});

test('ConflictBanner: destructive confirmation — declining the native confirm() prompt never discards the edit', async () => {
  const container = dom.window.document.createElement('div');
  let discardCalls = 0;
  const originalConfirm = dom.window.confirm;
  dom.window.confirm = () => false; // user clicks "Cancel"

  let root!: ReturnType<typeof createRoot>;
  await React.act(async () => {
    root = render(
      container,
      h(ConflictBanner, { phase: 'conflict', error: null, onDiscardConfirmed: () => discardCalls++ }),
    );
  });

  const button = container.querySelector('button')!;
  await React.act(async () => {
    button.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
  });

  assert.equal(discardCalls, 0, 'declining the confirmation prompt must never invoke the discard action');

  dom.window.confirm = originalConfirm;
  await React.act(async () => { root.unmount(); });
});

test('ConflictBanner: destructive confirmation — accepting the native confirm() prompt discards exactly once', async () => {
  const container = dom.window.document.createElement('div');
  let discardCalls = 0;
  const originalConfirm = dom.window.confirm;
  dom.window.confirm = () => true; // user clicks "OK"

  let root!: ReturnType<typeof createRoot>;
  await React.act(async () => {
    root = render(
      container,
      h(ConflictBanner, { phase: 'conflict', error: null, onDiscardConfirmed: () => discardCalls++ }),
    );
  });

  const button = container.querySelector('button')!;
  await React.act(async () => {
    button.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
  });

  assert.equal(discardCalls, 1, 'accepting the confirmation prompt must invoke the discard action exactly once');

  dom.window.confirm = originalConfirm;
  await React.act(async () => { root.unmount(); });
});

test('Workspace.tsx: the real ConflictBanner source still has the accessibility attributes and the destructive confirmation gate (guards against silent removal)', () => {
  const workspaceTsxPath = new URL('../Workspace.tsx', import.meta.url);
  const source = readFileSync(workspaceTsxPath, 'utf8');

  assert.match(source, /role="alert"/, 'ConflictBanner must keep role="alert" for immediate screen-reader announcement');
  assert.match(source, /aria-live="assertive"/, 'ConflictBanner must keep aria-live="assertive"');
  assert.match(
    source,
    /window\.confirm\(/,
    'the destructive discard action must keep a native confirm() gate — a single click must never be sufficient',
  );
  assert.match(
    source,
    /Discard unsaved edit and load cloud/,
    'the button label must stay explicit about what the action does',
  );
  assert.doesNotMatch(
    source,
    /kept locally/i,
    '"kept locally" wrongly implies durable storage and must not reappear in Workspace.tsx',
  );
  assert.match(
    source,
    /this (browser )?tab/i,
    'the conflict copy must keep scoping the claim to this tab, not imply device-wide/durable persistence',
  );
});
