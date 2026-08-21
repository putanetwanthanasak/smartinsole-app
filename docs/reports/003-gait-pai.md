# 003 — Gait screen: PAI wired as a real rolling-window metric

Implements `docs/BACKLOG.md` item 1 (decided, ready to implement). No
BLE, no classifier, no IMU processing, no stride segmentation, no walking
gate, no `RiskAssessment` type, no `thresholds.json` — all explicitly out of
scope for this pass, per instruction. Only `gait.ts`, `css/gait.css`, and
`constants.ts` changed; the other four screens are untouched.

---

## What changed, file by file

- **`src/ts/gait.ts`** — rewritten. PAI (Peak Asymmetry Index) is now a real
  metric computed from `DeviceManager.onSnapshot()`, accumulated into a
  rolling wall-clock window and rendered as both a headline figure and an
  8-column bar chart. The classification card, CoP trajectory, and 7-day
  trend are now static "unavailable" cards — the old `MOCK_DATA` /
  hardcoded-array content (`87%`, `2/5`, the 8-stride array, the decorative
  CoP SVG path) is deleted, not replaced with different fake numbers.
- **`css/gait.css`** — rewritten. Removed the now-dead rules for the deleted
  content (`.gait-classify*`, `.cop-*`, `.trend-row`/`.spark-*`/`.day-row`).
  Added `.nodata` / `.section-empty` (the shared unavailable-card pattern)
  and `.pai-row` / `.pai-big` / `.pai-sub` / `.pill.watch` (the PAI headline).
  `.symmetry-grid` / `.bar` / `.legend-row` kept — same chart chrome, now
  driven by real per-window peaks instead of the static `STRIDES` array.
- **`src/ts/constants.ts`** — added `PAI_WATCH_PCT = 15`, following the
  `PRESSURE_WATCH_KPA` pattern (named constant, not inlined), with the same
  "contract-recorded, not measurement-validated" caveat as the pressure
  thresholds (see `docs/BACKLOG.md` item 4).
- **`CLAUDE.md`** — "Wiring status" and "Next phase" updated: Gait was
  listed as entirely unwired; it's now "partially wired" (PAI real, the
  other three sections still unavailable-by-design). This report is linked
  from there so the next reader isn't working from a stale claim.
- **`docs/BACKLOG.md`** item 1 — marked IMPLEMENTED, plus a correction (see
  "What the backlog entry got wrong" below) and the `docs/BACKLOG.md` item
  10 addition on the `PRESSURE_PEAK` walking-gate cost estimate, done before
  this implementation started, per instruction.

---

## Design: how PAI is computed

`DeviceManager` does not accumulate a windowed peak anywhere (see
correction below) — the window logic lives entirely in `gait.ts`, screen-
local, since nothing else needs it yet:

- On every throttled snapshot (10 Hz) where both feet are usable
  (`isUsable(left) && isUsable(right) && left.pressure && right.pressure`),
  the per-side max-over-all-6-zones is folded into that side's running max
  for the in-progress window.
- When `WINDOW_MS` (2000 ms) elapses, that window closes: its `{peakL,
  peakR}` is pushed into a capped history array (`WINDOW_COUNT - 1` = 7
  entries) and a fresh window starts.
- The chart always shows exactly `WINDOW_COUNT` (8) columns: the 7 most
  recent completed windows, plus one live column that is the still-filling
  in-progress window. The headline PAI figure is computed from that same
  live column's numbers — by construction, the headline and the last bar
  cannot disagree, because they're reading the same two numbers.
- PAI itself: `|peakL - peakR| / ((peakL + peakR) / 2) × 100`, `null` when
  both peaks are 0 (undefined ratio, not a 0% asymmetry claim).

**The moment either foot stops being usable**, all window state (history +
in-progress accumulator) is discarded — not paused, not shown stale — and
the whole section falls back to the unavailable card. A fresh window starts
if/when both feet become usable again. This was a deliberate choice over
"pause and resume": resuming a window that was interrupted mid-way would mix
samples from before and after a gap of unknown length into one supposedly
2-second window, which is worse than just starting over.

---

## Exact wording used

### PAI section (`#symmetry`), live state

```
th:  ดัชนีความไม่สมมาตรของแรงกด
en:  Peak Asymmetry Index (PAI) · 2s rolling window
pill: OK | WATCH   (WATCH when PAI > PAI_WATCH_PCT)
big number: <PAI value to 1 decimal>%
sub (th): ต่ำกว่าเกณฑ์เฝ้าระวัง 15%  |  เกินเกณฑ์เฝ้าระวัง 15%
sub (en): watch threshold 15%
legend: เท้าซ้าย · L  /  เท้าขวา · R
```

**Axis labels under each bar column** (this is the answer to "the exact
wording used for the axis label"): each of the 8 columns is labeled by how
many seconds before now that window ended — `-14s`, `-12s`, `-10s`, `-8s`,
`-6s`, `-4s`, `-2s`, and `now` for the live column. Chosen specifically
instead of an ordinal ("#1"–"#8", what the old stride chart used) so the
chart cannot be misread as numbering discrete steps.

### PAI section, unavailable (no data / one foot down)

```
pill: NO DATA
body-th: ต้องมีข้อมูลทั้งสองข้าง
body-en: needs both feet
```

This is the exact phrase reused verbatim from `home.ts`'s ΔT tile
(`ต้องมีข้อมูลทั้งสองข้าง · needs both feet`) and matches `temperature.ts`'s
`dt-hero.nodata` state in structure (pill + em-dash + TH/EN caption pair).

### The three static unavailable sections

All three, and the PAI-unavailable state above, are rendered through one
shared helper (`unavailableCardHTML` in `gait.ts`) — same markup shape, same
`bluetooth` icon (the icon this app already uses for "no data from device"
in `heatmap.ts`'s risk summary and `home.ts`'s connection strip), same
`.nodata` CSS class. One pattern, four call sites:

| Section | th | en | pill | body-th | body-en |
| --- | --- | --- | --- | --- | --- |
| Classification | การจำแนกรูปแบบการเดิน | Gait classification | NOT AVAILABLE | ยังไม่มีระบบจำแนกรูปแบบการเดิน | No classifier built yet |
| CoP trajectory | ทางเดินจุดศูนย์ถ่วงแรงกด | Center of Pressure trajectory | NOT AVAILABLE | ยังไม่มีการคำนวณจุดศูนย์ถ่วงแรงกด | Not computed yet |
| 7-day trend | แนวโน้ม 7 วัน | 7-day trend | NOT AVAILABLE | ยังไม่มีข้อมูลแนวโน้มความสมมาตร | No trend data yet |

**Why these say "NOT AVAILABLE" and PAI's says "NO DATA":** the three static
sections are unavailable for a different reason than PAI — there is no
classifier, no CoP computation, and no trend-history source *regardless* of
how many feet are connected, whereas PAI's unavailability is specifically a
foot-connectivity question. Reusing "needs both feet" on the classifier card
would be false — connecting both insoles would not make a classifier exist.
Same visual pattern throughout; the copy stays honest about *why* each
section is empty.

---

## Grep verification (hard constraint)

Commands run, and results:

```
$ grep -vE '^\s*//' src/ts/gait.ts | grep -in "stride\|ก้าว"
(no output, exit code 1)

$ grep -in "stride\|ก้าว" dist/assets/index-*.js
145:        <div class="val">${t.steps.toLocaleString()}<span class="unit">ก้าว</span></div>
```

Zero hits in `gait.ts` outside of comments (the file's own header comment
and the window-definition comment, which *describe* the hard constraint and
explain why stride segmentation isn't used — comments are stripped by the
build, confirmed by checking the compiled bundle). The one bundle hit is
`home.ts`'s pre-existing "steps" tile unit label (`ก้าว` = "steps"),
unrelated to gait and outside this pass's scope (Home was not touched).

The first grep (`grep -in "stride\|ก้าว" src/ts/gait.ts` with no
comment-filter) does return 5 hits — all five are in `//` comments
explaining the constraint itself (e.g. "the words 'stride' / 'ก้าว' must not
appear..."), not in any rendered string. Both the filtered-source and
compiled-bundle checks confirm zero hits in anything a user could see.

---

## Verification performed vs. not performed

**Performed:**
- `npm run build` clean (`tsc --noEmit && vite build`), multiple times
  across the pass, most recently after the final edit.
- `npm run dev` (port 5173) and `npm run preview` (port 4174) both confirmed
  serving HTTP 200 via `curl`.
- Grep verification above.
- Careful manual trace of the subscribe/unsubscribe path: `gait.ts` pushes
  exactly one `deviceManager.onSnapshot(applySnapshot)` unsubscribe into
  `unsubs` in `mount()`, and `unmount()` calls every entry and clears the
  array — structurally identical to `home.ts`'s already-verified pattern
  (same push-in-mount / forEach-and-clear-in-unmount shape). `unmount()`
  also nulls out every cached DOM ref (`pillEl`, `paiNumEl`, `subThEl`,
  `barEls`) so a stale reference from a previous mount can't leak into a
  new one.

**NOT performed — the Chrome extension was disconnected this session, so no
browser automation was available:**
- Visually loading all five routes and eyeballing the render.
- The literal "10 navigations across all five screens, confirm subscriber
  count unchanged" check. `DeviceManager.stats().snapshotListeners` (exposed
  dev-only as `window.__insole.deviceManager.stats()`) is the intended way
  to confirm this — reasoned through above, not run.
- Watching the bars update live at 10 Hz to confirm no flicker/no restarted
  transition, and confirming the PAI figure visibly tracks the last bar.
- Forcing "one side down" via `window.__insole.mockSources.left.disconnect()`
  (the existing dev console hook, unused by me this pass) and watching PAI
  fall back to the unavailable card rather than showing a one-footed number.

These four are the ones the original VERIFY list asked for that require an
actual browser. I did not fabricate results for them. If the extension gets
reconnected, this is the fastest way to close the gap — happy to run it
immediately.

---

## What the backlog entry got wrong once I was in the code

`docs/BACKLOG.md` item 1's reasoning paragraph said PAI "needs only a peak
per foot per window, which `DeviceManager` already computes per side." That
computation didn't exist — `DeviceManager`'s snapshot only ever carries the
single latest sample's pressure per side; nothing upstream of the screen
tracked a windowed peak. I built the windowing (running max per side,
rolled every `WINDOW_MS`) inside `gait.ts` itself rather than in
`DeviceManager`, since nothing else in the app needs it yet and it's
straightforward to hoist into the data layer later if a second consumer
(e.g. `AlertStore`'s eventual `ASYMMETRY_PEAK` rule, item 9) needs the same
windowed peaks. Corrected in `docs/BACKLOG.md` item 1 directly rather than
silently fixed.

No other requirement in the backlog entry turned out to be wrong or need
reinterpretation once in the code — the six requirements and the hard
constraint were followed as written, no forks hit that needed stopping to
ask about.

---

## Decisions made that the backlog entry left unspecified

Not forks — these were within the stated requirements, just not spelled out
to the letter, so recorded here rather than asked about:

- **Bar chart labeling**: relative-time offsets (`-14s`…`now`) rather than
  ordinals (`#1`–`#8`, what the old chart used), specifically to avoid any
  reading of the axis as counting discrete steps.
- **Carry-forward smoothing**: right after a window rolls over, before the
  new window has its first sample, the headline/live-bar keep showing the
  just-completed window's numbers rather than flashing to a placeholder.
  Avoids a cosmetic flicker every `WINDOW_MS`; doesn't change what's
  computed or when a window is considered "complete."
- **Icon choice**: `bluetooth` for all four unavailable states (already the
  established "no data from device" icon per `heatmap.ts`'s risk summary),
  even though the three static sections aren't really about device data —
  chosen for visual consistency across the one shared pattern over a
  more literally accurate icon per section.
