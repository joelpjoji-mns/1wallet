// Regression coverage for a privacy bug: `AuthProvider` can switch directly
// from signed-in user A to signed-in user B while `WalletDataProvider` stays
// mounted (only its `user` context value changes) — and because
// `WalletDataProvider`'s `snapshot` state is only reset by an *effect*, the
// render that first sees `user.uid === B` can still carry `snapshot` still
// holding user A's accounts/transactions, since effects run after React
// commits (and, for a plain `useEffect`, after the browser paints).
//
// The fix (see `Workspace.tsx`'s `Workspace` component) is to key
// `<WalletDataProvider key={user?.uid}>` so React fully unmounts the old
// provider instance (destroying its state entirely) and mounts a brand-new
// one — whose initial `snapshot` state is always `emptyLedgerSnapshot()` —
// synchronously as part of the *same* reconciliation pass that picks up the
// new uid. There is structurally no render where the new uid is visible
// alongside the old user's data, because the component instance holding
// that data no longer exists.
//
// `WalletDataProvider`/`AuthProvider` can't be imported directly outside
// Vite (they transitively pull in `../lib/firebase`, which reads
// `import.meta.env.VITE_FIREBASE_*` — a Vite-only feature that throws under
// plain `node --test`). This test instead exercises the exact React
// remount/reset mechanics `Workspace.tsx` and `WalletDataContext.tsx` rely
// on, using a minimal reproduction of the same shape (props-driven `user`,
// `useState` snapshot reset via a mount/uid-change effect), and additionally
// asserts the real `Workspace.tsx` source still contains the
// `key={user?.uid}` guard, so removing it there also fails this test.
//
// Run with: node --test src/lib/uidSwitchRender.test.ts

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

interface FakeUser {
  uid: string;
}

type RenderLogEntry = { uid: string | null; snapshot: string };

function createDeferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((res) => {
    resolve = res;
  });
  return { promise, resolve };
}

type Deferred<T> = ReturnType<typeof createDeferred<T>>;

/**
 * Minimal reproduction of `WalletDataProvider`'s reset-on-uid-change shape:
 * `snapshot` starts empty and is reset to empty whenever the `user.uid` it's
 * keyed to changes, via a mount/dependency effect — exactly mirroring the
 * `useLayoutEffect` in `WalletDataContext.tsx` that resets
 * `snapshot`/`lastKnownMetaRef` on every uid change. The "load" is an
 * explicit, test-controlled `Deferred` (rather than a bare
 * `Promise.resolve().then(...)`) so the test can resolve it and observe the
 * resulting state update deterministically inside one `act()` call.
 */
function DataProvider(props: {
  user: FakeUser | null;
  loadDeferred: Deferred<string> | null;
  log: (entry: RenderLogEntry) => void;
}): null {
  const [snapshot, setSnapshot] = React.useState('EMPTY');

  React.useLayoutEffect(() => {
    setSnapshot('EMPTY');
    if (props.loadDeferred) {
      props.loadDeferred.promise.then((data) => setSnapshot(data));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.user?.uid]);

  // Synchronous render-body side channel: logs *every* render pass,
  // including any "stale" one that happens before the reset effect above has
  // had a chance to run — this is exactly the frame that must never expose
  // the previous user's data.
  props.log({ uid: props.user?.uid ?? null, snapshot });
  return null;
}

function renderApp(
  container: HTMLElement,
  user: FakeUser | null,
  loadDeferred: Deferred<string> | null,
  log: (e: RenderLogEntry) => void,
  keyed: boolean,
) {
  const root = createRoot(container);
  const element = keyed
    ? h(DataProvider, { user, loadDeferred, log, key: user?.uid ?? 'signed-out' })
    : h(DataProvider, { user, loadDeferred, log });
  root.render(element);
  return root;
}

test('BUG (reproduced): an unkeyed provider can render the new uid paired with the previous user\'s stale data', async () => {
  const container = dom.window.document.createElement('div');
  const log: RenderLogEntry[] = [];
  let root!: ReturnType<typeof createRoot>;
  const userADeferred = createDeferred<string>();

  await React.act(async () => {
    root = renderApp(container, { uid: 'user-a' }, userADeferred, (e) => log.push(e), false);
  });
  // Let user A's simulated load resolve so `snapshot` holds real data.
  await React.act(async () => {
    userADeferred.resolve('WALLET-DATA-FOR-user-a');
    await userADeferred.promise;
  });
  assert.ok(log.some((e) => e.uid === 'user-a' && e.snapshot === 'WALLET-DATA-FOR-user-a'));

  log.length = 0;
  // Direct A -> B switch, same provider instance (no key).
  await React.act(async () => {
    root.render(h(DataProvider, { user: { uid: 'user-b' }, loadDeferred: null, log: (e) => log.push(e) }));
  });

  const stalePairing = log.find((e) => e.uid === 'user-b' && e.snapshot.includes('user-a'));
  assert.ok(
    stalePairing,
    'expected the unkeyed reproduction to log at least one render pairing the new uid with the old user\'s data (this documents the bug being fixed, not the fixed behavior)',
  );

  await React.act(async () => { root.unmount(); });
});

test('FIX: a provider keyed by user.uid never renders the new uid paired with the previous user\'s data', async () => {
  const container = dom.window.document.createElement('div');
  const log: RenderLogEntry[] = [];
  let root!: ReturnType<typeof createRoot>;
  const userADeferred = createDeferred<string>();
  const userBDeferred = createDeferred<string>();

  await React.act(async () => {
    root = renderApp(container, { uid: 'user-a' }, userADeferred, (e) => log.push(e), true);
  });
  await React.act(async () => {
    userADeferred.resolve('WALLET-DATA-FOR-user-a');
    await userADeferred.promise;
  });
  assert.ok(log.some((e) => e.uid === 'user-a' && e.snapshot === 'WALLET-DATA-FOR-user-a'));

  log.length = 0;
  // Direct A -> B switch, but this time the element is keyed by uid, exactly
  // like `<WalletDataProvider key={user?.uid}>` in `Workspace.tsx`.
  await React.act(async () => {
    root.render(
      h(DataProvider, {
        user: { uid: 'user-b' },
        loadDeferred: userBDeferred,
        log: (e) => log.push(e),
        key: 'user-b',
      }),
    );
  });

  const stalePairing = log.find((e) => e.uid === 'user-b' && e.snapshot.includes('user-a'));
  assert.equal(
    stalePairing,
    undefined,
    'a keyed remount must never render the new uid paired with the previous user\'s data, in any render pass',
  );
  // The very first render of the new (remounted) instance must already be
  // the fresh default, not a stale carry-over.
  assert.equal(log[0]?.uid, 'user-b');
  assert.equal(log[0]?.snapshot, 'EMPTY');

  await React.act(async () => {
    userBDeferred.resolve('WALLET-DATA-FOR-user-b');
    await userBDeferred.promise;
  });
  assert.ok(log.some((e) => e.uid === 'user-b' && e.snapshot === 'WALLET-DATA-FOR-user-b'));

  await React.act(async () => { root.unmount(); });
});

test('Workspace.tsx keys the real WalletDataProvider by user.uid (guards against the fix being silently removed)', () => {
  const workspaceTsxPath = new URL('../Workspace.tsx', import.meta.url);
  const source = readFileSync(workspaceTsxPath, 'utf8');
  assert.match(
    source,
    /<WalletDataProvider\s+key=\{user\?\.uid/,
    'Workspace.tsx must render <WalletDataProvider key={user?.uid ...}> so a direct account switch fully ' +
      'remounts it instead of relying solely on effect timing to clear the previous user\'s data',
  );
});
