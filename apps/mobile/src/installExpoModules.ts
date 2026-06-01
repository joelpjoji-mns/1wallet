import { TurboModuleRegistry } from 'react-native';

type ExpoModulesCore = {
  installModules?: () => void;
};

try {
  (TurboModuleRegistry.get('ExpoModulesCore') as ExpoModulesCore | null)?.installModules?.();
} catch {
  // Expo modules can still fall back to their own runtime checks.
}
