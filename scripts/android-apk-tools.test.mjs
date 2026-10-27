import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseApkBadging, publishedApkVersionCode, updateChannelFields } from './android-apk-tools.mjs';

const badging = code => `package: name='com.joelpjoji.one.wallet' versionCode='${code}' versionName='2.2.06'\nnative-code: 'arm64-v8a'\n`;
const options = { versionName: '2.2.06', baseVersionCode: 2102206, architecture: 'arm64-v8a' };

test('publication uses the real ABI-split Android build, not the Flutter base build', () => {
  const actual = publishedApkVersionCode(parseApkBadging(badging(2104206)), options);
  assert.equal(actual, 2104206);
  assert.notEqual(actual, options.baseVersionCode);
  const installed = 2104201;
  assert.ok(actual > installed);
  assert.ok(options.baseVersionCode < installed, 'The former metadata suppressed the shipped native worker.');
});

test('publication rejects wrong package, version, architecture, and invalid builds', () => {
  const info = parseApkBadging(badging(2104206));
  assert.throws(() => publishedApkVersionCode({ ...info, packageName: 'wrong.package' }, options), /identity/);
  assert.throws(() => publishedApkVersionCode({ ...info, versionName: '2.2.05' }, options), /identity/);
  assert.throws(() => publishedApkVersionCode({ ...info, architectures: ['x86_64'] }, options), /architecture/);
  assert.throws(() => publishedApkVersionCode({ ...info, versionCode: 1 }, options), /base build/);
  assert.throws(() => parseApkBadging(badging(0)), /invalid/);
  assert.throws(() => parseApkBadging(badging(2147483648)), /invalid/);
});

test('channel and release references carry the same actual code and both current name keys', () => {
  const fields = updateChannelFields({ channel: 'stable', versionCode: 2104206,
    versionName: '2.2.06', generatedAt: '2026-10-27T18:00:00Z' }, 'stable-2104206');
  assert.equal(fields.latestVersionCode, 2104206);
  assert.equal(fields.versionName, '2.2.06');
  assert.equal(fields.latestVersionName, fields.versionName);
  assert.equal(fields.latestReleaseId, 'stable-2104206');
  assert.throws(() => updateChannelFields({ channel: 'stable', versionCode: 2104206,
    versionName: '2.2.06' }, 'stable-2102206'), /actual published/);
});
