import { spawnSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { availableParallelism } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const mobileRoot = resolve(scriptDir, '..');
const repoRoot = resolve(mobileRoot, '../..');
const androidRoot = join(mobileRoot, 'android');
const signingFile = join(androidRoot, 'release-signing.properties.local');

loadEnvFile(join(repoRoot, '.env.local'));
loadEnvFile(join(mobileRoot, '.env.local'));
const signing = loadPropertiesFile(signingFile);

const requiredSigningKeys = [
  'ONEWALLET_RELEASE_STORE_FILE',
  'ONEWALLET_RELEASE_STORE_PASSWORD',
  'ONEWALLET_RELEASE_KEY_ALIAS',
  'ONEWALLET_RELEASE_KEY_PASSWORD',
];
const missingSigningKeys = requiredSigningKeys.filter(
  (key) => !value(process.env[key]) && !value(signing[key]),
);

if (missingSigningKeys.length > 0) {
  console.error('Release signing is not configured.');
  console.error(`Create ${relative(signingFile)} or set these environment variables:`);
  for (const key of missingSigningKeys) console.error(`- ${key}`);
  process.exit(1);
}

process.env.JAVA_TOOL_OPTIONS = appendEnvFlag(
  process.env.JAVA_TOOL_OPTIONS,
  '--enable-native-access=ALL-UNNAMED',
);
process.env.NODE_OPTIONS = appendEnvFlag(process.env.NODE_OPTIONS, '--preserve-symlinks');

for (const [key, nextValue] of Object.entries(signing)) {
  if (!process.env[key] && value(nextValue)) process.env[key] = nextValue.trim();
}

const gradleCommand = process.platform === 'win32' ? 'cmd.exe' : './gradlew';
const gradlePrefix = process.platform === 'win32' ? ['/d', '/s', '/c', 'gradlew.bat'] : [];
const { customArgs, extraGradleArgs } = parseArgs(process.argv.slice(2));
const buildBundle = customArgs.has('--bundle');
const buildUniversal = customArgs.has('--universal');
const buildSplits = buildUniversal || customArgs.has('--splits');
const buildAllAbis = customArgs.has('--all-abis');
const releaseArchitectures =
  value(process.env.ONEWALLET_RELEASE_ARCHITECTURES) ||
  (buildAllAbis
    ? 'armeabi-v7a,arm64-v8a,x86,x86_64'
    : buildSplits
      ? 'arm64-v8a,x86_64'
      : 'arm64-v8a');
const maxWorkers =
  value(process.env.ONEWALLET_GRADLE_MAX_WORKERS) || String(availableParallelism());
const architectureArgs = hasGradleProperty(extraGradleArgs, 'reactNativeArchitectures')
  ? []
  : [`-PreactNativeArchitectures=${releaseArchitectures}`];
const sizeArgs = [
  ['expo.useLegacyPackaging', 'true'],
  [
    'onewallet.resourceConfigurations',
    value(process.env.ONEWALLET_RESOURCE_CONFIGURATIONS) || 'en',
  ],
  ['onewallet.enableAbiSplits', buildSplits ? 'true' : 'false'],
  ['onewallet.enableUniversalApk', buildUniversal ? 'true' : 'false'],
];
const workerArgs = extraGradleArgs.some((arg) => arg.startsWith('--max-workers'))
  ? []
  : [`--max-workers=${maxWorkers}`];
const gradleArgs = [
  ...gradlePrefix,
  buildBundle ? ':app:bundleRelease' : ':app:assembleRelease',
  '-x',
  'lint',
  '-x',
  'test',
  '--parallel',
  '--configure-on-demand',
  '--build-cache',
  ...workerArgs,
  ...architectureArgs,
  ...sizeArgs.flatMap(([propertyName, propertyValue]) =>
    hasGradleProperty(extraGradleArgs, propertyName) ? [] : [`-P${propertyName}=${propertyValue}`],
  ),
  '-Pandroid.enableProguardInReleaseBuilds=true',
  '-Pandroid.enableShrinkResourcesInReleaseBuilds=true',
  ...extraGradleArgs,
];
const outputDir = join(
  androidRoot,
  'app/build/outputs',
  buildBundle ? 'bundle/release' : 'apk/release',
);
const buildStartedAt = Date.now();

console.log(
  `Building signed 1wallet Android release ${buildBundle ? 'bundle' : 'APK'} (${releaseArchitectures})...`,
);
const result = spawnSync(gradleCommand, gradleArgs, {
  cwd: androidRoot,
  env: process.env,
  stdio: 'inherit',
});

if (result.error) console.error(`Failed to start Gradle: ${result.error.message}`);
if (result.status !== 0) process.exit(result.status ?? 1);
const extension = buildBundle ? '.aab' : '.apk';
const artifacts = listCurrentArtifacts(outputDir, extension, buildStartedAt);
for (const artifact of artifacts) {
  console.log(`Release artifact: ${relative(artifact)} (${formatMB(statSync(artifact).size)})`);
}

function loadEnvFile(filePath) {
  if (!existsSync(filePath)) return;
  const lines = readFileSync(filePath, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const equalsIndex = trimmed.indexOf('=');
    if (equalsIndex <= 0) continue;
    const key = trimmed.slice(0, equalsIndex).trim();
    const nextValue = stripQuotes(trimmed.slice(equalsIndex + 1).trim());
    if (!process.env[key]) process.env[key] = nextValue;
  }
}

function loadPropertiesFile(filePath) {
  if (!existsSync(filePath)) return {};
  const result = {};
  const lines = readFileSync(filePath, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const equalsIndex = trimmed.indexOf('=');
    if (equalsIndex <= 0) continue;
    result[trimmed.slice(0, equalsIndex).trim()] = stripQuotes(
      trimmed.slice(equalsIndex + 1).trim(),
    );
  }
  return result;
}

function stripQuotes(raw) {
  if ((raw.startsWith('"') && raw.endsWith('"')) || (raw.startsWith("'") && raw.endsWith("'"))) {
    return raw.slice(1, -1);
  }
  return raw;
}

function appendEnvFlag(current, flag) {
  if (!current) return flag;
  return current.includes(flag) ? current : `${current} ${flag}`;
}

function value(raw) {
  return typeof raw === 'string' && raw.trim().length > 0 ? raw.trim() : undefined;
}

function hasGradleProperty(args, propertyName) {
  return args.some((arg, index) => {
    if (arg === '-P') return args[index + 1]?.startsWith(`${propertyName}=`) ?? false;
    return arg.startsWith(`-P${propertyName}=`);
  });
}

function parseArgs(args) {
  const customArgNames = new Set(['--all-abis', '--bundle', '--splits', '--universal']);
  const customArgs = new Set(args.filter((arg) => customArgNames.has(arg)));
  return {
    customArgs,
    extraGradleArgs: args.filter((arg) => !customArgNames.has(arg)),
  };
}

function listFiles(directory) {
  if (!existsSync(directory)) return [];
  return readdirSync(directory).flatMap((entry) => {
    const filePath = join(directory, entry);
    return statSync(filePath).isDirectory() ? listFiles(filePath) : [filePath];
  });
}

function listCurrentArtifacts(directory, extension, startedAt) {
  const artifacts = listFiles(directory).filter((filePath) => filePath.endsWith(extension));
  const currentArtifacts = artifacts.filter(
    (filePath) => statSync(filePath).mtimeMs >= startedAt - 2000,
  );
  return currentArtifacts.length > 0 ? currentArtifacts : artifacts;
}

function formatMB(bytes) {
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
}

function relative(filePath) {
  return filePath.startsWith(repoRoot) ? filePath.slice(repoRoot.length + 1) : filePath;
}
