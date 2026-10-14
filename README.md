# QR Registration Number Scanner

A Flutter app reads student registration numbers from QR codes, or from
manual entry, and submits them to a Node.js/Express API. The API stores
**only** unique, normalised registration numbers in a JSON file on a
persistent disk.

```
Track-app/
├── track/        Flutter app (Android/iOS)       → track/README.md
├── backend/      Node.js + Express API            → backend/README.md
├── render.yaml   Render Blueprint (web service + persistent disk)
└── README.md     this file
```

Both parts live in one repository so the API contract and the shared
validation pattern change together. Render deploys only `backend/` (via
`rootDir`).

## Architecture

```
 ┌───────────── Flutter app ─────────────┐            ┌──────── Render web service (1 instance) ────────┐
 │ QR camera ─► QrPayloadParser ─┐       │   HTTPS    │ express.json(1kb) ─► rate limit ─► [ingest key] │
 │   (ScanGate dedupes frames)   ├─► RegistrationApiService ──POST /api/roll-numbers──► validate ─► service │
 │ Manual input (uppercase) ─────┘   .submitRegistrationNumber   │      └─► JsonFileStorage (serial queue,   │
 │ Status card + session history       │  GET /api/health      │           temp file + fsync + rename)     │
 └─────────────────────────────────────┘                        └────────── /var/data/roll_numbers.json ────┘
```

### Assumptions and defaults

- **Registration number format:** after trimming and upper-casing, the value
  must match `^[A-Z0-9]{4,20}$` (for example `22A91A0501`). The pattern is
  configurable on both sides: `ROLL_NUMBER_PATTERN` on the server,
  `REG_PATTERN` in the app. The server's check is authoritative. Patterns
  are always applied to the whole value.
- **QR payload:** by default the entire QR text is the registration number.
  Links, JSON, multi-value text and arbitrary text are rejected. JSON
  (`QR_FORMAT=json`) and prefixed (`QR_FORMAT=prefixed`, for example
  `REG:22A91A0501`) formats can be enabled without touching the scanning
  screen.
- **Duplicates:** the server answers 201 for a new number and 200 with
  `duplicate: true` for an existing one. Resubmitting is always safe.

## Commands

```bash
# Backend
cd backend
npm install
npm run dev            # http://localhost:3000 (data in backend/data/, git-ignored)
npm test               # 30 tests on temp files

# App
cd track
flutter pub get
cp env/dev.example.json env/dev.json     # set API_BASE_URL (see table below)
flutter run --dart-define-from-file=env/dev.json
flutter analyze
flutter test
flutter test test/integration/live_api_test.dart --dart-define=LIVE_API_BASE_URL=http://127.0.0.1:3000
```

### API base URL per environment

| App runs on | Local backend | Production |
|---|---|---|
| Android emulator | `http://10.0.2.2:3000` | `https://YOUR-SERVICE.onrender.com` |
| iOS simulator | `http://localhost:3000` | same |
| Physical phone | `http://<PC LAN IP>:3000` (same Wi-Fi, firewall open) or `adb reverse tcp:3000 tcp:3000` + `http://localhost:3000` | same |

The URL is a build-time setting (`--dart-define` /
`--dart-define-from-file`), so switching environments never requires code
changes.

### Sample request

```bash
curl -i -X POST https://YOUR-SERVICE.onrender.com/api/roll-numbers \
  -H "Content-Type: application/json" \
  -d '{"rollNumber":" 22a91a0501 "}'
# 201 {"success":true,"message":"Registration number stored successfully","rollNumber":"22A91A0501","duplicate":false}
# again → 200 {"success":true,"message":"Registration number already exists","rollNumber":"22A91A0501","duplicate":true}
```

## Deployment (Render)

See **[backend/README.md → Deploying on Render](backend/README.md#deploying-on-render)**
for the full guide. In brief:

1. Push this repo to GitHub, then go to Render and choose **New → Blueprint**
   (it uses `render.yaml`).
2. A paid instance type with a **1 GB disk mounted at `/var/data`**, and
   `DATA_FILE_PATH=/var/data/roll_numbers.json`.
3. Keep **one instance**. The file lock is per process.
4. Health check: `/api/health`. Copy the `https://….onrender.com` URL into
   `track/env/prod.json` and build the release app.
5. To verify persistence, POST a test number, redeploy or restart, then POST
   it again. You must get `200` with `"duplicate": true`.

Without a disk, Render's filesystem is ephemeral and every deploy wipes the
file. The backend refuses to start in production unless `DATA_FILE_PATH` (or
`DATA_DIR`) is set explicitly.

## Manual device checklist

Automated tests cover the logic, but not the camera hardware. Before using
the app in the field, check on at least one real Android phone (and an
iPhone, if relevant):

- [ ] First launch asks for camera permission; deny it, and the explanation
      plus "Try again" appear and manual entry still works.
- [ ] A QR code with `22A91A0501` is submitted automatically → "Registration
      stored"; holding it in view does **not** resubmit.
- [ ] Remove the code and show it again after ~3 s → "Already registered".
- [ ] A rotated (90°/180°/45°) and slightly tilted code scans.
- [ ] Near/far distances: use the zoom slider and tap-to-focus for small or
      distant codes; toggle the torch in low light.
- [ ] A URL QR code or a JSON QR code → "Unsupported QR code", with no request.
- [ ] Typed lowercase text appears in uppercase; Submit is disabled while
      sending.
- [ ] Airplane mode → "No network connection", logged as Failed in the
      recent list.
- [ ] Rotate the phone to landscape, and try a small-screen device. Nothing
      overflows, and the keyboard does not hide the input.

## Known limitations

- **Single writer:** the JSON store is safe for concurrent requests within
  one process only. Multiple instances, or other processes writing the same
  file, need a real database.
- **Public ingestion:** the POST endpoint is open unless `INGEST_API_KEY` is
  set, and that key can be extracted from the app. See the security notes in
  `backend/README.md`.
- **Deploy gap:** services with a disk have no zero-downtime deploys, so
  submissions fail briefly (with a clear error) during a redeploy.
- **Network classification is heuristic:** a DNS failure is reported as "No
  network", and a refused connection or 5xx as "Server unavailable". Some
  networks, such as captive portals, can blur the two.
- **A timeout is ambiguous:** the server may have stored the number. The app
  says so, and resubmitting reveals the truth (`duplicate`).
- **Scanning limits:** detection depends on the device camera, focus, lighting
  and print quality. Manual zoom, focus and torch help, but no setting
  guarantees reads at every angle or distance.
- The Android `applicationId` is still `com.example.track`. Change it before
  publishing to Play Store.
