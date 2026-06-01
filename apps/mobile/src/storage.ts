import type { KVAdapter } from '@1wallet/ledger/store/memory';
import { KVStore } from '@1wallet/ledger/store/memory';
import * as FileSystem from 'expo-file-system/legacy';

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

const adapter: KVAdapter = {
  async getItem(key) {
    const value = await getStorageItem(key);
    const manifest = parseChunkManifest(value);
    if (!manifest) return value;

    const chunkKeys = Array.from({ length: manifest.chunks }, (_, index) => chunkKey(key, index));
    const chunks = await Promise.all(
      chunkKeys.map(async (chunk) => [chunk, await getStorageItem(chunk)] as const),
    );
    return chunks
      .map(([chunk, chunkValue]) => {
        if (chunkValue === null) {
          throw new LedgerStorageError(
            `Wallet storage is incomplete. Missing persisted ledger chunk ${chunk}.`,
          );
        }
        return chunkValue;
      })
      .join('');
  },
  async setItem(key, value) {
    const previousManifest = await readChunkManifest(key);

    if (value.length <= CHUNK_SIZE) {
      await setStorageItem(key, value);
      if (previousManifest) await removeChunks(key, 0, previousManifest.chunks);
      return;
    }

    const chunkValues = splitIntoChunks(value);
    await Promise.all(
      chunkValues.map((chunkValue, index) => setStorageItem(chunkKey(key, index), chunkValue)),
    );
    await setStorageItem(
      key,
      JSON.stringify({ [CHUNK_MARKER]: true, chunks: chunkValues.length } satisfies ChunkManifest),
    );
    if (previousManifest && previousManifest.chunks > chunkValues.length) {
      await removeChunks(key, chunkValues.length, previousManifest.chunks);
    }
  },
  async removeItem(key) {
    const previousManifest = await readChunkManifest(key);
    await removeStorageItem(key);
    if (previousManifest) await removeChunks(key, 0, previousManifest.chunks);
  },
};

export const ledgerStore = new KVStore(adapter, '1wallet.ledger.v1');

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

function splitIntoChunks(value: string) {
  const chunks: string[] = [];
  for (let index = 0; index < value.length; index += CHUNK_SIZE) {
    chunks.push(value.slice(index, index + CHUNK_SIZE));
  }
  return chunks;
}

async function readChunkManifest(key: string) {
  const value = await getStorageItem(key).catch(() => null);
  return parseChunkManifest(value);
}

async function removeChunks(key: string, startIndex: number, endIndex: number) {
  const chunkKeys = Array.from({ length: endIndex - startIndex }, (_, index) =>
    chunkKey(key, startIndex + index),
  );
  if (chunkKeys.length > 0) await Promise.all(chunkKeys.map(removeStorageItem));
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
  return `${STORAGE_DIRECTORY}${encodeURIComponent(key)}.txt`;
}

async function getStorageItem(key: string) {
  const file = storageFile(key);
  const info = await FileSystem.getInfoAsync(file);
  if (!info.exists) return null;
  return FileSystem.readAsStringAsync(file);
}

async function setStorageItem(key: string, value: string) {
  await ensureStorageDirectory();
  await FileSystem.writeAsStringAsync(storageFile(key), value);
}

async function removeStorageItem(key: string) {
  await FileSystem.deleteAsync(storageFile(key), { idempotent: true });
}
