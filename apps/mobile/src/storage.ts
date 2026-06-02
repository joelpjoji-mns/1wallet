import type { KVAdapter } from '@1wallet/ledger/store/memory';
import { KVStore } from '@1wallet/ledger/store/memory';
import * as FileSystem from 'expo-file-system/legacy';

const LEDGER_STORAGE_KEY = '1wallet.ledger.v1';
const CHUNK_SIZE = 256 * 1024;
const CHUNK_MARKER = '__1wallet_chunked_v1';
const STORAGE_DIRECTORY = `${FileSystem.documentDirectory ?? FileSystem.cacheDirectory}1wallet-kv/`;

type ChunkManifest = {
  [CHUNK_MARKER]: true;
  chunks: number;
};

export class LedgerStorageError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LedgerStorageError';
  }
}

export type LedgerStorageMaintenanceResult = {
  activeBytes: number;
  activeFiles: number;
  removedBytes: number;
  removedFiles: number;
  totalBytesBefore: number;
  totalFilesBefore: number;
};

const adapter: KVAdapter = {
  async getItem(key) {
    const value = await getStorageItem(key);
    const manifest = parseChunkManifest(value);
    if (!manifest) return value;

    const chunks: string[] = [];
    for (let index = 0; index < manifest.chunks; index += 1) {
      const keyForChunk = chunkKey(key, index);
      const chunkValue = await getStorageItem(keyForChunk);
      if (chunkValue === null) {
        throw new LedgerStorageError(
          `Wallet storage is incomplete. Missing persisted ledger chunk ${keyForChunk}.`,
        );
      }
      chunks.push(chunkValue);
    }
    return chunks.join('');
  },
  async setItem(key, value) {
    const previousManifest = await readChunkManifest(key);

    if (value.length <= CHUNK_SIZE) {
      await setStorageItem(key, value);
      if (previousManifest) await removeChunks(key, 0, previousManifest.chunks);
      return;
    }

    const chunkCount = Math.ceil(value.length / CHUNK_SIZE);
    for (let index = 0; index < chunkCount; index += 1) {
      const start = index * CHUNK_SIZE;
      await setStorageItem(chunkKey(key, index), value.slice(start, start + CHUNK_SIZE));
    }
    await setStorageItem(
      key,
      JSON.stringify({ [CHUNK_MARKER]: true, chunks: chunkCount } satisfies ChunkManifest),
    );
    if (previousManifest && previousManifest.chunks > chunkCount) {
      await removeChunks(key, chunkCount, previousManifest.chunks);
    }
  },
  async removeItem(key) {
    const previousManifest = await readChunkManifest(key);
    await removeStorageItem(key);
    if (previousManifest) await removeChunks(key, 0, previousManifest.chunks);
  },
};

export const ledgerStore = new KVStore(adapter, LEDGER_STORAGE_KEY);

export async function compactLedgerStorage(
  key = LEDGER_STORAGE_KEY,
): Promise<LedgerStorageMaintenanceResult> {
  const directoryInfo = await FileSystem.getInfoAsync(STORAGE_DIRECTORY);
  if (!directoryInfo.exists) {
    return emptyMaintenanceResult();
  }

  const manifest = await readChunkManifest(key);
  const expectedNames = new Set(storageFileNames(key));
  if (manifest) {
    for (let index = 0; index < manifest.chunks; index += 1) {
      storageFileNames(chunkKey(key, index)).forEach((name) => expectedNames.add(name));
    }
  }

  const entries = await FileSystem.readDirectoryAsync(STORAGE_DIRECTORY);
  let activeBytes = 0;
  let activeFiles = 0;
  let removedBytes = 0;
  let removedFiles = 0;
  let totalBytesBefore = 0;
  let totalFilesBefore = 0;

  for (const entry of entries) {
    const uri = `${STORAGE_DIRECTORY}${entry}`;
    const size = await fileSize(uri);
    totalBytesBefore += size;
    totalFilesBefore += 1;

    if (!isLedgerStorageEntry(entry, key)) continue;
    if (expectedNames.has(entry)) {
      activeBytes += size;
      activeFiles += 1;
      continue;
    }

    await FileSystem.deleteAsync(uri, { idempotent: true }).catch(() => undefined);
    removedBytes += size;
    removedFiles += 1;
  }

  return {
    activeBytes,
    activeFiles,
    removedBytes,
    removedFiles,
    totalBytesBefore,
    totalFilesBefore,
  };
}

function chunkKey(key: string, index: number) {
  return `${key}:chunk:${index}`;
}

function parseChunkManifest(value: string | null): ChunkManifest | null {
  if (!value?.includes(CHUNK_MARKER)) return null;
  try {
    const parsed = JSON.parse(value) as Partial<ChunkManifest>;
    if (parsed[CHUNK_MARKER] !== true) return null;
    const chunks = parsed.chunks;
    if (!Number.isInteger(chunks) || chunks === undefined || chunks < 0) return null;
    return { [CHUNK_MARKER]: true, chunks };
  } catch {
    return null;
  }
}

async function readChunkManifest(key: string) {
  const value = await getStorageItem(key).catch(() => null);
  return parseChunkManifest(value);
}

async function removeChunks(key: string, startIndex: number, endIndex: number) {
  for (let index = startIndex; index < endIndex; index += 1) {
    await removeStorageItem(chunkKey(key, index));
  }
}

async function ensureStorageDirectory() {
  if (!STORAGE_DIRECTORY.startsWith('file://')) {
    throw new LedgerStorageError('Wallet storage is unavailable on this device.');
  }

  const info = await FileSystem.getInfoAsync(STORAGE_DIRECTORY);
  if (!info.exists) {
    await FileSystem.makeDirectoryAsync(STORAGE_DIRECTORY, { intermediates: true });
  }
}

function storageFile(key: string) {
  return `${STORAGE_DIRECTORY}${storageFileName(key)}`;
}

function legacyStorageFile(key: string) {
  return `${STORAGE_DIRECTORY}${legacyStorageFileName(key)}`;
}

function storageFileName(key: string) {
  return `${encodeURIComponent(key)}.txt`;
}

function legacyStorageFileName(key: string) {
  return `${key}.txt`;
}

function storageFileNames(key: string) {
  return [storageFileName(key), legacyStorageFileName(key)];
}

function isLedgerStorageEntry(entry: string, key: string) {
  const encodedChunkPrefix = encodeURIComponent(`${key}:chunk:`);
  const legacyChunkPrefix = `${key}:chunk:`;
  return (
    storageFileNames(key).includes(entry) ||
    (entry.startsWith(encodedChunkPrefix) && entry.endsWith('.txt')) ||
    (entry.startsWith(legacyChunkPrefix) && entry.endsWith('.txt'))
  );
}

async function getStorageItem(key: string) {
  const file = storageFile(key);
  const info = await FileSystem.getInfoAsync(file);
  if (info.exists) return FileSystem.readAsStringAsync(file);

  const legacyFile = legacyStorageFile(key);
  if (legacyFile === file) return null;
  const legacyInfo = await FileSystem.getInfoAsync(legacyFile);
  if (!legacyInfo.exists) return null;
  return FileSystem.readAsStringAsync(legacyFile);
}

async function setStorageItem(key: string, value: string) {
  await ensureStorageDirectory();
  await FileSystem.writeAsStringAsync(storageFile(key), value);
}

async function removeStorageItem(key: string) {
  await FileSystem.deleteAsync(storageFile(key), { idempotent: true });
  await FileSystem.deleteAsync(legacyStorageFile(key), { idempotent: true });
}

async function fileSize(uri: string) {
  const info = await FileSystem.getInfoAsync(uri).catch(() => null);
  return info?.exists ? ((info as { size?: number }).size ?? 0) : 0;
}

function emptyMaintenanceResult(): LedgerStorageMaintenanceResult {
  return {
    activeBytes: 0,
    activeFiles: 0,
    removedBytes: 0,
    removedFiles: 0,
    totalBytesBefore: 0,
    totalFilesBefore: 0,
  };
}
