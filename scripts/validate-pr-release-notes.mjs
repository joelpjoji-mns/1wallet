import { readFileSync } from 'node:fs';

const eventPath = process.env.GITHUB_EVENT_PATH ?? process.argv[2];
if (!eventPath) throw new Error('GITHUB_EVENT_PATH or an event JSON path is required.');

const event = JSON.parse(readFileSync(eventPath, 'utf8'));
const pullRequest = event.pull_request;
if (!pullRequest) {
  console.log('No pull request payload found; skipping release-note validation.');
  process.exit(0);
}

const labels = (pullRequest.labels ?? []).map((label) => String(label.name ?? '').toLowerCase());
if (labels.includes('skip-release')) {
  console.log('skip-release label present; release-note validation skipped.');
  process.exit(0);
}

const changelog = parsePullRequestBody(pullRequest.body ?? '');
if (isEmpty(changelog)) {
  throw new Error(
    'Release notes are required. Add at least one non-placeholder item under New Features, Bug Fixes, or Notes, or add the skip-release label.',
  );
}

console.log(
  `Release notes ok: ${changelog.newFeatures.length} feature(s), ${changelog.bugFixes.length} fix(es), ${changelog.notes.length} note(s).`,
);

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
  if (normalized.includes('note') || normalized.includes('risk')) return 'notes';
  return null;
}

function stripBullet(value) {
  return value
    .replace(/^- \[[ xX]\]\s+/, '')
    .replace(/^[-*]\s*/, '')
    .trim();
}

function isPlaceholder(value) {
  return /^(none|n\/a|na|todo|tbd|not applicable|-|_)$/i.test(value);
}

function isEmpty(changelog) {
  return !changelog.newFeatures.length && !changelog.bugFixes.length && !changelog.notes.length;
}
