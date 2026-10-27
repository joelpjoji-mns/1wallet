#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { findAapt } from './android-apk-tools.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

export function requiredNotificationResources(source) {
  if (/['"]@(?:drawable|mipmap)\/[a-z0-9_]+['"]/.test(source)) {
    throw new Error('Notification plugin resource names must not use XML @ prefixes.');
  }
  const icons = ['androidSmallIcon', 'androidLargeIcon'].map(name => {
    const icon = source.match(new RegExp(`static const ${name}\\s*=\\s*'([a-z0-9_]+)'`));
    if (!icon) throw new Error(`NotificationService must declare its ${name} drawable resource.`);
    return `drawable/${icon[1]}`;
  });
  return [...new Set([
    ...icons,
    ...Array.from(source.matchAll(/['"]((?:drawable|mipmap)\/[a-z0-9_]+)['"]/g),
      match => match[1]),
  ])];
}

export function validateNotificationResources(required, resourceTable, packagedFiles) {
  for (const resource of required) {
    const escaped = resource.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const pattern = new RegExp(
      `^\\s*resource\\s+0x[0-9a-f]+\\s+\\S+:${escaped}:\\s+t=0x03[^\\r\\n]*\\r?\\n` +
      '\\s*\\(string(?:8|16)\\)\\s+"([^"]+)"', 'gm',
    );
    const files = Array.from(resourceTable.matchAll(pattern), match => match[1]);
    if (!files.length || files.some(file => !packagedFiles.has(file))) {
      throw new Error(`Missing packaged Android notification resource @${resource}. ` +
        'Preserve dynamic notification resources in res/raw/onewallet_notification_keep.xml.');
    }
  }
}

function main() {
  const args = process.argv.slice(2);
  const argument = name => {
    const index = args.indexOf(name);
    return index === -1 ? undefined : args[index + 1];
  };
  const apk = argument('--apk');
  if (!apk || !fs.existsSync(apk)) throw new Error('--apk must name the built release APK.');
  const aapt = findAapt(argument('--aapt'));
  const run = options => execFileSync(aapt, options, { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  const required = requiredNotificationResources(fs.readFileSync(
    path.join(root, 'lib', 'src', 'services', 'notification_service.dart'), 'utf8'));
  validateNotificationResources(required, run(['dump', '--values', 'resources', apk]),
    new Set(run(['list', apk]).split(/\r?\n/).map(line => line.trim())));
  console.log(`Verified packaged notification resources in ${path.basename(apk)}: ${required.join(', ')}.`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
