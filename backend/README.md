# Registration Number API (Node.js + Express)

Stores unique, normalised student registration numbers in a single JSON file.
It stores nothing else: no names, emails, phone numbers or images.

- Node.js ≥ 22.12 (Render is pinned to Node 24 LTS via `NODE_VERSION`)
- Express 5, `express-rate-limit`, `helmet`; no database
- Tests use Node's built-in test runner and `fetch`, so there are no test dependencies

## Quick start

```bash
cd backend
npm install
cp .env.example .env        # optional; edit values
npm run dev                 # http://localhost:3000, reloads on change, loads .env
npm test                    # 30 tests, run against temporary files only
npm start                   # production-style start (no .env loading, no watch)
```

In development, data goes to `backend/data/roll_numbers.json` (git-ignored).

## API

All bodies are JSON. Errors always have the shape
`{ "success": false, "code": "<MACHINE_CODE>", "message": "<human text>" }`.

### `POST /api/roll-numbers`

```http
POST /api/roll-numbers
Content-Type: application/json
X-Api-Key: <INGEST_API_KEY>        # only if INGEST_API_KEY is configured

{ "rollNumber": "22a91a0501 " }
```

The server trims the value, upper-cases it and validates it against
`ROLL_NUMBER_PATTERN`. Client-side checks are a convenience; this check is
the authoritative one.

| Result | Status | Body |
|---|---|---|
| New number stored | **201** | `{"success":true,"message":"Registration number stored successfully","rollNumber":"22A91A0501","duplicate":false}` |
| Already stored (nothing appended) | **200** | `{"success":true,"message":"Registration number already exists","rollNumber":"22A91A0501","duplicate":true}` |
| Missing / empty / malformed / too long | 400 | codes `ROLL_NUMBER_REQUIRED`, `ROLL_NUMBER_EMPTY`, `ROLL_NUMBER_INVALID`, `ROLL_NUMBER_TOO_LONG`, `INVALID_JSON`, `INVALID_BODY` |
| Missing/wrong ingestion key | 401 | `UNAUTHORIZED` |
| Body larger than `BODY_LIMIT` (1 kB) | 413 | `PAYLOAD_TOO_LARGE` |
| Not `application/json` | 415 | `UNSUPPORTED_MEDIA_TYPE` |
| Rate limit exceeded | 429 | `RATE_LIMITED` |
| Data file unreadable/corrupt/unwritable | 503 | `STORAGE_UNAVAILABLE` |
| Handler exceeded `REQUEST_TIMEOUT_MS` | 503 | `REQUEST_TIMEOUT` |
| Unexpected bug | 500 | `INTERNAL_ERROR` |

Submissions are **idempotent**: resending a stored number returns
`duplicate: true`. Clients can therefore retry safely after a timeout.

```bash
curl -i -X POST https://YOUR-SERVICE.onrender.com/api/roll-numbers \
  -H "Content-Type: application/json" \
  -d '{"rollNumber":"22A91A0501"}'
```

### `GET /api/health`

Returns `200` whenever the process is running. Storage health is reported
separately, because a running process does not prove the data file is usable:

```json
{ "success": true, "status": "ok", "uptimeSeconds": 42, "storage": { "status": "ok" } }
{ "success": true, "status": "ok", "uptimeSeconds": 42, "storage": { "status": "error", "code": "STORAGE_CORRUPT" } }
```

### Admin: `GET /api/roll-numbers` and `GET /api/roll-numbers/count`

These require `Authorization: Bearer <ADMIN_API_KEY>`. If `ADMIN_API_KEY` is
not set, both return `503 ADMIN_DISABLED`; they are never left open. They have
a stricter rate limit (`RATE_LIMIT_ADMIN_MAX`, default 30/min) to slow
key guessing.

```json
GET /api/roll-numbers        → { "success": true, "count": 2, "rollNumbers": ["22A91A0501", "22A91A0502"] }
GET /api/roll-numbers/count  → { "success": true, "count": 2 }
```

Records are listed in insertion order.

```bash
curl -H "Authorization: Bearer $ADMIN_API_KEY" https://YOUR-SERVICE.onrender.com/api/roll-numbers
```

## Configuration

| Variable | Default | Notes |
|---|---|---|
| `PORT` | `3000` | Render sets this automatically |
| `HOST` | `0.0.0.0` | Binding to all interfaces is required on Render |
| `DATA_FILE_PATH` | `./data/roll_numbers.json` | **Required in production** (or `DATA_DIR`). On Render: `/var/data/roll_numbers.json` |
| `DATA_DIR` | — | Alternative to `DATA_FILE_PATH`; the file name is `roll_numbers.json` |
| `ALLOW_EPHEMERAL_STORAGE` | `false` | Lets production start without explicit storage (data lost on restart) |
| `ROLL_NUMBER_PATTERN` | `^[A-Z0-9]{4,20}$` | Applied after trim + uppercase, always to the whole value. Keep it in sync with the app's `REG_PATTERN` |
| `ROLL_NUMBER_MAX_LENGTH` | `64` | Hard cap checked before the pattern |
| `ADMIN_API_KEY` | — | Enables the admin endpoints. Use 32+ random characters |
| `INGEST_API_KEY` | — | Optional `X-Api-Key` required for POST (see Security) |
| `TRUST_PROXY` | unset | Set to `1` on Render so rate limits apply to real client IPs |
| `RATE_LIMIT_WINDOW_MS` | `60000` | |
| `RATE_LIMIT_WRITE_MAX` | `300` | Per IP per window. Phones on one campus Wi-Fi share an IP, so keep it generous |
| `RATE_LIMIT_ADMIN_MAX` | `30` | |
| `REQUEST_TIMEOUT_MS` | `10000` | |
| `BODY_LIMIT` | `1kb` | |
| `LOG_LEVEL` | `info` | `debug`/`info`/`warn`/`error`/`silent` |

## Storage design

File format (`roll_numbers.json`):

```json
{ "rollNumbers": ["22A91A0501", "22A91A0502"] }
```

- **Serialised access:** every read and write goes through one in-process
  promise queue (`src/storage/serial_queue.js`). Concurrent requests cannot
  interleave a read-modify-write cycle. The tests send 40 parallel requests
  for one number (exactly one is stored) and 60 parallel requests for
  different numbers (all are stored).
- **Validate before modifying:** each write re-reads the file and checks it
  has the `{"rollNumbers": [string, …]}` shape before changing anything.
  Unknown top-level fields are preserved.
- **Atomic writes:** the store writes a temporary file in the same directory,
  `fsync`s it and `rename`s it over the original, then `fsync`s the directory
  on POSIX. A crash leaves either the old file or the new one, never a
  truncated one.
- **Never destroys data:** a missing file is created with the exclusive `wx`
  flag. A file that is unreadable, invalid JSON or the wrong shape is **never
  overwritten**. Writes return `503`, `/api/health` reports
  `storage.status: "error"`, and the server recovers as soon as someone
  repairs the file. The server still starts in this state, so health checks
  stay reachable.

### Limitations (read before scaling)

- The lock is **in-memory and per process**. It does not protect against two
  processes or instances writing the same file. Run **exactly one instance**.
  Render enforces this for services with a disk.
- A JSON file is not a database: there are no transactions across files, no
  point-in-time recovery and no query engine.
- Each operation re-reads the whole file. That is fine for tens of thousands
  of numbers (a 10 000-entry file is about 150 kB). For far more, or for
  multiple instances, move to a real database such as SQLite on the disk or
  Postgres.
- A timed-out request (`503 REQUEST_TIMEOUT`) may still complete its write.
  Because submissions are idempotent, a retry reports `duplicate: true`.

## Deploying on Render

### Ephemeral filesystem vs persistent disk

A Render web service's filesystem is **ephemeral**. Everything written outside
a persistent disk, including anything under the project directory, is lost on
every deploy, restart or instance replacement. Only paths under a **persistent
disk's mount path** survive. Disks are only available on paid instance
types, and a service with a disk:

- cannot scale beyond one instance (correct for this JSON store);
- has no zero-downtime deploys: Render stops the old instance before starting
  the new one, so expect a short gap during each deploy. The app reports
  "Server unavailable" during that gap.

### Option A: Blueprint (uses `render.yaml` in the repo root)

1. Push the repository (containing `backend/`, `track/` and `render.yaml`) to
   GitHub, GitLab or Bitbucket.
2. In Render, choose **New → Blueprint** and select the repository.
3. Review the plan (`starter`), region, and disk (`/var/data`, 1 GB). Set
   `INGEST_API_KEY` if you want one, then click **Apply**.
4. Wait for the deploy to finish. Copy the service URL, e.g.
   `https://roll-number-api.onrender.com`.
5. Open **Environment** to read the generated `ADMIN_API_KEY`.

### Option B: Manual setup

1. **New → Web Service**, then connect the repository.
2. Set **Root Directory** to `backend`, **Runtime** to Node, **Build Command**
   to `npm ci --omit=dev`, **Start Command** to `npm start`, and choose a
   paid instance type.
3. Under **Advanced → Add Disk**, set name `roll-number-data`, **Mount Path**
   `/var/data` and size 1 GB.
4. Under **Advanced → Health Check Path**, enter `/api/health`.
5. Add these environment variables: `NODE_VERSION=24`, `NODE_ENV=production`,
   `DATA_FILE_PATH=/var/data/roll_numbers.json`, `TRUST_PROXY=1`,
   `ADMIN_API_KEY=<random 64 hex chars>`, and optionally `INGEST_API_KEY`.
   You can generate a key with:
   `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`
6. Create the service and wait for **Live**. The URL is shown at the top of
   the service page, and HTTPS is automatic.

### Verify the deployment

```bash
URL=https://YOUR-SERVICE.onrender.com
curl -s $URL/api/health                     # storage.status must be "ok"
curl -s -X POST $URL/api/roll-numbers -H "Content-Type: application/json" \
     -d '{"rollNumber":"TEST0001"}'          # 201 first time
curl -s -H "Authorization: Bearer $ADMIN_API_KEY" $URL/api/roll-numbers/count
```

### Verify records survive a redeploy

1. Note the current count with `GET /api/roll-numbers/count`, then POST a
   test number such as `TEST0001`.
2. In the dashboard, run **Manual Deploy → Deploy latest commit**, or
   **Restart service**.
3. Once the service is Live again, POST `TEST0001` again. It must return
   **200 with `"duplicate": true`**, and the count must be unchanged.
4. If you get `201` instead, the file is not on the disk. Check that
   `DATA_FILE_PATH` starts with the disk's mount path.

The startup log line `Storage ready … count: N` also shows how many records
were loaded.

### Backups

A persistent disk is not a backup. Export the data regularly with the admin
list endpoint (for example, a scheduled `curl` that saves the JSON), and check
your Render plan's disk snapshot and restore options.

## Security notes

- **The POST endpoint is public by default.** Anyone who knows the URL can
  submit syntactically valid numbers. Mitigations in place: strict format
  validation, a 1 kB body limit, per-IP rate limiting, no data echo beyond
  the normalised number, and an optional `INGEST_API_KEY`.
- **The ingestion key is weak.** Any key compiled into a distributed mobile
  app can be extracted from the APK/IPA. It deters casual misuse, nothing
  more. If you need real access control, give each operator a login (for
  example, short-lived tokens issued after signing in) or keep the service
  on a private network or VPN.
- The admin key is compared in constant time and is never logged. Rotate it
  by changing the environment variable and redeploying.
- Responses never include file paths, stack traces or environment values.
  Request logs include the method, path, status and duration only; bodies and
  registration numbers are not logged.
- HTTPS is provided by Render. The app's release builds refuse cleartext
  HTTP on Android by default.
