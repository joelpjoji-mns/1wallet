const fs = require('fs');
const path = require('path');
const { getDefaultConfig } = require('expo/metro-config');

const projectRoot = fs.existsSync(path.join(process.cwd(), 'app.json')) ? process.cwd() : __dirname;
const workspaceRoot = path.resolve(projectRoot, '../..');
const packagesRoot = path.resolve(workspaceRoot, 'packages');
const projectNodeModules = path.resolve(projectRoot, 'node_modules');
const realProjectNodeModules = fs.realpathSync(projectNodeModules);
const workspaceNodeModules = path.resolve(workspaceRoot, 'node_modules');
const realWorkspaceNodeModules = fs.realpathSync(workspaceNodeModules);
const config = getDefaultConfig(projectRoot);
const sourceExtensions = config.resolver.sourceExts.map((extension) => `.${extension}`);
const defaultModulesRunBeforeMainModule = config.serializer.getModulesRunBeforeMainModule;

config.serializer.getModulesRunBeforeMainModule = (...args) => {
  const modules = defaultModulesRunBeforeMainModule?.(...args) ?? [];
  const runtimeGlobalsModule = path.resolve(projectRoot, 'src/installExpoRuntimeGlobals.ts');
  const expoModulesInstallModule = path.resolve(projectRoot, 'src/installExpoModules.ts');

  if (modules.includes(runtimeGlobalsModule) && modules.includes(expoModulesInstallModule)) {
    return modules;
  }

  const [initializeCoreModule, ...remainingModules] = modules;
  return initializeCoreModule
    ? [initializeCoreModule, runtimeGlobalsModule, expoModulesInstallModule, ...remainingModules]
    : [runtimeGlobalsModule, expoModulesInstallModule];
};

config.watchFolders = Array.from(
  new Set([
    workspaceRoot,
    packagesRoot,
    projectNodeModules,
    realProjectNodeModules,
    workspaceNodeModules,
    realWorkspaceNodeModules,
  ]),
);
config.resolver.unstable_enableSymlinks = true;
config.resolver.disableHierarchicalLookup = false;
config.resolver.nodeModulesPaths = Array.from(
  new Set([projectNodeModules, realProjectNodeModules, workspaceNodeModules, realWorkspaceNodeModules]),
);

const workspaceSourceRoots = [
  path.resolve(workspaceRoot, 'packages'),
  path.resolve(projectRoot, 'app'),
  path.resolve(projectRoot, 'src'),
];
const workspacePackages = new Map(
  ['config', 'domain', 'ledger', 'state', 'ui', 'validation'].map((packageName) => [
    `@1wallet/${packageName}`,
    path.resolve(packagesRoot, packageName, 'src'),
  ]),
);

function isWorkspaceSource(filePath) {
  return workspaceSourceRoots.some((root) => filePath.startsWith(root + path.sep));
}

function extensionCandidates(platform, extensions) {
  const candidates = [];

  for (const extension of extensions) {
    if (platform && platform !== 'web') {
      candidates.push(`.${platform}${extension}`, `.native${extension}`);
    } else if (platform === 'web') {
      candidates.push(`.web${extension}`);
    }

    candidates.push(extension);
  }

  return candidates;
}

function resolveSourceFile(modulePath, platform, extensions = sourceExtensions) {
  for (const extension of extensionCandidates(platform, extensions)) {
    const filePath = modulePath + extension;
    if (fs.existsSync(filePath)) {
      return { type: 'sourceFile', filePath };
    }
  }

  return null;
}

function resolveWorkspacePackage(moduleName, platform) {
  for (const [packageName, packageSourceRoot] of workspacePackages) {
    if (moduleName !== packageName && !moduleName.startsWith(`${packageName}/`)) {
      continue;
    }

    const subpath = moduleName === packageName ? 'index' : moduleName.slice(packageName.length + 1);
    const modulePath = path.resolve(packageSourceRoot, subpath);

    return (
      resolveSourceFile(modulePath, platform) ||
      resolveSourceFile(path.join(modulePath, 'index'), platform)
    );
  }

  return null;
}

function originDirectory(originModulePath) {
  const normalized = path.normalize(originModulePath);
  if (fs.existsSync(normalized) && fs.statSync(normalized).isDirectory()) {
    return normalized;
  }
  return path.dirname(normalized);
}

config.resolver.resolveRequest = (context, moduleName, platform) => {
  const workspacePackage = resolveWorkspacePackage(moduleName, platform);

  if (workspacePackage) {
    return workspacePackage;
  }

  if (moduleName.startsWith('./node_modules/')) {
    const workspaceModulePath = path.resolve(workspaceRoot, moduleName.slice(2));
    const resolved = resolveSourceFile(workspaceModulePath, platform);

    if (resolved) {
      return resolved;
    }
  }

  if (moduleName.startsWith('.') && path.extname(moduleName)) {
    const modulePath = path.resolve(originDirectory(context.originModulePath), moduleName);
    if (fs.existsSync(modulePath) && fs.statSync(modulePath).isFile()) {
      return { type: 'sourceFile', filePath: modulePath };
    }
  }

  if (moduleName.startsWith('.') && !path.extname(moduleName)) {
    const originDir = originDirectory(context.originModulePath);
    const modulePath = path.resolve(originDir, moduleName);
    const resolved = resolveSourceFile(modulePath, platform);

    if (resolved) {
      return resolved;
    }
  }

  if (
    moduleName.startsWith('.') &&
    moduleName.endsWith('.js') &&
    isWorkspaceSource(context.originModulePath)
  ) {
    const originDir = originDirectory(context.originModulePath);
    const modulePath = moduleName.slice(0, -3);

    for (const extension of extensionCandidates(platform, ['.ts', '.tsx', '.jsx'])) {
      const filePath = path.resolve(originDir, modulePath + extension);
      if (fs.existsSync(filePath)) {
        return { type: 'sourceFile', filePath };
      }

      const indexPath = path.resolve(originDir, modulePath, `index${extension}`);
      if (fs.existsSync(indexPath)) {
        return { type: 'sourceFile', filePath: indexPath };
      }
    }
  }

  return context.resolveRequest(context, moduleName, platform);
};

module.exports = config;
