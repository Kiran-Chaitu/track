# Registration Scanner (Flutter)

Scans QR codes that contain student registration numbers and submits them to
the backend automatically. Numbers can also be typed by hand. Both input
paths call the same `RegistrationApiService.submitRegistrationNumber`.

## Run

```bash
cd track
flutter pub get
cp env/dev.example.json env/dev.json      # then edit API_BASE_URL
flutter run --dart-define-from-file=env/dev.json
```

Release build pointing at Render:

```bash
cp env/prod.example.json env/prod.json    # set https://YOUR-SERVICE.onrender.com
flutter build apk --release --dart-define-from-file=env/prod.json
flutter build ipa --release --dart-define-from-file=env/prod.json   # macOS only
```

Single values can also be passed directly:
`flutter run --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com`

`env/*.json` is git-ignored because it may contain the ingestion key; the
`*.example.json` files are committed.

### Which `API_BASE_URL` to use

| Where the app runs | Backend on your PC (`npm run dev`, port 3000) | Deployed backend |
|---|---|---|
| Android emulator | `http://10.0.2.2:3000` (10.0.2.2 is the emulator's alias for the host) | `https://YOUR-SERVICE.onrender.com` |
| iOS simulator | `http://localhost:3000` | same |
| Physical phone on the same Wi-Fi | `http://<your PC's LAN IP>:3000`, e.g. `http://192.168.1.20:3000`; allow port 3000 in the PC firewall | same |
| Physical phone via USB (Android) | run `adb reverse tcp:3000 tcp:3000`, then use `http://localhost:3000` | same |

`localhost` on a phone or emulator means the device itself, not your PC.
Plain `http://` is only allowed in Android **debug** builds (via
`android/app/src/debug/AndroidManifest.xml`) and to local-network hosts on iOS
(`NSAllowsLocalNetworking`). Production must use HTTPS.

If `API_BASE_URL` is missing or invalid, the app still launches. The header
shows **Not configured** and submissions explain how to fix it.

### Build-time settings

| Key | Default | Purpose |
|---|---|---|
| `API_BASE_URL` | — | Backend origin, e.g. `https://x.onrender.com` (no `/api` suffix) |
| `INGEST_API_KEY` | empty | Sent as `X-Api-Key` if set. It is extractable from the app, so it is not a real secret |
| `REG_PATTERN` | `^[A-Z0-9]{4,20}$` | Accepted format after trim + uppercase. Keep it equal to the backend's `ROLL_NUMBER_PATTERN` |
| `REG_MAX_LENGTH` | `64` | Input length cap |
| `REQUEST_TIMEOUT_SECONDS` | `10` | |
| `SCAN_COOLDOWN_MS` | `2500` | How long a code must be out of view before the same code is accepted again |
| `QR_FORMAT` | `plain` | `plain` (whole payload is the number), `json` (object field), `prefixed` (e.g. `REG:22A91A0501`) |
| `QR_JSON_KEY` | `rollNumber` | Field for `QR_FORMAT=json` |
| `QR_PREFIX` | empty | Prefix for `QR_FORMAT=prefixed` |
| `SCANNER_AUTO_ZOOM` | `false` | Android-only ML Kit zoom suggestions |

## How it works

```
lib/
  main.dart                          App + Material 3 theme
  config/app_config.dart             --dart-define configuration, URL building
  controllers/scan_session_controller.dart
                                     Screen state: both input paths → _submit → API service
  models/                            RegistrationResult/Status, ScanRecord, StatusMessage
  screens/scanner_screen.dart        Responsive layout (column on phones, row in landscape)
  services/registration_api_service.dart
                                     The ONE submission method + health check
  utils/registration_validator.dart  trim + uppercase + configurable pattern
  utils/qr_payload_parser.dart       Configurable QR → registration number extraction
  utils/scan_gate.dart               Suppresses repeated detections of a visible code
  utils/upper_case_text_formatter.dart
  widgets/                           qr_scanner_view, registration_input, submission_status,
                                     recent_scans_list, connection_indicator
```

**Submission (`submitRegistrationNumber`)** works as follows:
1. Trim and uppercase the value, then validate it. Invalid input never leaves
   the device.
2. If the same number is already in flight, return that request's future, so
   no second request is sent.
3. POST `{"rollNumber": …}` with a timeout.
4. Map the response:
   - 201 → stored
   - 200 with `duplicate:true` → duplicate
   - 400 → invalid input
   - 401 → unauthorised
   - 429 → rate limited
   - 5xx → server unavailable
   - DNS or unreachable network → network unavailable
   - refused connection → server unavailable
   - timeout → timed out
   - anything that doesn't confirm success → "unexpected response"

   Success is shown **only** when the response body confirms it.
5. Release the in-flight lock in `finally`.

**QR handling:**
- The parser trims and uppercases the payload. In the default `plain` mode it
  rejects links, JSON, multi-value text and anything that fails the pattern,
  so arbitrary QR text is never submitted.
- `ScanGate` lets one detection through at a time. While a code stays in
  view, every new sighting extends its cooldown, so it is not resubmitted.
  It is accepted again only after being out of view for `SCAN_COOLDOWN_MS`.
  A different code goes through as soon as the current request finishes.
- If two QR codes are in the frame at once, nothing is submitted and the app
  asks you to show one at a time.

**Camera (mobile_scanner 7.x):**
- Uses ML Kit on Android and Apple Vision on iOS. Both detect QR codes at
  any in-plane rotation.
- Continuous autofocus by default, plus tap-to-focus.
- Torch toggle, front/back camera switch, and a zoom slider mapped to the
  device's own minimum–maximum zoom range.
- Optional Android auto-zoom.
- The camera stops when the app goes to the background and resumes when it
  returns.
- If camera permission is denied, an explanation and a "Try again" button
  are shown, and manual entry keeps working.

**Recent list:** the last 30 submissions from this device in this session,
held in memory only. Each one is labelled New, Duplicate or Failed. It is
*not* the server's dataset.

## Tests

```bash
flutter analyze
flutter test                       # unit + widget tests (live tests skipped)

# End-to-end against a running backend (writes one random test number):
flutter test test/integration/live_api_test.dart \
  --dart-define=LIVE_API_BASE_URL=http://127.0.0.1:3000
```

| Area | File |
|---|---|
| Uppercase entry, empty input, clear button, disabled while submitting, small-screen layout | `test/widgets/registration_input_test.dart` |
| Validation, configurable pattern | `test/utils/registration_validator_test.dart` |
| QR payload validation (URL/JSON/multi-value rejection, opt-in formats) | `test/utils/qr_payload_parser_test.dart` |
| Repeated-detection suppression | `test/utils/scan_gate_test.dart`, `test/controllers/scan_session_controller_test.dart` |
| Shared API logic: success, duplicate, errors, network failure, timeout, concurrent same-number dedupe | `test/services/registration_api_service_test.dart` |
| Real HTTP against the backend | `test/integration/live_api_test.dart` |

The camera itself cannot be exercised by `flutter test` because it needs a
real device. See "Manual device checklist" in the root README.
