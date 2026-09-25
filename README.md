# RM Pulse Installer — JSON-driven mobile app (Radar engine)

A **config-driven** field-installation app for RM Arts, built on the **Radar**
architecture (Appilary Technologies): one static Flutter build whose theme,
text, forms, validations, feature flags **and geofencing** are all controlled
by a JSON config served from a backend. Change the JSON → the app changes, with
no rebuild.

It combines two specs:

- **Radar** — dynamic survey/form engine driven by JSON (`optype` controls,
  `vtype` validations, skip logic, theme/fonts/logo/header buttons, offline
  storage & upload).
- **RM Pulse** — offline-first installer capture: live-camera-only photos,
  9-layer GPS authenticity, IMEI/device-bound login, multi-language, and
  **geofencing with a hard block** when outside an active zone.

```
rm_pulse/
├── app/          Flutter mobile app (the JSON renderer)
├── backend/      Node/Express config API + live web editor
└── README.md
```

---

## 1. What is controllable from JSON

Everything below lives in `backend/data/config.json` and is editable live from
the web editor. The app fetches it on launch and caches it offline.

| Area | JSON path | Effect |
|---|---|---|
| Theme colours | `appConfig.themeConfig` | Header/background/text colours |
| Fonts | `appConfig.fontsConfig` | Font family & sizes |
| Logo / splash | `appConfig.logoConfig` | Branding assets |
| Header buttons | `appConfig.buttons` | Show/hide Home, Upload, Settings, Report, Tasks |
| API endpoints | `appConfig.apiUrls` | Where survey/media/config go |
| Feature flags | `appConfig.featureConfig` | Live-camera-only, offline sync, device binding, GPS authenticity + accuracy limit, block mock/rooted |
| **Geofencing** | `appConfig.geoConfig` | Global on/off, enforcement mode, default radius, periodic tagging interval, and per-zone `lat/lng/radiusMeters/active` |
| Languages & strings | `appConfig.languageConfig` + `strings` | 8 languages, all UI text |
| Survey forms | `appForms[]` | Pages and controls (see below) |

### Geofencing (hard block)

`geoConfig` drives it entirely:

```jsonc
"geoConfig": {
  "active": 1,                 // master on/off
  "enforcement": "block",      // block | warn | off
  "defaultRadiusMeters": 250,  // fallback limit
  "periodicTaggingSeconds": 60,// background geo-tag interval (Radar Phase 2)
  "zones": [
    { "id":"z1", "name":"Shirur", "lat":18.8267, "lng":74.3736, "radiusMeters":300, "active":1 }
  ]
}
```

When `active=1` and `enforcement="block"`, a capture is **blocked** unless the
installer's GPS fix is inside the radius of at least one **active** zone. Turn a
zone off with `"active":0`, change its `radiusMeters` to widen/narrow the limit,
or set `geoConfig.active:0` to disable geofencing globally — all from JSON.

### Survey controls (`optype`) implemented

Label (0), Radio (1), Checkbox (2), Rating (3), Input+validation (4),
Dropdown (5), **Image upload – live camera (6)**, Date (7), Time (8),
Grid (13), Dependent dropdown (23), Toggle (25), Chips single/multi (26/27).
Phase-2/3 types (video, signature, barcode/QR, webview, voice…) parse from JSON
and render a "planned" placeholder, so the config can already reference them.

### Validations

All 20 `vtype` regex families from the Radar appendix (name, email, mobile,
pincode, number, percentage, etc.) plus `mn` (mandatory), `len` (length range),
`min`/`max`, and `dtype` (keypad). Skip logic (`skipFlag`/`skipLogic`) on
radio/checkbox jumps to a target page.

---

## 2. Run the backend + web editor

```bash
cd backend
npm install
npm start          # http://localhost:4000
npm test           # end-to-end smoke test (all endpoints)
```

Open **http://localhost:4000/** — a live editor with a phone preview. Edit the
JSON on the left, watch the preview update, click **Save to server**. The
version auto-bumps so devices pick up the change on their next refresh.

Endpoints: `GET/PUT /api/config`, `POST /api/auth/request-otp`,
`POST /api/auth/verify-otp`, `POST /api/survey/upload`, `POST /api/media/upload`,
`GET /api/stats`, `GET /api/lookup/creatives`.
(Demo OTP is `123456`.)

---

## 3. Run the Flutter app

The `app/lib` source is complete. Platform folders (android/ios) are generated
by Flutter — this repo ships the Dart code + assets, not the generated shells.

```bash
cd app
flutter create .          # generates android/ ios/ using pubspec name
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000   # Android emulator
```

- `10.0.2.2` is the emulator's alias for your host machine. On a physical
  device use your machine's LAN IP (e.g. `http://192.168.1.10:4000`).
- If the backend is unreachable, the app runs on the **bundled** config
  (`assets/config/default_config.json`) and everything except live upload works.

### Required Android permissions

After `flutter create .`, add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

Set `minSdkVersion 21` (camera plugin requirement). Note: the "support Android
4.4 KitKat" line in the Radar doc predates current plugin baselines; the
camera/geolocator plugins require API 21+.

---

## 4. Architecture (app)

```
core/
  config/app_config.dart      AppEnv boot constants (fallback)
  models/                     AppConfig, survey (Control/OpType/Validations), GPS, SurveyResponse
  services/
    remote_config_service     fetch JSON, cache offline, bundled fallback
    validation_service        20 vtype regexes + mandatory/len/min/max
    location_service          GPS capture + 9-layer authenticity
    geofence_service          hard-block evaluation vs JSON zones
    device_service            device binding id + root/emulator detection
    auth_service              OTP + device-bound login (secure storage)
    local_store               SQLite offline outbox + duplicate-hash log
    sync_service              drains outbox on timer / connectivity
  localization/app_strings    resolves text from JSON per active language
features/
  auth, bootstrap, home, site (survey runner + camera + summary), home/upload
```

Flow: **Splash → (cache/bundled config loads) → Login (OTP + device bind) →
Home (feature flags, geofence status, header buttons — all from JSON) → Start →
GPS + geofence hard-block gate → dynamic survey pages → summary → queue offline
→ auto-sync.**

---

## 5. Notes for production

- **Device id / IMEI:** raw IMEI is blocked on Android 10+. The app binds to a
  stable device identifier and sends it as `imei` for backend compatibility.
  Swap in your own hardware-attestation scheme if stricter binding is required.
- **Auth/tokens** are demo-grade (in-memory OTP, demo token). Wire to your SMS
  gateway and JWT issuer.
- **Storage** is in-memory on the backend; move config + submissions to a DB.
- The dependent-dropdown `dataUrl` hook exists; wire it to live lookups
  (`/api/lookup/creatives?parent=…`) to replace the placeholder options.
```
