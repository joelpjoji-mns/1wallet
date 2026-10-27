#!/usr/bin/env node
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { readApkInfo, updateChannelFields } from './android-apk-tools.mjs';

const args = process.argv.slice(2);
const argument = name => {
  const index = args.indexOf(name);
  return index < 0 ? undefined : args[index + 1];
};
try {
  const apk = argument('--apk');
  const file = argument('--manifest');
  if (!apk || !file) throw new Error('--apk and --manifest are required.');
  const manifest = JSON.parse(fs.readFileSync(file, 'utf8'));
  const info = readApkInfo(apk, argument('--aapt'));
  const bytes = fs.readFileSync(apk);
  if (info.packageName !== 'com.joelpjoji.one.wallet' ||
      manifest.versionCode !== info.versionCode || manifest.versionName !== info.versionName) {
    throw new Error('Published update identity must match the installed APK, including its ABI build offset.');
  }
  if (manifest.apk?.sizeBytes !== bytes.length ||
      manifest.apk?.sha256 !== createHash('sha256').update(bytes).digest('hex') ||
      !info.architectures.includes(manifest.apk?.architecture)) {
    throw new Error('Update APK hash, size, or architecture does not match the manifest.');
  }
  const channel = updateChannelFields(manifest, `${manifest.channel}-${manifest.versionCode}`);
  console.log(`Verified update manifest ${manifest.versionName}: Android build ${channel.latestVersionCode}, APK integrity, and channel naming.`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
