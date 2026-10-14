import { randomBytes } from 'node:crypto';
import fs from 'node:fs/promises';
import { constants as fsConstants } from 'node:fs';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

import { StorageError } from '../errors.js';
import { SerialQueue } from './serial_queue.js';

const INITIAL_DATA = Object.freeze({ rollNumbers: [] });

// Windows can briefly refuse a rename while another process (antivirus, an
// editor) has the target open. These codes are retried a few times.
const RETRYABLE_RENAME_CODES = new Set(['EPERM', 'EACCES', 'EBUSY']);
const RENAME_ATTEMPTS = 5;

/**
 * Stores unique registration numbers in a single JSON file:
 *
 *   { "rollNumbers": ["22A91A0501", "22A91A0502"] }
 *
 * Guarantees (within ONE process):
 * - Every read and write runs through a serial queue, so concurrent requests
 *   cannot interleave a read-modify-write cycle and lose or duplicate records.
 * - Each write re-reads and validates the file first, then writes a temporary
 *   file, fsyncs it and atomically renames it over the original. A crash
 *   mid-write leaves either the old or the new file, never a truncated one.
 * - A missing file is created. A file that exists but is unreadable, not
 *   valid JSON or the wrong shape is NEVER overwritten; operations fail with
 *   StorageError until a human fixes it.
 *
 * Not guaranteed: coordination between multiple processes or instances
 * writing the same file. Run exactly one backend instance per data file.
 */
export class JsonFileStorage {
  #filePath;
  #queue = new SerialQueue();

  constructor(filePath) {
    if (!filePath) throw new Error('JsonFileStorage requires a file path');
    this.#filePath = path.resolve(filePath);
  }

  /** Creates the directory/file if needed and validates existing data. */
  init() {
    return this.#queue.run(async () => {
      const { rollNumbers } = await this.#load();
      return { count: rollNumbers.length };
    });
  }

  /**
   * Adds a normalised roll number unless it is already stored.
   * @returns {Promise<{added: boolean, count: number}>}
   */
  add(rollNumber) {
    return this.#queue.run(async () => {
      const data = await this.#load();
      if (data.rollNumbers.includes(rollNumber)) {
        return { added: false, count: data.rollNumbers.length };
      }
      const next = { ...data, rollNumbers: [...data.rollNumbers, rollNumber] };
      await this.#writeAtomic(next);
      return { added: true, count: next.rollNumbers.length };
    });
  }

  list() {
    return this.#queue.run(async () => [...(await this.#load()).rollNumbers]);
  }

  count() {
    return this.#queue.run(async () => (await this.#load()).rollNumbers.length);
  }

  /** Verifies the file is readable/valid and its directory is writable. */
  checkHealth() {
    return this.#queue.run(async () => {
      try {
        await this.#load();
        await fs.access(path.dirname(this.#filePath), fsConstants.W_OK);
        return { ok: true };
      } catch (err) {
        return { ok: false, code: err instanceof StorageError ? err.code : 'STORAGE_IO' };
      }
    });
  }

  /** Waits for queued operations to finish (used during graceful shutdown). */
  drain() {
    return this.#queue.onIdle();
  }

  async #load() {
    let raw;
    try {
      raw = await fs.readFile(this.#filePath, 'utf8');
    } catch (err) {
      if (err.code === 'ENOENT') return this.#createInitialFile();
      throw new StorageError('STORAGE_IO', `Cannot read ${this.#filePath}: ${err.code ?? err.message}`, { cause: err });
    }

    let data;
    try {
      data = JSON.parse(raw);
    } catch (err) {
      throw new StorageError('STORAGE_CORRUPT', `${this.#filePath} is not valid JSON; refusing to modify it`, {
        cause: err,
      });
    }
    validateShape(data, this.#filePath);
    return data;
  }

  async #createInitialFile() {
    try {
      await fs.mkdir(path.dirname(this.#filePath), { recursive: true });
      // 'wx' fails if the file appeared in the meantime, so this can never
      // replace existing data.
      await fs.writeFile(this.#filePath, serialize(INITIAL_DATA), { encoding: 'utf8', flag: 'wx' });
    } catch (err) {
      if (err.code === 'EEXIST') return this.#load();
      throw new StorageError('STORAGE_IO', `Cannot create ${this.#filePath}: ${err.code ?? err.message}`, {
        cause: err,
      });
    }
    return { ...INITIAL_DATA, rollNumbers: [] };
  }

  async #writeAtomic(data) {
    const dir = path.dirname(this.#filePath);
    const tmpPath = path.join(
      dir,
      `.${path.basename(this.#filePath)}.${process.pid}.${randomBytes(6).toString('hex')}.tmp`,
    );

    try {
      const handle = await fs.open(tmpPath, 'wx');
      try {
        await handle.writeFile(serialize(data), 'utf8');
        await handle.sync();
      } finally {
        await handle.close();
      }
      await renameWithRetry(tmpPath, this.#filePath);
    } catch (err) {
      await fs.rm(tmpPath, { force: true }).catch(() => {});
      throw new StorageError('STORAGE_IO', `Cannot write ${this.#filePath}: ${err.code ?? err.message}`, {
        cause: err,
      });
    }

    await fsyncDirectory(dir);
  }
}

function validateShape(data, filePath) {
  const valid =
    data !== null &&
    typeof data === 'object' &&
    !Array.isArray(data) &&
    Array.isArray(data.rollNumbers) &&
    data.rollNumbers.every((item) => typeof item === 'string');
  if (!valid) {
    throw new StorageError(
      'STORAGE_CORRUPT',
      `${filePath} does not have the expected {"rollNumbers": [string]} shape; refusing to modify it`,
    );
  }
}

function serialize(data) {
  return `${JSON.stringify(data, null, 2)}\n`;
}

async function renameWithRetry(from, to) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await fs.rename(from, to);
      return;
    } catch (err) {
      if (attempt >= RENAME_ATTEMPTS || !RETRYABLE_RENAME_CODES.has(err.code)) throw err;
      await delay(20 * attempt);
    }
  }
}

/** Persists the rename itself on POSIX filesystems. Not supported on Windows. */
async function fsyncDirectory(dir) {
  if (process.platform === 'win32') return;
  let handle;
  try {
    handle = await fs.open(dir, 'r');
    await handle.sync();
  } catch {
    // Best effort: some filesystems do not support fsync on directories.
  } finally {
    await handle?.close().catch(() => {});
  }
}
