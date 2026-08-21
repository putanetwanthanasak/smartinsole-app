# CLAUDE.md

Guidance for Claude Code working in this repository. This file is written as a
**handoff** — assume whoever (or whatever) is reading it has no memory of how
the code got this way. For the pass-by-pass history and reasoning, see
`docs/PROGRESS.md`. For what's deliberately not done yet, see
`docs/BACKLOG.md`. For the wire format and clinical thresholds everything here
derives from, see `docs/DATA-CONTRACT.md`.

## Read this first if the contract file is still a placeholder

`docs/DATA-CONTRACT.md` should contain the actual Data Contract v1.1. If it
still says "PLACEHOLDER — NOT YET FILLED IN" at the top, **stop and ask the
user to paste it in** before making any change to `constants.ts`,
`data/types.ts`, or anything touching thresholds, channel order, or packet
parsing. Every number and shape in those files was typed from a *remembered*
version of the contract during earlier sessions; treat that as provisional
until the real document is in the repo and re-checked against it.

## Sibling projects (outside this repo)

Two other projects exist outside this repository that the next phase of work
depends on. Neither is checked into this repo; both are referenced here so
their existence isn't lost.

- **An ESP32 BLE simulator** — a PlatformIO project using NimBLE-Arduino 2.x.
  It advertises as `SMARTINSOLE-L` and streams synthetic gait data matching
  the Data Contract's packet format. **Flashed, working, and verified.**
- **A standalone single-file BLE test page** — connects to the simulator via
  Web Bluetooth. **Confirmed working end to end**: 200-byte packets, MTU 247
  negotiated successfully, correct parsing of pressure, IMU, temperature,
  device status, and the calibration blob.

**This web app has not been connected to either of them yet.** That
integration — building `WebBleDataSource` against the already-working
simulator — is the next major phase; see "Next phase" at the bottom of this
file.

## Commands

- `npm run dev` — starts the Vite dev server (default <http://localhost:5173>) with HMR. This is how you view the app; there is no separate build step during development.
- `npm run build` — `tsc --noEmit && vite build`. Type-checks every `.ts` under `src/ts/`, then bundles to `dist/`. Fails the build on any type error.
- `npm run preview` — serves the built `dist/` output, for checking the real bundle.
- `npm run typecheck` / `npm run watch` — `tsc --noEmit`, once or in watch mode. Vite strips types without checking them, so type errors do not surface in `npm run dev`.

There is no linter and no test runner. `dist/` is generated output — gitignored, never edited or committed.

## Reporting

Write the report for each pass to `docs/reports/NNN-<short-name>.md`
(zero-padded, incrementing — check the highest existing number in
`docs/reports/` first) and commit it. Chat gets only a short summary: what
changed, anything that needs a decision, and a pointer to the file. If the
chat summary would run long, that's the signal the report should carry it,
not chat — chat output has been observed to truncate mid-pass, silently
dropping content (including, once, a real defect finding), and a committed
file cannot be truncated that way.

## Git workflow

- **Never push directly to `main`.**
- Each pass of work happens on its own branch, named `work/<short-topic>`
  (e.g. `work/research-capture-mode`).
- Before starting a new pass: `git checkout main`, `git pull`, then
  `git checkout -b work/<topic>` from there.
- Push the branch, do not merge it yourself — the user merges via a Pull
  Request on GitHub after reviewing.
- Commit messages and report files (`docs/reports/NNN-*.md`) stay exactly as
  already established in the "Reporting" section above — only the
  branch/push step changes.

## Architecture

This is a **single-page vanilla TS app** — Thai-language Smart Insole
companion app for diabetic foot care — currently driven by a mock data layer
that stands in for two BLE insoles. There is no UI framework (no
React/Vue/etc.) and no backend. Vite is the dev server and bundler; the only
runtime dependencies are Lucide (icons) and three `@fontsource` font
packages, both bundled — **the app makes no external network requests and
works offline**, which is a requirement for the eventual Capacitor build.

### Shell + router, not pages

`index.html` at the project root is the entry point and the whole shell:

```
.device-frame
  .status-bar          ← faux iOS status bar, filled by renderStatusBar()
  main.app-scroll      ← the scroll container (position:absolute; inset:0)
    #app-header        ← persistent header host, INSIDE the scroller so it scrolls
    #view              ← the router swaps this
  nav.tab-bar           ← filled by initNavigation(); left empty on Settings
```

It loads `/src/ts/main.ts` as its single module. `main.ts` imports the fonts,
calls `startRouter()`, and — this is the app-level entry point for the data
layer — calls `deviceManager.connectAll()` **once, here, and nowhere else**
(see "DeviceManager" below for why that matters).

**`src/ts/router.ts`** owns hash routing (`#/home`, `#/gait`, `#/temp`,
`#/alerts`, `#/settings`; empty or unknown → `#/home`). On every route change
it unmounts the outgoing screen, clears `#view`, sets the view's wrapper
class and `document.title`, blanks the tab bar, injects that screen's
section scaffolding, resets scroll, calls the screen's `mount()`, then runs
`refreshIcons()` once.

**The section scaffolding for every screen lives in the `*_TEMPLATE`
constants in `router.ts`.** That is the only live copy. `pages.reference/`
holds the original multi-page HTML, which no longer runs and is kept purely
as a visual reference — see its README.

### Screen = module with mount/unmount

Every screen is `src/ts/<name>.ts` + `css/<name>.css`, and exports exactly
two functions:

- `mount()` — renders the screen and subscribes to whatever live data it
  needs.
- `unmount()` — releases anything that would outlive the screen. See
  "Cleanup discipline" below — this is the single easiest thing to get wrong
  in this codebase and it has already caused real bugs.

### The data seam: `IDataSource` → `DeviceManager` → screens

`src/ts/data/` is the abstraction between "where sensor data comes from" and
"what the UI renders." Nothing outside this directory should know whether
data is mocked, streamed over Web Bluetooth, or coming from a Capacitor
native plugin.

- **`IDataSource.ts`** — the interface. **One instance per foot, not one for
  both.** The two insoles are independent BLE peripherals: one side can be
  connected while the other is absent, stale, or errored, and the UI must be
  able to say which. A combined-source design cannot express that.
- **`MockDataSource.ts`** — implements `IDataSource` against the existing
  `PRESETS`/`MOCK_DATA`. Streams samples at 50 Hz to exercise the real
  throttle path, simulates a connect delay so `'connecting'` is actually
  reachable, and jitters values within their own colour-ramp band so nothing
  crosses a tier boundary from noise alone.
- **`DeviceManager.ts`** — the one place that owns both sides. Responsibilities:
  - Converts the wire format's indexed `fsrKpa[6]` array to the UI's
    name-keyed `FootPressure` object, using `FSR_CHANNEL_ORDER` from
    `constants.ts`. **This is the only place that conversion happens.**
    Screens and components must never touch `fsrKpa` directly.
  - Coalesces two independent 50 Hz push streams into one throttled 10 Hz
    `CombinedSnapshot`, emitted via `onSnapshot()`. The throttle timer is
    **reference-counted** — it starts on the first subscriber and stops on
    the last unsubscribe, so a screen nobody is viewing costs nothing.
  - Derives per-side `ConnectionState` and staleness — see "Staleness" below.
  - Computes ΔT (`deltaForefootC`) — `null` unless both sides are usable and
    both report a forefoot value.
  - Holds a per-side temperature ring buffer (`pushHistory`/`getTempHistory`,
    10-minute buckets, 24h span) for the trend chart.
- **`AlertStore.ts`** — subscribes to `DeviceManager` and generates real
  alerts from threshold crossings (pressure watch/alert tiers per side, ΔT),
  with the contract's 30-minute per-code repeat suppression. It subscribes at
  module load and keeps running regardless of which screen is mounted — an
  alert the user wasn't looking at is exactly the one that matters.
- **`data/types.ts`** — the contract-derived wire types (`SensorSample`,
  `TempReading`, `DeviceStatus`) plus the UI-facing snapshot vocabulary
  (`ConnectionState`, `SideSnapshot`, `CombinedSnapshot`, `isUsable()`).

**Wiring status:** Home, Temperature, Alerts, and Settings are wired to this
seam. **Gait is partially wired**: PAI (Peak Asymmetry Index) is a real
rolling-window metric computed from live snapshots; the classification card,
CoP trajectory, and 7-day trend have no data source yet and render an
explicit unavailable state rather than reading anything live — see
`docs/reports/003-gait-pai.md` and `docs/BACKLOG.md` item 1. Do not assume
every section of every screen reads live data; check before editing.

## Conventions that are easy to violate

These are listed because each one has already caused a real bug in this
codebase, not as a hypothetical.

**1. Anything touching the DOM outside `#view` must be cleaned up in
`unmount()` — listeners AND style/class/attribute mutations, not just
listeners.** `#app-header`, `.status-bar`, and `nav.tab-bar` are shell
furniture that persists across every navigation; a screen that mutates them
without undoing it leaks into whichever screen mounts next. This already
happened: `settings.ts` sets an inline `justify-content` on `#app-header` to
centre its title, and the first version of the SPA conversion forgot to
reset it — every screen after Settings inherited a centred header until it
was caught and fixed in `unmount()`.

**2. Every subscribe returns an unsubscribe; screens call them in
`unmount()`.** This applies to `IDataSource.onSample/onTemp/onStatus/onStateChange`,
`DeviceManager.onSnapshot`, and `AlertStore.subscribe`. Unlike the app's other
DOM listeners (which die for free when the router clears `#view`), these
subscriptions live in the data layer and outlive `#view` being cleared —
forgetting to unsubscribe keeps an unmounted screen's closures alive and
doing work forever. Verified after every wiring pass: navigate across all
five screens 10× each and confirm subscriber counts return to baseline, not
grow.

**3. A screen taking live data must build its DOM once and mutate it, not
`innerHTML`-rebuild on every update.** The data layer emits at 10 Hz.
Rebuilding a subtree with `innerHTML` at that rate drops any listeners
attached inside it and restarts any CSS animation running inside it (the
heatmap's danger-tier pulse rings would never complete a single cycle). See
`Heatmap` in `heatmap.ts` for the reference pattern: built once in the
constructor, then `setPressure()` mutates existing SVG attributes and text
nodes. Where a section's markup only actually changes at human timescales
(once a second or slower, e.g. Temperature's ΔT hero), a cheaper pattern —
`writeIfChanged()`, rebuild via `innerHTML` but only when the produced string
actually differs from last time — is correct and used throughout
`temperature.ts`, `alerts.ts`, `home.ts`. Reach for full node-mutation only
when a section genuinely has listeners or animations living inside it that a
rebuild would break.

**4. Staleness is derived from timestamps at read time, never latched by a
timer.** `DeviceManager.derivedState()` compares `Date.now() - lastSampleAt`
against `STALE_AFTER_MS` fresh on every call — `getStateOf()`, `snapshot()`,
each throttle tick. This was originally a `setInterval` that flipped a
`'stale'` flag, and it was wrong in the dangerous direction: **Chrome
throttles background-tab timers by seconds** (measured: a 400 ms `setTimeout`
sleep took 1400 ms with the tab hidden), so a backgrounded tab could keep
reporting a dead stream as `'connected'` because the timer that would have
caught it never fired on schedule. A comparison evaluated at read time cannot
drift no matter how badly timers are starved — verified by silencing a
source and leaving the tab backgrounded 78.7 s; the very first read
afterward returned `'stale'` correctly, with no delay. This will matter far
more on Android, where the app runs backgrounded routinely — see "Next
phase."

**5. `lastSampleAt` is arrival time (`Date.now()` when the sample was
received), never the device's own `tUnixMs`.** The peripheral's clock starts
at boot and is unsynced until a `SYNC_TIME` exchange happens (see the Data
Contract once it's in the repo) — trusting the device's own timestamp for
staleness would let a device with a skewed or unsynced clock make its own
data look permanently fresh, or permanently stale, regardless of whether
packets are actually arriving.

**6. Thresholds live in `constants.ts`. Never inline a number that has a
name.** `PRESSURE_WATCH_KPA`, `PRESSURE_ALERT_KPA`, `PRESSURE_SCALE_MAX_KPA`,
`TEMP_DELTA_THRESHOLD`, `PRESSURE_RAMP_KPA` (the derived colour-ramp
breakpoints), `PRESSURE_LABEL_INVERT_MAX_KPA` (a text-contrast boundary, not
a clinical one — don't confuse the two), `FSR_CHANNEL_ORDER`. CSS derives its
copy of the ramp from these via `--stop-*` custom properties set in
`Heatmap.renderLegend()` — it does not restate the numbers. A restated
threshold is a threshold that can silently drift from the one the contract
actually specifies.

**7. TS imports use `.js` extensions** (`import { ZONES } from
'./constants.js'`), even though the source files are `.ts`. This holds under
Vite: `tsconfig.json` sets `moduleResolution: "bundler"`, and Vite resolves
the `.js` specifier straight to the `.ts` source at both dev and build time.
Always write new imports this way.

## The safety rule: no fabricated bilateral readings

**Any bilateral metric computed from data on only one foot is a fabricated
clinical reading, not a degraded or rounded one.** ΔT, and eventually PAI and
symmetry once those exist, must show an explicit no-data state instead of a
number derived from whichever single foot happens to be reporting. This is
enforced at the data layer (`DeviceManager.deltaForefootC` is `null` unless
`isUsable(left) && isUsable(right)` and both report a value) and repeated at
every render site that displays it (Home's ΔT tile, Temperature's ΔT hero) —
deliberately redundant, because getting this wrong is worse than most bugs
this app could ship.

This rule has already caught two real bugs during development, which is why
it's stated this strongly:

- Status `0` ("not worn" / no usable data) was originally rendering with the
  same reassuring green as a genuinely safe reading, because the code that
  mapped tone → colour treated `'neutral'` as a fallback case of `'safe'`.
  Fixed by giving status 0 its own explicit `tone-neutral` styling.
- The heatmap's risk summary was reading "No high-risk zones" — the same
  all-clear message a genuinely safe reading produces — on a screen that had
  received **no data at all**. Fixed by adding a distinct `"No data"` /
  `tone-none` state, separate from the zero-high-risk-zones-found state.

If you're implementing anything that combines both feet into one number,
assume there's a third bug of this shape waiting and design the no-data path
first, not as an afterthought.

## Shared modules in `src/ts/`

- **`types.ts`** — UI-facing types: `AppData`, `PressureData`,
  `FootPressure` (keys: `hallux`, `meta1`, `meta3`, `meta5`, `midfoot`,
  `heel` — matches the contract's anatomical names), `AlertEntry` (now
  timestamp-based, `tUnixMs`, not a display string), `SeverityLevel`,
  `RiskStatus` (`0`–`5`; `0` is a UI-only "not worn" state the contract's
  1–5 scale doesn't define — see the comment at its declaration before
  "fixing" it), `PresetName`.
- **`constants.ts`** — clinical thresholds (see "Conventions" #6 above), the
  6-zone foot anatomy (`ZONES`), the SVG foot-silhouette path, the 6-state
  `STATUS_META` risk classifier metadata, preset labels,
  `ALERT_RECOMMENDATIONS`, `FSR_CHANNEL_ORDER`.
- **`mockData.ts`** — `MOCK_DATA: AppData` and the four `PRESETS`
  (`normal`, `diabetic`, `heavyHeel`, `forefoot`), all in kPa. `PRESETS`
  feeds `MockDataSource`, not the UI directly — screens read live data
  through `DeviceManager`, not `PRESETS`, wherever they're wired.
- **`navigation.ts`** — the bottom tab bar. Exports `TabId = 'home' | 'gait'
  | 'temp' | 'alerts'`, `currentTabId()` (derives the active tab from the
  hash), `initNavigation(opts?)`. Settings is reached via the header gear
  button, not a tab — it deliberately never calls `initNavigation`, leaving
  the bar empty. Also exports `renderStatusBar()`.
- **`heatmap.ts`** — `class Heatmap`. The reference implementation of the
  build-once-then-mutate pattern (see Conventions #3). Takes pressure data
  through its constructor and `setPressure()`; does **not** import
  `PRESETS` — the preset switcher buttons are built and owned by
  `home.ts`, which is a mock-source concern, and injected into `Heatmap` as
  an opaque `controls` element.
- **`pressureColor.ts`** — pure functions mapping a kPa value to colour,
  severity (`SeverityLevel`), and bilingual TH/EN advice, all derived from
  `PRESSURE_RAMP_KPA` in `constants.ts`.
- **`icons.ts`** — exports `refreshIcons()`, wrapping Lucide's
  `createIcons`. Only the icons the app uses are bundled, in the explicit
  `USED_ICONS` map. **If you add a new `data-lucide="..."` name, add it to
  that map too**, including names assigned dynamically (`home.ts`,
  `heatmap.ts`, `alerts.ts` all pick icon names at runtime). A dev-only
  warning fires for unresolved placeholders.
- **`data/`** — see "The data seam" above.

## Bilingual UI (TH primary, EN secondary)

All user-facing strings are pairs: a Thai label with the English label
rendered smaller alongside it (see the `th`/`en` fields throughout
`constants.ts`, `navigation.ts`, and the renderers). The `lang="th"`
attribute is set on `index.html`. Keep both languages in sync when adding
labels — never ship Thai-only or English-only copy.

## Visualization style

Every chart, sparkline, and foot diagram is hand-rolled SVG (see
`src/ts/gait.notes.md`, which predates the data layer and is now partly
stale — see `docs/BACKLOG.md` item 1). Do not introduce a charting library —
the app is deliberately dependency-light and must stay offline-capable.

---

## Next phase

In order:

1. ~~**Gait pass.**~~ Done — PAI is wired as a real rolling-window metric;
   see `docs/reports/003-gait-pai.md` and `docs/BACKLOG.md` item 1. What's
   NOT done, deliberately: the classifier, CoP, and 7-day trend all still
   have no data source and show an explicit unavailable state.
2. **`WebBleDataSource`** — a real `IDataSource` implementation using Web
   Bluetooth, built against the already-working ESP32 simulator (see
   "Sibling projects" above). The simulator and the standalone test page are
   both verified working independently; this app has not been connected to
   either yet.
3. **Capacitor**, to ship on Android.

Two architectural constraints already known to matter for that work,
both already reflected in code written before this handoff:

- **Web Bluetooth requires a user gesture per device.** Two insoles means
  two separate connect prompts — there is no way to pair both from a single
  gesture. `DeviceManager.connect(side)` and `connectAll()` are already
  per-side so the UI can drive this correctly, but the *UI* for two separate
  pairing prompts doesn't exist yet.
- **The app will run backgrounded on Android routinely** — this is why the
  timestamp-based staleness fix (Conventions #4) mattered enough to fix
  before wiring the remaining four screens rather than after. Anything else
  built on a timer-latches-state pattern will have the same failure mode;
  prefer derive-at-read-time wherever a background tab/app could plausibly
  starve a timer.
