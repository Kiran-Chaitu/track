import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { JsonFileStorage } from '../src/storage/json_file_storage.js';

export const ADMIN_KEY = 'test-admin-key-0123456789abcdef';

/** Creates an isolated temporary directory; tests never touch real data. */
export async function makeTempDir() {
  return fs.mkdtemp(path.join(os.tmpdir(), 'roll-numbers-test-'));
}

export async function removeDir(dir) {
  await fs.rm(dir, { recursive: true, force: true });
}

/**
 * Starts the real app on an ephemeral port.
 * @param {object} options
 * @param {string} options.dataFilePath
 * @param {object} [options.env] extra environment overrides
 * @param {object} [options.storage] injected storage implementation
 */
export async function startServer({ dataFilePath, env = {}, storage } = {}) {
  const config = loadConfig({
    NODE_ENV: 'test',
    DATA_FILE_PATH: dataFilePath,
    ADMIN_API_KEY: ADMIN_KEY,
    RATE_LIMIT_WRITE_MAX: '100000',
    RATE_LIMIT_ADMIN_MAX: '100000',
    ...env,
  });
  const realStorage = storage ?? new JsonFileStorage(config.dataFilePath);
  // Mirror server.js: initialise storage at startup, tolerating failures.
  await realStorage.init?.().catch(() => {});
  const app = createApp({ config, storage: realStorage });

  const server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  const baseUrl = `http://127.0.0.1:${server.address().port}`;

  return {
    baseUrl,
    storage: realStorage,
    async close() {
      server.closeAllConnections();
      await new Promise((resolve) => server.close(resolve));
      await realStorage.drain?.();
    },
  };
}

export async function postRollNumber(baseUrl, body, { headers = {}, raw = false } = {}) {
  const res = await fetch(`${baseUrl}/api/roll-numbers`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: raw ? body : JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}

export async function getJson(url, headers = {}) {
  const res = await fetch(url, { headers });
  return { status: res.status, headers: res.headers, body: await res.json() };
}

export async function readStoredFile(file) {
  return JSON.parse(await fs.readFile(file, 'utf8'));
}
