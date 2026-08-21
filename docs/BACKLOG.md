# Backlog

Deferred work, with enough context to act on each item without re-deriving it.
Ordered roughly by what blocks what. Items marked **(assistant-flagged)** were
raised by Claude during earlier passes rather than requested by the user —
worth knowing which is which when prioritizing.

---

## 1. Gait screen pass — IMPLEMENTED

**Done.** See `docs/reports/003-gait-pai.md` for the full pass report,
including where this entry's own reasoning turned out to be slightly
wrong once in the code (flagged inline below rather than silently fixed).
The rest of this entry is kept as the historical record of the decision.

The gait screen used to show nothing real: the classification card's
"87% confidence" and "status 2/5" are literal template text, the 8-stride bar
chart array has no data source, and the CoP trajectory is a fixed decorative
SVG path. There is no gait classifier and none is in scope for this pass.

**The decision (previously recorded here as open — it was not; the user had
simply not sent it yet):** rolling-window relabel, option (a), built as a
real metric, not a placeholder.

**Why this is the right call, not just the available one** — this is the
part that makes the choice non-obvious, so it's recorded rather than just the
conclusion: PAI (Peak Asymmetry Index) is a metric the Data Contract already
specifies, and it was designed specifically to avoid needing stride
segmentation. With six discrete sensors per foot rather than a full pressure
mat, absolute peak pressure under-reads badly (see item 4 below) — but the
left-vs-right *ratio* stays meaningful even when both sides under-read
together. PAI = `|L-R| / ((L+R)/2) × 100` needs only a peak per foot per
window. So this is not a stand-in awaiting IMU work — it is the metric. When
stride segmentation eventually lands, the window definition changes from "2 s
wall-clock" to "1 stride" and the metric formula survives unchanged.

**Correction found while implementing:** this paragraph originally said the
per-window peak was something "`DeviceManager` already computes per side" —
it wasn't. `DeviceManager`'s snapshot only ever carries the latest single
sample's pressure per side; nothing upstream of the screen accumulates a
peak over a window. The rolling-window accumulation (fold each 10 Hz
snapshot's per-zone max into a running window peak, roll the window every
`WINDOW_MS`) is implemented in `gait.ts` itself, not in `DeviceManager` — see
the report for why that's the right layer for it (screen-local state, not
shared data-layer state, since nothing else needs it yet).

**Now recorded in Data Contract v1.1 §8.2–8.3** (`docs/DATA-CONTRACT.md`,
filled in after this entry was first written): PAI watch threshold is
**15%** (`"asymmetry": { "peakPct": 15, ... }`). That is the team's agreed
figure, not a value validated against measurement — same caveat as item 4
below applies here too; treat it as a starting point, not a settled number.
The contract's alert rule
for it, `ASYMMETRY_PEAK`, additionally requires PAI > 15% to hold for "≥ 20
ก้าว" (≥20 steps) before firing — the same rolling-window substitution this
whole item is built around applies there too: there is no step count yet,
so the alert-firing condition (not the on-screen metric label, which stays
under the hard constraint below) will need its own window-based stand-in
when `AlertStore` gains an `ASYMMETRY_PEAK` rule (currently unimplemented —
see item 9).

**Requirements (not suggestions):**
- Surface the computed PAI number on screen, not just the bars — it is a
  contract metric, not a decorative chart.
- The PAI watch threshold (15%, per above) goes in `constants.ts`, named,
  not inlined — follow the pattern of `PRESSURE_WATCH_KPA` /
  `PRESSURE_ALERT_KPA`. Same caveat as item 11: the contract wants this in
  `thresholds.json` eventually, not hardcoded — match whatever that item
  lands on, don't solve it independently here.
- PAI is computed only when both feet are usable (`isUsable(left) &&
  isUsable(right)`, same guard as `DeviceManager.deltaForefootC`). One-footed
  asymmetry is not a degraded reading, it's meaningless — same no-data state
  as everywhere else this rule applies (see "The safety rule" in
  `CLAUDE.md`).
- **HARD CONSTRAINT: the words "stride" / "ก้าว" must not appear anywhere in
  that section** — heading, axis label, legend, tooltip, or any other label.
  Grep both terms before reporting the pass done.
- Structure the window definition (currently "2 s wall-clock") as a single
  named constant/comment such that swapping it for "1 stride" once
  segmentation exists is a one-line change — comment it as such at the
  declaration site.
- The other three sections on the screen — the classification card, the CoP
  trajectory, and the 7-day sparkline — become explicit unavailable states,
  visually consistent with the unavailable-foot treatment already used on
  Home. Delete the "87%" and the "2/5" outright, don't replace them with a
  different fake number. Remove the decorative CoP path entirely — a fake
  trace next to an "unavailable" caption is worse than an empty box.

This is ready to implement — no further decision is pending.

---

## 2. Redundant encoding on the two bilateral charts — needs usability validation **(assistant-flagged)**

The gait symmetry bar chart and the 24h temperature chart both distinguish
left vs. right by colour alone (`--brand-primary` green vs. `--brand-accent`
purple). Analysis during the `--brand-accent` fix concluded **colour alone is
not sufficient for this app's audience** — this reasoning is non-obvious and
would be expensive to redo, so it's preserved here rather than just the
conclusion:

- The accent colour (`#7E22CE`) was chosen by simulating CIEDE2000 distance
  under protanopia, deuteranopia, *and* tritanopia against the left-foot
  green, not just picking "a different-looking colour." Tritanopia
  (blue-yellow deficiency) was weighted deliberately: it's commonly an
  **acquired** condition in diabetic patients specifically (this app's stated
  population), not just a rare congenital case to token-check.
- Even with a colour pair that survives all three deficiency simulations,
  colour-only encoding is fragile at the actual rendered size — the gait bars
  are ~9px wide with a 3px gap, well below the visual angle where hue
  discrimination is reliable, and diabetic retinopathy independently reduces
  contrast sensitivity in exactly this population.
- Proposed redundant encoding (not implemented, scoped out of every pass so
  far on explicit instruction): a pattern-fill or texture difference between
  the two bar/line series, or persistent inline "L"/"R" labels at the data
  rather than only in the legend.

This needs actual usability validation before implementation, not another
round of colour-theory analysis — tag it as such when picked up.

---

## 3. Font subsetting before Capacitor

`dist/` is currently ~1.6 MB; 98 of its 101 files are font files. The
`@fontsource/*` packages ship every Unicode subset (Latin, Latin-ext, Greek,
Cyrillic, Vietnamese, Thai) in multiple formats. The browser only fetches the
subsets it actually needs, so this is invisible in normal web use — but a
Capacitor build bundles the entire `dist/` into the APK regardless of what a
given device would fetch. Needs trimming to the subsets actually used
(Latin + Thai, essentially) before the Android phase.

---

## 4. `PRESSURE_WATCH_KPA = 75` / `PRESSURE_ALERT_KPA = 200` are provisional — still open

Both values are documented in comments at their declarations in
`constants.ts`, repeating here so it isn't missed: published peak plantar
pressures for normal barefoot gait routinely exceed 75 kPa, so taken at face
value this threshold would flag healthy walking as a concern. Simultaneously,
this build's six discrete FSRs per foot (vs. a full pressure mat) will
systematically under-read the true peak, since a sensor rarely sits exactly
on it. Those two errors push in opposite directions and neither is
quantified. `PRESSURE_ALERT_KPA` (200 kPa) carries the same caveat — it's
sourced from Owings et al. (2009), measured with high-density pressure
mapping, so the same discrete-sensor under-reading problem applies to it as
much as to the watch tier. **Do not tune either value against the mock
`PRESETS`** — both need recalibration against real hardware data once the
ESP32 simulator or real insoles are feeding the pipeline.

**Now that Data Contract v1.1 is in the repo (`docs/DATA-CONTRACT.md` §8.3),
one distinction is worth stating precisely, because it's easy to blur:**
75/200 appear there as the team's agreed values
(`"pressure": { "watchKpa": 75, "alertKpa": 200 }`) — that means they're
*settled as a decision*, not that they're *validated against measurement*.
The contract is a document this project's team drafted; it records what was
agreed, not what's been checked against real device data. §8.3's own note —
that 200 kPa comes from a dense research pressure mat while this system has
six discrete FSRs per foot and will under-read true peaks — says the
validation gap explicitly, in the contract's own words. Nothing about that
gap has closed by the contract existing. Treat these two numbers exactly as
provisional as before; the contract changes where they're recorded, not
their evidentiary status.

The architectural question of *how* these get recalibrated without a
rebuild — the contract requires a runtime-loadable `thresholds.json`, which
doesn't exist yet — is its own item now: see item 11. That item is a
dependency of this one; recalibrating 75/200 against real hardware
repeatedly, as expected, is exactly the scenario `thresholds.json` exists
to avoid rebuilding for.

---

## 5. Settings sensitivity slider — inert, proposed mapping not implemented

`settings.ts`'s "Alert sensitivity" slider writes to in-memory `state` and
drives nothing. Proposed mapping, not implemented: it should scale
`PRESSURE_WATCH_KPA` and the ΔT alert margin within clinician-set bounds, so
a patient can make the app more or less talkative.

**Design constraint (already agreed, recorded here as a requirement, not a
suggestion): the slider must never be able to disable or move
`PRESSURE_ALERT_KPA` (200 kPa) or `TEMP_DELTA_THRESHOLD` (2.2 °C).** Both are
fixed floors, not user preferences — but for different reasons, worth
keeping straight: `TEMP_DELTA_THRESHOLD` is externally clinically validated
(Lavery et al. 2004, an RCT validated against patient outcomes) and a
patient-side slider has no business softening a threshold that's already
been tested against real outcomes. `PRESSURE_ALERT_KPA` is a
project-internal, contract-recorded value still pending its own real-hardware
validation (see item 4) — it stays fixed here not because it's proven, but
because it's the hard notification-worthy tier and loosening it is a
clinical decision, not a comfort setting.

**Blocked on item 11:** this mapping can't actually be implemented until
thresholds are runtime-adjustable rather than hardcoded `constants.ts`
exports — see item 11, which this item depends on.

---

## 6. Seed alerts anchored to "today" — will go stale, and can be future-dated

`mockData.ts`'s seed alerts (`MOCK_DATA.recentAlerts`) are timestamped
relative to the moment the app runs (`at(daysAgo, hh, mm)`) specifically so
their rendered strings match what the old hardcoded values said
(`'14:32'`, `'เมื่อวาน 18:05'`, etc.) regardless of what day it actually is.
One side effect: if the app is opened before the anchored time-of-day (e.g.
before 14:32), that seed alert is timestamped slightly in the future. This is
a mock-data artifact, not a real bug — **delete `MOCK_DATA.recentAlerts` and
its `at()` helper entirely once `AlertStore` is seeded from real generated
alerts** (i.e. once there's been enough real usage, or once this is no longer
being demoed from a cold start).

---

## 7. Dead CSS rule in `heatmap.css` **(assistant-flagged)**

`css/heatmap.css` line 95, `fill: url(#shade)`, targets an SVG gradient id
that doesn't exist — the actual per-foot gradients are `shade-left` /
`shade-right`, and each zone's `fill` is set as an inline SVG attribute
anyway, which wins over the CSS rule regardless. Harmless (the rule never
fires) but should be deleted or corrected next time that file is touched.

---

## 8. Other items flagged during earlier passes, not yet actioned **(assistant-flagged)**

- **`RiskAssessment` type does not exist yet.** Every pass so far has been
  explicitly told to keep Home's derived-status logic ad hoc rather than
  introduce it. It will eventually need: `statusLevel`, `gaitClass`,
  `confidence`, `deltaT*`, `peakKpa`, `ptiKpaS`, `peakAsymmetryPct`,
  `ptiAsymmetryPct`, `loadConcentrationPct`, `symmetryScore`,
  `highRiskZones`, `source`. Waiting on the gait/PAI work above and, likely,
  on-device or backend classifier output — not just a type definition
  exercise.
- **`RiskStatus` keeps a `0` state ("not worn") that the Data Contract's
  1–5 scale doesn't define.** This is intentional and documented at its
  declaration in `types.ts` — flagging here only so nobody "fixes" it to
  match the contract without reading that comment first.
- **Alert repeat-suppression is per-code, in-memory, 30 minutes,
  matching the Data Contract** — but there's no persistence across a page
  reload (the whole `AlertStore` is an in-memory singleton). Fine for a
  prototype; will matter once this needs to survive an app restart on
  Android.

---

## 9. `AlertStore` implements 2 of the contract's 9 alert codes **(found reconciling against Data Contract v1.1, §8.3)**

`AlertStore.evaluate()` currently raises two families of alert:
`pressure.watch`/`pressure.alert` (→ contract's `PRESSURE_WATCH` /
`PRESSURE_PEAK`) and `temp.delta` (→ `TEMP_DELTA`). The contract specifies
seven more, none implemented yet:

| Code | Condition | Level | Depends on |
| --- | --- | --- | --- |
| `PRESSURE_PTI` | PTI > 80 kPa·s cumulative, 1 hr window | 3 | a cumulative pressure-time integral, not currently computed anywhere |
| `ASYMMETRY_PEAK` | PAI > 15%, continuous ≥ 20 steps | 2 | the gait pass (item 1) — and step counting, which doesn't exist |
| `LOAD_CONCENTRATION` | one zone > 40% of the foot's total load | 3 | a new per-sample computation, not currently done |
| `GAIT_ABNORMAL` | Model A classifies class 3 or 4, confidence ≥ 0.60 | 4 | a gait classifier model — explicitly out of scope per item 1 |
| `DEVICE_LOST` | disconnected > 5 minutes | 1 | `DeviceManager`'s existing per-side state already has what this needs; just no rule raises it yet |
| `BATTERY_LOW` | battery < 15% | 1 | `DeviceStatus.batteryPct` already exists on the wire type; same situation |

`DEVICE_LOST` and `BATTERY_LOW` are the cheapest of these — both read off
data `DeviceManager`/`DeviceStatus` already carries, no new computation
needed, just a new rule in `evaluate()`. The other four all depend on
work scoped elsewhere in this file (PTI integral, item 1's PAI, load
concentration, and the explicitly-out-of-scope classifier) and shouldn't be
attempted ahead of that work landing.

---

## 10. DEFECT — `TEMP_DELTA` fires on one reading; contract requires two consecutive **(found reconciling against Data Contract v1.1, §8.3)**

**This is a defect, not an enhancement.** It changes what the app tells a
patient today, not just what it will eventually support.

**What the contract requires vs. what the code does:** the contract's
condition (§8.3) is "ΔT > 2.2°C ต่อเนื่อง ≥ 2 ครั้งวัด" — the threshold must
be exceeded on **at least 2 consecutive measurements** before the alert
fires. `AlertStore.evaluate()` (`src/ts/data/AlertStore.ts`) raises
`temp.delta` the instant a single `CombinedSnapshot` crosses
`TEMP_DELTA_THRESHOLD` — there is no consecutive-reading check at all; one
noisy sample is sufficient.

**Affected code path:** `AlertStore.evaluate()`, the `dT !== null && dT >
TEMP_DELTA_THRESHOLD` branch that calls `this.raise('temp.delta', …)`. This
runs on every `DeviceManager.onSnapshot()` tick (10 Hz), so a single noisy
sample is enough to fire.

**Why this matters more than it looks:** skin temperature fluctuates for
mundane reasons — poor sensor contact, airflow, shoes just removed. The
contract's 2-consecutive-reading condition exists specifically to filter
that noise out before it reaches the patient. Firing on one reading
produces false alerts, and false alerts in a diabetic foot monitor are not
a cosmetic annoyance: alert fatigue means the patient stops reading the
alert that matters. This is the same class of harm the safety rule in
`CLAUDE.md` (no fabricated bilateral readings) is written to prevent —
a technically-derived number reaching the patient as a false clinical
signal.

**What IS implemented correctly, so it isn't confused with this gap:** the
30-minute per-code repeat suppression (`REPEAT_SUPPRESSION_MS` in
`AlertStore`) is present and correct, and matches the contract's §8.5
requirement exactly. The gap here is specifically in the **firing
condition** — whether a single noisy reading is enough to raise the alert
in the first place — not in how often an already-raised alert can re-fire.
Suppression cannot compensate for this: it only prevents the *same* alert
firing twice within 30 minutes, it does nothing to stop the *first* false
firing.

**Checked every other rule in the contract's §8.3 table for a similar
gap** (an implemented alert missing part of its firing condition, as
opposed to not being implemented at all — that's item 9's scope):

| Code | Contract condition | Implemented as | Gap? |
| --- | --- | --- | --- |
| `TEMP_DELTA` | ΔT > 2.2°C, ≥2 consecutive readings | fires on 1 reading | **Yes — this item** |
| `PRESSURE_WATCH` | any point > 75 kPa (no persistence condition in the contract itself) | fires on 1 reading | No — matches; the contract's own condition is single-reading |
| `PRESSURE_PEAK` (→ `pressure.alert` in code) | Peak > 200 kPa **ขณะเดิน** ("while walking") | fires on 1 reading, with **no walking/gait-state check at all** | **Yes — found while checking this table.** The app has no walking-detection state anywhere (`walkingMinutes` on Home is a display-only mock summary stat, not a live signal `AlertStore` can read); a foot resting on something heavy while seated could raise a false `PRESSURE_PEAK`-equivalent alert exactly as easily as if the patient were actually walking. Not scoped further here — recording it so it doesn't get missed again. |
| `PRESSURE_PTI`, `ASYMMETRY_PEAK`, `LOAD_CONCENTRATION`, `GAIT_ABNORMAL`, `DEVICE_LOST`, `BATTERY_LOW` | — | not implemented at all | Out of scope for this item — already tracked as missing rules in item 9, not a partial-condition gap on an existing rule |

**The `PRESSURE_PEAK` walking gate is cheaper than it looks — not blocked on
IMU work.** `SensorSample` already carries `accelG` and `gyroDps` per
sample; a walking/not-walking signal can be derived from acceleration
magnitude sustained over a short window, which needs none of stride
segmentation or any IMU processing this codebase hasn't built. This is the
same shape of reasoning as item 1's PAI: the useful signal is available
without the hard part. Whoever picks this up should not assume it's
blocked on the gait/IMU pipeline landing first.

**Why the gate matters clinically — worth restating, since "fires early"
understates it:** static loading while seated can exceed 200 kPa with no
tissue risk at all — sitting with a foot propped under load is not the
hazard this alert exists to catch. Diabetic foot ulceration is driven by
*repetitive* loading during ambulation, not by transient static pressure.
An ungated `PRESSURE_PEAK` doesn't just fire a little early or a little
often — it fires on a condition that isn't the hazard the code is supposed
to represent, which is a different and worse kind of wrong than a timing
gap.

**Not fixed in this pass**, as instructed — recorded and scoped only. A
comment at `TEMP_DELTA_THRESHOLD`'s declaration in `constants.ts` already
points here. Implementing the 2-reading requirement means `AlertStore`
needs to start tracking a small amount of state per side (e.g. the last N
temperature readings, or a simple "was over threshold last time" flag) that
it currently doesn't carry — small in scope, but a behavior change to
alert firing, and (per the `PRESSURE_PEAK` finding above, now known to be
similarly cheap) worth re-examining alongside the walking-state gap rather
than fixing in isolation, since both are the same category of defect on
adjacent rules.

---

## 11. Thresholds are hardcoded; the contract requires them runtime-loadable **(found reconciling against Data Contract v1.1, §8.3)**

Data Contract v1.1 §8.3 requires every threshold value to live in a
runtime-loadable `thresholds.json`, not be hardcoded in source, explicitly
because they "จะต้องปรับหลังการทดสอบกับฮาร์ดแวร์จริงอย่างแน่นอน" — will
definitely need tuning after real-hardware testing, without a rebuild for
each adjustment:

```json
{
  "version": 1,
  "pressure": { "watchKpa": 75, "alertKpa": 200, "ptiKpaS": 80 },
  "temperature": { "deltaC": 2.2, "consecutiveReadings": 2 },
  "asymmetry": { "peakPct": 15, "ptiPct": 20, "concentrationPct": 40 },
  "model": { "minConfidence": 0.60 }
}
```

`constants.ts` currently exports every one of these as a hardcoded TS
constant instead — `PRESSURE_WATCH_KPA`, `PRESSURE_ALERT_KPA`,
`TEMP_DELTA_THRESHOLD`, and (once item 1 lands) the PAI watch threshold.
Changing any of them today means editing source and shipping a rebuild.

**This is not just a contract-compliance nicety — it blocks two other items
already in this backlog:**
- **Item 5** (sensitivity slider): the proposed mapping scales
  `PRESSURE_WATCH_KPA` and the ΔT margin per-patient within clinician-set
  bounds. That cannot work against a compile-time constant — there is
  nothing for the slider to write to at runtime.
- **Item 4** (75/200 kPa recalibration): once real hardware or the ESP32
  simulator is feeding data, tuning `PRESSURE_WATCH_KPA` is expected to
  happen repeatedly during that calibration phase. Doing that via source
  edits and rebuilds, over and over, is exactly the friction the contract's
  `thresholds.json` requirement exists to eliminate.

**Design constraint carried over from item 5, restated here since it
constrains the implementation:** whatever runtime-loading mechanism gets
built, patient-facing adjustment (the sensitivity slider) must be able to
scale `PRESSURE_WATCH_KPA` and the ΔT alert margin within clinician-set
bounds, but must never be able to move or disable `PRESSURE_ALERT_KPA` (200
kPa) or `TEMP_DELTA_THRESHOLD` (2.2 °C) — those stay fixed regardless of who
or what is writing to the runtime config. A `thresholds.json` design that
lets any writer touch every field equally would violate this the moment the
slider ships.

Not scoped further here — where the file lives, how/when it's fetched, what
happens on a missing or malformed file, and whether `MockDataSource` needs
its own copy are all open questions for whoever picks this up. This is an
architectural decision, not a threshold correction.
