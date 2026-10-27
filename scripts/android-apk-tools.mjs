import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

export function findAapt(explicitPath) {
  if (explicitPath) return explicitPath;
  const sdk = process.env.ANDROID_SDK_ROOT || process.env.ANDROID_HOME ||
    (process.platform === 'win32' && process.env.LOCALAPPDATA
      ? path.join(process.env.LOCALAPPDATA, 'Android', 'Sdk') : null);
  if (!sdk) throw new Error('Set ANDROID_SDK_ROOT/ANDROID_HOME or pass --aapt.');
  const directory = path.join(sdk, 'build-tools');
  const versions = fs.readdirSync(directory)
    .filter(version => /^\d+\.\d+\.\d+$/.test(version))
    .sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
  for (const version of versions) {
    const executable = path.join(directory, version, process.platform === 'win32' ? 'aapt.exe' : 'aapt');
    if (fs.existsSync(executable)) return executable;
  }
  throw new Error('No Android build-tools aapt executable is available.');
}

export function parseApkBadging(badging) {
  const entry = badging.match(/^package:\s+name='([^']+)'\s+versionCode='(\d+)'\s+versionName='([^']+)'/m);
  const nativeCode = badging.match(/^native-code:\s*(.+)$/m);
  const versionCode = Number(entry?.[2]);
  if (!entry || !Number.isSafeInteger(versionCode) || versionCode < 1 || versionCode > 2147483647) {
    throw new Error('APK package identity or Android version code is invalid.');
  }
  return {
    packageName: entry[1], versionCode, versionName: entry[3],
    architectures: Array.from((nativeCode?.[1] ?? '').matchAll(/'([^']+)'/g), match => match[1]),
  };
}

export function readApkInfo(apk, aapt) {
  return parseApkBadging(execFileSync(findAapt(aapt), ['dump', 'badging', apk], {
    encoding: 'utf8', maxBuffer: 8 * 1024 * 1024,
  }));
}

export function publishedApkVersionCode(info, { versionName, baseVersionCode, architecture }) {
  if (info.packageName !== 'com.joelpjoji.one.wallet' || info.versionName !== versionName) {
    throw new Error('The APK identity/version does not match the requested release.');
  }
  if (!Number.isSafeInteger(baseVersionCode) || baseVersionCode < 1 ||
      info.versionCode < baseVersionCode) {
    throw new Error('The APK Android version code is below its declared base build.');
  }
  if (architecture !== 'universal' && !info.architectures.includes(architecture)) {
    throw new Error('The APK does not contain the declared release architecture.');
  }
  return info.versionCode;
}

export function updateChannelFields(manifest, releaseId) {
  const code = manifest.versionCode;
  if (!Number.isSafeInteger(code) || code < 1 || code > 2147483647 ||
      releaseId !== `${manifest.channel}-${code}`) {
    throw new Error('Update channel must reference the actual published APK build.');
  }
  const name = manifest.versionName ?? manifest.version;
  if (typeof name !== 'string' || !name.trim()) throw new Error('Update channel version name is required.');
  return {
    channel: manifest.channel, latestVersionCode: code, latestReleaseId: releaseId,
    versionName: name, latestVersionName: name, updatedAt: manifest.generatedAt,
  };
}
