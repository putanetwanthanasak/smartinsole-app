# Smart Insole for Proactive Diabetic Foot Ulcer Monitoring

> Development of a Smart Insole Featuring Pressure and Skin‑Temperature Sensor
> Fusion for Proactive Diabetic Foot Ulcer Monitoring — senior capstone project,
> Media Technology, KMUTT.

![status](https://img.shields.io/badge/status-in%20development-orange)
![language](https://img.shields.io/badge/TypeScript-5.9-3178c6)
![build](https://img.shields.io/badge/bundler-Vite%208-646cff)
![runtime](https://img.shields.io/badge/network-offline--first-2ea44f)
![tests](https://img.shields.io/badge/tests-none-lightgrey)

A wearable system that pairs a **6‑point plantar‑pressure sensor array** and
**skin‑temperature sensing** in each of two insoles, streams the data over
Bluetooth Low Energy, and surfaces early biomechanical and thermal warning signs
of diabetic foot ulcers in a companion mobile app — before visible tissue
damage appears.

**This repository contains the companion app only** (`smart-insole-app`): a
Thai‑language, single‑page front‑end that visualizes the two insoles' data and
raises threshold‑based alerts. The insole firmware, the BLE simulator, and the
machine‑learning models are separate efforts described in
[`docs/DATA-CONTRACT.md`](docs/DATA-CONTRACT.md) and are **not** part of this
repo (see [Related components](#related-components-not-in-this-repository)).

---

## Table of contents

- [Project status](#project-status)
- [What the app does](#what-the-app-does)
- [Implemented features](#implemented-features)
- [Tech stack](#tech-stack)
- [Getting started](#getting-started)
- [Folder structure](#folder-structure)
- [Documentation](#documentation)
- [Team](#team)
- [Disclaimer](#disclaimer)

---

## Project status

**In active development. Human‑subject data collection has not started.**
The 30‑participant gait study in
[`docs/SmartInsole_TestProtocol_v1.md`](docs/SmartInsole_TestProtocol_v1.md) is
still a draft pending ethics‑committee (IRB) approval, and there is no
fabricated PCB hardware yet — an ESP32‑C3 BLE simulator stands in for the real
insoles.

Work happens one pass at a time on `work/<topic>` branches, merged into `main`
via reviewed pull requests (PR #1–#12 at the time of writing). Each pass is
written up in [`docs/reports/`](docs/reports/) (`001`–`017`).

| Area | State | Evidence |
|---|---|---|
| Single‑page app shell + hash router (5 patient screens) | **Done** | `src/ts/router.ts`, `index.html` |
| Offline build (fonts + icons bundled, zero runtime network calls) | **Done** | `src/ts/main.ts`, `src/ts/icons.ts` |
| Mock data layer (`IDataSource` → `DeviceManager` → screens) | **Done** | `src/ts/data/`, reports `003`–`006` |
| Home / Temperature / Alerts / Settings wired to live (mock) data | **Done** | `docs/PROGRESS.md` §5–6 |
| `AlertStore` — real alerts from threshold crossings | **Done** (3 of the contract's 9 alert codes) | `src/ts/data/AlertStore.ts`, reports `016`–`017` |
| Runtime‑loadable `thresholds.json` + validation | **Done** | `src/ts/data/thresholds.ts`, `public/thresholds.json`, report `017` |
| Gait screen | **Partial** — PAI is a real rolling‑window metric; classifier, CoP trajectory and 7‑day trend show an explicit "not available" state | `src/ts/gait.ts`, report `003`/`004` |
| Research Capture mode (`#/capture`, operator‑only) | **Done** — verified against the mock source; real‑hardware run pending | `src/ts/capture.ts`, report `010` |
| `WebBleDataSource` (Web Bluetooth, ESP32 simulator) | **Implemented, experimental** — dev‑only `?ds=ble` switch; full end‑to‑end verification against the simulator still listed as pending in `CLAUDE.md` | `src/ts/data/WebBleDataSource.ts`, reports `005`–`009`, `013`–`015` |
| CNN‑LSTM gait classifier / risk‑fusion model | **Not started** (out of scope for this repo) | `docs/BACKLOG.md` items 8–9 |
| Capacitor Android packaging | **Not started** | `CLAUDE.md` "Next phase" |

---

## What the app does

The system models **two independent BLE peripherals** — one insole per foot —
so one side can be connected while the other is absent, stale, or errored, and
the UI always says which. All sensor data reaches the screens through a single
abstraction (`src/ts/data/`) so the source can be swapped (mock ↔ Web
Bluetooth ↔ future native plugin) without touching UI code.

The UI is bilingual: **Thai primary, English secondary**, on every label. It is
built to run fully **offline** (a requirement for the eventual Capacitor build)
— all fonts and icons are bundled and the app makes no external network
requests at runtime.

Screens (hash routes):

| Route | Screen | Content |
|---|---|---|
| `#/home` | Dashboard | Per‑side connection state, derived risk badge, hand‑rolled SVG pressure heatmap, forefoot ΔT tile |
| `#/gait` | Gait analysis | Peak Asymmetry Index (PAI) rolling‑window metric; other sections show an explicit unavailable state |
| `#/temp` | Temperature | Forefoot ΔT hero, bilateral foot map, 24‑hour trend chart (draws real gaps for missing data) |
| `#/alerts` | Alert log | Timestamped alerts from `AlertStore`, grouped by day, with Thai advice text and an acknowledge action |
| `#/settings` | Settings | Live per‑side device rows (state / battery / firmware), profile, language toggle; sensitivity slider and PDF export are present but inert |
| `#/capture` | Research capture (operator‑only, not a tab) | Subject entry → 30 s calibration → per‑pattern recording → CSV/JSON export for the planned gait study |

---

## Implemented features

Everything below exists in the code today.

### App shell

- Single `index.html` shell (status bar · persistent header · `#view` · tab
  bar) with a hash router (`src/ts/router.ts`). Each screen is a module
  exporting `mount()` / `unmount()`; section scaffolding lives in the router's
  `*_TEMPLATE` constants.
- Fonts (`@fontsource` — Noto Sans Thai, Inter, JetBrains Mono) and a curated
  Lucide icon subset are imported from npm and bundled — no CDN, no runtime
  fetches.

### Data seam (`src/ts/data/`)

- **`IDataSource`** — one instance per foot.
- **`MockDataSource`** — streams synthetic samples at **50 Hz** from the four
  `PRESETS`, with a simulated connect delay and per‑zone jitter clamped inside
  each value's colour band so noise never crosses a tier boundary.
- **`DeviceManager`** — the one place that:
  - converts the wire format's indexed `fsrKpa[6]` to the UI's name‑keyed
    `FootPressure` via `FSR_CHANNEL_ORDER`;
  - coalesces two 50 Hz push streams into one throttled **10 Hz**
    `CombinedSnapshot`, on a **reference‑counted** timer (runs only while a
    screen is subscribed);
  - derives per‑side staleness by **comparing timestamps at read time** (never a
    latched timer — Chrome throttles background‑tab timers), using sample
    *arrival* time, not the device clock;
  - computes forefoot **ΔT only when both feet are usable** and both report a
    good‑quality reading — otherwise `null`;
  - keeps a per‑side temperature ring buffer (10‑minute buckets, 24‑hour span)
    for the trend chart;
  - exposes an **unthrottled `onRawSample`** (up to 50 Hz/side) for code that
    needs to *measure* the signal rather than display it (PAI, research
    capture).
- **`AlertStore`** — subscribes at module load and runs regardless of the
  active screen. Generates real alerts from threshold crossings:
  - `PRESSURE_WATCH` (any zone over the watch tier),
  - `PRESSURE_PEAK` (over the alert tier **and** an accel‑magnitude "walking
    gate" indicates the user is walking — otherwise it degrades to the watch
    tier),
  - `TEMP_DELTA` (ΔT over threshold on **two consecutive measurements**, keyed
    to the underlying temperature sample so 10 Hz ticks don't over‑count),
  - the Data Contract §8.3.1 **gait‑pattern advisory** layer (appends
    explanatory Thai text to a pressure alert when a gait prediction is
    available and confident — never raises an alert on its own),
  - 30‑minute per‑code repeat suppression.
  - *Not yet implemented:* the contract's other alert codes — `PRESSURE_PTI`,
    `ASYMMETRY_PEAK`, `LOAD_CONCENTRATION`, `DEVICE_LOST`, `BATTERY_LOW` (see
    `docs/BACKLOG.md` item 9).

### Screens

- **Home** — SVG heatmap (`src/ts/heatmap.ts`) built once then mutated in place
  (no `innerHTML` rebuild at 10 Hz); mock preset switcher; explicit "no data"
  states distinct from "all clear".
- **Temperature** — ΔT hero, two‑zone bilateral foot map, 24‑hour SVG trend
  chart that breaks the line on a missing bucket instead of interpolating.
- **Alerts** — real, timestamp‑based entries; day bucketing derived from the
  timestamp; working acknowledge button.
- **Settings** — device rows read live `DeviceStatus` (connection state,
  battery, firmware).
- **Gait** — **PAI** (`|L−R| / avg(L,R) × 100`) computed over a rolling 2 s
  window off the raw 50 Hz stream, only while both feet are usable; window
  length is a single named constant for a future swap to stride segmentation.
  Classifier card, CoP trajectory and 7‑day trend are explicit unavailable
  states (no classifier / no CoP computation / no trend source exists).

### Runtime‑loadable thresholds

- `constants.ts` holds compiled‑in `DEFAULT_THRESHOLDS`; every threshold export
  is a live binding.
- `data/thresholds.ts` fetches `public/thresholds.json` at boot
  (fire‑and‑forget), validates every field and cross‑field relationship, and on
  **any** failure logs a specific error and falls back to the bundled defaults
  — never `undefined`, never a partial merge.
- The two hard clinical floors (`PRESSURE_ALERT_KPA` 200 kPa,
  `TEMP_DELTA_THRESHOLD` 2.2 °C) can only be written through the trusted loader;
  the (not‑yet‑built) patient sensitivity control has a narrow API that
  structurally cannot reach them.

### Research capture mode (`#/capture`)

Operator tool for the planned 30‑participant study — not linked from the
patient UI:

- subject entry (random code only — never name/ID, per ethics requirement);
- 30 s session calibration (both feet required), with a sanity review step;
- per‑pattern recording (`normal`, `antalgic`, `toe_walking`, `heel_walking`,
  `rotated_foot`) from the **50 Hz raw stream**, batched to IndexedDB every 1 s;
- mark‑segment‑invalid toggle, per‑pattern progress, storage‑quota warning;
- **interrupted‑session recovery** on reload (resume or export what exists);
- export to CSV (fixed schema) + metadata JSON.

Verified end‑to‑end at 50.1 Hz/side against `MockDataSource`; a real‑hardware
run is documented but not yet performed (report `010` §8).

### Web Bluetooth data source (experimental)

`src/ts/data/WebBleDataSource.ts` is a real `IDataSource` for the ESP32
simulator / hardware: GATT connect, MTU 247, `START_STREAM`, `SYNC_TIME` with
5‑minute resync, 200‑byte sensor‑packet parsing, calibration‑blob read, and
ADC→kPa scaling (with the `offset_adc` subtraction and Pa→kPa fixes from
reports `006`/`008`). It is **dev‑only**, enabled with `?ds=ble` in the URL,
and paired through an on‑screen dev panel (`src/ts/devBlePanel.ts`). It is not
the default path, and `CLAUDE.md` still lists full simulator integration as the
next major phase.

---

## Tech stack

Read from `package.json`, `tsconfig.json`, and `SETUP.md`.

| Area | Technology |
|---|---|
| Language | **TypeScript** `^5.9.3` — `strict`, `noEmit`, `target: ES2020`, `moduleResolution: "bundler"` |
| Dev server & bundler | **Vite** `^8.2.2` (serves `.ts` directly in dev; `tsc --noEmit && vite build` for production) |
| UI | Vanilla DOM + hand‑rolled inline **SVG** — no UI framework, no charting library |
| Icons | **lucide** `^1.33.0` (curated subset, bundled) |
| Fonts | **@fontsource** `^5.3.0` — `noto-sans-thai`, `inter`, `jetbrains-mono` (bundled) |
| Persistence | **IndexedDB** (research‑capture sessions) |
| Connectivity | **Web Bluetooth** — dev‑only BLE data source |
| Backend | None |
| Tests / linter | None configured |
| Node | ≥ 20 (per `SETUP.md`) |

There is no runtime dependency beyond Lucide and the three font packages, and
all of them are bundled.

### Related components (not in this repository)

Described in [`docs/DATA-CONTRACT.md`](docs/DATA-CONTRACT.md) (v1.5) and
`CLAUDE.md`; referenced here so their existence isn't lost. **None of this code
is in this repo.**

- **ESP32‑C3 insole firmware** and an **ESP32 BLE simulator** — a PlatformIO
  project using NimBLE‑Arduino 2.x, advertising as `SMARTINSOLE-L` /
  `SMARTINSOLE-R`. Reported as flashed and verified.
- **A standalone single‑file Web Bluetooth test page** — reported working end
  to end against the simulator.
- **Planned system architecture** (per the Data Contract, not yet built):
  React Native app · SQLite · on‑device TFLite models (Model A — CNN‑LSTM gait
  classifier; Model B — dual‑branch pressure/temperature risk fusion) ·
  Firebase for summaries and alerts · a Capacitor wrapper to ship this app on
  Android.

---

## Getting started

### Prerequisites

- **Node.js ≥ 20** (ships with `npm`).

```bash
node --version
npm --version
```

### Install

```bash
npm install
```

Downloads the dev dependencies (TypeScript, Vite) and the bundled runtime
dependencies (Lucide, `@fontsource`). Run once after cloning.

### Run (development)

```bash
npm run dev
```

Starts the Vite dev server, normally at <http://localhost:5173>, with hot module
replacement. Vite serves the TypeScript in `src/ts/` directly — **there is no
separate build step while developing**.

Every screen has its own address:

- <http://localhost:5173/#/home>
- <http://localhost:5173/#/gait>
- <http://localhost:5173/#/temp>
- <http://localhost:5173/#/alerts>
- <http://localhost:5173/#/settings>
- <http://localhost:5173/#/capture> — operator research‑capture screen

### Type‑checking

Vite strips types without checking them, so type errors do **not** stop the dev
server:

```bash
npm run typecheck   # tsc --noEmit, once
npm run watch       # tsc --noEmit --watch, alongside npm run dev
```

### Production build

```bash
npm run build     # tsc --noEmit && vite build  → dist/   (fails on any type error)
npm run preview   # serve the built dist/ output
```

`dist/` is generated output — gitignored, never edited or committed.

### Running against the ESP32 BLE simulator (optional, dev‑only)

The simulator firmware is **not in this repository** — it is a separate
PlatformIO / NimBLE‑Arduino project (see
[Related components](#related-components-not-in-this-repository)). With that
device already flashed and advertising:

1. `npm run dev`, then open **`http://localhost:5173/?ds=ble#/home`** in Chrome
   (Web Bluetooth requires a Chromium‑based browser).
2. Use the dev BLE panel to pair **LEFT**, then **RIGHT** — Web Bluetooth
   requires a separate user gesture per device, so this is two prompts.
3. Once both show connected, every screen behaves as it does with the mock
   source.

See [`docs/BLE-TEST-CHECKLIST.md`](docs/BLE-TEST-CHECKLIST.md) for the
hardware‑verification steps.

### Scripts

| Command | What it does |
|---|---|
| `npm install` | Install dependencies (run once after cloning) |
| `npm run dev` | Start the Vite dev server with HMR |
| `npm run build` | Type‑check, then bundle to `dist/`; fails on any type error |
| `npm run preview` | Serve the built `dist/` output |
| `npm run typecheck` | `tsc --noEmit` once |
| `npm run watch` | `tsc --noEmit --watch` |

There is no test runner and no linter.

---

## Folder structure

```
smart-insole-app/
├── index.html               SPA shell: status bar · persistent header · #view · tab bar
├── package.json              Scripts and dependencies
├── tsconfig.json             Type‑check‑only config (noEmit); Vite does the transform
├── CLAUDE.md                 Engineering handoff for contributors (read this first)
├── SETUP.md                  Install / run / build guide
├── detail.md                 Historical pre‑refactor code survey (kept for the "why")
│
├── public/
│   └── thresholds.json       Runtime‑loadable clinical thresholds (Data Contract §8.3)
│
├── src/ts/                   All application code
│   ├── main.ts               Entry: import fonts, start router, connect devices once, load thresholds
│   ├── router.ts             Hash router + each screen's section scaffolding (*_TEMPLATE)
│   ├── home.ts               Dashboard screen (mount/unmount)
│   ├── gait.ts               Gait screen — PAI metric + unavailable states
│   ├── temperature.ts        Temperature screen
│   ├── alerts.ts             Alert‑log screen
│   ├── settings.ts           Settings screen
│   ├── capture.ts            Operator‑only research‑capture screen (#/capture)
│   ├── capture/              Recorder, IndexedDB store, CSV/JSON builders, capture types
│   ├── heatmap.ts            SVG pressure‑heatmap component (build‑once‑then‑mutate)
│   ├── navigation.ts         Bottom tab bar + faux iOS status bar
│   ├── icons.ts              Curated Lucide icon set (USED_ICONS) + refreshIcons()
│   ├── pressureColor.ts      kPa → colour / severity / bilingual advice (pure functions)
│   ├── constants.ts          Thresholds, zone geometry, status metadata, FSR channel order
│   ├── types.ts              UI‑facing types
│   ├── mockData.ts           MOCK_DATA + the four pressure PRESETS
│   ├── devBlePanel.ts        Dev‑only two‑device BLE pairing panel
│   └── data/                 The data seam — "where data comes from" vs "what the UI renders"
│       ├── IDataSource.ts        Per‑foot source interface
│       ├── MockDataSource.ts     50 Hz synthetic stream from PRESETS
│       ├── WebBleDataSource.ts   Web Bluetooth source (dev‑only, ?ds=ble)
│       ├── bleProtocol.ts        BLE UUIDs, opcodes, timing constants
│       ├── blePacketParser.ts    Wire‑format parsing + ADC→kPa scaling
│       ├── webBluetooth.d.ts     Web Bluetooth type declarations
│       ├── DeviceManager.ts      Owns both feet: throttle, staleness, ΔT, temp history
│       ├── AlertStore.ts         Real alerts from threshold crossings
│       ├── gaitPrediction.ts     Seam for Model A output (mock only today)
│       ├── thresholds.ts         Fetch + validate public/thresholds.json
│       └── types.ts              Wire types + snapshot vocabulary
│
├── css/                      global + components + one stylesheet per screen
├── pages.reference/          Dead pre‑SPA HTML, kept only as a visual reference
│
└── docs/
    ├── DATA-CONTRACT.md              Cross‑team BLE wire format + clinical thresholds (v1.5)
    ├── BLE-INTERFACE.md              BLE extract for the WebBle implementer
    ├── BLE-TEST-CHECKLIST.md         Hardware verification checklist
    ├── SmartInsole_TestProtocol_v1.md  30‑participant human‑subject protocol (draft)
    ├── PROGRESS.md                   Pass‑by‑pass history and reasoning
    ├── BACKLOG.md                    Deferred work, with context to act on each item
    └── reports/                      One report per work pass (001–017)
```

---

## Documentation

- **[`CLAUDE.md`](CLAUDE.md)** — the engineering handoff: architecture, the data
  seam, and the conventions that have each already caused a bug (cleanup
  discipline, subscribe/unsubscribe, no `innerHTML` rebuild at 10 Hz,
  read‑time staleness, thresholds live in one place, the "no fabricated
  bilateral readings" safety rule).
- **[`docs/DATA-CONTRACT.md`](docs/DATA-CONTRACT.md)** — the authoritative
  cross‑team spec (v1.5): BLE advertising/GATT, packet formats, unit
  conversions, model interfaces, and every alert rule and threshold.
- **[`docs/SmartInsole_TestProtocol_v1.md`](docs/SmartInsole_TestProtocol_v1.md)**
  — the planned 30‑participant gait‑data protocol (draft, pending ethics
  approval).
- **[`docs/PROGRESS.md`](docs/PROGRESS.md)** / **[`docs/BACKLOG.md`](docs/BACKLOG.md)**
  — what's been done and why, and what's deliberately not done yet.
- **[`docs/reports/`](docs/reports/)** — a dated report for every work pass.

---

## Team

Per project documentation:

- **Putanet Wanthanasak** (ภูธเนศ วรรธนะศักดิ์)
- **Phumraphi Boonthai** (ภูมิรพี บุญไทย)

**Academic advisor:** Dr. Patiyuth Pramkaew

Media Technology Program, Faculty of Architecture and Design, King Mongkut's
University of Technology Thonburi (KMUTT).

---

## Disclaimer

This is an **academic research project**, not a certified or regulator‑approved
medical device. It has **not** been clinically validated, and it has not been
tested on people with diabetes in this phase. Nothing here is intended for
clinical, diagnostic, or treatment use. The clinical thresholds in the code are
drawn from published literature and internal team agreement and are explicitly
marked as provisional pending validation against real hardware and study data.

No license file is present in this repository; treat the contents as
all‑rights‑reserved by the authors and KMUTT unless stated otherwise.
