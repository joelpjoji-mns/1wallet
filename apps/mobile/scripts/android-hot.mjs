#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const MOBILE_ROOT = path.resolve(SCRIPT_DIR, '..');
const REPO_ROOT = path.resolve(MOBILE_ROOT, '..', '..');
const PACKAGE_NAME = 'com.joelpjoji.one.wallet';
const MAIN_ACTIVITY = `${PACKAGE_NAME}/.MainActivity`;
const DEFAULT_PORT = 8081;
const DEFAULT_ARCH = 'x86_64';
const WINDOWS_JDK17 = 'C:\\Program Files\\Eclipse Adoptium\\jdk-17.0.19.10-hotspot';

const action = process.argv[2] ?? 'start';
const port = Number(process.env.ONEWALLET_METRO_PORT ?? process.env.METRO_PORT ?? DEFAULT_PORT);
const arch = process.env.ONEWALLET_ANDROID_ARCH ?? DEFAULT_ARCH;
const adb = resolveAdb();
const serial = resolveSerial();

if (!Number.isInteger(port) || port <= 0) {
  fail(`Invalid Metro port: ${port}`);
}

switch (action) {
  case 'install':
    installDebug();
    reversePort();
    break;
  case 'launch':
    reversePort();
    launchApp();
    break;
  case 'setup':
    installDebug();
    reversePort();
    startMetro({ launchAfterStart: true });
    break;
  case 'start':
    reversePort();
    startMetro({ launchAfterStart: true });
    break;
  default:
    fail(`Unknown action "${action}". Use install, start, launch, or setup.`);
}

function installDebug() {
  const androidDir = resolveAndroidDir();
  const env = androidBuildEnv();
  const gradleArgs = [
    ':app:installDebug',
    '-x',
    'lint',
    '-x',
    'test',
    '--configure-on-demand',
    '--build-cache',
    `-PreactNativeDevServerPort=${port}`,
    `-PreactNativeArchitectures=${arch}`,
  ];
  const command = process.platform === 'win32' ? 'cmd.exe' : './gradlew';
  const args =
    process.platform === 'win32' ? ['/d', '/s', '/c', 'gradlew.bat', ...gradleArgs] : gradleArgs;
  console.log(
    `Installing debug build for ${serial ?? 'default adb device'} on Metro port ${port} (${arch})`,
  );
  run(command, args, { cwd: androidDir, env });
}

function reversePort() {
  console.log(`Routing device localhost:${port} to this machine via adb reverse`);
  run(adb, adbArgs(['reverse', `tcp:${port}`, `tcp:${port}`]));
}

function launchApp() {
  console.log(`Launching ${PACKAGE_NAME}`);
  run(adb, adbArgs(['shell', 'am', 'force-stop', PACKAGE_NAME]));
  run(adb, adbArgs(['shell', 'am', 'start', '-W', '-n', MAIN_ACTIVITY]));
}

function startMetro({ launchAfterStart }) {
  const reactNativeCli = require.resolve('react-native/cli.js', { paths: [MOBILE_ROOT] });
  const metroEnv = { ...process.env };
  delete metroEnv.NODE_OPTIONS;

  const args = [
    reactNativeCli,
    'start',
    '--projectRoot',
    MOBILE_ROOT,
    '--config',
    path.join(MOBILE_ROOT, 'metro.config.js'),
    '--port',
    String(port),
    '--host',
    '0.0.0.0',
    '--no-interactive',
  ];
  if (process.env.ONEWALLET_METRO_CLEAR === '1') args.push('--reset-cache');

  console.log(`Starting React Native Metro on http://127.0.0.1:${port}`);
  const metro = spawn(process.execPath, args, {
    cwd: MOBILE_ROOT,
    env: metroEnv,
    stdio: 'inherit',
  });

  if (launchAfterStart) {
    const launchDelayMs = Number(process.env.ONEWALLET_LAUNCH_DELAY_MS ?? 4500);
    setTimeout(() => {
      try {
        launchApp();
      } catch (error) {
        console.error(error instanceof Error ? error.message : String(error));
      }
    }, launchDelayMs);
  }

  metro.on('exit', (code, signal) => {
    if (signal) process.kill(process.pid, signal);
    process.exit(code ?? 0);
  });
}

function resolveAndroidDir() {
  const configuredProject = process.env.ONEWALLET_ANDROID_PROJECT_DIR;
  if (configuredProject && existsSync(configuredProject)) return configuredProject;

  const configuredRoot = process.env.ONEWALLET_ANDROID_BUILD_ROOT;
  if (configuredRoot) {
    const configuredDir = path.join(configuredRoot, 'apps', 'mobile', 'android');
    if (existsSync(configuredDir)) return configuredDir;
  }

  const shortDir = 'C:\\w\\apps\\mobile\\android';
  if (process.platform === 'win32' && existsSync(shortDir)) return shortDir;

  return path.join(MOBILE_ROOT, 'android');
}

function androidBuildEnv() {
  const env = { ...process.env };
  if (!env.JAVA_HOME && process.platform === 'win32' && existsSync(WINDOWS_JDK17)) {
    env.JAVA_HOME = WINDOWS_JDK17;
  }
  if (env.JAVA_HOME) {
    const pathKey = Object.keys(env).find((key) => key.toLowerCase() === 'path') ?? 'PATH';
    env[pathKey] = `${path.join(env.JAVA_HOME, 'bin')}${path.delimiter}${env[pathKey] ?? ''}`;
  }
  env.NODE_OPTIONS = appendFlag(env.NODE_OPTIONS, '--preserve-symlinks');
  env.JAVA_TOOL_OPTIONS = appendFlag(env.JAVA_TOOL_OPTIONS, '--enable-native-access=ALL-UNNAMED');
  env.NODE_ENV ??= 'development';
  if (serial) env.ANDROID_SERIAL = serial;
  return env;
}

function resolveAdb() {
  if (process.env.ADB && existsSync(process.env.ADB)) return process.env.ADB;
  const localAppData = process.env.LOCALAPPDATA;
  if (localAppData) {
    const sdkAdb = path.join(localAppData, 'Android', 'Sdk', 'platform-tools', adbName());
    if (existsSync(sdkAdb)) return sdkAdb;
  }
  return 'adb';
}

function resolveSerial() {
  if (process.env.ANDROID_SERIAL) return process.env.ANDROID_SERIAL;
  const devices = listDevices();
  if (devices.length === 0) return undefined;
  const emulator = devices.find((device) => device.startsWith('emulator-'));
  return emulator ?? devices[0];
}

function listDevices() {
  const result = spawnSync(adb, ['devices'], { encoding: 'utf8' });
  if (result.status !== 0) return [];
  return result.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => /\tdevice$/.test(line))
    .map((line) => line.split(/\s+/)[0])
    .filter(Boolean);
}

function adbArgs(args) {
  return serial ? ['-s', serial, ...args] : args;
}

function adbName() {
  return process.platform === 'win32' ? 'adb.exe' : 'adb';
}

function appendFlag(value, flag) {
  if (!value) return flag;
  return value.split(/\s+/).includes(flag) ? value : `${value} ${flag}`;
}

function run(command, args, options = {}) {
  console.log(`> ${command} ${args.join(' ')}`);
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? MOBILE_ROOT,
    env: options.env ?? process.env,
    shell: options.shell ?? false,
    stdio: 'inherit',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
