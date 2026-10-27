import { test } from 'node:test';
import assert from 'node:assert/strict';
import { requiredNotificationResources, validateNotificationResources } from './validate-android-notification-resources.mjs';

const required = ['drawable/ic_notification', 'drawable/ic_launcher_foreground'];
const entry = (resource, file) =>
  `        resource 0x7f080001 com.example:${resource}: t=0x03 d=0x00000001 (s=0x0008 r=0x00)\n` +
  `          (string8) "${file}"\n`;
const complete = entry(required[0], 'res/a.xml') + entry(required[1], 'res/b.png');
const files = new Set(['res/a.xml', 'res/b.png']);

test('notification requirements follow the service small-icon constant and bitmap references', () => {
  assert.deepEqual(requiredNotificationResources(
    "static const androidSmallIcon = 'ic_notification'; " +
    "static const androidLargeIcon = 'ic_launcher_foreground';"), required);
  assert.throws(() => requiredNotificationResources(''), /must declare/);
  assert.throws(() => requiredNotificationResources("icon: '@drawable/ic_notification'"), /XML @ prefixes/);
});

test('release validation accepts retained resource names with obfuscated ZIP filenames', () => {
  assert.doesNotThrow(() => validateNotificationResources(required, complete, files));
});

test('release validation rejects a missing small icon even if the launcher survives', () => {
  assert.throws(() => validateNotificationResources(required,
    entry(required[1], 'res/b.png'), files), /drawable\/ic_notification/);
});

test('a spec entry or shrunk scalar placeholder is not proof of a packaged drawable', () => {
  const removed = 'spec resource 0x7f080001 com.example:drawable/ic_notification: flags=0x0\n' +
    'resource 0x7f080001 com.example:drawable/ic_notification: t=0x12 d=0x00000000\n';
  assert.throws(() => validateNotificationResources(required,
    removed + entry(required[1], 'res/b.png'), files), /drawable\/ic_notification/);
});

test('release validation rejects missing resource payloads and missing large icons', () => {
  assert.throws(() => validateNotificationResources(required, complete,
    new Set(['res/b.png'])), /drawable\/ic_notification/);
  assert.throws(() => validateNotificationResources(required,
    entry(required[0], 'res/a.xml'), files), /drawable\/ic_launcher_foreground/);
});
