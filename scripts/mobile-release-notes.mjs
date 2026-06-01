import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = parseArgs(process.argv.slice(2));
const explicit = {
  newFeatures: listValues(args.feature),
  bugFixes: listValues(args.fix),
  notes: listValues(args.note),
};
const pr = readPullRequest(args['pr-json']);
const parsed = parsePullRequestBody(pr?.body ?? '');
const commits = readCommitLog(args['commit-log']);
const title = pr?.title || commits[0] || 'Android app update';
const changelog = {
  newFeatures: mergeItems(explicit.newFeatures, parsed.newFeatures),
  bugFixes: mergeItems(explicit.bugFixes, parsed.bugFixes),
  notes: mergeItems(explicit.notes, parsed.notes),
};

if (args['require-changelog'] === 'true' && isEmpty(changelog)) {
  throw new Error(
    'Release changelog is required. Fill at least one New Features, Bug Fixes, or Notes item in the PR body, or pass release note inputs.',
  );
}

if (isEmpty(changelog)) {
  const fallbackTarget = looksLikeFix(title) ? changelog.bugFixes : changelog.newFeatures;
  fallbackTarget.push(stripConventionalPrefix(title));
}
if (changelog.notes.length === 0 && pr?.url) changelog.notes.push(`Source PR: ${pr.url}`);
if (changelog.notes.length === 0 && commits.length > 1)
  changelog.notes.push(...commits.slice(1, 6));

const output = {
  title,
  source: pr ? { type: 'pull_request', number: pr.number, url: pr.url } : { type: 'commits' },
  ...changelog,
};
const markdown = renderMarkdown(output, args.version, args['version-code']);

if (args.output)
  writeFileSync(resolve(repoRoot, args.output), `${JSON.stringify(output, null, 2)}\n`);
else process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
if (args.markdown) writeFileSync(resolve(repoRoot, args.markdown), markdown);

function readPullRequest(filePath) {
  if (!filePath || !existsSync(filePath)) return null;
  const raw = JSON.parse(readFileSync(filePath, 'utf8'));
  if (Array.isArray(raw)) return raw[0] ?? null;
  return raw;
}

function readCommitLog(filePath) {
  if (!filePath || !existsSync(filePath)) return [];
  return readFileSync(filePath, 'utf8')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map(stripConventionalPrefix);
}

function parsePullRequestBody(body) {
  const result = { newFeatures: [], bugFixes: [], notes: [] };
  let current = null;
  for (const rawLine of body.split(/\r?\n/)) {
    const line = rawLine.trim();
    const heading = /^#{2,6}\s+(.+)$/.exec(line);
    if (heading) {
      current = sectionForHeading(heading[1]);
      continue;
    }
    if (!current) continue;
    const bullet = stripBullet(line);
    if (bullet && !isPlaceholder(bullet)) result[current].push(bullet);
  }
  return result;
}

function sectionForHeading(value) {
  const normalized = value
    .toLowerCase()
    .replace(/[^a-z ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (normalized.includes('feature') || normalized.includes('new')) return 'newFeatures';
  if (normalized.includes('fix') || normalized.includes('bug')) return 'bugFixes';
  if (normalized.includes('note') || normalized.includes('risk') || normalized.includes('qa'))
    return 'notes';
  return null;
}

function renderMarkdown(changelog, versionName, versionCode) {
  const title = versionName ? `1Wallet Android ${versionName} (${versionCode})` : changelog.title;
  return [
    `# ${title}`,
    '',
    renderSection('New Features', changelog.newFeatures),
    renderSection('Bug Fixes', changelog.bugFixes),
    renderSection('Notes', changelog.notes),
  ]
    .filter(Boolean)
    .join('\n');
}

function renderSection(title, items) {
  if (!items.length) return '';
  return [`## ${title}`, '', ...items.map((item) => `- ${item}`), ''].join('\n');
}

function listValues(value) {
  if (Array.isArray(value)) return value.flatMap(listValues);
  if (typeof value !== 'string') return [];
  return value
    .split(/\r?\n/)
    .map((item) => stripBullet(item.trim()))
    .filter((item) => item && !isPlaceholder(item));
}

function stripBullet(value) {
  return value
    .replace(/^[-*]\s+/, '')
    .replace(/^- \[[ xX]\]\s+/, '')
    .trim();
}

function stripConventionalPrefix(value) {
  return value.replace(/^[a-z]+(\([^)]+\))?!?:\s+/i, '').trim();
}

function looksLikeFix(value) {
  return /\b(fix|bug|crash|error|repair|resolve|correct)\b/i.test(value);
}

function isPlaceholder(value) {
  return /^(none|n\/a|na|todo|tbd|not applicable)$/i.test(value);
}

function mergeItems(...groups) {
  return [
    ...new Set(
      groups
        .flat()
        .map((item) => item.trim())
        .filter(Boolean),
    ),
  ];
}

function isEmpty(changelog) {
  return !changelog.newFeatures.length && !changelog.bugFixes.length && !changelog.notes.length;
}

function parseArgs(values) {
  const result = {};
  for (let index = 0; index < values.length; index += 1) {
    const raw = values[index];
    if (!raw?.startsWith('--')) continue;
    const key = raw.slice(2);
    const next = values[index + 1];
    if (next === undefined || next.startsWith('--')) {
      result[key] = 'true';
      continue;
    }
    if (result[key] === undefined) result[key] = next;
    else if (Array.isArray(result[key])) result[key].push(next);
    else result[key] = [result[key], next];
    index += 1;
  }
  return result;
}
