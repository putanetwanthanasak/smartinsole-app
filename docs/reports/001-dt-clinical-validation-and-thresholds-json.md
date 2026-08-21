# 001 — ΔT clinical-validation correction, thresholds.json promoted to its own item

**Written retroactively.** The chat summary for this pass was cut off
mid-sentence before reaching the user, losing most of its content — including
a real defect finding. This file exists so that never has to be reconstructed
from memory again; see item 2 of `docs/BACKLOG.md`'s originating request for
why reports now live here going forward.

**Commit:** `79303d2` — *comments+docs: separate DT clinical validation from
pressure's; promote thresholds.json*

**Scope:** comments and docs only. No `export const` line changed anywhere —
verified by diff before committing. `npm run build` clean.

---

## 1. `TEMP_DELTA_THRESHOLD`'s comment was wrongly swept into a correction meant for pressure

The previous pass ("contract agreement is not measurement validation",
commit `5411379`) corrected `PRESSURE_WATCH_KPA` / `PRESSURE_ALERT_KPA`'s
comments, which had drifted into claiming the Data Contract's presence
*validated* those values. That correction was right for the pressure
tiers — but it was applied to `TEMP_DELTA_THRESHOLD` too, and that was a
mistake: ΔT is not the same kind of value.

**Why it's different, in the user's own framing, preserved here because
it's the reasoning that makes the distinction non-obvious:**

- 2.2 °C comes from Lavery et al. (2004), a randomised controlled trial that
  validated the threshold against patient outcomes. That is external
  clinical validation — not a value this project agreed on internally the
  way 75/200 kPa were.
- The six-sensor absolute-magnitude under-reading caveat that legitimately
  applies to the pressure tiers does not transfer to ΔT. ΔT is a
  differential between two feet measured by the same system, so absolute
  sensor error largely cancels — the same reasoning that justifies using
  left-vs-right comparison for pressure asymmetry (PAI) in the first place.
  Applying a caveat reasoned from absolute-magnitude error to a differential
  metric conflates two different failure modes.

**The limitation that IS ours, stated in the corrected comment:** this
system samples two points per foot (forefoot, heel) rather than the
measurement protocol Lavery et al. used, so site selection — not the
threshold value — is the open question for ΔT.

### The corrected comment, verbatim (`src/ts/constants.ts`)

```ts
// °C between L/R same zone. Clinically validated threshold from Lavery et
// al. (2004) — a randomised controlled trial that validated 2.2°C against
// patient outcomes. That is external clinical validation, not a value this
// project agreed on internally, and it puts this constant in a different
// category from PRESSURE_WATCH_KPA/PRESSURE_ALERT_KPA above: the six-FSR
// absolute-magnitude under-reading caveat that applies to those two does NOT
// transfer here. ΔT is a differential between two feet measured by the same
// system, so absolute sensor error largely cancels out — the same reasoning
// that justifies using left-vs-right comparison for pressure asymmetry too.
//
// The limitation that IS ours: this system samples two points per foot
// (forefoot, heel) rather than the measurement protocol Lavery et al. used,
// so site selection — not the threshold value — is the open question here.
//
// One additional gap vs. the contract's own condition (Data Contract v1.1
// §8.3): the contract requires this to fire only after ≥2 consecutive
// over-threshold readings ("ต่อเนื่อง ≥ 2 ครั้งวัด"); `AlertStore.evaluate()`
// currently fires on a single reading. Not changed here — see
// `docs/BACKLOG.md` item 10.
export const TEMP_DELTA_THRESHOLD   = 2.2;
```

That last paragraph — the ≥2-consecutive-reading gap — is what item 2 of
this pass's follow-up request asked to be logged properly as a defect. See
`docs/reports/002-temp-delta-consecutive-reading-defect.md` for that
write-up; it was only a pointer here, not fully scoped, when this comment
was first written.

### Everywhere else checked for the same conflation

Per instruction, every comment touched by the prior "confirmed" correction
was re-checked, not just `TEMP_DELTA_THRESHOLD`:

- `PRESSURE_WATCH_KPA` / `PRESSURE_ALERT_KPA` — correctly left provisional;
  this was the one place the original correction was right.
- `FSR_CHANNEL_ORDER` and `data/types.ts`'s type-shape note — both are
  structural/definitional equality claims against the contract text (array
  index order, TS field shapes), not clinical-value claims. No change
  needed; confirmed nothing else had been swept up.
- `docs/BACKLOG.md` item 5 (sensitivity slider) had grouped ΔT and the
  200 kPa alert tier under one label, "clinical thresholds from the Data
  Contract, not user preferences." Rewritten to keep the *design
  constraint* (both stay fixed, slider can't touch either) but separate the
  *reason*: ΔT stays fixed because it's already validated against outcomes;
  `PRESSURE_ALERT_KPA` stays fixed because it's the hard notification floor,
  not because it's proven — it's still pending its own real-hardware
  validation (item 4).

---

## 2. `thresholds.json` promoted from a footnote in item 4 to its own item (11)

Item 4 (`PRESSURE_WATCH_KPA` / `PRESSURE_ALERT_KPA` provisional) had picked
up a secondary finding during contract reconciliation: the Data Contract
requires every threshold value to live in a runtime-loadable
`thresholds.json`, not be hardcoded in source, specifically so they can be
retuned after real-hardware testing without a rebuild. That finding is
correct but was underweighted as a footnote — it's a real architectural
gap that blocks two other backlog items, not a minor aside:

- **Item 5** (sensitivity slider): the proposed mapping scales
  `PRESSURE_WATCH_KPA` and the ΔT margin per-patient within clinician-set
  bounds. That can't work against a compile-time TS constant — there's
  nothing for the slider to write to at runtime.
- **Item 4** itself (75/200 kPa recalibration): once real hardware or the
  ESP32 simulator is feeding data, tuning `PRESSURE_WATCH_KPA` is expected
  to happen repeatedly during calibration. Doing that via source edits and
  rebuilds every time is exactly the friction `thresholds.json` exists to
  eliminate.

Promoted to **item 11**, cross-referenced from items 1 (PAI's threshold
pointer, previously pointing at item 4), 4, and 5. Item 11 also carries
forward the design constraint items 4/5 had already agreed: patient-facing
adjustment may scale the watch tier and ΔT margin within clinician-set
bounds, but must never move or disable the 200 kPa alert tier or the 2.2 °C
ΔT rule — whatever runtime-loading mechanism gets built has to preserve
that asymmetry between what a patient can and can't touch.

Not scoped further — where the file lives, how/when it's fetched, failure
behavior on a missing/malformed file, and whether `MockDataSource` needs its
own copy are all open for whoever picks item 11 up.

---

## What changed, file by file

- `src/ts/constants.ts` — `TEMP_DELTA_THRESHOLD` comment rewritten (verbatim
  above). No other constant's comment changed in this pass. No `export
  const` line changed.
- `docs/BACKLOG.md` — item 5 rewritten to separate ΔT's validation category
  from the pressure tier's; item 4's `thresholds.json` paragraph replaced
  with a short pointer to the new item 11; item 1's cross-reference
  repointed from item 4 to item 11; new item 11 added in full.
