#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');

function readPubspecVersion() {
  const pubspecPath = path.join(repoRoot, 'pubspec.yaml');
  const pubspecContent = fs.readFileSync(pubspecPath, 'utf8');
  const match = pubspecContent.match(/^version:\s*([^\s+]+)\+(\d+)/m);
  if (!match) {
    throw new Error('Could not parse version from pubspec.yaml');
  }
  return {
    versionName: match[1],
    versionCode: match[2],
  };
}

function extractChangelogFromDart(versionName) {
  const providerPath = path.join(
    repoRoot,
    'lib',
    'src',
    'features',
    'updates',
    'app_update_provider.dart',
  );
  if (!fs.existsSync(providerPath)) return null;

  const content = fs.readFileSync(providerPath, 'utf8');
  const historyStart = content.indexOf('kBuiltInReleaseHistory = [');
  if (historyStart === -1) return null;

  const historyBlock = content.slice(historyStart, historyStart + 4000);
  // Find release block for the version or take the first one
  let versionIndex = historyBlock.indexOf(`versionName: '${versionName}'`);
  if (versionIndex === -1) {
    versionIndex = historyBlock.indexOf('AppUpdateRelease(');
  }
  if (versionIndex === -1) return null;

  const releaseChunk = historyBlock.slice(versionIndex, versionIndex + 1500);

  function parseStringList(fieldName) {
    const fieldIndex = releaseChunk.indexOf(fieldName);
    if (fieldIndex === -1) return [];
    const listStart = releaseChunk.indexOf('[', fieldIndex);
    const listEnd = releaseChunk.indexOf(']', listStart);
    if (listStart === -1 || listEnd === -1) return [];
    const rawList = releaseChunk.slice(listStart + 1, listEnd);
    return rawList
      .split('\n')
      .map((line) => line.trim())
      .map((line) => line.replace(/^['"]|['"],?$/g, '').trim())
      .filter((line) => line.length > 0 && !line.startsWith('//'));
  }

  const features = parseStringList('newFeatures:');
  const fixes = parseStringList('bugFixes:');
  const notes = parseStringList('notes:');

  const allItems = [...features, ...fixes, ...notes];
  return allItems.length > 0 ? allItems : null;
}

function extractFromGit() {
  try {
    const raw = execSync('git log -n 10 --oneline', { cwd: repoRoot, encoding: 'utf8' });
    const lines = raw
      .split('\n')
      .map((l) => l.trim().replace(/^[a-f0-9]+\s+/, ''))
      .filter((l) => l.length > 0 && !l.startsWith('Merge'));

    const items = [];
    for (const line of lines) {
      const clean = line.replace(/^(feat|fix|perf|refactor|chore|style)\([^)]*\):\s*/i, '');
      items.push(clean.charAt(0).toUpperCase() + clean.slice(1));
    }
    return items;
  } catch {
    return [];
  }
}

function buildPlayStoreWhatsNew(items, maxChars = 500) {
  const lines = [];
  let currentLength = 0;

  for (const item of items) {
    const bullet = `- ${item.trim()}`;
    const addedLength = lines.length === 0 ? bullet.length : 1 + bullet.length; // +1 for newline

    if (currentLength + addedLength <= maxChars) {
      lines.push(bullet);
      currentLength += addedLength;
    } else {
      // If we cannot fit this item, stop adding
      break;
    }
  }

  if (lines.length === 0 && items.length > 0) {
    // If even the first item was too long, truncate it
    const first = items[0].slice(0, maxChars - 5) + '...';
    return `- ${first}`;
  }

  return lines.join('\n');
}

function main() {
  const { versionName, versionCode } = readPubspecVersion();
  console.log(`Configuring release notes for version ${versionName} (build ${versionCode})...`);

  let items = [];

  const envNotes = (process.env.RELEASE_NOTES || process.env.INPUT_RELEASE_NOTES || '').trim();
  if (envNotes) {
    console.log('Using release notes provided via environment / workflow input.');
    items = envNotes.split(/\r?\n/).map((l) => l.replace(/^[-*]\s*/, '').trim()).filter(Boolean);
  }

  if (items.length === 0) {
    console.log('Extracting release notes from app_update_provider.dart...');
    items = extractChangelogFromDart(versionName) || [];
  }

  if (items.length === 0) {
    console.log('Falling back to recent git commit messages...');
    items = extractFromGit();
  }

  if (items.length === 0) {
    items = [
      'Performance and visual polish improvements',
      'Stability enhancements and bug fixes across all platforms',
    ];
  }

  const whatsNewText = buildPlayStoreWhatsNew(items, 500);

  if (whatsNewText.length > 500) {
    throw new Error(`Google Play release notes exceed 500 characters (${whatsNewText.length} chars)`);
  }

  console.log(`Generated release notes (${whatsNewText.length} / 500 chars):\n${whatsNewText}\n`);

  // 1. Output for r0adkll/upload-google-play (distribution/whatsnew/whatsnew-en-US)
  const whatsNewDir = path.join(repoRoot, 'distribution', 'whatsnew');
  fs.mkdirSync(whatsNewDir, { recursive: true });
  const whatsNewFile = path.join(whatsNewDir, 'whatsnew-en-US');
  fs.writeFileSync(whatsNewFile, whatsNewText, 'utf8');
  console.log(`Wrote ${whatsNewFile}`);

  // 2. Output for Fastlane metadata
  const fastlaneChangelogDir = path.join(
    repoRoot,
    'android',
    'fastlane',
    'metadata',
    'android',
    'en-US',
    'changelogs',
  );
  fs.mkdirSync(fastlaneChangelogDir, { recursive: true });
  const versionedFastlaneFile = path.join(fastlaneChangelogDir, `${versionCode}.txt`);
  fs.writeFileSync(versionedFastlaneFile, whatsNewText, 'utf8');
  console.log(`Wrote ${versionedFastlaneFile}`);

  const defaultFastlaneFile = path.join(fastlaneChangelogDir, 'default.txt');
  fs.writeFileSync(defaultFastlaneFile, whatsNewText, 'utf8');
  console.log(`Wrote ${defaultFastlaneFile}`);
}

main();
