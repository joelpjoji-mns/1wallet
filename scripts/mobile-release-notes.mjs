#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function valuesForArg(name) {
  const values = [];
  for (let index = 2; index < process.argv.length; index += 1) {
    if (process.argv[index] === name && process.argv[index + 1] !== undefined) {
      values.push(process.argv[index + 1]);
      index += 1;
    }
  }
  return values.flatMap(splitMultiline).map(cleanEntry).filter(isRealEntry);
}

function readArg(name, fallback = undefined) {
  const index = process.argv.indexOf(name);
  return index === -1 ? fallback : process.argv[index + 1] ?? fallback;
}

function splitMultiline(value) {
  return String(value)
    .split(/\r?\n/)
    .map((line) => line.replace(/^\s*[-*]\s*/, '').trim());
}

function cleanEntry(value) {
  return String(value).replace(/^\s*[-*]\s*/, '').trim();
}

function isRealEntry(value) {
  const normalized = value.trim().toLowerCase();
  return normalized.length > 0 && normalized !== '-' && normalized !== 'n/a' && normalized !== 'none' && normalized !== 'todo';
}

function readJsonArray(file) {
  if (!file || !fs.existsSync(file)) return [];
  try {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    console.warn(`Could not parse ${file}: ${error.message}`);
    return [];
  }
}

function extractSection(body, heading) {
  const lines = body.split(/\r?\n/);
  const entries = [];
  const escaped = heading.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const headingPattern = new RegExp(`^#{2,4}\\s+${escaped}\\s*$`, 'i');
  let inSection = false;

  for (const line of lines) {
    if (/^#{2,4}\s+/.test(line)) {
      inSection = headingPattern.test(line);
      continue;
    }
    if (inSection && /^\s*[-*]\s+/.test(line) && isRealEntry(line)) {
      entries.push(cleanEntry(line));
    }
  }
  return entries;
}

function readCommitNotes(file) {
  if (!file || !fs.existsSync(file)) return [];
  return fs
    .readFileSync(file, 'utf8')
    .split(/\r?\n/)
    .map(cleanEntry)
    .filter(isRealEntry)
    .slice(0, 20);
}

function unique(values) {
  return [...new Set(values)];
}

const prJson = readArg('--pr-json', '.tmp-pr.json');
const commitLog = readArg('--commit-log', '.tmp-commits.txt');
const version = readArg('--version', '0.0.0');
const versionCode = readArg('--version-code', '0');
const requireChangelog = readArg('--require-changelog', 'false') === 'true';
const outputJson = readArg('--output', '.tmp-release-notes.json');
const outputMarkdown = readArg('--markdown', '.tmp-release-notes.md');

const features = valuesForArg('--feature');
const fixes = valuesForArg('--fix');
const notes = valuesForArg('--note');

const pr = readJsonArray(prJson)[0];
if (pr?.body) {
  features.push(...extractSection(pr.body, 'New Features'));
  fixes.push(...extractSection(pr.body, 'Bug Fixes'));
  notes.push(...extractSection(pr.body, 'Notes'));
}

if (features.length === 0 && fixes.length === 0 && notes.length === 0) {
  notes.push(...readCommitNotes(commitLog));
}

const changelog = {
  features: unique(features),
  fixes: unique(fixes),
  notes: unique(notes),
};

if (
  requireChangelog &&
  changelog.features.length === 0 &&
  changelog.fixes.length === 0 &&
  changelog.notes.length === 0
) {
  console.error('Release notes require at least one feature, fix, or note.');
  process.exit(1);
}

const generatedAt = new Date().toISOString();
const releaseNotes = {
  version,
  versionCode: Number.parseInt(versionCode, 10),
  date: generatedAt.slice(0, 10),
  generatedAt,
  source: pr
    ? {
      pullRequest: pr.number,
      title: pr.title,
      url: pr.url,
    }
    : null,
  ...changelog,
  changelog,
};

fs.mkdirSync(path.dirname(outputJson), { recursive: true });
fs.writeFileSync(outputJson, `${JSON.stringify(releaseNotes, null, 2)}\n`, 'utf8');

const lines = [`# 1Wallet Android ${version}`, '', `Generated: ${generatedAt}`, ''];
for (const [title, items] of [
  ['New Features', changelog.features],
  ['Bug Fixes', changelog.fixes],
  ['Notes', changelog.notes],
]) {
  if (items.length === 0) continue;
  lines.push(`## ${title}`, '', ...items.map((item) => `- ${item}`), '');
}

fs.mkdirSync(path.dirname(outputMarkdown), { recursive: true });
fs.writeFileSync(outputMarkdown, `${lines.join('\n').trim()}\n`, 'utf8');
console.log(`Wrote ${outputJson} and ${outputMarkdown}.`);
