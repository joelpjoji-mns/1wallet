#!/usr/bin/env node
import fs from 'node:fs';

function labelName(label) {
  return String(typeof label === 'string' ? label : label?.name ?? '').toLowerCase();
}

function cleanEntry(value) {
  return String(value).replace(/^\s*[-*]\s*/, '').trim();
}

function isRealEntry(value) {
  const normalized = cleanEntry(value).toLowerCase();
  return normalized.length > 0 && normalized !== '-' && normalized !== 'n/a' && normalized !== 'none' && normalized !== 'todo';
}

function extractSection(body, heading) {
  const lines = body.split(/\r?\n/);
  const entries = [];
  let inSection = false;
  const headingPattern = new RegExp(`^#{2,4}\\s+${heading.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*$`, 'i');

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

const eventPath = process.env.GITHUB_EVENT_PATH;
if (!eventPath || !fs.existsSync(eventPath)) {
  console.log('No GitHub PR event payload found; skipping local release-notes validation.');
  process.exit(0);
}

const event = JSON.parse(fs.readFileSync(eventPath, 'utf8'));
const pr = event.pull_request;
if (!pr) {
  console.log('Event is not a pull_request payload; skipping release-notes validation.');
  process.exit(0);
}

const labels = (pr.labels ?? []).map(labelName);
if (labels.includes('skip-release')) {
  console.log('skip-release label present; release notes are not required.');
  process.exit(0);
}

const body = pr.body ?? '';
const entries = [
  ...extractSection(body, 'New Features'),
  ...extractSection(body, 'Bug Fixes'),
  ...extractSection(body, 'Notes'),
];

if (entries.length === 0) {
  console.error(
    'Release notes are required. Add at least one non-placeholder bullet under New Features, Bug Fixes, or Notes, or add the skip-release label.',
  );
  process.exit(1);
}

console.log(`Release notes validation passed with ${entries.length} entr${entries.length === 1 ? 'y' : 'ies'}.`);
