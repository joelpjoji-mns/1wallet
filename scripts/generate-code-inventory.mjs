import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

let ts = null;
try {
  ts = await import('typescript').then((module) => module.default ?? module);
} catch {
  console.warn('TypeScript compiler API not found; using lightweight parser fallback.');
}

const root = process.cwd();
const outputPath = path.join(root, 'docs', 'code-inventory.csv');

const ignoredDirectoryNames = new Set([
  '.git',
  '.gradle',
  '.cxx',
  '.expo',
  '.idea',
  '.next',
  '.turbo',
  '.venv',
  'backups',
  'build',
  'coverage',
  'dist',
  'node_modules',
]);

const inventoryExtensions = new Set([
  '.cjs',
  '.csv',
  '.css',
  '.gradle',
  '.html',
  '.js',
  '.json',
  '.jsx',
  '.kt',
  '.kts',
  '.md',
  '.mjs',
  '.patch',
  '.properties',
  '.sql',
  '.svg',
  '.toml',
  '.ts',
  '.tsx',
  '.xml',
  '.yml',
]);

const sourceExtensions = new Set(['.ts', '.tsx', '.js', '.jsx', '.cjs', '.mjs']);
const kotlinExtensions = new Set(['.kt', '.kts']);
const assetExtensions = new Set(['.png', '.jpg', '.jpeg', '.gif', '.webp', '.ttf', '.otf', '.svg']);
const binaryExtensions = new Set(['.jar', '.keystore']);

const packageNamesByDirectory = loadPackageNames(root);
const files = collectInventoryFiles(root)
  .map((filePath) => path.relative(root, filePath).replaceAll(path.sep, '/'))
  .sort((left, right) => left.localeCompare(right));

const sourceFiles = files.filter((file) => sourceExtensions.has(path.extname(file)));
const importCounts = buildImportCounts(sourceFiles);
const rows = [];

for (const file of files) {
  const absolutePath = path.join(root, file);
  const extension = path.extname(file).toLowerCase();
  const language = languageFor(file);
  const lineCount = countLines(absolutePath, extension);
  const keepReason = keepByConventionReason(file);
  const refactorCandidate = refactorCandidateForFile(file, lineCount, extension);

  rows.push({
    area: areaFor(file),
    package: packageFor(file),
    file,
    language,
    symbol: '',
    kind: 'file',
    exported: keepReason ? 'yes' : 'no',
    async: 'no',
    component: isRouteComponentFile(file) ? 'yes' : 'no',
    line: '1',
    referencesKnown: keepReason || `imports:${importCounts.get(file) ?? 0}`,
    notes: lineCount ? `${lineCount} lines` : '',
    refactorCandidate,
  });

  if (sourceExtensions.has(extension)) {
    rows.push(...extractTypeScriptSymbols(file, absolutePath));
  } else if (kotlinExtensions.has(extension)) {
    rows.push(...extractKotlinSymbols(file, absolutePath));
  }
}

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, toCsv(rows), 'utf8');
console.log(
  `Wrote ${path.relative(root, outputPath)} with ${rows.length} rows for ${files.length} files.`,
);

function loadPackageNames(startDirectory) {
  const names = new Map();
  for (const filePath of collectFiles(startDirectory, { packageOnly: true })) {
    try {
      const packageJson = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      const directory = path.dirname(path.relative(root, filePath)).replaceAll(path.sep, '/');
      names.set(directory === '.' ? '' : directory, packageJson.name ?? directory);
    } catch {
      // Ignore malformed package metadata; validation commands will catch it elsewhere.
    }
  }
  return names;
}

function collectFiles(startDirectory, options = {}) {
  const results = [];

  for (const entry of fs.readdirSync(startDirectory, { withFileTypes: true })) {
    const fullPath = path.join(startDirectory, entry.name);
    const relativePath = path.relative(root, fullPath).replaceAll(path.sep, '/');

    if (entry.isDirectory()) {
      if (ignoredDirectoryNames.has(entry.name)) {
        continue;
      }
      results.push(...collectFiles(fullPath, options));
      continue;
    }

    if (!entry.isFile()) {
      continue;
    }

    if (options.packageOnly) {
      if (entry.name === 'package.json') {
        results.push(fullPath);
      }
      continue;
    }

    if (entry.name === 'code-inventory.csv') {
      continue;
    }

    if (entry.name === 'local.properties' || entry.name === 'expo-env.d.ts') {
      continue;
    }

    const extension = path.extname(entry.name).toLowerCase();
    if (
      inventoryExtensions.has(extension) ||
      assetExtensions.has(extension) ||
      binaryExtensions.has(extension) ||
      !extension
    ) {
      results.push(fullPath);
    } else if (relativePath === 'pnpm-lock.yaml' || relativePath === 'pnpm-workspace.yaml') {
      results.push(fullPath);
    }
  }

  return results;
}

function collectInventoryFiles(startDirectory) {
  const gitFiles = spawnSync(
    'git',
    ['ls-files', '--cached', '--others', '--exclude-standard', '-z'],
    {
      cwd: startDirectory,
      encoding: 'utf8',
    },
  );

  if (gitFiles.status === 0 && gitFiles.stdout.trim()) {
    return gitFiles.stdout
      .split('\0')
      .filter(Boolean)
      .filter((file) => file !== 'docs/code-inventory.csv')
      .filter((file) => !isGeneratedOrLocalPath(file))
      .filter((file) => fs.existsSync(path.join(startDirectory, file)))
      .map((file) => path.join(startDirectory, file));
  }

  return collectFiles(startDirectory);
}

function buildImportCounts(filesToRead) {
  const counts = new Map(files.map((file) => [file, 0]));

  for (const file of filesToRead) {
    const absolutePath = path.join(root, file);
    const text = fs.readFileSync(absolutePath, 'utf8');

    if (!ts) {
      for (const specifier of importSpecifiersFromText(text)) {
        incrementResolvedImport(counts, file, specifier);
      }
      continue;
    }

    const sourceFile = ts.createSourceFile(
      file,
      text,
      ts.ScriptTarget.Latest,
      true,
      scriptKindFor(file),
    );

    sourceFile.forEachChild((node) => {
      if (ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) {
        const moduleSpecifier = node.moduleSpecifier;
        if (moduleSpecifier && ts.isStringLiteral(moduleSpecifier)) {
          incrementResolvedImport(counts, file, moduleSpecifier.text);
        }
      } else if (ts.isCallExpression(node) && node.expression.getText(sourceFile) === 'require') {
        const [firstArgument] = node.arguments;
        if (firstArgument && ts.isStringLiteral(firstArgument)) {
          incrementResolvedImport(counts, file, firstArgument.text);
        }
      }
    });
  }

  return counts;
}

function incrementResolvedImport(counts, fromFile, specifier) {
  if (!specifier.startsWith('.')) {
    return;
  }

  const resolved = resolveRelativeImport(fromFile, specifier);
  if (!resolved) {
    return;
  }

  counts.set(resolved, (counts.get(resolved) ?? 0) + 1);
}

function resolveRelativeImport(fromFile, specifier) {
  const fromDirectory = path.dirname(path.join(root, fromFile));
  const candidate = path.resolve(fromDirectory, specifier);
  const relativeCandidates = [];

  if (path.extname(candidate)) {
    relativeCandidates.push(candidate);
  } else {
    for (const extension of [...sourceExtensions, '.json']) {
      relativeCandidates.push(`${candidate}${extension}`);
    }
    for (const extension of [...sourceExtensions, '.json']) {
      relativeCandidates.push(path.join(candidate, `index${extension}`));
    }
  }

  for (const absoluteCandidate of relativeCandidates) {
    const relativeCandidate = path.relative(root, absoluteCandidate).replaceAll(path.sep, '/');
    if (files.includes(relativeCandidate)) {
      return relativeCandidate;
    }
  }

  return '';
}

function extractTypeScriptSymbols(file, absolutePath) {
  if (!ts) {
    return extractTypeScriptSymbolsWithRegex(file, absolutePath);
  }

  const extension = path.extname(file).toLowerCase();
  const text = fs.readFileSync(absolutePath, 'utf8');
  const sourceFile = ts.createSourceFile(
    file,
    text,
    ts.ScriptTarget.Latest,
    true,
    scriptKindFor(file),
  );
  const symbols = [];
  const classStack = [];

  visit(sourceFile);
  return symbols;

  function visit(node) {
    if (ts.isClassDeclaration(node)) {
      const name = node.name?.text ?? '(anonymous class)';
      pushSymbol(
        node,
        name,
        'class',
        hasExportModifier(node),
        false,
        componentFor(name, extension),
      );
      classStack.push(name);
      ts.forEachChild(node, visit);
      classStack.pop();
      return;
    }

    if (ts.isFunctionDeclaration(node)) {
      const name = node.name?.text ?? '(anonymous function)';
      pushSymbol(
        node,
        scopedName(name),
        'function',
        hasExportModifier(node),
        hasAsyncModifier(node),
        componentFor(name, extension),
      );
    } else if (
      ts.isMethodDeclaration(node) ||
      ts.isGetAccessorDeclaration(node) ||
      ts.isSetAccessorDeclaration(node)
    ) {
      const name = propertyName(node.name, sourceFile);
      pushSymbol(
        node,
        scopedName(name),
        ts.isMethodDeclaration(node) ? 'method' : 'accessor',
        hasExportModifier(node),
        hasAsyncModifier(node),
        false,
      );
    } else if (ts.isConstructorDeclaration(node)) {
      pushSymbol(node, scopedName('constructor'), 'constructor', false, false, false);
    } else if (ts.isInterfaceDeclaration(node)) {
      pushSymbol(node, node.name.text, 'interface', hasExportModifier(node), false, false);
    } else if (ts.isTypeAliasDeclaration(node)) {
      pushSymbol(node, node.name.text, 'type', hasExportModifier(node), false, false);
    } else if (ts.isEnumDeclaration(node)) {
      pushSymbol(node, node.name.text, 'enum', hasExportModifier(node), false, false);
    } else if (ts.isVariableStatement(node)) {
      for (const declaration of node.declarationList.declarations) {
        if (!ts.isIdentifier(declaration.name)) {
          continue;
        }
        const initializer = declaration.initializer;
        const exported = hasExportModifier(node);
        const functionLike =
          initializer && (ts.isArrowFunction(initializer) || ts.isFunctionExpression(initializer));
        const wrappedComponent =
          initializer &&
          ts.isCallExpression(initializer) &&
          componentFactoryName(initializer.expression.getText(sourceFile));
        if (functionLike || wrappedComponent || exported) {
          const name = declaration.name.text;
          const kind = functionLike ? 'const-function' : wrappedComponent ? 'component' : 'const';
          const asyncValue = functionLike ? hasAsyncModifier(initializer) : false;
          pushSymbol(
            declaration,
            name,
            kind,
            exported,
            asyncValue,
            componentFor(name, extension) || Boolean(wrappedComponent),
          );
        }
      }
    }

    ts.forEachChild(node, visit);
  }

  function pushSymbol(node, symbol, kind, exported, asyncValue, component) {
    const line = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile)).line + 1;
    symbols.push({
      area: areaFor(file),
      package: packageFor(file),
      file,
      language: languageFor(file),
      symbol,
      kind,
      exported: exported ? 'yes' : 'no',
      async: asyncValue ? 'yes' : 'no',
      component: component ? 'yes' : 'no',
      line: String(line),
      referencesKnown: '',
      notes: '',
      refactorCandidate: refactorCandidateForSymbol(file, symbol, kind, exported),
    });
  }

  function scopedName(name) {
    return classStack.length ? `${classStack[classStack.length - 1]}.${name}` : name;
  }
}

function extractKotlinSymbols(file, absolutePath) {
  const lines = fs.readFileSync(absolutePath, 'utf8').split(/\r?\n/);
  const symbols = [];
  const declarationPattern =
    /^\s*(private\s+|internal\s+|public\s+)?(class|object|fun)\s+([A-Za-z_][A-Za-z0-9_]*)/;

  lines.forEach((line, index) => {
    const match = declarationPattern.exec(line);
    if (!match) {
      return;
    }

    symbols.push({
      area: areaFor(file),
      package: packageFor(file),
      file,
      language: languageFor(file),
      symbol: match[3],
      kind: match[2] === 'fun' ? 'function' : match[2],
      exported: match[1]?.trim() === 'private' || match[1]?.trim() === 'internal' ? 'no' : 'yes',
      async: 'no',
      component: 'no',
      line: String(index + 1),
      referencesKnown: '',
      notes: '',
      refactorCandidate: '',
    });
  });

  return symbols;
}

function hasExportModifier(node) {
  return Boolean(node.modifiers?.some((modifier) => modifier.kind === ts.SyntaxKind.ExportKeyword));
}

function hasAsyncModifier(node) {
  return Boolean(node.modifiers?.some((modifier) => modifier.kind === ts.SyntaxKind.AsyncKeyword));
}

function propertyName(name, sourceFile) {
  if (!name) {
    return '(anonymous)';
  }
  return ts.isIdentifier(name) || ts.isStringLiteral(name) || ts.isNumericLiteral(name)
    ? name.text
    : name.getText(sourceFile);
}

function componentFactoryName(expressionText) {
  return ['memo', 'React.memo', 'forwardRef', 'React.forwardRef'].includes(expressionText);
}

function componentFor(symbol, extension) {
  return extension === '.tsx' && /^[A-Z]/.test(symbol);
}

function scriptKindFor(file) {
  const extension = path.extname(file).toLowerCase();
  if (extension === '.tsx') return ts.ScriptKind.TSX;
  if (extension === '.jsx') return ts.ScriptKind.JSX;
  if (extension === '.js' || extension === '.cjs' || extension === '.mjs') return ts.ScriptKind.JS;
  return ts.ScriptKind.TS;
}

function languageFor(file) {
  const extension = path.extname(file).toLowerCase();
  if (extension === '.tsx') return 'tsx';
  if (extension === '.ts') return 'ts';
  if (extension === '.jsx') return 'jsx';
  if (extension === '.js' || extension === '.cjs' || extension === '.mjs') return 'js';
  if (extension === '.kt' || extension === '.kts') return 'kotlin';
  if (extension === '.md') return 'markdown';
  if (extension === '.csv') return 'csv';
  if (extension === '.sql') return 'sql';
  if (extension === '.json') return 'json';
  if (extension === '.xml') return 'xml';
  if (assetExtensions.has(extension)) return 'asset';
  if (binaryExtensions.has(extension)) return 'binary';
  return extension.replace(/^\./, '') || 'text';
}

function areaFor(file) {
  const parts = file.split('/');
  if (parts[0] === 'apps' && parts[1]) return `${parts[0]}/${parts[1]}`;
  if (parts[0] === 'packages' && parts[1]) return `${parts[0]}/${parts[1]}`;
  return parts[0] ?? 'root';
}

function packageFor(file) {
  const parts = file.split('/');
  const candidates = [parts.slice(0, 2).join('/'), parts[0], ''];
  for (const candidate of candidates) {
    if (packageNamesByDirectory.has(candidate)) {
      return packageNamesByDirectory.get(candidate);
    }
  }
  return areaFor(file);
}

function keepByConventionReason(file) {
  if (/^apps\/mobile\/app\/.+\.(tsx|ts)$/.test(file)) return 'framework-entrypoint:expo-router';
  if (file === 'apps/mobile/index.js') return 'framework-entrypoint:expo';
  if (/^apps\/mobile\/android\/app\/src\/main\/java\//.test(file))
    return 'native-entrypoint:android';
  if (/^patches\/.+\.patch$/.test(file)) return 'dependency-patch:pnpm';
  if (/^supabase\/migrations\/.+\.sql$/.test(file)) return 'schema-history:migration';
  if (/^(package|pnpm-workspace|turbo|tsconfig\.base)\./.test(file)) return 'repo-config';
  if (
    /\.(config|rc)\.(js|mjs|json)$/.test(file) ||
    file.endsWith('.config.js') ||
    file.endsWith('.config.mjs')
  )
    return 'tooling-config';
  if (assetExtensions.has(path.extname(file).toLowerCase())) return 'asset';
  return '';
}

function isRouteComponentFile(file) {
  return /^apps\/mobile\/app\/.+\.tsx$/.test(file);
}

function refactorCandidateForFile(file, lineCount, extension) {
  const candidates = [];
  if (lineCount >= 1000 && sourceExtensions.has(extension)) candidates.push('large-file');
  if (lineCount >= 700 && file.startsWith('apps/mobile/app/'))
    candidates.push('screen-decomposition');
  if (file.includes('/capture/messages.')) candidates.push('parser-hot-path');
  if (file.includes('/services/indexes.')) candidates.push('derived-index-hot-path');
  if (file.includes('/components/record/RecordPickers.')) candidates.push('picker-reuse');
  return candidates.join(';');
}

function refactorCandidateForSymbol(file, symbol, kind, exported) {
  if (!exported && kind === 'const' && symbol === symbol.toUpperCase()) return '';
  if (file === 'apps/mobile/app/add.tsx') return 'add-record-extraction-review';
  if (file.includes('/capture/messages.')) return 'parser-performance-review';
  if (file.includes('/services/indexes.')) return 'index-performance-review';
  return '';
}

function countLines(absolutePath, extension) {
  if (binaryExtensions.has(extension) || (assetExtensions.has(extension) && extension !== '.svg')) {
    return 0;
  }

  try {
    return fs.readFileSync(absolutePath, 'utf8').split(/\r?\n/).length;
  } catch {
    return 0;
  }
}

function toCsv(values) {
  const headers = [
    'area',
    'package',
    'file',
    'language',
    'symbol',
    'kind',
    'exported',
    'async',
    'component',
    'line',
    'referencesKnown',
    'notes',
    'refactorCandidate',
  ];

  return (
    [
      headers.join(','),
      ...values.map((row) => headers.map((header) => csvCell(row[header] ?? '')).join(',')),
    ].join('\n') + '\n'
  );
}

function csvCell(value) {
  const text = String(value);
  if (/[",\r\n]/.test(text)) {
    return `"${text.replaceAll('"', '""')}"`;
  }
  return text;
}

function extractTypeScriptSymbolsWithRegex(file, absolutePath) {
  const extension = path.extname(file).toLowerCase();
  const lines = fs.readFileSync(absolutePath, 'utf8').split(/\r?\n/);
  const symbols = [];
  const classStack = [];
  let classDepth = 0;
  let braceDepth = 0;

  lines.forEach((line, index) => {
    const trimmedLine = line.trim();
    const classMatch = /^(export\s+)?(default\s+)?class\s+([A-Za-z_$][A-Za-z0-9_$]*)/.exec(
      trimmedLine,
    );
    if (classMatch) {
      pushSymbol(
        classMatch[3],
        'class',
        Boolean(classMatch[1]),
        false,
        componentFor(classMatch[3], extension),
        index + 1,
      );
      classStack.push(classMatch[3]);
      classDepth = braceDepth + bracesDelta(line);
    }

    const functionMatch =
      /^(export\s+)?(default\s+)?(async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)/.exec(
        trimmedLine,
      );
    if (functionMatch) {
      pushSymbol(
        functionMatch[4],
        'function',
        Boolean(functionMatch[1] || functionMatch[2]),
        Boolean(functionMatch[3]),
        componentFor(functionMatch[4], extension),
        index + 1,
      );
    }

    const typeMatch = /^(export\s+)?(interface|type|enum)\s+([A-Za-z_$][A-Za-z0-9_$]*)/.exec(
      trimmedLine,
    );
    if (typeMatch) {
      pushSymbol(typeMatch[3], typeMatch[2], Boolean(typeMatch[1]), false, false, index + 1);
    }

    const variableMatch =
      /^(export\s+)?const\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(async\s+)?(\([^)]*\)|[A-Za-z_$][A-Za-z0-9_$]*)?\s*=>/.exec(
        trimmedLine,
      ) ??
      /^(export\s+)?const\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(async\s+)?function\b/.exec(
        trimmedLine,
      ) ??
      /^(export\s+)?const\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(memo|React\.memo|forwardRef|React\.forwardRef)\b/.exec(
        trimmedLine,
      );
    if (variableMatch) {
      const name = variableMatch[2];
      const wrappedComponent = variableMatch[4] && componentFactoryName(variableMatch[4]);
      pushSymbol(
        name,
        wrappedComponent ? 'component' : 'const-function',
        Boolean(variableMatch[1]),
        Boolean(variableMatch[3]),
        componentFor(name, extension) || Boolean(wrappedComponent),
        index + 1,
      );
    }

    const methodMatch = classStack.length
      ? /^(async\s+)?([A-Za-z_$][A-Za-z0-9_$]*)\s*\([^)]*\)\s*[:{]/.exec(trimmedLine)
      : null;
    if (
      methodMatch &&
      !['if', 'for', 'while', 'switch', 'catch', 'function'].includes(methodMatch[2])
    ) {
      pushSymbol(
        `${classStack[classStack.length - 1]}.${methodMatch[2]}`,
        'method',
        false,
        Boolean(methodMatch[1]),
        false,
        index + 1,
      );
    }

    braceDepth += bracesDelta(line);
    while (classStack.length && braceDepth < classDepth) {
      classStack.pop();
      classDepth = braceDepth;
    }
  });

  return symbols;

  function pushSymbol(symbol, kind, exported, asyncValue, component, line) {
    symbols.push({
      area: areaFor(file),
      package: packageFor(file),
      file,
      language: languageFor(file),
      symbol,
      kind,
      exported: exported ? 'yes' : 'no',
      async: asyncValue ? 'yes' : 'no',
      component: component ? 'yes' : 'no',
      line: String(line),
      referencesKnown: '',
      notes: 'lightweight-parser',
      refactorCandidate: refactorCandidateForSymbol(file, symbol, kind, exported),
    });
  }
}

function importSpecifiersFromText(text) {
  const specifiers = [];
  const patterns = [
    /(?:import|export)\s+(?:[^'";]+\s+from\s+)?['"]([^'"]+)['"]/g,
    /require\(\s*['"]([^'"]+)['"]\s*\)/g,
  ];

  for (const pattern of patterns) {
    for (const match of text.matchAll(pattern)) {
      specifiers.push(match[1]);
    }
  }

  return specifiers;
}

function bracesDelta(line) {
  const withoutStrings = line.replace(/(['"`])(?:\\.|(?!\1).)*\1/g, '');
  return (withoutStrings.match(/{/g)?.length ?? 0) - (withoutStrings.match(/}/g)?.length ?? 0);
}

function isGeneratedOrLocalPath(file) {
  if (file === 'apps/mobile/android/local.properties' || file === 'apps/mobile/expo-env.d.ts') {
    return true;
  }

  return file.split('/').some((segment) => ignoredDirectoryNames.has(segment));
}
