import { NativeModules, Platform } from 'react-native';

export class UpdateInstallerUnavailableError extends Error {
  constructor(message = 'Update installer is unavailable in this build.') {
    super(message);
    this.name = 'UpdateInstallerUnavailableError';
  }
}

type NativePackageInstaller = {
  canRequestPackageInstalls?: () => Promise<boolean>;
  openInstallSettings?: () => Promise<void>;
  installApk?: (fileUri: string) => Promise<void>;
  sha256?: (fileUri: string) => Promise<string>;
};

const nativeInstaller = NativeModules.OneWalletPackageInstaller as
  | NativePackageInstaller
  | undefined;

export function isApkInstallSupported(): boolean {
  return Platform.OS === 'android' && Boolean(nativeInstaller?.installApk);
}

export async function canRequestPackageInstalls(): Promise<boolean> {
  if (Platform.OS !== 'android') return false;
  if (!nativeInstaller?.canRequestPackageInstalls) return false;
  return nativeInstaller.canRequestPackageInstalls();
}

export async function openInstallSettings(): Promise<void> {
  if (Platform.OS !== 'android' || !nativeInstaller?.openInstallSettings) {
    throw new UpdateInstallerUnavailableError(
      'Android install settings are unavailable in this build.',
    );
  }
  await nativeInstaller.openInstallSettings();
}

export async function installApk(fileUri: string): Promise<void> {
  if (Platform.OS !== 'android' || !nativeInstaller?.installApk) {
    throw new UpdateInstallerUnavailableError();
  }
  await nativeInstaller.installApk(fileUri);
}

export async function sha256File(fileUri: string): Promise<string> {
  if (Platform.OS !== 'android' || !nativeInstaller?.sha256) {
    throw new UpdateInstallerUnavailableError(
      'Update checksum verification needs a rebuilt Android app.',
    );
  }
  const hash = await nativeInstaller.sha256(fileUri);
  return hash.replace(/^sha256:/i, '').toLowerCase();
}
