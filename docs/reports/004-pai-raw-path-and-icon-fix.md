# 004 — PAI raw-sample path, unavailable-card icon fix, browser verification closed

Three corrections to `docs/reports/003-gait-pai.md`'s pass. Item 1 is a
correctness fix, not polish — see below.

---

## 1. PAI was computed from downsampled data — fixed

**The bug:** `gait.ts` folded its running window-peak from
`DeviceManager.onSnapshot()`, which is throttled to 10 Hz. A 2 s window at
the source's real 50 Hz rate is 100 samples; `onSnapshot` only ever
delivered 20 of them. The reported "peak" was the maximum of a set with 80%
of the data discarded — and discarded non-randomly: plantar pressure rises
and falls fast at heel strike, exactly the kind of signal downsampling loses
the peak of. The result was compared against thresholds (`PAI_WATCH_PCT`,
and indirectly `PRESSURE_ALERT_KPA` via the bar heights) drawn from
research using much higher measurement rates, compounding the under-reading
this app already has from six discrete sensors per foot.

**The fix — a raw path in `DeviceManager`, alongside the throttled one, not
instead of it:**

- `DeviceManager.onSnapshot()` is completely unchanged — still 10 Hz, still
  what every other screen uses, still what UI rendering should use.
- Added `DeviceManager.onRawSample(cb): Unsubscribe` (`src/ts/data/
  DeviceManager.ts`) — fires on every converted sample as it arrives,
  unthrottled (up to 50 Hz per side). Emits a new `RawPressureSample`
  (`side`, `tUnixMs` — arrival time, matching every other timestamp in this
  file — and `pressure`, pre-converted to `FootPressure` so nothing outside
  `DeviceManager` ever touches raw `fsrKpa`, preserving the existing
  wire-conversion invariant).
- `gait.ts` now has two subscriptions, two jobs: `onRawSample` folds the
  running per-side max into the current window (measurement); `onSnapshot`
  gates accumulation on both-feet-usability and drives the 10 Hz render
  (display). Measurement rate and render rate are two different
  subscriptions now, not one conflated stream.
- The both-feet-usable gate is now a module-level flag (`bothUsableNow`),
  refreshed once per `onSnapshot` tick and read (not re-derived) by the raw
  handler — accurate to within 100 ms, which is more than enough resolution
  for a 2000 ms window.

**Empirically re-verified after the fix** (see §3 below): the headline PAI
figure was independently recomputed from the live bar's rendered heights and
matched the displayed number exactly (46.5% both ways) — confirming the fix
didn't just change the code, the live app's numbers are internally
consistent post-fix.

### What the raw path costs, and what would need to change for a heavier subscriber

Asked to state this explicitly rather than leave it implicit:

- **Current cost: negligible.** `onRawSample` fires synchronously, on the
  same thread as everything else, before the sample handler that triggered
  it returns — up to ~100 calls/sec combined across both feet. The one
  current subscriber (`gait.ts`'s window-fold) does O(1) work per call (a
  6-element `Math.max`, two comparisons, occasionally an array push/shift
  capped at 7 entries). That's microseconds of work at 100 Hz — not a
  measurable cost against a 10 Hz UI render budget.
- **What would NOT be safe:** anything synchronous and heavier — model
  inference, a per-sample IndexedDB write, network calls — run directly in
  an `onRawSample` callback. Because it fires on the same single JS thread
  as DOM updates and every other timer in the app, a slow raw-subscriber
  callback would block that thread for its duration, which would stall the
  10 Hz UI (the exact failure mode the throttle split exists to avoid) for
  however long the heavy work takes.
- **Nothing had to change for THIS subscriber**, because it stays cheap by
  design. But there is no queueing, batching, or Web Worker offload
  mechanism in `onRawSample` today — if the eventual Model A inference path
  or a raw data-collection export subscribes here and does real
  per-sample work, that infrastructure does not exist yet and would need to
  be built at that point, not assumed to be already handled. Documented as
  a warning directly in `onRawSample`'s docstring in `DeviceManager.ts` so
  it isn't missed by whoever adds the second subscriber.

### `docs/BACKLOG.md` item 1 updated

The item's "Correction found while implementing" note (from report 003, which said the window-fold happened in `gait.ts` off the throttled snapshot) is now itself corrected in place — updated, not left contradicting the code. Also added: Data Contract v1.1 §7.1 fixes Model A's input at `[1, 100, 24]`, i.e. 100 timesteps at the contract's 50 Hz rate — exactly the raw path's rate, not `onSnapshot`'s. Recorded so whoever builds that model input or a raw-data export starts from `onRawSample`, not from copying `onSnapshot` usage elsewhere in the codebase.

---

## 2. The `bluetooth` icon on the three "not built yet" cards was wrong — fixed

The copy on those three cards was deliberately written to avoid the false
implication that connecting both insoles would make a classifier/CoP/trend
exist — but the icon said exactly that anyway, and most people read an icon
before its caption.

**Fix:** `bluetooth` now appears only on the PAI-unavailable state, where
it's accurate (that unavailability really is a connectivity question — see
`docs/reports/003-gait-pai.md`'s reasoning for why PAI alone gets the
"needs both feet" copy). The three static cards (classification, CoP,
7-day trend) now use `construction` — reads as absent-by-design, not
absent-for-now — added to `USED_ICONS` in `src/ts/icons.ts`. One icon
shared across all three, as suggested; visual consistency across the four
unavailable states now comes from the shared layout/colour/card-shape
(unchanged), not from a shared icon that misstated the reason.

Verified live in the browser (not just by reading the code) — see §3.

---

## 3. The four previously-unverified checks — all closed, browser was available this session

The Chrome extension connected successfully this session. All four ran for
real; none of these numbers are inferred from code review.

### Five routes render

Navigated to `#/home`, `#/gait`, `#/temp`, `#/alerts`, `#/settings` in a
real tab against `npm run dev`. All five rendered correctly (screenshots
taken for each). No console errors traceable to the app — the only console
exceptions present were `"A listener indicated an asynchronous response..."`,
a known Chrome-extension-messaging artifact unrelated to this app's code (no
`gait`/`TypeError`/`ReferenceError`/`[icons]` matches in the console at any
point).

### 10 navigations across all five screens, subscriber count

Cycled `#/home → #/gait → #/temp → #/alerts → #/settings` ten times via
`window.location.hash`, then returned to `#/gait` and read
`window.__insole.deviceManager.stats()` (now reports `rawListeners` too,
added alongside the fix in §1) before and after:

```
before: { snapshotListeners: 2, rawListeners: 1, timerRunning: true }
after:  { snapshotListeners: 2, rawListeners: 1, timerRunning: true }
```

Unchanged. `snapshotListeners: 2` while `gait` is mounted is the expected
baseline, not a leak — `AlertStore` holds its own permanent `onSnapshot`
subscription from module load (by design, per `CLAUDE.md`: "an alert the
user wasn't looking at is exactly the one that matters"), so 1 belongs to
`AlertStore` and 1 to whichever screen is currently mounted.
`rawListeners: 1` is exactly `gait.ts`'s one raw subscription, present only
while gait is mounted — separately confirmed by reading `stats()` on
`#/home` mid-cycle (`rawListeners: 0` there) and back on `#/gait`
(`rawListeners: 1` again), so the raw subscription's mount/unmount symmetry
was checked directly, not just inferred from the before/after pair.

### Bars update live without flicker or restarted transition; PAI figure tracks the last bar

Tagged every `.bar.l` element with a `dataset.testMarker` (a value only
JavaScript could have set, that an `innerHTML` rebuild would wipe), recorded
the live PAI figure and all bar heights, waited 1.8 s, then re-read:

- **Same DOM nodes**: `sameNodeIdentity: true` for all 8 bars — the exact
  element references from before the wait were still in the DOM after,
  proving no `innerHTML` rebuild happened (the same failure mode the
  heatmap pulse-ring bug came from, per `CLAUDE.md` Convention #3).
- **Values genuinely moved**: PAI went `45.3 → 46.0` over that window, and
  the live column's bar heights changed continuously — this is a live
  signal, not a frozen one that merely avoided a rebuild.
- **PAI figure tracks the bars, checked by direct recomputation, not just
  visual comparison**: read the live column's rendered `L`/`R` bar heights,
  converted back to kPa peaks, recomputed PAI independently —
  `recomputedPai: "46.5"` — and compared against the DOM's own displayed
  figure — `displayedPai: "46.5"`. Exact match.

### One side down via the dev hook: PAI falls back to unavailable, not a one-footed number

Ran `window.__insole.mockSources.left.disconnect()` from the console (the
existing dev-only hook, unused until now):

```
{ className: "gait-card nodata", pill: "NO DATA",
  bodyTh: "ต้องมีข้อมูลทั้งสองข้าง", bodyEn: "needs both feet",
  hasBars: false, leftState: "disconnected" }
```

`hasBars: false` — the bar chart's host element was gone entirely
(replaced by the unavailable card), not showing a partial or one-footed
figure. Screenshot confirms the same visually: PAI shows the `bluetooth`
icon + "NO DATA" pill, classification/CoP still show `construction`.
Reconnected (`mockSources.left.connect()`), waited 3 s: PAI resumed —
`{ className: "gait-card", pill: "WATCH", paiNum: "45.5", leftState:
"connected" }` — confirming the recovery path (fresh window on reconnect,
not a resumed stale one) also works, not just the failure path.

---

## What changed, file by file

- **`src/ts/data/types.ts`** — added `RawPressureSample` (side, arrival
  `tUnixMs`, pre-converted `pressure`).
- **`src/ts/data/DeviceManager.ts`** — added `onRawSample()`, the
  `rawListeners` set, firing it from inside the existing `onSample` handler
  in `box()`; `stats()` now also reports `rawListeners`; `dispose()` clears
  the new set too.
- **`src/ts/gait.ts`** — split into `handleRawSample()` (accumulation, off
  the raw stream) and `applySnapshot()` (gating + 10 Hz render, off
  `onSnapshot`); two subscriptions in `mount()`, both unsubscribed in
  `unmount()`. `unavailableCardHTML()` now takes an `icon` parameter; the
  three static cards pass `construction`, the PAI-unavailable state passes
  `bluetooth`.
- **`src/ts/icons.ts`** — added `Construction` to `USED_ICONS` and the
  docstring listing dynamically-assigned icon names.
- **`docs/BACKLOG.md`** item 1 — corrected the stale note from report 003
  about where window accumulation happens; added the Model A / raw-export
  consumption note.

---

## Verify

`npm run build` clean (`tsc --noEmit && vite build`), confirmed after every
edit in this pass and again at the end. No other screen touched.
