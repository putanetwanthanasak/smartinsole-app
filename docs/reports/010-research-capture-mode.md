# 010 — Research capture mode

Builds `#/capture`, the operator-only screen for the 30-volunteer data
collection study: subject entry → session calibration → per-pattern
recording → CSV/JSON export, backed by IndexedDB so a session survives a
reload. Additive only — the five patient screens, `DeviceManager`'s
throttling, `WebBleDataSource`, and all thresholds are untouched except one
necessary, minimal extension noted below.

Also in this pass, ahead of the capture-mode work: merged the contract
owner's Data Contract v1.2 into `docs/DATA-CONTRACT.md` (Model A's classes
are now gait patterns, not risk levels — see the merge commit), and added
the real `docs/SmartInsole_TestProtocol_v1.md`. Both already committed and
confirmed with the user in chat; not re-covered here except where they
constrain this pass's design (they do, throughout §2–§4 below).

## 1. Files

- `src/ts/capture.ts` — the screen (`mount`/`unmount`), all UI.
- `src/ts/capture/types.ts` — `GaitLabel`, `SubjectInfo`, `SessionCalibration`,
  `SessionRecord`, `SampleRow`, `CSV_COLUMNS` (the fixed schema).
- `src/ts/capture/store.ts` — IndexedDB (`sessions` + `samples` stores,
  cursor-based streaming, storage estimate, delete).
- `src/ts/capture/recorder.ts` — buffers `onRawSample` into rows, flushes on
  an interval.
- `src/ts/capture/csv.ts` — CSV + metadata JSON builders, download trigger.
- `css/capture.css`, route wiring in `router.ts`, two new icons
  (`Play`/`Square`) in `icons.ts`.
- One extension to existing code: `RawPressureSample` (`data/types.ts`) grew
  `accelG`/`gyroDps` alongside `pressure`; `DeviceManager.ts` populates them
  at the one existing emit site. See §5.

## 2. The one deviation from "don't touch existing files": `RawPressureSample`

The spec is explicit that recording must read `DeviceManager.onRawSample()`,
and the CSV schema is explicit that it needs `accel_x/y/z` and `gyro_x/y/z`.
But `RawPressureSample` as it existed only carried `pressure` — gait.ts (the
only other consumer) never needed IMU data, so it was never added.

I extended the interface with `accelG`/`gyroDps`, populated from the same
`SensorSample` already in scope at the one place `RawPressureSample` is
constructed (`DeviceManager.ts`'s `onSample` handler). This is additive —
new fields, same emit rate, same call site, existing consumer (gait.ts)
unaffected because it only ever destructured `.pressure`. I judged this
necessary rather than a fork to stop and ask over, since the alternative was
either inventing a second raw subscription (duplicate 50 Hz plumbing) or
silently deviating from the fixed CSV schema — both worse. Flagging it here
per the report instructions.

## 3. Batching interval — chosen and measured

**Chosen: 1000 ms**, per the spec's suggested starting point. `Recorder`
accumulates `SampleRow`s in a plain array from the raw callback (O(1) work
per sample — push + one counter increment, per `DeviceManager.onRawSample`'s
own cost warning) and flushes the whole array in one IndexedDB transaction
per tick, not per sample.

**Measured:** Verified end-to-end against `MockDataSource` (which
deliberately mirrors real hardware's 50 Hz, per its own top-of-file
comment) via Chrome automation driving the actual dev build:

- Isolated raw-callback rate, tab foregrounded: 502 callbacks over
  5008 ms measured wall-clock = **100.2/s combined** (50.1 Hz × 2 sides).
- Through the full path (Recorder → IndexedDB → CSV), an 8.0 s take
  produced 401 rows per side = **50.1 Hz per side**, confirmed three ways:
  cursor count on the `samples` store, the exported CSV's row count, and the
  CSV's first/last row timestamps.
- A ~100-row combined batch every 1 s stayed well under any visible cost —
  no dropped frames or blocked UI observed on the recording screen's
  10 Hz-driven timer/badges during sustained recording.

One artifact worth recording since it looked alarming mid-verification: an
*earlier* attempt at this same measurement, taken while the automation
tab was backgrounded (`document.hidden === true`), showed only 26 rows over
~11.7 s — Chrome's background-tab timer throttling (the exact mechanism
CLAUDE.md's Convention #4 already documents and measured at 400 ms→1400 ms)
hitting `MockDataSource`'s own `setInterval`-based stream, not a defect in
capture's write path. Re-measured with the tab confirmed foregrounded and
the rate was correct. Noted here because it's a real trap for anyone
re-verifying this by driving the app through browser automation rather than
a human's foregrounded tab.

**Not yet measured: real ESP32 hardware.** The mock stands in faithfully
for rate (both are nominally 50 Hz, and the DeviceManager code path is
identical downstream of `onSample`), but BLE notify jitter, MTU/packet-loss
retries, and actual device timing are unverified. See §8 for exactly what
to run.

## 4. `isValid` in the CSV

Written as the literal strings `"true"`/`"false"` (not `1`/`0`, not
Python's `"True"`/`"False"`) — the most interoperable encoding for a reader
that doesn't already know the column is boolean. This was a real choice,
not a given, since the schema fixes the column name but not its encoding —
recorded here per the report instructions rather than left implicit in
`capture/csv.ts`'s `csvCell()`.

Mechanically: `Recorder.toggleInvalid()` flips an `invalidActive` flag;
every row built from `handleRaw()` while that flag is set gets
`isValid: false`. It's a toggle, not a momentary mark — press once when the
subject falls out of the instructed gait, press again when they're back.
Verified at the sample level: a take with invalid marked for ~1.2 s produced
three contiguous runs (true ×40, false ×60, true ×46 rows) — the false run
landing at exactly the marked span, confirmed both via the live
"ช่วงที่ทำเครื่องหมาย" list the operator sees and by reading the stored rows
directly.

## 5. What happens on reload

`capture.ts`'s `mount()` calls `store.getActiveSessions()` — any session
record with `endedAtUnixMs === null` — before rendering anything else. If
one exists, the operator sees a resume prompt (subject code, how long ago it
started, whether calibration was captured) with two choices, never a silent
default:

- **Resume** — recomputes `patternCounts` from the actual stored rows
  (`store.recountPatterns`, a full cursor scan) rather than trusting
  whatever was last flushed before the interruption, then jumps to the
  calibration step (if calibration was never captured) or straight to
  recording (if it was).
- **Export what exists** — runs the same CSV/JSON export immediately, then
  offers the same resume-or-not choice again.

No delete option is offered here, deliberately — the resume prompt's copy
says so explicitly. `Recorder`'s in-memory `patternCounts` mirror is only a
display convenience for the *current* mount; `recountPatterns()` is the
authoritative source of truth on resume, since a crash mid-flush can leave
the mirror stale by up to one flush interval.

Verified: recorded ~3.5 s of `toe_walking` at 50 Hz/side, full page reload
(not SPA navigation — a real `navigate()` to a fresh load), resume prompt
appeared with the correct subject code and elapsed time, Resume landed
directly in the recording step with `L 4w`/`R 4w` for the pattern recorded
before reload — accurate because `windowCount()` counts floor(samples/100),
and the pre-reload row count was already in IndexedDB.

## 6. Bugs found during verification (all fixed)

Found by actually driving the built app, not by inspection — listed because
two of them would have shipped invisibly otherwise.

1. **Subject-entry form overflowed its container.** `.cap-input` had no
   explicit `width`, so browser-default input sizing (~20ch) blew out the
   402 px device frame in the two-column grid. Fixed: `width: 100%` +
   `min-width: 0` on the grid/field ancestors.

2. **Invalid-interval list didn't refresh when a span closed.** The list
   only re-rendered on the interval *array's length* changing (a cheap
   guard against rebuilding on every 10 Hz tick), but closing a span only
   mutates the last entry's `endMs` — same length, no re-render. The
   operator would see "กำลังดำเนินอยู่ (in progress)" stuck forever after
   tapping the invalid button off. Fixed: the button's own click handler
   now forces one immediate re-render on both open *and* close, independent
   of the tick-driven length check.

3. **The real one — `recountPatterns()` returned a partial map, and that
   crashed the whole per-pattern progress list on resume.** It only created
   an entry for a `GaitLabel` if at least one row with that label existed,
   so a resumed session that hadn't yet recorded, say, `antalgic` had no
   `antalgic` key at all. `Recorder.windowCount()` indexed straight into
   that map without a guard, threw `TypeError: Cannot read properties of
   undefined (reading 'left')` on the first untouched pattern, and — since
   this fired inside `DeviceManager`'s `tick()` loop calling every
   `onSnapshot` listener in sequence — silently aborted the `for...of` over
   `GAIT_LABELS` partway through. Result: the progress list rendered only
   the first pattern (`normal`) correctly and left the other four
   permanently blank, with the actual exception visible only in the
   console, never surfaced to the operator. Fixed at the source:
   `recountPatterns()` now seeds from `emptyPatternCounts()` so all five
   keys always exist; `windowCount()` also gained a defensive
   `?? {left:0,right:0}` fallback so a future malformed record degrades to
   showing zero instead of taking the render down with it. Re-verified:
   all five patterns render correctly after the fix, no console errors.

This third one is exactly the shape of bug CLAUDE.md's safety-rule section
warns about generalizing to — a silent partial failure that "looks correct"
(one pattern updates fine) until you check the other four. Caught only
because the VERIFY checklist called for reload-recovery testing, not
because anything looked wrong at first glance.

## 7. Scope cuts (deliberate, not oversights)

- Invalid-span visibility is a plain append-only text list ("marked for
  X.Xs"), not a graphical timeline. Satisfies "make its effect visible
  after the fact" without the complexity of a scaled timeline widget for a
  device-frame-width screen.
- No in-app browsing of past *ended* sessions — only the currently-active
  (or just-resumed) session is addressable from the UI. Ended sessions stay
  in IndexedDB (queryable via devtools) until explicitly deleted; nothing
  in the spec asked for a session list/browser.
- Calibration's 30 s average reads from `onSnapshot` (10 Hz), not
  `onRawSample` (50 Hz) — unlike recording, which must use the raw path.
  300 samples over 30 s of someone standing still is plenty for a stable
  mean, and it avoids a second raw subscription running alongside
  `Recorder`'s. This is a considered choice, not the same requirement as
  §RECORDING's 50 Hz mandate (that one is about not silently sub-sampling a
  *signal being classified*; calibration is averaging a *static* value).
- `CALIBRATION_DELTA_WARN_C = 0.5°C` and `RECORDING_TARGET_WINDOWS = 90`
  (from the protocol's 3-minute-per-pattern figure) are both local,
  UI-only heuristics I picked — not contract thresholds, don't confuse with
  `TEMP_DELTA_THRESHOLD` (2.2°C). Neither blocks anything; both are purely
  visual aids. Documented inline in `capture.ts` at declaration.

## 8. What to run for the real hardware check

I verified the write path end-to-end against `MockDataSource` (§3) since I
have no access to your ESP32 simulator. To confirm the same 50 Hz result
against real hardware:

1. Flash/power the simulator so it's advertising as `SMARTINSOLE-L` /
   `SMARTINSOLE-R`.
2. `npm run dev`, then open **`http://localhost:5173/?ds=ble#/capture`** in
   Chrome (Web Bluetooth requires Chrome; `?ds=ble` is the existing
   dev-only switch in `DeviceManager.ts` — see "Sibling projects" in
   CLAUDE.md).
3. Use the dev BLE connect panel (`devBlePanel.ts`, already mounted
   whenever `?ds=ble` is active) to pair LEFT then RIGHT — two separate
   browser permission prompts, expected.
4. Once both show connected, capture mode's calibration gate behaves
   identically to the mock run — proceed through calibration → recording as
   normal.
5. Record ~10–15 s of any pattern, export, and check the CSV: count rows
   per side, divide by the take's wall-clock duration. Should land at
   ~50/s/side, not ~10 (a ~10 Hz result would mean something is reading
   from `onSnapshot` instead of `onRawSample` — it isn't, per §3, but this
   is the check that would catch it if a future edit broke it).

## 9. Verify checklist

- [x] `npm run build` clean (`tsc --noEmit && vite build`) — confirmed
      after every fix, final state clean.
- [x] All five existing routes unchanged — navigated to all five via the
      running dev build, correct `viewClass` on `#view` each time, zero
      console errors.
- [x] 50 Hz in the exported CSV (mock) — 50.1 Hz/side measured three
      independent ways (§3). Real hardware: see §8, not run by me.
- [x] Column names/order match the schema exactly — CSV header string
      compared directly against `CSV_COLUMNS`, identical.
- [x] Reload mid-recording recoverable — verified (§5).
- [x] Disconnect one side mid-recording visible & recorded, not dropped —
      disconnected LEFT ~1 s into a take: LEFT stopped writing rows
      immediately (51 rows ≈ 1.0 s), RIGHT kept writing for the full
      ~3 s take (151 rows), connection badge showed `L: disconnected`
      live. Nothing silently dropped.
- [x] Subscriber count unchanged after 10× navigation in/out of
      `#/capture` — `deviceManager.stats()` identical before and after
      (`rawListeners: 0, snapshotListeners: 2, timerRunning: true` both
      times — the 2 is Home's own baseline, capture leaves nothing behind).
- [x] Calibration blocks with a specific missing-side message — verified
      by disconnecting RIGHT before starting a session: banner read
      "ยังไม่เชื่อมต่อ: ขวา · right", Start button disabled.

## 10. Things that turned out to need a decision, or were wrong in the spec as read

None where I had to stop and ask beyond the two already resolved in
chat (the Data Contract v1.2/§5.1 merge, and the
`SmartInsole_TestProtocol_v1.md` filename). Within this pass itself,
everything in the spec mapped cleanly onto the existing architecture except
§2's `RawPressureSample` gap (§2 above) — flagged, not asked about, because
the fix was unambiguous once the CSV schema was taken as fixed (per your
own instruction not to touch that).
