# SmartInsole Android App (Flutter) — Main Plan (v2)

> Updated 2026-10-17 · Developer: Putanet Wanthanasak (+ Claude Code) · Test phone: Samsung Galaxy Note 10 · Dev machine: Ubuntu (ThinkPad P14s) · Repo: `~/smartinsole-app`
> Source of truth for wire format and thresholds: `docs/DATA-CONTRACT.md` and `docs/BLE-INTERFACE.md` (if this file disagrees with them, they win) · Design: `docs/design/DESIGN-SPEC.md` · Work order: `docs/SESSIONS.md`
> Language rule: every document, prompt, code comment, commit message and report is in **English**. The only Thai text allowed is user-facing UI copy, always quoted as string literals.

---

## 1. Goal and scope

**Goal:** an Android app that shows live data from both insoles. It is used to test the display during the volunteer study. Research data capture stays on the existing web app running on a laptop.

| In v1 | Not in v1 (but the architecture must allow it later) |
|---|---|
| Screens: Home, Gait, Temperature, Alerts, Device connection, Settings, **Daily foot check** | Research capture mode (stays in the web app) |
| Two ESP32 insoles connected at the same time | Background operation / push notifications with screen off |
| All 9 alert codes from the contract | Firebase / cloud sync |
| Rule-based gait estimate + slot for a TFLite model | Real AI model (separate workstream) |
| Local storage (SQLite), including foot photos | AI analysis of foot photos (future work) |
| Meaningful animations | iOS |

---

## 2. Decisions

| Topic | Decision |
|---|---|
| Code location | Same repo; add `mobile/`, `shared/`, `firmware/simulator/` |
| Existing web app | **Frozen.** Used only for data capture on the laptop. Do not modify it unless the user asks because of a bug that affects data capture. |
| ESP32 simulator | **Rewrite from scratch** following `docs/BLE-INTERFACE.md` |
| Primary user | People with diabetes: simple, friendly, not complex |
| UI language | Plain, easy Thai. English only for words with no real Thai equivalent. |
| Colour theme | Clean blue / teal |
| Home status | 3 levels shown to patients (Safe / Be careful / Rest your feet) + No data |
| Risk-level mapping | See section 7 |
| Storage | On-device only |
| Sensor count | App must support a variable number of FSR and NTC channels. Use 6 FSR + 2 NTC per foot for now (NTC may increase to 6 per foot). |
| Risk decision | Contract rules (RuleBasedEngine). Gait result is context only. |
| Daily foot check | 4 photos + 3 questions, no AI, photos stored on device only |
| Study day | The phone app runs alongside the laptop that captures data (so the dual-connection test S3B is required). The photo feature is not used with volunteers, so no feature flag is needed. |
| Foot-check entry point | A card on Home ("today's foot check not done yet"), shown only until today's check is done + an in-app evening reminder |
| Simulator scenario mode (`0x10 SET_SCENARIO`) | Not now; main app first (backlog) |
| Claude Code language | English only for prompts, docs, code, commits, reports |

---

## 3. Repo layout

```
smartinsole-app/
├── (existing web app — frozen)
├── mobile/                  ← Flutter app
│   ├── lib/
│   │   ├── ble/             ← parser, unit conversion, one connection per foot
│   │   ├── device/          ← DeviceManager combining both feet
│   │   ├── rules/           ← 9 alert codes + level 1–5 + mapping to 3 patient levels
│   │   ├── gait/            ← GaitClassifier (rules now / TFLite later)
│   │   ├── footcheck/       ← daily foot check (camera, photos, questions)
│   │   ├── storage/         ← SQLite (drift)
│   │   ├── notify/          ← notification interface (in-app only for now)
│   │   ├── config/          ← thresholds loading
│   │   └── ui/              ← theme, shared motion, screens
│   ├── assets/fonts/        ← IBM Plex Sans Thai + Looped (bundled)
│   └── CLAUDE.md
├── shared/
│   ├── thresholds.json
│   ├── sensor_layout.json
│   └── test_vectors/
├── firmware/simulator/      ← new simulator (PlatformIO, NimBLE)
└── docs/
    ├── FLUTTER-PLAN.md      ← this file
    ├── SESSIONS.md
    └── design/DESIGN-SPEC.md
```

---

## 4. Tooling

| Area | Choice |
|---|---|
| BLE | `flutter_blue_plus` |
| State | Riverpod |
| Database | `drift` (SQLite) |
| Heatmap / charts | `CustomPainter` (no chart library) |
| Animation | Built-in Flutter animation, `flutter_animate`, `animations` (page transitions), `lottie` (only if needed) |
| Camera / photos | `camera`, files stored in the app's private directory |
| Model (later) | `tflite_flutter` in an isolate |
| Keep screen on | `wakelock_plus` |

Check the latest stable version of each package when installing. Fonts must be bundled (no runtime download).

---

## 5. Technical requirements (must match the repo docs)

- **Sensor packet:** 8 samples/packet at 6.25 Hz (= 50 Hz), 200 bytes, little-endian, 8-byte header (`seq`, `t0_ms`, `count`, `flags`)
- **Sample size:** `2N + 12` bytes, N = FSR count from the calibration blob
- **Service UUID:** `f0a5c000-9b4d-4e8a-a3c1-72d6e1b45900` (scan by UUID, not by name)
- **Connect sequence:** connect → `requestMtu(247)` → read status (check `foot_side`) → read calibration → enable notifications → `SYNC_TIME` → `START_STREAM`
- **FSR:** `max(0, adc − offset_adc)` → V → R → `F = a·R^b` → `P = F / A / 1000` (kPa)
- **Temperature:** `raw / 100` °C; `-32768` = could not read

---

## 6. Rules that must never be broken

1. Sample i time = `t0 + i × 20 ms`
2. Staleness is derived from timestamps at read time, never latched by a timer
3. `lastSampleAt` = time the phone received the data
4. Two-foot metrics (ΔT, PAI) are "no data" if either foot is missing
5. "No data" must always look different from "Safe" (never green)
6. ΔT must exceed the threshold on 2 consecutive readings
7. 200 kPa peak alerts only while walking
8. Wrong foot side → reject the connection
9. Drop a stale packet left over from a previous connection
10. 50 Hz processing path is separate from the 10 Hz display path
11. Gait result is not a risk level
12. Thresholds are read from `thresholds.json`, never hardcoded
13. Every alert carries plain-Thai advice
14. **The app never says a foot is "normal" from a photo.** Only the user's answers count, and "not sure" counts as abnormal.
15. **Foot photos stay on the device.** Never send them anywhere unless the user explicitly does so.
16. **Respect the system "reduce motion" setting** — disable animations when it is on.

---

## 7. Risk-level mapping (internal 1–5 → what the patient sees)

| Situation | Patient sees |
|---|---|
| No rule triggered | Safe |
| Level 1 `DEVICE_LOST` | No data (grey) |
| Level 1 `BATTERY_LOW` | Status unchanged; battery label turns orange |
| Level 2 | Safe + orange dot on the foot map (no push alert) |
| Level 3 | Be careful |
| Level 4–5 | Rest your feet |

Levels 1–5 are still stored internally for reporting and for expert review.

---

## 8. Animation

**Global rules:** most animations 200–400 ms · no fast flashing · disabled when "reduce motion" is on · 10 Hz updates must not stutter · all durations and curves live in one shared file.

| Session | Screen | Animation |
|---|---|---|
| S1B | All | Material page transitions |
| S5 | Home | Status card colour cross-fade, foot-dot colour tween, slow pulse ring on "high" dots, numbers counting to new values, cards sliding up on open |
| S6B | Temperature | Chart line draws in |
| S6B | Alerts | Cards slide in; bell wiggles on new alert |
| S8A | Gait | Left/right bar slides to value |
| S8B | Connection | Scanning ripple; check mark on success |
| S8C | Foot check | Self-timer countdown; captured photo slides in |

---

## 9. Daily foot check

- **Why:** the insole only measures under the sole. Ulcers from shoe friction and accidents (top of foot, toe tips) must be checked visually.
- **Flow (~1 minute):** evening reminder → 4 guided photos (sole/top × left/right) → compare with yesterday → 3 questions ("none" / "yes or not sure") → if any "yes", show advice and log an alert
- **Options:** answer questions only (no photos), 3-second self-timer, skip a photo
- **Entry:** Home card shown until today's check is done + in-app evening reminder
- **Privacy:** photos in the app's private folder, deletable, never synced
- **IRB:** not used with study volunteers
- **Medical advice text:** must be reviewed by a medical expert before real use

---

## 10. Future work (not now, but keep the architecture ready)

| Feature | What exists now |
|---|---|
| Background operation / push alerts | BLE, rules, storage independent of UI; `Notifier` interface |
| Firebase | Storage behind a repository pattern |
| TFLite model | `GaitClassifier` interface + `assets/models/` |
| New sensor counts | Read from calibration + `sensor_layout.json` |
| AI on foot photos | Photos stored as a standard 4-view set |
| Move capture mode from web to app | After the November data collection |
| Personal temperature baseline | Per-site ΔT history already stored |
| Simulator scenario mode (`0x10 SET_SCENARIO`) | Simulator data generation kept in separate functions |

---

## 11. External dependencies

| From | Need | Before session |
|---|---|---|
| Phumirapee (hardware) | Final FSR/NTC count and positions; how many NTC the PCB supports | Not blocking (use current values) |
| Putanet | Two ESP32 boards + PlatformIO installed | S2B |
| Putanet | Approval of the remaining 5 screen designs | S6B |
| Medical expert | Review of advice text | S9 |
| AI team | `model_a.tflite` + `normalization.json` | Not blocking |
