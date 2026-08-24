# 016 — Data Contract v1.2→v1.4 merge, then §8.3.1 gait-pattern advisory layer

Two things in this pass: reconciling `docs/DATA-CONTRACT.md` to v1.4 (blocked
the original ask until done), then implementing v1.4 §8.3's AlertStore
changes on top of it.

---

## Part 0 — DATA-CONTRACT.md merge (v1.2 → v1.4)

The repo's contract was still v1.2 and missing §8.0/§8.3.1 entirely — stopped
and reported this rather than guessing, per this pass's brief and the
project's own instruction to do so when the contract file is stale. The user
supplied the authoritative `docs/DATA-CONTRACT-v1.4-new.md`; diffed it
against the repo's v1.2 before touching anything, same protocol as the
v1.1→v1.2 merge earlier in the project.

**Found and flagged before merging, both confirmed with the user:**

1. **The incoming file's own H1 read "Data Contract v1.0"** while its
   metadata table and revision history both said 1.4 — an internal
   inconsistency in the file as received, not a repo-side issue. Fixed to
   read v1.4.
2. **§5.1's FSR formula in the incoming file reverted the two hardware-
   verified local corrections this repo has carried since the v1.2 merge**
   (`offset_adc` zero-point subtraction, confirmed resolved by the contract
   owner per `docs/reports/006-*.md`; the Pa→kPa `/1000` step, confirmed
   against real ADC/kPa hardware pairs per `docs/reports/008-*.md`). Same
   gap as the v1.2 merge, not yet sent upstream a second time. **Kept the
   repo's corrected §5.1 text**, not the incoming reverted version —
   `src/ts/data/blePacketParser.ts`'s `adcToKpa()`/`correctAdc()` already
   implement both corrections, confirmed unchanged.

Everything else in v1.4-new.md — the new §8.0 clinical background, the
`GAIT_ABNORMAL` removal + §8.3.1 addition, the §8.4 `gaitClass` fusion note,
and revision history rows 1.3/1.4 — adopted as received, no repo-side
content at risk there. Merge committed separately
(`merge: reconcile DATA-CONTRACT.md to v1.4`) before any code change.

---

## Part 1 — `GAIT_ABNORMAL` removal

**Turned out to be a no-op in code.** Grepped `src/` before changing
anything: `GAIT_ABNORMAL` was never implemented in `AlertStore` — it's
listed among the seven not-yet-implemented alert codes in
`docs/BACKLOG.md` item 9 ("a gait classifier model — explicitly out of
scope per item 1"), confirmed against `docs/reports/002-*.md`. Nothing to
remove. `AlertStore.evaluate()` today only raises `pressure.watch`/
`pressure.alert` (→ `PRESSURE_WATCH`/`PRESSURE_PEAK`) and `temp.delta` (→
`TEMP_DELTA`).

## Part 2 — the §8.3.1 advisory layer

### The gap this pass had to design around

The contract's condition is "Model A's most recent prediction... at that
same moment." **No such thing exists anywhere in this codebase** — there is
no live gait-classifier output; `data/types.ts`'s own comment already
flagged this (`GaitClass` "does not exist in this codebase yet"), and
`docs/BACKLOG.md` items 8/9 confirm it's explicitly out of scope elsewhere.
The task's own verify steps ask to test with "MockDataSource... set to
simulate heel_walking with confidence >= 0.6" — implying a mock seam needed
to be built, since none exists.

This pass's brief also said: don't touch `DeviceManager`, `WebBleDataSource`,
or capture mode. `DeviceManager` is the only place that currently combines
both feet into one snapshot — and Model A's input is explicitly **both
feet's channels combined** (§7.1), not per-side, so it doesn't fit
`IDataSource`'s per-foot shape either (`MockDataSource`'s existing
`setPreset()` pattern is per-side; a gait prediction isn't).

Given the constraint and the shape mismatch, built this as a new,
independent seam rather than routing it through the forbidden files:

- **`src/ts/data/types.ts`** — added `GaitClass` (the 5-way union) and
  `GaitPrediction` (`{ tUnixMs, pattern, confidence }`), next to the
  existing comment that already anticipated this gap.
- **`src/ts/data/gaitPrediction.ts` (new)** — a standalone module-level
  singleton: `getGaitPrediction()` / `setMockGaitPrediction()`. Deliberately
  NOT on `IDataSource` or routed through `DeviceManager`, for the reason
  above. No production caller exists yet — same status as
  `MockDataSource.setPreset()` had before any UI called it. This is the seam
  a real Model A integration will eventually write into.
- **`src/ts/constants.ts`** — `MIN_CONFIDENCE = 0.60` and `GAIT_ADVISORY`
  (the zone-relevance + Thai-text table from §8.3.1), keeping with this
  file's existing convention of centralizing contract-derived thresholds and
  text (`ALERT_RECOMMENDATIONS` already lives here the same way).
- **`src/ts/data/AlertStore.ts`** — new private `withGaitAdvisory(message,
  zoneId)`, called at both existing pressure-rule call sites
  (`pressure.alert.*`, `pressure.watch.*`) with the triggering zone. Returns
  `message` unchanged if there's no prediction, confidence is below
  `MIN_CONFIDENCE`, or the pattern isn't relevant to `zoneId`. Never touches
  `severity`/`type`/`statusLevel`. `PRESSURE_PTI` and `LOAD_CONCENTRATION`
  have no call site to attach to — neither rule is implemented yet
  (`docs/BACKLOG.md` item 9); when they land, they should call the same
  helper.
- **`src/ts/main.ts`** — dev-only console hooks, gated on
  `import.meta.env.DEV`, next to the existing `__insole` handle in
  `DeviceManager.ts` (not touched): `window.mockGait.set(pattern,
  confidence)` / `.clear()` to drive the mock prediction, and
  `window.__alertStore` (the singleton) so a rule's 30-minute repeat-
  suppression can be cleared for retesting from the console.

### The rotated_foot direction question

Per your answer: live `AlertStore` has no way to know in-toeing vs.
out-toeing (that's only `PatternNotes.rotatedFootNote`, a capture-mode
session note, not available at inference time). Used the direction-neutral
wording you supplied, `zones: 'any'` (same no-zone-targeting treatment as
`antalgic`), rather than inferring direction from pressure asymmetry — which
would fabricate an unmeasured value the same way `deltaForefootC` on one
foot would. Implemented exactly as specified; no judgment call needed here
since you'd already resolved it.

---

## Verify

- **`npm run build`** — clean (`tsc --noEmit && vite build`), twice (once
  after the contract merge only touched docs, again after all code changes).
- **`grep -rn "GAIT_ABNORMAL" src/`** — zero hits.
- **Live verification**, `npm run dev` + Chrome, using the new
  `window.mockGait`/`window.__alertStore` console hooks (mock presets don't
  naturally land a *watch*-tier value at *heel* specifically, so most cases
  below use the *alert* tier — same `withGaitAdvisory()` code path, both
  call sites are identical logic):
  - `heel_walking` @ 0.75 confidence, heel zone (alert tier, `heavyHeel`
    preset) → advisory appended, `severity: 'danger'` unchanged. ✅
  - Same alert, confidence 0.4 → base message only, no advisory. ✅
  - Same alert, pattern `normal` @ 0.9 → base message only, no advisory. ✅
  - `heel_walking` @ 0.9 at a *non-heel* zone (meta1, watch tier, right
    side `diabetic` preset) → no advisory, `severity: 'warning'` unchanged
    — the exact "wrong zone" case from the brief. ✅
  - `toe_walking` @ 0.8 at meta1 (alert tier) → advisory appended. ✅
  - `antalgic` @ 0.9 at meta1 (`zones: 'any'`) → advisory appended. ✅
  - `rotated_foot` @ 0.9 at meta1 (`zones: 'any'`, direction-neutral
    wording) → advisory appended, exact text matches your answer. ✅
  - No `mockGait` call at all (prediction stays `null`, the real-world
    no-Model-A-yet state) → message byte-identical to pre-pass output. ✅
  - One transient false alarm during this: after many console round-trips
    in the same tab, `DeviceManager` correctly reported `left` as `'stale'`
    (Chrome throttling the mock source's `setInterval` in a long-running
    automated tab — the exact background-timer behavior
    `docs/DATA-CONTRACT.md`'s Conventions #4 already documents and defends
    against). Reloading the page cleared it. Not a regression from this
    pass — reproduced the same way against pre-pass code by inspection of
    the unrelated timer/staleness logic, which this pass didn't touch.

No screen was touched; `alerts.ts` already renders `AlertEntry.message` as
one string, so the appended sentence needs no UI change.
