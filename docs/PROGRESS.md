# Progress log

Pass history, in order. Each entry is what changed and what it unblocked —
not a full diff. Read `git log` (once this is under version control) or the
conversation history for the mechanics; read this for *why the code looks the
way it does*.

---

## 1. SPA conversion

**What changed:** Replaced the five independent `pages/*.html` (each its own
full page load, its own `<script type="module">`, its own `DOMContentLoaded`)
with a single `index.html` shell and a hash router (`src/ts/router.ts`,
`#/home` `#/gait` `#/temp` `#/alerts` `#/settings`). Every screen's
`DOMContentLoaded` listener became an exported `mount()`/`unmount()` pair. The
original per-page HTML files were kept as `pages.reference/` — dead markup,
not loaded by anything, retained only as a visual reference for what each
screen's scaffolding looked like.

**What it unblocked:** A page load tears down the entire JS context, which is
fatal to a persistent BLE connection — Web Bluetooth's `BluetoothDevice`/GATT
handle cannot survive one. The SPA shell is the prerequisite for any live data
source; nothing that came after this pass was possible without it.

**Notable fallout:** the settings screen was found to set an inline style
directly on the shared `#app-header` and never clean it up — harmless when
`#app-header` was recreated on every page load, a real leak once it became
persistent shell furniture. Fixed in this pass; the general lesson (see
CLAUDE.md) is the one that has bitten us more than once since.

---

## 2. Vite

**What changed:** Replaced the bare-`tsc` build with Vite. `index.html`
became Vite's entry, loading `/src/ts/main.ts` directly in dev.
`tsconfig.json` switched to `noEmit: true` (Vite's esbuild transform does the
actual emit; `tsc --noEmit` in the build script is what still catches type
errors). Vendored the two CDN dependencies that used to be `<script src=...>`
tags: Lucide icons (`src/ts/icons.ts`, a curated `USED_ICONS` map rather than
the full 2000+-icon barrel) and the three Google Fonts (`@fontsource/*`
packages, imported in `main.ts`).

**What it unblocked:** a dev server with HMR, and — the actual reason —
`node_modules` package imports, which the old `tsc`-only setup could not
resolve. This is the prerequisite for both the eventual Capacitor wrapper and
any BLE library. It also means the app now makes zero external network
requests at runtime, which matters once it's expected to run offline in a
native shell.

---

## 3. kPa units, zone renames, two-tier thresholds

**What changed:** The pressure pipeline moved from a unitless 0–100 "pressure
index" to kPa on a 0–250 display scale. Two zone keys were renamed to match
the contract's anatomical names: `toe` → `hallux`, `arch` → `midfoot` (the
other four — `meta1`, `meta3`, `meta5`, `heel` — were already correct). The
single `PRESSURE_DANGER_THRESHOLD = 75` became two named tiers,
`PRESSURE_WATCH_KPA = 75` and `PRESSURE_ALERT_KPA = 200`, plus
`PRESSURE_SCALE_MAX_KPA = 250` and a derived `PRESSURE_RAMP_KPA` object that
every colour breakpoint in both TS and CSS now reads from, so the ramp cannot
drift out of sync with the tiers it depicts. Added `FSR_CHANNEL_ORDER` in
`constants.ts` — the one authoritative mapping between the contract's indexed
wire array and the UI's name-keyed object, unused until the next pass.

**What it unblocked:** this is the pass that made the type shapes match the
Data Contract's units and vocabulary, which every subsequent pass depended on.

**Notable fallout:** a real label-collision bug was found and fixed — 3-digit
kPa values (e.g. "220") no longer fit the zone ellipses sized for the old
2-digit index values; the alert-tier label font size was reduced 14px → 12px.
The four mock `PRESETS` were rescaled by roughly ×2.5 with hand adjustments so
each preset still tells its intended clinical story (which zones cross into
which tier) rather than a blind linear scale.

---

## 4. `--brand-accent` fix

**What changed:** `--brand-accent` was referenced in five CSS rules (the
right-foot series colour on the gait symmetry bars and the 24h temperature
chart) and defined nowhere, so it resolved to nothing — the right-foot data on
both charts was invisible. Defined it as `#7E22CE`, chosen and justified by
CIEDE2000 colour-distance analysis, not by eye — see `docs/BACKLOG.md` for the
reasoning, which is worth preserving.

**What it unblocked:** nothing architecturally; this was a pass in its own
right because a bilateral-comparison app silently showing only one foot's
data on two charts is a correctness bug, not a cosmetic one.

---

## 5. `IDataSource` + `DeviceManager` + Home wired

**What changed:** Introduced the data-source seam: `src/ts/data/`
(`IDataSource.ts`, `MockDataSource.ts`, `DeviceManager.ts`, `types.ts`). One
`IDataSource` per foot, not one for both — two independent BLE peripherals
means one side can be connected while the other is absent, and a
combined-source design cannot express that. `DeviceManager` owns both sides,
converts `fsrKpa[]` → the UI's `FootPressure` via `FSR_CHANNEL_ORDER`,
coalesces two 50 Hz push streams into one throttled 10 Hz snapshot
(reference-counted timer — runs only while something is subscribed), and
refuses to compute ΔT unless both sides are usable.

Only Home was wired to it in this pass, deliberately — it's the screen that
exercises every hard part (the `Heatmap` component, the derived status badge,
per-side connection state, the ΔT tile) — so the cost of wiring the remaining
four screens could be estimated before committing to them.

`Heatmap` was rewritten from a rebuild-on-every-change component to a
build-once-then-mutate one: at 10 Hz, `innerHTML`-rebuilding the whole subtree
would restart the CSS pulse animation on every tick and drop the zone-detail
card mid-interaction.

**What it unblocked:** proved the seam's shape end-to-end (mock source →
manager → throttled snapshot → live-updating UI with correct no-data states)
on the hardest screen first, derisking the remaining four.

---

## 6. Remaining four screens wired + staleness fix

**What changed:**

- **Staleness bug fixed first.** It was originally a `setInterval` that
  latched a `'stale'` flag. Chrome throttles background-tab timers by
  seconds — measured a 400 ms sleep taking 1400 ms — so a backgrounded tab
  could report a dead stream as `'connected'` long after it died, which is
  the dangerous direction. Replaced with `derivedState()`: staleness is
  `Date.now() - lastSampleAt > 3000`, evaluated fresh on every read
  (`getStateOf()`, `snapshot()`, each throttle tick), never latched. Verified
  by silencing a source and leaving the tab backgrounded 78.7 s — the very
  first read afterward returned `'stale'` correctly.
- **Temperature** wired to the snapshot for the ΔT hero and foot map. Added a
  per-side temperature ring buffer to `DeviceManager`
  (`pushHistory`/`getTempHistory`, 10-minute buckets, 24h span) — the old
  `TempHistoryPoint` pre-joined both feet into one row and dropped the heel
  channel, which cannot represent "left present, right absent." The new
  per-side `TempHistoryPoint` (`data/types.ts`) can, and the 24h chart now
  draws a genuine gap — breaks the SVG path — on a missing bucket or a null
  channel instead of interpolating across it. The two synthetic "make the
  screen feel realistic" temperature alerts are gone; alerts are real now
  (next bullet).
- **Alerts.** `AlertEntry.time` (a display string like `'เมื่อวาน 18:05'`,
  grouped by substring-matching Thai words in it) became `tUnixMs`; the
  display string and the day bucket are both derived from the timestamp
  (`data/AlertStore.ts`). A new `AlertStore` generates real alerts from
  threshold crossings on the `DeviceManager` snapshot (pressure watch/alert
  tiers per side, ΔT), with the contract's 30-minute per-code repeat
  suppression. The acknowledge pill is now a real button wired to
  `alertStore.acknowledge()`.
- **Settings** device rows read live per-side connection state, battery, and
  firmware from `DeviceStatus` — previously a hardcoded `'v2.4.1'`.
- **Bootstrap fix:** every screen used to call `deviceManager.connectAll()`
  from its own `mount()`. That meant simply switching tabs silently
  re-established a link the user had deliberately disconnected, and made
  Home and Temperature disagree about ΔT. Connect now happens once, in
  `main.ts`, at app start.

**What it unblocked:** four of five screens now read live data end-to-end
with correct multi-state handling (`connecting` / `connected` / `stale` /
`error` / `disconnected`, both-sides-required no-data rules). Gait remains
deliberately unwired — see `docs/BACKLOG.md`.

---

## Current state

**Wired to live data (via `DeviceManager` / `AlertStore`):** Home, Temperature,
Alerts, Settings.

**Still static** (read `MOCK_DATA` or hardcoded values directly, no
`mount()`/`unmount()` subscription to the data layer): Gait — entirely. Its
classification card, stride array, and CoP trace are all literal/hardcoded;
see `docs/BACKLOG.md` for the pending pass and the decision it's waiting on.
Home's "today" tiles (steps / walking minutes / gait symmetry score) also
still read `MOCK_DATA.todaySummary` — there is no source for that data yet
and none is implied by anything built so far.

**Explicitly showing an unavailable state, by design, rather than a stale or
fabricated number:** ΔT on both Home and Temperature (null unless both sides
are usable); the heatmap's per-foot "no data" overlay; the temperature foot
map's per-foot "no data" overlay; the status badge's `0/5 Not worn` /
`tone-neutral` state; the risk summary's `"No data"` state (distinct from
`"No high-risk zones"`); the 24h temperature chart's line gaps.
