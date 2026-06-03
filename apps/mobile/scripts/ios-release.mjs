#!/usr/bin/env node

import { spawnSync } from 'node:child_process';

const args = parseArgs(process.argv.slice(2));
const profile = args.profile ?? 'production';
const submit = args.submit === true;
const submitOnly = args['submit-only'] === true;
const local = args.local === true;

const allowedProfiles = new Set(['development', 'simulator', 'preview', 'production']);
if (!allowedProfiles.has(profile)) {
  throw new Error(`Unsupported iOS EAS profile: ${profile}.`);
}

if ((submit || submitOnly) && profile === 'simulator') {
  throw new Error('Simulator builds cannot be submitted to TestFlight or App Store Connect.');
}

if (!process.env.EXPO_TOKEN && !local) {
  console.warn('EXPO_TOKEN is not set. EAS may prompt for interactive login outside CI.');
}

if (submitOnly) {
  runEas(['submit', '--platform', 'ios', '--profile', profile, '--non-interactive']);
  process.exit(0);
}

const buildArgs = ['build', '--platform', 'ios', '--profile', profile, '--non-interactive'];
if (local) buildArgs.push('--local');
if (submit) buildArgs.push('--auto-submit');
runEas(buildArgs);

function runEas(easArgs) {
  const command = process.platform === 'win32' ? 'pnpm.cmd' : 'pnpm';
  const result = spawnSync(command, ['dlx', 'eas-cli@latest', ...easArgs], {
    cwd: process.cwd(),
    env: process.env,
    stdio: 'inherit',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function parseArgs(values) {
  const result = {};
  for (let index = 0; index < values.length; index += 1) {
    const raw = values[index];
    if (!raw?.startsWith('--')) continue;
    const key = raw.slice(2);
    const next = values[index + 1];
    if (next === undefined || next.startsWith('--')) {
      result[key] = true;
      continue;
    }
    result[key] = next;
    index += 1;
  }
  return result;
}