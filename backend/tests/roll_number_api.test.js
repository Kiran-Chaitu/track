import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { afterEach, beforeEach, describe, test } from 'node:test';

import { StorageError } from '../src/errors.js';
import {
  ADMIN_KEY,
  getJson,
  makeTempDir,
  postRollNumber,
  readStoredFile,
  removeDir,
  startServer,
} from './helpers.js';

const adminHeaders = { Authorization: `Bearer ${ADMIN_KEY}` };

describe('Roll number API', () => {
  let dir;
  let dataFile;
  let server;

  beforeEach(async () => {
    dir = await makeTempDir();
    dataFile = path.join(dir, 'nested', 'roll_numbers.json');
    server = await startServer({ dataFilePath: dataFile });
  });

  afterEach(async () => {
    await server?.close();
    await removeDir(dir);
  });

  // 1
  test('health endpoint reports process and storage status', async () => {
    const { status, body } = await getJson(`${server.baseUrl}/api/health`);
    assert.equal(status, 200);
    assert.equal(body.status, 'ok');
    assert.deepEqual(body.storage, { status: 'ok' });
    assert.equal(typeof body.uptimeSeconds, 'number');
  });

  // 2
  test('stores a new valid registration number (201)', async () => {
    const { status, body } = await postRollNumber(server.baseUrl, { rollNumber: '22A91A0501' });
    assert.equal(status, 201);
    assert.deepEqual(body, {
      success: true,
      message: 'Registration number stored successfully',
      rollNumber: '22A91A0501',
      duplicate: false,
    });
    assert.deepEqual(await readStoredFile(dataFile), { rollNumbers: ['22A91A0501'] });
  });

  // 3
  test('normalises lowercase input to uppercase', async () => {
    const { status, body } = await postRollNumber(server.baseUrl, { rollNumber: '22a91a0502' });
    assert.equal(status, 201);
    assert.equal(body.rollNumber, '22A91A0502');
    assert.deepEqual((await readStoredFile(dataFile)).rollNumbers, ['22A91A0502']);
  });

  // 4
  test('trims leading and trailing whitespace', async () => {
    const { status, body } = await postRollNumber(server.baseUrl, { rollNumber: '  \t22A91A0503 \n' });
    assert.equal(status, 201);
    assert.equal(body.rollNumber, '22A91A0503');
  });

  // 5
  test('rejects empty, whitespace-only and missing values', async () => {
    for (const payload of [{ rollNumber: '' }, { rollNumber: '    ' }, {}, { rollNumber: null }]) {
      const { status, body } = await postRollNumber(server.baseUrl, payload);
      assert.equal(status, 400, JSON.stringify(payload));
      assert.equal(body.success, false);
      assert.match(body.code, /^ROLL_NUMBER_(EMPTY|REQUIRED)$/);
    }
    assert.deepEqual((await readStoredFile(dataFile)).rollNumbers, []);
  });

  // 6
  test('rejects malformed registration numbers', async () => {
    const invalid = [
      '22A91-0501',
      '22A9 1A0501',
      '<script>',
      'https://example.com/22A91A0501',
      '{"rollNumber":"22A91A0501"}',
      'ABC', // shorter than the default minimum of 4
      'A'.repeat(21), // longer than the default maximum of 20
      'A'.repeat(500), // longer than the hard cap
      12345,
      ['22A91A0501'],
    ];
    for (const rollNumber of invalid) {
      const { status, body } = await postRollNumber(server.baseUrl, { rollNumber });
      assert.equal(status, 400, `expected 400 for ${JSON.stringify(rollNumber)}`);
      assert.equal(body.success, false);
    }
    assert.deepEqual((await readStoredFile(dataFile)).rollNumbers, []);
  });

  test('rejects invalid JSON, non-JSON bodies and oversized bodies', async () => {
    const badJson = await postRollNumber(server.baseUrl, '{"rollNumber":', { raw: true });
    assert.equal(badJson.status, 400);
    assert.equal(badJson.body.code, 'INVALID_JSON');

    const arrayBody = await postRollNumber(server.baseUrl, ['22A91A0501']);
    assert.equal(arrayBody.status, 400);

    const textRes = await fetch(`${server.baseUrl}/api/roll-numbers`, {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain' },
      body: '22A91A0501',
    });
    assert.equal(textRes.status, 415);

    const huge = await postRollNumber(server.baseUrl, { rollNumber: '22A91A0501', pad: 'x'.repeat(5000) });
    assert.equal(huge.status, 413);
    assert.equal(huge.body.code, 'PAYLOAD_TOO_LARGE');
  });

  // 7
  test('does not store duplicates and reports them with 200', async () => {
    assert.equal((await postRollNumber(server.baseUrl, { rollNumber: '22A91A0501' })).status, 201);

    const { status, body } = await postRollNumber(server.baseUrl, { rollNumber: ' 22a91a0501 ' });
    assert.equal(status, 200);
    assert.deepEqual(body, {
      success: true,
      message: 'Registration number already exists',
      rollNumber: '22A91A0501',
      duplicate: true,
    });
    assert.deepEqual((await readStoredFile(dataFile)).rollNumbers, ['22A91A0501']);
  });

  // 8
  test('concurrent requests for the same number create exactly one record', async () => {
    const results = await Promise.all(
      Array.from({ length: 40 }, (_, i) =>
        postRollNumber(server.baseUrl, { rollNumber: i % 2 ? '22a91a0599' : '22A91A0599' }),
      ),
    );
    assert.equal(results.filter((r) => r.status === 201).length, 1);
    assert.equal(results.filter((r) => r.status === 200 && r.body.duplicate === true).length, 39);
    assert.deepEqual((await readStoredFile(dataFile)).rollNumbers, ['22A91A0599']);
  });

  // 9
  test('concurrent requests for different numbers are all preserved', async () => {
    const numbers = Array.from({ length: 60 }, (_, i) => `22A91A${String(i).padStart(4, '0')}`);
    const results = await Promise.all(numbers.map((rollNumber) => postRollNumber(server.baseUrl, { rollNumber })));
    assert.ok(results.every((r) => r.status === 201));

    const stored = (await readStoredFile(dataFile)).rollNumbers;
    assert.equal(stored.length, numbers.length);
    assert.deepEqual([...stored].sort(), [...numbers].sort());

    const leftovers = (await fs.readdir(path.dirname(dataFile))).filter((f) => f.endsWith('.tmp'));
    assert.deepEqual(leftovers, [], 'no temporary files should be left behind');
  });

  // 10
  test('existing records survive a service restart', async () => {
    await postRollNumber(server.baseUrl, { rollNumber: '22A91A0501' });
    await postRollNumber(server.baseUrl, { rollNumber: '22A91A0502' });
    await server.close();

    server = await startServer({ dataFilePath: dataFile });

    const again = await postRollNumber(server.baseUrl, { rollNumber: '22A91A0501' });
    assert.equal(again.status, 200);
    assert.equal(again.body.duplicate, true);

    const added = await postRollNumber(server.baseUrl, { rollNumber: '22A91A0503' });
    assert.equal(added.status, 201);

    const { body } = await getJson(`${server.baseUrl}/api/roll-numbers`, adminHeaders);
    assert.deepEqual(body.rollNumbers, ['22A91A0501', '22A91A0502', '22A91A0503']);
  });

  // 11
  test('a corrupt data file is never overwritten and produces 503', async () => {
    const corrupt = '{"rollNumbers": ["22A91A0501", ';
    await fs.mkdir(path.dirname(dataFile), { recursive: true });
    await fs.writeFile(dataFile, corrupt);

    const { status, body } = await postRollNumber(server.baseUrl, { rollNumber: '22A91A0502' });
    assert.equal(status, 503);
    assert.equal(body.code, 'STORAGE_UNAVAILABLE');
    assert.doesNotMatch(JSON.stringify(body), /roll_numbers\.json|nested|tmp/i, 'must not leak paths');
    assert.equal(await fs.readFile(dataFile, 'utf8'), corrupt, 'corrupt file must be left untouched');

    const health = await getJson(`${server.baseUrl}/api/health`);
    assert.equal(health.status, 200);
    assert.deepEqual(health.body.storage, { status: 'error', code: 'STORAGE_CORRUPT' });
  });

  test('a data file with the wrong structure is never overwritten', async () => {
    const wrongShape = JSON.stringify({ rollNumbers: 'not-an-array' });
    await fs.mkdir(path.dirname(dataFile), { recursive: true });
    await fs.writeFile(dataFile, wrongShape);

    const { status } = await postRollNumber(server.baseUrl, { rollNumber: '22A91A0502' });
    assert.equal(status, 503);
    assert.equal(await fs.readFile(dataFile, 'utf8'), wrongShape);
  });

  test('unexpected storage failures return 503 without internal details', async () => {
    await server.close();
    const failingStorage = {
      add: async () => {
        throw new StorageError('STORAGE_IO', 'EACCES: permission denied, open /var/data/roll_numbers.json');
      },
      list: async () => [],
      count: async () => 0,
      checkHealth: async () => ({ ok: false, code: 'STORAGE_IO' }),
    };
    server = await startServer({ dataFilePath: dataFile, storage: failingStorage });

    const { status, body } = await postRollNumber(server.baseUrl, { rollNumber: '22A91A0501' });
    assert.equal(status, 503);
    assert.doesNotMatch(JSON.stringify(body), /EACCES|\/var\/data/);
  });

  test('non-storage exceptions return a generic 500', async () => {
    await server.close();
    const brokenStorage = {
      add: async () => {
        throw new TypeError('secret internal detail');
      },
    };
    server = await startServer({ dataFilePath: dataFile, storage: brokenStorage });

    const { status, body } = await postRollNumber(server.baseUrl, { rollNumber: '22A91A0501' });
    assert.equal(status, 500);
    assert.equal(body.code, 'INTERNAL_ERROR');
    assert.doesNotMatch(JSON.stringify(body), /secret internal detail/);
  });

  // 12
  test('administrative endpoints require the admin key', async () => {
    await postRollNumber(server.baseUrl, { rollNumber: '22A91A0501' });

    for (const url of ['/api/roll-numbers', '/api/roll-numbers/count']) {
      const missing = await getJson(`${server.baseUrl}${url}`);
      assert.equal(missing.status, 401);
      assert.equal(missing.headers.get('www-authenticate'), 'Bearer');
      assert.equal(missing.body.rollNumbers, undefined);

      const wrong = await getJson(`${server.baseUrl}${url}`, { Authorization: 'Bearer wrong-key' });
      assert.equal(wrong.status, 401);
    }

    const list = await getJson(`${server.baseUrl}/api/roll-numbers`, adminHeaders);
    assert.equal(list.status, 200);
    assert.deepEqual(list.body, { success: true, count: 1, rollNumbers: ['22A91A0501'] });

    const count = await getJson(`${server.baseUrl}/api/roll-numbers/count`, adminHeaders);
    assert.deepEqual(count.body, { success: true, count: 1 });
  });

  test('administrative endpoints are disabled when no admin key is configured', async () => {
    await server.close();
    server = await startServer({ dataFilePath: dataFile, env: { ADMIN_API_KEY: '' } });

    const res = await getJson(`${server.baseUrl}/api/roll-numbers`, { Authorization: 'Bearer anything' });
    assert.equal(res.status, 503);
    assert.equal(res.body.code, 'ADMIN_DISABLED');
  });

  test('optional ingestion key is enforced when configured', async () => {
    await server.close();
    server = await startServer({ dataFilePath: dataFile, env: { INGEST_API_KEY: 'ingest-key' } });

    const missing = await postRollNumber(server.baseUrl, { rollNumber: '22A91A0501' });
    assert.equal(missing.status, 401);

    const ok = await postRollNumber(server.baseUrl, { rollNumber: '22A91A0501' }, {
      headers: { 'X-Api-Key': 'ingest-key' },
    });
    assert.equal(ok.status, 201);
  });

  test('registration pattern is configurable', async () => {
    await server.close();
    server = await startServer({
      dataFilePath: dataFile,
      env: { ROLL_NUMBER_PATTERN: '[0-9]{4}/[A-Z]{2}/[0-9]{3}' },
    });

    assert.equal((await postRollNumber(server.baseUrl, { rollNumber: '2022/cs/001' })).status, 201);
    assert.equal((await postRollNumber(server.baseUrl, { rollNumber: '22A91A0501' })).status, 400);
    // The pattern is anchored automatically, so partial matches are rejected.
    assert.equal((await postRollNumber(server.baseUrl, { rollNumber: 'X2022/CS/001' })).status, 400);
  });

  test('write endpoint is rate limited', async () => {
    await server.close();
    server = await startServer({ dataFilePath: dataFile, env: { RATE_LIMIT_WRITE_MAX: '3' } });

    const statuses = [];
    for (let i = 0; i < 5; i += 1) {
      statuses.push((await postRollNumber(server.baseUrl, { rollNumber: `22A91A050${i}` })).status);
    }
    assert.deepEqual(statuses, [201, 201, 201, 429, 429]);
  });

  test('unknown routes return a JSON 404', async () => {
    const { status, body } = await getJson(`${server.baseUrl}/api/unknown`);
    assert.equal(status, 404);
    assert.equal(body.success, false);
  });
});
