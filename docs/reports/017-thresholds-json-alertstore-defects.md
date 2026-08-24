# 017 — thresholds.json (BACKLOG item 11) + AlertStore's two §8.3 defects (item 10)

## Branch note — reads before anything else

This branch is **`work/thresholds-json-alertstore-defects`, branched off
`work/alertstore-gait-advisory` (report 016), not off `main`.** `main` does
not yet have report 016's two commits (the DATA-CONTRACT.md v1.2→v1.4 merge,
and `GAIT_ABNORMAL` removal/§8.3.1 advisory layer) — that PR is still open.
This pass's code imports things report 016 added (`GAIT_ADVISORY`,
`MIN_CONFIDENCE`, `withGaitAdvisory`, `getGaitPrediction`) and edits files
report 016 already restructured, so branching off `main` directly would have
meant redoing or duplicating that work rather than building on it. **Merge
report 016's PR first, then this one** (or rebase this branch onto `main`
after that merge) — merging this one first would reintroduce report 016's
changes as part of this PR's diff.

## BACKLOG item numbers — also flagged before proceeding, per this pass's own instruction

The prompt referenced "items 3 and 4/10" / "items 3, 4, and 10." In the
current `docs/BACKLOG.md`, items 3 and 4 are Font subsetting and the
PRESSURE_WATCH_KPA/PRESSURE_ALERT_KPA provisional-value note — neither
matches this pass's actual scope. The content described in the prompt (the
`thresholds.json` JSON shape, the write-protection design constraint, the
TEMP_DELTA consecutive-reading defect, the PRESSURE_PEAK walking-gate
finding) matches **items 10 and 11** exactly, word-for-word in the case of
the JSON shape. Read both fully before writing any code. Not treated as a
stop-and-ask case like report 016's contract-version mismatch — the content
itself is unambiguous and internally consistent (unlike that case, where the
document was genuinely a different version), so this looks like the item
numbers having drifted, not the content. Flagging so it isn't silently
"corrected" without you seeing it.

---

## PART 1 — `thresholds.json` (BACKLOG item 11)

### Design decisions item 11 explicitly left open, made and documented here

**Where the file lives:** `public/thresholds.json`, fetched at runtime from
`/thresholds.json`. Vite copies `public/` into `dist/` unchanged, so this is
simultaneously "bundled" (ships with every build, works offline the first
time) and "fetchable/overridable at runtime" (ops or a clinician can replace
that one file in a deployed build's static assets — swap it on the server,
or in the Capacitor asset directory later — without a JS rebuild). Both
options from item 11's open question, not a choice between them.

**What happens on missing/malformed:** `data/thresholds.ts`'s `loadThresholds()`
never throws and never leaves anything partially applied. On ANY failure —
network error, non-2xx, invalid JSON syntax, or a shape/range violation
caught by `validateThresholds()` — it logs one `console.error` naming
exactly what was wrong (every violation found, not just the first), then
explicitly re-applies `DEFAULT_THRESHOLDS` (the compiled-in fallback,
`Object.freeze`d, matching Data Contract §8.3's JSON exactly). "Fail loud
with the bundled default" from the brief, literally: loud (console.error,
specific), safe (a complete, valid, known-good config either way — never a
partial merge, never `undefined`). Demonstrated in Verify below.

**Whether `MockDataSource` needs awareness of it:** No, for pressure/temp
thresholds — it already reads `PRESETS`/`MOCK_DATA` (fixed scenario data
unrelated to alert thresholds) and clamps jitter using `PRESSURE_RAMP_KPA`,
which now updates live with zero changes to `MockDataSource.ts` needed (see
the live-binding mechanism below — confirmed working in Verify). It DOES
need one new thing for Part 2's walking gate: `setWalking()`, a mock-only
method in the same spirit as the existing `setPreset()`.

### How every existing call site kept working with zero import changes

Grepped exhaustively first (12 files reference these constants:
`AlertStore.ts`, `MockDataSource.ts`, `heatmap.ts`, `gait.ts`,
`temperature.ts`, `home.ts`, `pressureColor.ts`, plus comment-only mentions
in `capture.ts`/`blePacketParser.ts`/`data/types.ts`). Several of those are
screens — this pass's brief said not to touch any screen's rendering, which
looked at first like a real conflict with "every call site... needs to
switch to reading from this loaded config."

Resolved by changing WHERE `constants.ts`'s exports get their values from,
not WHAT anything imports:

- Every threshold (`PRESSURE_WATCH_KPA`, `PRESSURE_ALERT_KPA`,
  `TEMP_DELTA_THRESHOLD`, `PAI_WATCH_PCT`, `MIN_CONFIDENCE`, plus new ones
  below) is now `export let`, not `export const`, initialized from
  `DEFAULT_THRESHOLDS` at module load.
- `PRESSURE_RAMP_KPA` is now a plain mutable object (dropped `as const`),
  with its properties updated in place by `recomputeDerivedRamp()` instead
  of being computed once.
- `data/thresholds.ts`'s loader calls `applyThresholds(cfg)` (exported from
  `constants.ts`), which reassigns every `let` and calls
  `recomputeDerivedRamp()`.
- ES modules give `let` exports **live bindings** — every importer sees the
  current value on every read, because none of the 7 consumer files copy a
  threshold into their own module-top-level variable; all of them read the
  imported name at call time, inside a function invoked after boot (checked
  each one before relying on this). This is exactly what CLAUDE.md
  convention #6 ("thresholds live in `constants.ts`") already set up — one
  indirection point is what makes swapping the backing store possible
  without touching a single screen.

Confirmed live in the browser (Verify below): loading an override with
`watchKpa: 80` changed `PRESSURE_WATCH_KPA` AND the already-computed
`PRESSURE_RAMP_KPA` object, readable via the exact same import every
screen already uses, no reload needed.

### New fields beyond the contract's current shape

- `motion: { walkingAccelG, walkingWindowMs }` — needed for Part 2's
  `PRESSURE_PEAK` walking gate, which the contract's `thresholds.json`
  shape doesn't define. Same status as the §5.1 `offset_adc`/`÷1000` fix
  from earlier passes: a local addition, documented as such in
  `constants.ts`, not yet sent upstream to the contract owner.
- `PRESSURE_PTI_KPA_S`, `PTI_ASYMMETRY_WATCH_PCT`, `LOAD_CONCENTRATION_ALERT_PCT`
  — flat constants for `pressure.ptiKpaS`/`asymmetry.ptiPct`/`asymmetry.concentrationPct`,
  which the contract's shape already specifies but no rule consumes yet
  (`PRESSURE_PTI`/`ASYMMETRY_PEAK`/`LOAD_CONCENTRATION` are all still
  unimplemented, BACKLOG item 9). Added for shape parity — `applyThresholds()`
  sets them from a loaded file even though nothing reads them yet, so they
  don't silently regress to stale/wrong values whenever those rules do land.

### The hard-floor write-protection — structural, not conventional

Two DIFFERENT trust levels needed separating, which the brief's wording
("patient-facing... vs. downstream of a user-facing control") pointed at but
didn't fully spell out — worth being explicit about since I had to make a
call here:

1. **`thresholds.json` itself (loaded by `applyThresholds()`)** — an
   ops/clinician-controlled file, not reachable from any in-app UI. This
   channel CAN and SHOULD be able to set every field, hard floor included:
   that's the entire point of BACKLOG item 4/12's real-hardware
   recalibration of `PRESSURE_ALERT_KPA` itself, not just the watch tier.
2. **A future patient-facing sensitivity slider (BACKLOG item 5, not built
   this pass)** — this is the actor the brief's hard-floor constraint is
   actually about. `setPatientSensitivity(pct: number)` in `constants.ts` is
   the one function meant to ever be reachable from that UI. The structural
   guarantee: its parameter is a bare percent — there is no field in its
   signature that could name `PRESSURE_ALERT_KPA` or `TEMP_DELTA_THRESHOLD`,
   so no caller, however buggy or malicious, can reach them through this
   entry point. Not "the slider doesn't call the dangerous function" — the
   dangerous capability isn't present in this function's surface at all.
   Confirmed in Verify: calling it at both extremes (0 and 100) only ever
   moves `PRESSURE_WATCH_KPA` (between a placeholder 50–100 kPa bound,
   flagged provisional pending real clinician input); `PRESSURE_ALERT_KPA`
   and `TEMP_DELTA_THRESHOLD` never move.

Item 5's older note also mentions scaling "the ΔT alert margin" — not
implemented, and said so explicitly in `constants.ts`'s comment: the
contract's `thresholds.json` shape has no separate soft ΔT tier, only the
hard-floor `deltaC`, so there's nothing to scale there yet. If the contract
grows one, extend `setPatientSensitivity` the same narrow-parameter way,
never by giving it access to `TEMP_DELTA_THRESHOLD`.

Per the brief, no slider UI was built — `setPatientSensitivity()` exists so
that pass has something correct to wire up to, unused by any caller today.

---

## PART 2 — AlertStore's two §8.3 defects (BACKLOG item 10)

Re-read item 10's full audit table first, per this pass's instruction — both
defects were already correctly diagnosed there; this pass just fixes them.

### 1. `TEMP_DELTA` — now requires 2 consecutive over-threshold readings

Added `AlertStore.tempDeltaState` (`{ streak, lastReadingKey }`) and
`evaluateTempDelta()`. The key design point: a "reading" has to mean an
actual new temperature SAMPLE arriving (contract: ~1/30 Hz on real
hardware; `MockDataSource`: 1/second), not an `onSnapshot` tick (10 Hz) —
otherwise the same one underlying reading would get counted as ~dozens of
"consecutive readings" before the next real temperature packet even
arrives. `lastReadingKey` (the newer of `left.temp.tUnixMs`/
`right.temp.tUnixMs`) detects a genuinely new reading; ticks that
re-observe the same reading are no-ops on the streak. Resets to 0 on ANY
under-threshold reading (not just disconnect) and on `deltaForefootC`
going `null` (disconnect/unusable/bad quality) — per the brief.

### 2. `PRESSURE_PEAK` — walking gate

`AlertStore` now also subscribes to `deviceManager.onRawSample()` (existing
API, not a `DeviceManager` change) and keeps a small per-side rolling buffer
of accel magnitude, pruned to `WALKING_WINDOW_MS`. The push+prune in the raw
callback is O(1)-amortized, per `DeviceManager.onRawSample`'s own cost note
(must stay cheap — it runs synchronously up to 50 Hz/side, before the sample
handler that triggered it returns); the actual gate check (`isWalking()`,
O(window size)) runs lazily from `evaluate()` at the throttled 10 Hz rate,
not from the raw callback.

**Gate signal:** mean deviation of accel magnitude from 1g over the window,
compared to `WALKING_ACCEL_G`. Magnitude (not a fixed axis) because a
foot-mounted IMU's orientation relative to gravity rotates through the gait
cycle — magnitude is the invariant that stays ~1g at rest regardless of
orientation. A MEAN over the window, not a single-sample peak, is what makes
this "sustained" per the brief, and — observed during testing, not
designed for this specifically — is also what makes it naturally robust
against `MockDataSource`'s existing per-tick independent random accel
jitter, which averages toward ~0 deviation over a window instead of reading
as sustained motion.

**Where the gate applies, and where it deliberately doesn't:** only the
alert tier (`pressure.alert.<side>`, §8.3's actual `PRESSURE_PEAK` text:
"...ขณะเดิน"). `PRESSURE_WATCH` has no walking condition in the contract
(confirmed against item 10's own audit table), so a static high reading
correctly still surfaces at the watch tier — informational, no push
notification — even while seated. Implemented as
`if (worst >= ALERT_KPA && isWalking(side)) { alert-tier } else if (worst >= WATCH_KPA) { watch-tier }`:
a static 230 kPa reading falls through to the watch tier rather than firing
nothing, which is correct per the contract's own two-tier design (BACKLOG
item 10's clinical reasoning: static seated loading isn't the hazard
`PRESSURE_PEAK` exists to catch, but it's still worth surfacing
non-urgently). Confirmed in Verify.

**`MockDataSource.setWalking()`** (mock-only, same status as `setPreset()`):
default `accelG` is uncorrelated per-tick noise that averages near zero over
any window (quiet stance); `true` generates a sustained ~2 Hz oscillation
with amplitude well above any reasonable gate threshold — not a physically
accurate gait waveform, just something clearly distinguishable for testing.

---

## Verify

**`npm run build`** — clean (`tsc --noEmit && vite build`) after every
change, several times through the pass.

**Grep confirms zero hardcoded threshold reads outside the loader.** The
same 12 files reference these names before and after this pass; all still
do so via `import` — none inline a literal number that duplicates a named
threshold (the DEFAULT_THRESHOLDS object, `public/thresholds.json`, and the
placeholder `WATCH_KPA_MIN`/`MAX` slider bounds are the only literals, and
all three are the intended single source, not a duplicate).

**Live browser verification** (`npm run dev` + Chrome console, using
`window.__thresholds`/`window.__alertStore`/`window.__insole` dev hooks):

- **Live config update, zero screen changes needed:** loaded a Blob-URL
  override (`watchKpa: 80, alertKpa: 210, deltaC: 2.5, ...`) via
  `window.__thresholds.load(url)` → `{ ok: true, source: 'file' }`; a fresh
  dynamic `import('/src/ts/constants.ts')` (same cached module instance)
  showed `PRESSURE_WATCH_KPA: 80`, `PRESSURE_ALERT_KPA: 210`,
  `TEMP_DELTA_THRESHOLD: 2.5`, and `PRESSURE_RAMP_KPA` fully recomputed
  (`{low:26.67, mid:53.33, watch:80, watchHigh:145, alert:210}`) — the
  live-binding mechanism, and that the file channel legitimately can set the
  hard-floor fields (see the trust-level distinction above). ✅
- **Missing/malformed file, all three modes, all fail loud + fail safe:**
  a 404 path, syntactically invalid JSON, and a well-formed-JSON-but-bad-shape
  file (`watchKpa >= alertKpa`, `deltaC: "not-a-number"`,
  `minConfidence: 5`) each returned `{ ok: false, source: 'default', error: "..." }`
  with a specific, itemized message (the bad-shape case listed all 3
  violations in one error, not just the first); `PRESSURE_WATCH_KPA`/
  `PRESSURE_ALERT_KPA`/`TEMP_DELTA_THRESHOLD` were confirmed back at their
  bundled-default values after all three, no leftover partial state. ✅
- **ΔT consecutive-reading, isolated from the live mock stream** (both
  sides disconnected first, so the real stream's own ΔT~2.4°C couldn't
  interleave with the synthetic test): reading 1 (over threshold) → streak
  1, no alert. Same reading re-observed (same `tUnixMs`, simulating extra
  10 Hz ticks before the next real temp packet) → streak stays 1, no
  double-count. Reading 2 (new, over threshold) → streak 2, alert fires. ✅
  Separately: reading 1 (over) → streak 1; reading 2 (UNDER threshold) →
  streak resets to 0; reading 3 (over, 1st since reset) → does NOT fire;
  reading 4 (over, 2nd consecutive) → fires. ✅ (both scenarios from the
  brief, plus the same-reading-dedup case beyond what was asked)
- **Walking gate:** `heavyHeel` preset, left heel ≈230 kPa (alert-tier
  magnitude), `setWalking(false)` (default) → alert tier did NOT fire,
  watch tier DID fire (`"แรงกดเริ่มสูงที่ส้นเท้า...230 kPa..."`) — the
  static-load-still-surfaces-at-watch-tier behavior described above, not a
  silent no-op. ✅ Then `setWalking(true)`, waited past `WALKING_WINDOW_MS`
  → alert tier fired at the SAME 230 kPa reading
  (`"แรงกดเกินเกณฑ์อันตรายที่ส้นเท้า...230 kPa..."`). ✅
- **`setPatientSensitivity()` structural check:** called at both extremes
  (`0` and `100`) — only `PRESSURE_WATCH_KPA` moved (between 50 and 100,
  the placeholder bound), `PRESSURE_ALERT_KPA` (200) and
  `TEMP_DELTA_THRESHOLD` (2.2) never changed; confirmed the function takes
  exactly one parameter, so there is no argument position that could name
  either hard-floor field. ✅

One environment note, not a defect: mid-session, after many console
round-trips in one long-lived tab, `DeviceManager` correctly reported a side
as `'stale'` — the same Chrome background/long-running-tab timer throttling
documented in `docs/DATA-CONTRACT.md`'s Conventions #4 and hit once during
report 016's verification too. A page reload cleared it; not related to
anything changed this pass.

No screen was touched — `heatmap.ts`, `gait.ts`, `temperature.ts`,
`home.ts`, `pressureColor.ts` are byte-identical to before this pass.
