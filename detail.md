# SmartInsole Mockup — Pre-Refactor Survey

> **Historical document — do not treat as current. Noted 2026-08-21.**
>
> This is a point-in-time survey of the codebase as it stood on 2026-08-20, **before** the
> SPA refactor and **before** Vite was introduced. Since then the app has moved to a single
> `index.html` shell with a hash router (`src/ts/router.ts`), the per-screen pages have been
> retired to `pages.reference/`, the build has moved from bare `tsc` to Vite, and the
> pressure pipeline has been converted from a 0–100 index to kPa with two thresholds.
>
> **Every line number below is stale, and several described structures no longer exist.**
> Its value is as a record of what the code looked like before any of that, and of the
> reasoning that motivated the changes. Read it for the "why", not for addresses.

Read-only reconnaissance of the existing UI mockup, carried out before introducing the
`IDataSource` abstraction. No code was modified.

**Surveyed folder:** `smart-insole-app/` (the working directory)
**Date:** 2026-08-20

---

# 1. FILE INVENTORY

**Build setup:** plain `tsc`, no bundler. `package.json:6-7` defines only `build: "tsc"` and
`watch: "tsc --watch"`; the sole devDependency is `typescript@^5.9.3` (`package.json:9-11`).
`tsconfig.json` emits `ES2020` ES modules from `src/ts/` to `dist/js/` with
`moduleResolution: "bundler"` and `strict: true`. Each HTML page loads its compiled entry with
`<script type="module" src="../dist/js/<page>.js">` plus a CDN `<script src="https://unpkg.com/lucide@latest">`
(e.g. `pages/home.html:39,42`). No Vite/Webpack/Rollup config, no linter, no test runner
(`SETUP.md:105` confirms this explicitly). Fonts come from a Google Fonts `@import` at
`css/global.css:5`.

## TypeScript source (`src/ts/`)

| File | Lines | What it does |
|---|---|---|
| `types.ts` | 101 | All shared interfaces: `FootPressure`, `PressureData`, `FootTemperature`, `ZoneInfo`, `SeverityLevel`, `AlertEntry`, `RiskStatus`, `PresetName`, `AppData`, etc. |
| `constants.ts` | 69 | Two clinical thresholds, 6-zone `ZONES` geometry, foot silhouette SVG path, `TOES`, `STATUS_META` (6 risk states), preset labels, alert recommendations. |
| `mockData.ts` | 61 | `PRESETS` (4 static pressure scenarios) + `MOCK_DATA: AppData` — one frozen snapshot, all literals. |
| `pressureColor.ts` | 69 | Pure fns: `pressureColor`, `pressureSeverity`, `pressureAdvice`, `toneColor`, `toneSoft`, `tempColor`. |
| `navigation.ts` | 90 | Builds the 4-tab bottom bar (`initNavigation`) and the faux iOS status bar (`renderStatusBar`). |
| `heatmap.ts` | 371 | `class Heatmap` — the only stateful component. Renders both feet as SVG, zone tap to detail card, preset switcher, risk summary; `onChange` emitter. |
| `home.ts` | 174 | Home entry: header, connection strip, status badge, alert banner, ΔT tile, today summary, mounts `Heatmap`. |
| `gait.ts` | 162 | Gait entry: classification card, 8-stride symmetry bars, CoP trace, 7-day sparkline. |
| `temperature.ts` | 208 | Temp entry: ΔT hero meter, bilateral temp foot map, 24 h line chart, temp alert history. |
| `alerts.ts` | 158 | Alerts entry: emergency card, type filter chips, grouped timeline. |
| `settings.ts` | 242 | Settings entry: profile, device rows, sensitivity slider + toggles, language, export. |
| `gait.notes.md` | 24 | Design notes for the gait screen (not compiled). |

## HTML (`pages/`) — all are empty shells; every `<section>` is filled by JS

`home.html` (44), `gait.html` (28), `temperature.html` (28), `alerts.html` (27), `settings.html` (29).

## CSS (`css/`)

`global.css` (178, design tokens/reset/typography), `components.css` (274, header/cards/tab bar/status
badge/alert banner), `heatmap.css` (389), `temperature.css` (231), `settings.css` (257), `gait.css` (200),
`alerts.css` (163), `home.css` (87).

## Other

`package.json` (12), `package-lock.json` (16), `tsconfig.json` (15), `CLAUDE.md` (44), `SETUP.md` (105),
`.claude/settings.local.json` (7, permission allowlist only). `dist/js/*.js` + `.map` are generated build
output (12 files) — `SETUP.md:95` says never edit by hand.

---

# 2. DATA FLOW

## Where mock data is defined

- **`src/ts/mockData.ts:5-22`** — `PRESETS`: four hand-written `PressureData` objects
  (`normal`, `diabetic`, `heavyHeel`, `forefoot`), each with `left`/`right` × 6 named zones.
- **`src/ts/mockData.ts:24-60`** — `MOCK_DATA: AppData`: connection booleans (`:25`), battery (`:26`),
  `currentStatus: 3` (`:27`), `pressure` aliased to `PRESETS.diabetic` (`:30`), temperature (`:34-37`),
  today summary (`:39-43`), `gaitHistory7Days` (`:45`), `temperatureHistory24h` — 6 points (`:47-54`),
  `recentAlerts` — 3 entries (`:56-60`).
- **Data defined *outside* the mock module** (this matters for the refactor):
  - `src/ts/gait.ts:8-17` — `STRIDES`, 8 hardcoded left/right stride pairs, local to the gait page.
  - `src/ts/gait.ts:33-48` — the AI classification card's verdict, `status 2/5`, and `87%` confidence are
    literal HTML, not data at all.
  - `src/ts/alerts.ts:16-20` — `EXTRA_ALERTS`, 3 more alerts merged in at `alerts.ts:85`.
  - `src/ts/temperature.ts:174-178` — two synthetic temperature alerts appended at render time
    (comment at `:173` says "to make the screen feel realistic").
  - `src/ts/settings.ts:14-20` — `state`, the settings prefs.
  - `src/ts/settings.ts:77` — firmware string `v2.4.1` inlined in the template.

## What generates it

**Nothing dynamic.** A grep for `setInterval`, `setTimeout`, `Math.random`, `requestAnimationFrame`,
`fetch`, `Promise`, `async`/`await`, `new Date`, `localStorage`, `navigator.*` across `src/ts/` returns
**zero hits**. All values are static literals. The only "simulation" is the 4-button preset switcher
rendered by `heatmap.ts:283-299`, which swaps which static `PRESETS` entry is displayed
(`heatmap.ts:45-51`). Motion on screen is CSS-only (pulse rings, `heatmap.css:115-119`).

## How data reaches the DOM

Direct `innerHTML` string interpolation into pre-existing `<section id="...">` hosts, with one exception.
Pattern per page: a set of `renderXxx()` functions, each doing `document.getElementById(...)` then
`host.innerHTML = ...` (e.g. `home.ts:20-34`, `temperature.ts:22-57`, `alerts.ts:82-131`,
`settings.ts:60-97`), called in order from a single `DOMContentLoaded` listener (`home.ts:150-174`,
`gait.ts:153-162`, `temperature.ts:199-208`, `alerts.ts:150-158`, `settings.ts:233-241`). Every render
ends by re-running `lucide.createIcons()`.

The exception is `heatmap.ts`, which builds real DOM/SVG nodes via `document.createElement` /
`createElementNS` helpers (`heatmap.ts:362-371`) and attaches listeners directly (`heatmap.ts:226-230`) —
but still nukes and rebuilds its whole subtree on every state change (`heatmap.ts:57`).

No framework, no virtual DOM, no reactivity, no data-binding.

## Existing abstraction between data and rendering

**Essentially none.** Seven files import the mock module by name and read its fields inline inside
renderers:

```
alerts.ts:3, gait.ts:3, home.ts:4, settings.ts:3, temperature.ts:3   ->  import { MOCK_DATA }
heatmap.ts:16                                                        ->  import { PRESETS }
```

The single partial abstraction is `Heatmap`'s `onChange(({preset, pressure}) => ...)` emitter
(`heatmap.ts:41,50`), which `home.ts:164` uses to recompute the status badge. That is a component-level
event bus, not a data-source seam — and `Heatmap` itself still reaches straight into `PRESETS` at
`heatmap.ts:42,50,55` rather than receiving data through its constructor (`HeatmapOpts` at
`heatmap.ts:23-26` takes only `container` and `initialPreset`).

There is also a vestigial seam that is **never used**: `MOCK_DATA.pressure` (`mockData.ts:30`),
`MOCK_DATA.presets` (`:32`), and `MOCK_DATA.currentStatus` (`:27`) are read by **no** file — verified by
grep; the only hits are their own declarations plus the `types.ts` field declarations. `home.ts` instead
derives the risk status locally via `statusFromPressure()` (`home.ts:11-17`) from whatever preset the
heatmap currently shows (`home.ts:158`). So the `AppData.currentStatus` field is dead weight today.

## State container

No container. State lives in loose module-level or class-level variables:

- `heatmap.ts:31-33` — `private preset`, `private selected`, `private listeners` (class-scoped; the
  closest thing to a store).
- `alerts.ts:54` — `let activeFilter` (module-level mutable).
- `settings.ts:14-20` — `const state: SettingsState` (module-level mutable object, mutated at
  `:154,167,211`).
- `home.ts:155-158` — `heatmap` local in the `DOMContentLoaded` closure; status is recomputed on demand,
  never stored.

Nothing persists across page navigations — each `pages/*.html` is a full page load with its own module
instance, so all state resets on every tab switch (the tab bar uses `<a href>`, `navigation.ts:37`).

---

# 3. TYPE DEFINITIONS

Verbatim from `src/ts/types.ts`:

```ts
// Pressure data for a single foot (6 zones)            // :3-11
export interface FootPressure {
  toe: number;
  meta1: number;
  meta3: number;
  meta5: number;
  arch: number;
  heel: number;
}

// Both feet pressure                                    // :13-17
export interface PressureData {
  left: FootPressure;
  right: FootPressure;
}

// Foot temperature (forefoot + heel sensors per foot)   // :19-23
export interface FootTemperature {
  forefoot: number;
  heel: number;
}

// Zone metadata — drives the SVG rendering of each pressure zone   // :25-35
export interface ZoneInfo {
  id: keyof FootPressure;
  labelTH: string;
  labelEN: string;
  // SVG coordinates (within the 100x270 viewBox of one foot)
  cx: number;
  cy: number;
  rx: number;
  ry: number;
}

// Severity levels (used across pressure, temp, gait)    // :37-38
export type SeverityLevel = 'safe' | 'caution' | 'warning' | 'danger';

// Alert entry                                           // :40-48
export interface AlertEntry {
  id: number;
  time: string;
  type: 'pressure' | 'temperature' | 'gait';
  severity: SeverityLevel;
  message: string;
  acknowledged: boolean;
}

// AI classifier risk status (0–5)                       // :50-51
export type RiskStatus = 0 | 1 | 2 | 3 | 4 | 5;

// Preset scenario names                                 // :53-54
export type PresetName = 'normal' | 'diabetic' | 'heavyHeel' | 'forefoot';

// Temperature history data point                        // :56-61
export interface TempHistoryPoint {
  hour: string;
  leftForefoot: number;
  rightForefoot: number;
}

// Daily summary                                         // :63-68
export interface DailySummary {
  steps: number;
  walkingMinutes: number;
  gaitSymmetryScore: number;
}

// Side identifier                                       // :70-71
export type FootSide = 'left' | 'right';

// Tooltip data when a zone is tapped                    // :73-78
export interface ZoneTooltipData {
  side: FootSide;
  zone: ZoneInfo;
  value: number;
}

// Status metadata for one of the 6 risk states          // :80-87
export interface StatusMeta {
  th: string;
  en: string;
  tone: 'neutral' | 'safe' | 'warn' | 'danger';
  color: string;
  soft: string;
}

// Complete app state                                    // :89-101
export interface AppData {
  connectionStatus: { left: boolean; right: boolean };
  batteryLevel: { left: number; right: number };
  currentStatus: RiskStatus;
  pressure: PressureData;
  presets: Record<PresetName, PressureData>;
  temperature: { left: FootTemperature; right: FootTemperature };
  todaySummary: DailySummary;
  gaitHistory7Days: number[];
  temperatureHistory24h: TempHistoryPoint[];
  recentAlerts: AlertEntry[];
}
```

Supporting types declared outside `types.ts`:

```ts
// constants.ts:35
export interface ToeShape { cx: number; cy: number; rx: number; ry: number; }
// constants.ts:55
export interface PresetLabel { id: PresetName; th: string; en: string; }
// constants.ts:64
export interface AlertRecommendation { th: string; en: string; }

// pressureColor.ts:23-28
export interface SeverityInfo {
  level: SeverityLevel;
  th: string;
  en: string;
  tone: 'safe' | 'warn' | 'danger';
}

// navigation.ts:7-16
export type TabId = 'home' | 'gait' | 'temp' | 'alerts';
interface TabSpec { id: TabId; href: string; th: string; en: string; icon: string; badgeAttr?: string; }

// heatmap.ts:23-27
interface HeatmapOpts { container: HTMLElement; initialPreset?: PresetName; }
type ChangeHandler = (e: { preset: PresetName; pressure: PressureData }) => void;

// gait.ts:6
interface StridePair { l: number; r: number; }

// alerts.ts:8-14
type AlertType = AlertEntry['type'];
interface ExpandedAlert extends AlertEntry { day: 'today'|'yesterday'|'older'; iconName: string; tone: 'danger'|'warn'|'safe'; }

// settings.ts:6-12
interface SettingsState { sensitivity: number; notifications: boolean; vibration: boolean; doctorAlerts: boolean; language: 'th'|'en'; }
```

## Distance from the target shapes

### `SensorSample { tUnixMs, side, fsrKpa[6], accelG[3], gyroDps[3] }`

Nearest existing: `FootPressure` + `PressureData` (`types.ts:4-17`). **Gap: large.**
No timestamp anywhere in the codebase. `side` is not a field — it is the *key* of `PressureData`, so a
sample is never self-describing. Pressure is a 6-key **object** (`toe/meta1/meta3/meta5/arch/heel`), not an
indexed array, so there is no channel order in the type at all. Units are a unitless 0–100 "pressure
index" (`constants.ts:6` comment; `heatmap.ts:272` renders "pressure index"), not kPa. **No IMU concept
whatsoever** — zero references to accel or gyro in any file.

### `TempReading { tUnixMs, side, forefootC, heelC, quality }`

Nearest existing: `FootTemperature` (`types.ts:20-23`) + `TempHistoryPoint` (`:57-61`). **Gap: moderate.**
`forefoot`/`heel` map cleanly to `forefootC`/`heelC`. Missing `tUnixMs` (history uses a display string
`hour: '06:00'`, `types.ts:58`), missing `side` as a field, missing `quality`. The 24 h history type is
*pre-joined across feet* (`leftForefoot`/`rightForefoot` in one row) and drops the heel channel entirely,
so it is not a list of per-side readings.

### `DeviceStatus { side, batteryPct, connected, firmware, errorCode }`

Nearest existing: `AppData.connectionStatus` + `AppData.batteryLevel` (`types.ts:91-92`).
**Gap: moderate.** The two fields exist but are split into separate `{left,right}` maps rather than one
per-side record. No `firmware` field (the string `v2.4.1` is hardcoded in markup at `settings.ts:77`), no
`errorCode`.

### `RiskAssessment { statusLevel 1-5, gaitClass, confidence, deltaT*, peakKpa, ptiKpaS, peakAsymmetryPct, ptiAsymmetryPct, loadConcentrationPct, symmetryScore, highRiskZones, source }`

Nearest existing: `RiskStatus` (`types.ts:51`) + `StatusMeta` (`:81-87`) + `DailySummary.gaitSymmetryScore`
(`:67`). **Gap: largest — this type does not exist.** Only `statusLevel` has an analogue, and it is
`0 | 1 | 2 | 3 | 4 | 5` (six states including `0 = Not worn`), not 1–5. `symmetryScore` exists as a loose
number on `DailySummary`. `confidence` (87%) and `gaitClass` are literal strings in markup
(`gait.ts:41,45-46`), not typed data. `highRiskZones` is computed ad hoc into a local `ZoneTooltipData[]`
inside the heatmap (`heatmap.ts:302-311`) and never leaves that function. **No type or code anywhere for**
`deltaT*`, `peakKpa`, `ptiKpaS` (no PTI/impulse concept at all), `peakAsymmetryPct`, `ptiAsymmetryPct`,
`loadConcentrationPct`, or `source`.

---

# 4. SCREENS AND COMPONENTS

All four tabs exist, plus a fifth Settings screen reached via the gear button (`home.ts:143`),
deliberately not a tab (`navigation.ts:18-23` lists only four).

## Home — `pages/home.html` + `home.ts` (174) — most complete

| Element | Exists | How drawn |
|---|---|---|
| Header + greeting | Yes | `innerHTML`, `home.ts:135-147`. Patient name hardcoded. |
| Alert banner | Yes | `innerHTML`, `home.ts:59-76`. Shown only when derived status ≥ 3. |
| Connection strip (BT + 2 batteries) | Yes | `innerHTML`, `home.ts:20-34`. |
| Status gauge / badge | Yes, as a **badge not a gauge** | `innerHTML` + CSS ring, `home.ts:37-57`; pulse via `.live-dot` CSS. No arc/dial. |
| Pressure heatmap | Yes, complete | Hand-built **inline SVG** (`heatmap.ts:116-176`), 100×270 viewBox per foot, right foot mirrored by `scale(-1,1)` (`heatmap.ts:137`). |
| Zone detail card on tap | Yes | `innerHTML`, `heatmap.ts:250-281`. |
| Preset ("Simulate") switcher | Yes | 4 buttons, `heatmap.ts:283-299`. |
| Risk summary + high-risk zone list | Yes | `innerHTML`, `heatmap.ts:301-358`. |
| ΔT compact tile | Yes | `innerHTML`, `home.ts:78-99`. |
| Today summary (steps/minutes/symmetry) | Yes | `innerHTML` tiles, `home.ts:101-133`. |

## Gait — `pages/gait.html` + `gait.ts` (162) — visually complete, data-wise the thinnest

| Element | Exists | How drawn |
|---|---|---|
| AI classification card | Yes, but **fully static** | `innerHTML` literals, `gait.ts:33-48`. Verdict, `2/5`, `87%` are typed into the template. |
| Peak bar chart (L vs R, 8 strides) | Yes | **CSS flexbox divs with inline `height: %`**, not SVG — `gait.ts:54-62`, `css/gait.css:69-99`. |
| CoP trajectory | Yes, but **a fixed decorative path** | Inline **SVG** with a literal `d` attribute, `gait.ts:93-103`; animated by `stroke-dasharray` in CSS. Not computed from data. |
| 7-day trend sparkline | Yes, genuinely data-driven | Inline **SVG** path built from `MOCK_DATA.gaitHistory7Days`, `gait.ts:108-151`. |
| Heatmap / temperature | N/A on this screen | — |

## Temperature — `pages/temperature.html` + `temperature.ts` (208)

| Element | Exists | How drawn |
|---|---|---|
| ΔT hero + threshold meter | Yes | `innerHTML` + CSS gradient bar with absolutely-positioned needle/threshold, `temperature.ts:22-57`, `css/temperature.css:32-42`. |
| Bilateral temperature foot map | Yes | Inline **SVG**, `temperature.ts:76-116`. **Only 2 zones per foot** (forefoot, heel), at hardcoded coordinates `temperature.ts:82-85`. |
| 24 h trend chart | Yes | Inline **SVG**, two polylines + dots + 3 gridlines, `temperature.ts:118-167`. |
| Temperature alert history | Yes | `innerHTML` list, `temperature.ts:169-197`. |

## Alerts — `pages/alerts.html` + `alerts.ts` (158)

| Element | Exists | How drawn |
|---|---|---|
| Emergency contact card | Yes (button is inert — no handler) | `innerHTML`, `alerts.ts:133-148`. |
| Filter chips (All/Pressure/Temp/Gait) | Yes, functional | `innerHTML` + click listeners, `alerts.ts:56-80`. |
| Alert cards, grouped by day | Yes | `innerHTML`, `alerts.ts:82-131`. Grouping is by **substring match on a Thai time string** (`alerts.ts:34-36`). |
| Acknowledge action | **No** — `acknowledged` renders a pill but is never togglable | `alerts.ts:118-122`. |

## Settings — `pages/settings.html` + `settings.ts` (242)

Profile card, per-side device rows with battery bars (`:60-97`), sensitivity slider + 3 toggles
(`:99-171`, all functional but write only to the in-memory `state`), language segment, PDF export button
(inert, `:217-231`).

**No charting library anywhere** — confirmed by `package.json:9-11` (typescript only) and by
`gait.notes.md:15` ("no recharts dependency in the runtime"). No `<canvas>` in any file. Everything is
inline SVG, CSS gradients, or flexbox bars.

---

# 5. HARDCODED CONSTANTS

## Named constants (the two that are actually centralised)

| Value | Location | Contract comparison |
|---|---|---|
| `PRESSURE_DANGER_THRESHOLD = 75` — comment says "pressure index" | `constants.ts:6` | **Disagrees in unit and in count.** Contract fixes **75 kPa watch / 200 kPa alert** — two levels, in kPa. Code has **one** level, `75`, on a unitless **0–100** scale where 100 is the top of the color ramp. The numeral coincides with the watch level but means something else; there is **no** 200-level concept anywhere. |
| `TEMP_DELTA_THRESHOLD = 2.2` °C | `constants.ts:7` | **Agrees** with the contract's ΔT 2.2 °C. Used at `home.ts:83,90`, `temperature.ts:29,35,41,49`. |

## Sensor counts and channel order

| Item | Location | Note |
|---|---|---|
| 6 pressure zones, ordered `toe, meta1, meta3, meta5, arch, heel` | `constants.ts:12-19` (array order) and `types.ts:4-11` (object keys) | **Order matches** the contract (`hallux, met1, met3, met5, midfoot, heel`) **positionally**, but **naming differs**: `toe` vs `hallux`, `arch` vs `midfoot`. More importantly the data is an **object keyed by name**, so there is no array-index-to-channel mapping in the code; any BLE payload arriving as `fsrKpa[6]` needs an explicit ordering table that does not exist today. |
| 5 toe shapes (cosmetic) | `constants.ts:36-42`; duplicated at `temperature.ts:68-74` | Decoration only, unrelated to sensors — but easy to confuse with channel count. |
| 2 temperature zones per foot | `types.ts:20-23`; drawn at `temperature.ts:82-85` | Matches `forefootC`/`heelC`. No `quality` channel. |
| 6 risk states `0..5` | `types.ts:51`, `constants.ts:45-52` | Contract says `statusLevel 1-5`. Code carries an extra `0 = Not worn`. |
| 8 strides | `gait.ts:8-17` | Array length drives the bar chart; label at `gait.ts:68` says "last 8 strides". |
| 7-day history + 7 Thai day labels | `mockData.ts:45`; labels `gait.ts:124` | Two independent 7s that must stay in sync. |
| 6 points in 24 h history | `mockData.ts:47-54` | Labelled "24-hour trend" (`temperature.ts:149`) but covers 06:00–16:00 only. |

## Threshold literals duplicated outside `constants.ts` (all magic numbers)

| Value | Location | What it is |
|---|---|---|
| `25 / 40 / 55 / 70 / 80` | `pressureColor.ts:15-20` | Six-stop color ramp breakpoints on the 0–100 index. |
| `75`, `56` | `pressureColor.ts:34-35` | Severity buckets — re-states the danger threshold instead of importing it. |
| `81`, `75`, `56` | `pressureColor.ts:43-45` | Advice-text buckets; `81` appears nowhere else. |
| `29 / 30 / 31 / 31.5 / 32.2` °C | `pressureColor.ts:63-68` | Absolute temperature → color ramp. Contract fixes only ΔT, not absolute bands. |
| `mx >= 75` | `home.ts:15` | Third copy of the danger threshold, inside `statusFromPressure`. |
| `status < 3`, `status >= 4` | `home.ts:62,64,65,66` | Risk-level → banner tone/advice mapping. |
| `value <= 40` | `heatmap.ts:189` | Adds `invert-text` class — a fourth, undocumented pressure breakpoint. |
| `"75 · อันตราย"` (literal string) | `heatmap.ts:239` | Legend marker label. |
| `left: 75%` ×2 | `css/heatmap.css:137, 146` | Legend marker position — hardcodes both the threshold **and** the assumption that the scale is 0–100. |
| `0%, 25%, 40%, 55%, 70%, 100%` gradient stops | `css/heatmap.css:126-132` | CSS mirror of `pressureColor.ts:15-20`; the two can drift silently. |
| `(dT / 4) * 100`, `(TEMP_DELTA_THRESHOLD / 4) * 100` | `temperature.ts:28-29` | ΔT meter assumes a fixed 0–4 °C full scale. |
| `min = 28, max = 33` | `temperature.ts:123` | 24 h chart Y-range. |
| `[28, 30, 32]` | `temperature.ts:137` | Gridline values. |
| `28°` / `33°` legend text | `temperature.ts:113` | Duplicates the range as strings. |
| 5-stop temp gradient `#6BA3D6 … #E24B4A` | `css/temperature.css:157` | Third copy of the temperature color scale (after `pressureColor.ts:62-68` and the `--pressure-*` tokens). |
| ΔT meter gradient stops `40% / 60% / 65%` | `css/temperature.css:36-41` | Implies a threshold near 55–60 % of a 4 °C scale ≈ 2.2–2.4 °C; hand-tuned, not derived. |
| `max = 100` for stride bars | `gait.ts:52` | Stride values are 68–85, but the pill labels the axis **`PEAK kPa`** (`gait.ts:70`) — a **unit contradiction**: kPa values plotted against a 0–100 index scale. |
| `min - 4 / max + 4`, `w=220, h=60` | `gait.ts:113-114` | Sparkline padding and viewport. |
| `w=320, h=130` | `temperature.ts:122` | Temp chart viewport. |
| `87%`, `status 2/5` | `gait.ts:41,45` | Classifier confidence and level, as literal text. |
| `v2.4.1` | `settings.ts:77` | Firmware string. |
| `60`, `25` battery buckets | `settings.ts:23-24` | Battery color classes. |
| `sensitivity: 65` | `settings.ts:15` | Default alert sensitivity — **not wired to any threshold**. |
| `'9:41'` | `navigation.ts:72` | Faux status-bar clock. |
| `11 พ.ค.` | `home.ts:112` | Hardcoded date on the Today card. |
| viewBox `0 0 100 270` + all zone `cx/cy/rx/ry` | `heatmap.ts:118`, `constants.ts:13-18` | Foot geometry; a second, **different** foot path and toe set exists at `temperature.ts:60-74`. |
| Color hexes duplicated | `constants.ts:46-51` (`STATUS_META`) vs `css/global.css:22-27` (`--status-*`) | Same six colors defined in both TS and CSS. |

**Summary of contract disagreements:** unit system (0–100 index vs kPa) everywhere pressure appears;
missing 200 kPa alert tier; zone key names `toe`/`arch` vs `hallux`/`midfoot`; a 0-state in the risk enum
that the contract's 1–5 does not have; `PEAK kPa` label on index-scaled bars (`gait.ts:70`). ΔT 2.2 °C is
the one value that already matches.

---

# 6. COUPLING RISKS

**1. Direct static imports of the mock module in 6 of 7 non-shared files.**
`alerts.ts:3`, `gait.ts:3`, `home.ts:4`, `settings.ts:3`, `temperature.ts:3` import `MOCK_DATA`;
`heatmap.ts:16` imports `PRESETS`. There are 14 read sites total (verified by grep) — each is an inline
field access *inside a template literal*, e.g. `d.batteryLevel.left` (`home.ts:31`),
`MOCK_DATA.temperature` (`temperature.ts:25,79`), `MOCK_DATA.gaitHistory7Days` (`gait.ts:111`),
`MOCK_DATA.recentAlerts` (`alerts.ts:85,156`; `temperature.ts:172`; `home.ts:171`),
`MOCK_DATA.todaySummary` (`home.ts:104`). Every one is a place the UI would break on swap.

**2. `Heatmap` reads the data module itself.** `heatmap.ts:42,50,55` call `PRESETS[this.preset]` directly;
`HeatmapOpts` (`:23-26`) has no data parameter. The component cannot currently be handed live pressure
without editing its internals. Its `PresetName` state (`:31`) is also a *simulation* concept that has no
meaning once a real device is attached — `getPressure()` and `getPreset()` are part of its public API and
`home.ts:158` depends on both.

**3. Synchronous-data assumption is total.** Every renderer reads its values at call time inside
`DOMContentLoaded` (`home.ts:150-174`, `gait.ts:153-162`, `temperature.ts:199-208`, `alerts.ts:150-158`,
`settings.ts:233-241`). There is no `async`, no Promise, no loading state, no empty state, and no error
state anywhere in `src/ts/` (grep-confirmed). Nothing renders a "connecting…" or "no device" view.
`home.ts:154` does `document.getElementById('heatmap-host')!` with a non-null assertion and constructs
`Heatmap` immediately — the render happens in the constructor (`heatmap.ts:38`), so there is no point at
which data could arrive later.

**4. No update path other than full-subtree rebuild.** `innerHTML = ...` destroys and recreates nodes,
which drops event listeners. `home.ts:98` attaches the ΔT tile's click handler with `{ once: true }` — if
that tile were ever re-rendered on a data tick the handler would be silently lost. `alerts.ts:72-79` and
`settings.ts:162-170` re-bind listeners on every render by design; a streaming source would multiply this
cost at whatever rate samples arrive. *(Inference: no re-render on data change exists today, so this is a
hazard the refactor introduces, not a current bug.)*

**5. Left/right is baked in as a pair, not a stream of per-side samples.** `PressureData`
(`types.ts:14-17`), `AppData.temperature` (`:96`), `connectionStatus`/`batteryLevel` (`:91-92`) all model
both feet as one object. Renderers assume both are always present and simultaneous: `heatmap.ts:99-102`
renders both cells unconditionally; `heatmap.ts:303` iterates `['left','right']` hardcoded; `home.ts:82`
and `temperature.ts:26` compute ΔT as `Math.abs(left.forefoot - right.forefoot)` with no guard for a
missing side. With two independent BLE peripherals, one foot can be connected, stale, or absent —
**every ΔT and every asymmetry number becomes undefined or misleading**, and nothing in the UI can express
that. `home.ts:27` compounds this: the connection strip renders the literal Thai string "เชื่อมต่อแล้ว"
(connected) and "· L · R" **unconditionally**, ignoring `MOCK_DATA.connectionStatus` entirely — only
`settings.ts:67` actually reads the connection flags.

**6. Fixed-length / fixed-shape rendering assumptions.**

- `gait.ts:124` — 7 hardcoded day labels rendered independently of `data.length` (`gait.ts:111`); any
  other history length mismatches the axis.
- `gait.ts:115` — `w / (data.length - 1)` divides by zero on an empty array; `gait.ts:122` and `:125`
  index `data[data.length - 1]` unguarded.
- `temperature.ts:124` — same `data.length - 1` division; `:129-130` map the whole array with no length
  check.
- `gait.ts:54` — the symmetry chart's bar count comes from the local `STRIDES` array (`:8-17`), which has
  no data source at all; CSS `flex: 1` (`css/gait.css:79`) will keep laying out but bars become unreadable
  past roughly 12 strides.
- `heatmap.ts:170-171` — `for (const z of ZONES) … values[z.id]`: zone geometry and data keys are joined
  by name, so a payload missing a channel yields `undefined` rendered as text at `heatmap.ts:222` and
  `undefined >= 75` evaluating false at `:179`. **No validation, no defaults.**
- `temperature.ts:82-85` — the two temperature dots are hardcoded ellipses; a third sensor could not be
  shown without editing the renderer.

**7. Type-level blockers for the target shapes.** `keyof FootPressure` (`types.ts:27`) hard-binds
`ZoneInfo` to the six current key names, so renaming `toe` → `hallux` or moving to `fsrKpa[6]` is a
breaking change across `constants.ts:13-18`, `heatmap.ts:171,306`, and `heatmap.ts:322` (which
string-matches `['toe','meta1','meta3','meta5']`). `AlertEntry.time` is a **display string**
(`types.ts:43`, values like `'เมื่อวาน 18:05'`), and `alerts.ts:34-36` groups alerts by substring-matching
Thai words in it — real timestamped alerts cannot flow through this without rewriting the grouping logic.
`TempHistoryPoint` (`types.ts:57-61`) pre-joins both feet into one row, so a per-side `TempReading` stream
cannot populate it without a transform.

**8. Dead fields that will mislead the refactor.** `AppData.pressure`, `AppData.presets`, and
`AppData.currentStatus` (`types.ts:93-95`, populated at `mockData.ts:27,30,32`) are read by **nothing**.
Wiring a data source to `AppData` as-is would leave the heatmap and status badge still driven by `PRESETS`
and `statusFromPressure()` respectively.

**9. Cross-page state loss.** Navigation is `<a href>` full page loads (`navigation.ts:37`). A Web
Bluetooth `BluetoothDevice` connection cannot survive a tab switch — the GATT link would be torn down and
re-prompted on every navigation. This is the single largest architectural constraint the current
multi-page structure imposes on a live data source. *(Inference from the page structure; there is no BLE
code to read.)*

**10. Build/runtime footguns for a Capacitor target.** Lucide loads from `unpkg.com` at runtime in all
five pages (e.g. `pages/home.html:39`) and fonts from Google Fonts (`css/global.css:5`); both are
network-dependent and would need vendoring for a native shell. `dist/js/` is committed output that the
pages load by relative path (`../dist/js/home.js`), and `pages/*.html` are entry points with no bundler —
introducing a `@capacitor/*` npm import would require a bundler that does not currently exist.

---

# Decisions to make before the refactor

1. **Units.** Move the whole pressure pipeline to kPa (0–200+) per the contract, or keep the 0–100 index
   for display and convert at the boundary? This decides whether `pressureColor.ts:15-20`, the CSS ramps,
   and the `left: 75%` legend marker get rewritten or merely re-parameterised.
2. **Two thresholds, not one.** How do the contract's watch (75) and alert (200) tiers map onto the
   existing 4-value `SeverityLevel` and 6-state `RiskStatus`, and does `RiskStatus` keep its
   `0 = Not worn` state against the contract's 1–5?
3. **Zone representation.** Indexed `fsrKpa[6]` (contract-native, needs an explicit order table) vs the
   current named object (`keyof FootPressure` drives `ZoneInfo`). And whether to rename `toe` → `hallux`,
   `arch` → `midfoot`.
4. **Push or pull.** Does `IDataSource` expose an observable/callback stream that pushes samples, or a
   `getLatest()` the UI polls? This decides whether the `innerHTML`-rebuild renderers need to become
   diffing/partial updaters, and at what rate.
5. **Per-side independence.** One data source handling both feet, or one per side? And what the UI shows
   when only one foot is connected — specifically what ΔT, symmetry, and asymmetry render as.
6. **Where `RiskAssessment` is computed.** On-device/firmware, in the data-source adapter, or in a
   UI-side derivation layer — and what `source` is meant to distinguish. Everything in that shape except
   `statusLevel` and `symmetryScore` is currently absent.
7. **Loading / error / disconnected states.** None exist; each of the five screens needs a defined
   appearance for "no data yet", "device dropped", and "stale sample".
8. **Page architecture.** Whether to keep five independent HTML entry points (BLE connection dies on every
   tab switch) or move to a single-page shell before wiring a live source.
9. **What happens to the preset switcher.** `Heatmap`'s `PresetName` state and its
   `getPreset()`/`onChange` API are simulation-only — keep it as a "mock source" selector behind
   `IDataSource`, or remove it from the component's public surface.
10. **Whether a bundler comes in now.** A Capacitor plugin import cannot be resolved by the current
    tsc-only, no-bundler setup, and Lucide/fonts are CDN-loaded.
