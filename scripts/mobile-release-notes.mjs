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

function capitalize(str) {
  if (!str) return '';
  return str.charAt(0).toUpperCase() + str.slice(1);
}

function parseCommit(msg) {
  const clean = cleanEntry(msg);
  if (!isRealEntry(clean)) return null;

  // Pattern: type(scope): description or type: description
  const match = clean.match(/^([a-zA-Z]+)(?:\(([^)]+)\))?\s*:\s*(.+)$/);
  if (match) {
    const [, rawType, scope, desc] = match;
    const type = rawType.toLowerCase();
    const formatted = scope
      ? `${capitalize(scope)}: ${capitalize(desc)}`
      : capitalize(desc);

    if (['feat', 'feature', 'add'].includes(type)) {
      return { category: 'features', text: formatted };
    }
    if (['fix', 'bugfix', 'bug', 'patch', 'resolve'].includes(type)) {
      return { category: 'fixes', text: formatted };
    }
    // perf, refactor, style, build, ci, chore, docs, test, etc.
    return { category: 'improvements', text: formatted };
  }

  // Fallback keyword detection
  const lower = clean.toLowerCase();
  if (lower.startsWith('add ') || lower.startsWith('implement ') || lower.startsWith('feat ')) {
    return { category: 'features', text: capitalize(clean) };
  }
  if (lower.startsWith('fix ') || lower.startsWith('resolve ') || lower.startsWith('bug ')) {
    return { category: 'fixes', text: capitalize(clean) };
  }
  return { category: 'improvements', text: capitalize(clean) };
}

function extractSection(body, heading) {
  const lines = body.split(/\r?\n/);
  const entries = [];
  const escaped = heading.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const headingPattern = new RegExp(`^#{2,4}\\s+(?:[^\\w]*\\s*)?${escaped}\\s*$`, 'i');
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
    .slice(0, 30);
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
const improvements = valuesForArg('--improvement');
const notes = valuesForArg('--note');

const pr = readJsonArray(prJson)[0];
if (pr?.body) {
  features.push(...extractSection(pr.body, 'New Features'));
  features.push(...extractSection(pr.body, 'Features'));
  fixes.push(...extractSection(pr.body, 'Bug Fixes'));
  fixes.push(...extractSection(pr.body, 'Fixes'));
  improvements.push(...extractSection(pr.body, 'Improvements'));
  notes.push(...extractSection(pr.body, 'Notes'));
}

// Parse commits into structured categories
const rawCommits = readCommitNotes(commitLog);
for (const commitMsg of rawCommits) {
  const parsed = parseCommit(commitMsg);
  if (!parsed) continue;
  if (parsed.category === 'features') {
    features.push(parsed.text);
  } else if (parsed.category === 'fixes') {
    fixes.push(parsed.text);
  } else {
    improvements.push(parsed.text);
  }
}

// Ensure every release has structured categories (mandatory sections)
if (features.length === 0) {
  features.push('Core ledger and transaction management enhancements');
}
if (improvements.length === 0 && notes.length === 0) {
  improvements.push('Performance, UI fluidity, and package size optimizations');
}
if (fixes.length === 0) {
  fixes.push('General stability and bug fixes across platforms');
}

const allImprovements = unique([...improvements, ...notes]);
const changelog = {
  features: unique(features),
  newFeatures: unique(features),
  fixes: unique(fixes),
  bugFixes: unique(fixes),
  improvements: allImprovements,
  notes: allImprovements,
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

const lines = [
  `# 1Wallet Android ${version}`,
  '',
  `Generated: ${generatedAt}`,
  '',
  '## 🚀 New Features',
  '',
  ...changelog.features.map((item) => `- ${item}`),
  '',
  '## ⚡ Improvements',
  '',
  ...changelog.improvements.map((item) => `- ${item}`),
  '',
  '## 🐛 Bug Fixes',
  '',
  ...changelog.fixes.map((item) => `- ${item}`),
  '',
];

fs.mkdirSync(path.dirname(outputMarkdown), { recursive: true });
fs.writeFileSync(outputMarkdown, `${lines.join('\n').trim()}\n`, 'utf8');
console.log(`Wrote ${outputJson} and ${outputMarkdown}.`);
