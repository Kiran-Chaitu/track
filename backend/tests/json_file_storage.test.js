import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { afterEach, beforeEach, describe, test } from 'node:test';

import { loadConfig } from '../src/config.js';
import { JsonFileStorage } from '../src/storage/json_file_storage.js';
import { makeTempDir, removeDir } from './helpers.js';

describe('JsonFileStorage', () => {
  let dir;

  beforeEach(async () => {
    dir = await makeTempDir();
  });

  afterEach(async () => {
    await removeDir(dir);
  });

  test('creates missing directories and the file on init', async () => {
    const file = path.join(dir, 'a', 'b', 'roll_numbers.json');
    const storage = new JsonFileStorage(file);
    assert.deepEqual(await storage.init(), { count: 0 });
    assert.deepEqual(JSON.parse(await fs.readFile(file, 'utf8')), { rollNumbers: [] });
  });

  test('loads existing records without modifying them', async () => {
    const file = path.join(dir, 'roll_numbers.json');
    const original = JSON.stringify({ rollNumbers: ['A1234', 'B5678'] });
    await fs.writeFile(file, original);

    const storage = new JsonFileStorage(file);
    assert.deepEqual(await storage.init(), { count: 2 });
    assert.equal(await fs.readFile(file, 'utf8'), original);
  });

  test('preserves unknown top-level fields when writing', async () => {
    const file = path.join(dir, 'roll_numbers.json');
    await fs.writeFile(file, JSON.stringify({ rollNumbers: ['A1234'], note: 'keep me' }));

    const storage = new JsonFileStorage(file);
    await storage.add('B5678');
    assert.deepEqual(JSON.parse(await fs.readFile(file, 'utf8')), {
      rollNumbers: ['A1234', 'B5678'],
      note: 'keep me',
    });
  });

  test('rejects corrupt and empty files without overwriting them', async () => {
    for (const contents of ['', 'not json', '[]', 'null', '{"rollNumbers":[1,2]}', '{}']) {
      const file = path.join(dir, 'roll_numbers.json');
      await fs.writeFile(file, contents);
      const storage = new JsonFileStorage(file);

      await assert.rejects(storage.add('A1234'), { name: 'StorageError', code: 'STORAGE_CORRUPT' });
      assert.equal(await fs.readFile(file, 'utf8'), contents, `contents changed for ${JSON.stringify(contents)}`);
      assert.deepEqual(await storage.checkHealth(), { ok: false, code: 'STORAGE_CORRUPT' });
    }
  });

  test('recovers once a corrupt file is repaired', async () => {
    const file = path.join(dir, 'roll_numbers.json');
    await fs.writeFile(file, 'garbage');
    const storage = new JsonFileStorage(file);
    await assert.rejects(storage.init());

    await fs.writeFile(file, JSON.stringify({ rollNumbers: ['A1234'] }));
    assert.deepEqual(await storage.add('B5678'), { added: true, count: 2 });
  });

  test('serialises concurrent adds from one instance', async () => {
    const file = path.join(dir, 'roll_numbers.json');
    const storage = new JsonFileStorage(file);
    const values = Array.from({ length: 100 }, (_, i) => `R${String(i % 50).padStart(4, '0')}`);

    const results = await Promise.all(values.map((v) => storage.add(v)));
    assert.equal(results.filter((r) => r.added).length, 50);
    assert.equal(await storage.count(), 50);
  });
});

describe('loadConfig', () => {
  test('refuses to use project-local storage in production', () => {
    assert.throws(() => loadConfig({ NODE_ENV: 'production' }), /DATA_FILE_PATH/);
    assert.doesNotThrow(() => loadConfig({ NODE_ENV: 'production', DATA_FILE_PATH: '/var/data/roll_numbers.json' }));
    assert.doesNotThrow(() => loadConfig({ NODE_ENV: 'production', ALLOW_EPHEMERAL_STORAGE: 'true' }));
  });

  test('derives the file path from DATA_DIR', () => {
    const config = loadConfig({ DATA_DIR: path.join('x', 'data') });
    assert.equal(config.dataFilePath, path.resolve('x', 'data', 'roll_numbers.json'));
  });

  test('rejects an invalid pattern and invalid numbers', () => {
    assert.throws(() => loadConfig({ ROLL_NUMBER_PATTERN: '[A-Z' }), /ROLL_NUMBER_PATTERN/);
    assert.throws(() => loadConfig({ PORT: 'abc' }), /PORT/);
  });
});
