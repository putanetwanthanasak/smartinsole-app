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

**Correction found while implementing, then corrected again:** this
paragraph originally said the per-window peak was something "`DeviceManager`
already computes per side" — it wasn't, and the first implementation pass
(`docs/reports/003-gait-pai.md`) built the window accumulation in `gait.ts`
by folding `DeviceManager`'s throttled 10 Hz `onSnapshot` stream. That was
itself a bug, caught in review, not a stopping point: `onSnapshot` is
throttled to 10 Hz, so a 2 s window only ever saw 20 of the 100 samples the
source actually produced at 50 Hz — a peak taken from 20% of the data
under-reads exactly the kind of fast-rising-and-falling signal (plantar
pressure at heel strike) most likely to have its true peak in the discarded
80%. Fixed in `docs/reports/004-*.md`: `DeviceManager` now exposes a second,
**unthrottled** subscription, `onRawSample`, alongside the unchanged 10 Hz
`onSnapshot` — `gait.ts` accumulates its window from the raw stream and
still renders at 10 Hz off snapshots. Measurement rate and render rate are
now two different subscriptions, not one conflated stream.

**This raw path is not just for PAI.** Data Contract v1.1 §7.1 fixes Model
A's input shape at `[1, 100, 24]` — 100 timesteps, which at the contract's
50 Hz sample rate is exactly the full-rate stream, not the UI's 10 Hz. Once
that model (or a raw data-collection export) exists, both need
`DeviceManager.onRawSample`, not `onSnapshot` — feeding either from the
throttled path would silently produce wrong model input with no obvious
symptom until accuracy quietly under-performs training. Recorded here so
whoever builds either of those starts from `onRawSample`, not from copying
`gait.ts`'s or `home.ts`'s existing `onSnapshot` usage.

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

> Note (2026-10-24): v1.1 had 9 codes; v1.2 removed `GAIT_ABNORMAL`, so the current contract (v1.5) has **8**. The Flutter app follows the 8.

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

---

## 12. FSR calibration curve validation near ADC saturation — blocked on PCB arrival **(found in docs/reports/008-*.md, stopgapped in docs/reports/009-*.md)**

Illustrative (not measured) values while investigating the Pa/kPa bug in
report 008 showed the FSR curve's `F_newton = a × R_fsr^b` term is steeply
non-linear near the top of the 0–4095 ADC range: a 33% increase in
adc_corrected (3000→4000) produced a **15x** increase in computed kPa
(195→3067). That's either a real, correctly-fitted property of the curve
near saturation, or a sign the calibration curve fit is poor at the high
end — and the high end is exactly where `PRESSURE_ALERT_KPA` (200 kPa)
matters most: a poor fit there could mean the alert tier fires on curve
artifacts rather than real load, or conversely stays silent when it
shouldn't.

**Cannot be resolved with real data yet — there is no PCB to generate a
real heel-strike-range sample from.** `docs/BLE-TEST-CHECKLIST.md` and the
reports through 008 only have real data in the 200–350 raw-ADC range
(light/resting touch); nothing near saturation has been captured from
actual hardware.

**Stopgap shipped in report 009, not a fix:** `isSuspiciousKpaJump()`
(`src/ts/data/blePacketParser.ts`) and `WebBleDataSource.checkSaturationCurve()`
log a dev-only console warning when a channel's kPa reading jumps more than
5x for less than a 50% increase in adc_corrected between two consecutive
samples. It does not clamp, reject, or correct the value — only makes a
suspicious jump visible rather than silently trusting a possibly-bad curve
fit. The 5x/50% thresholds are a cheap heuristic chosen to catch exactly
the pattern already observed, not a validated boundary — they may need
retuning once real saturation-range data exists.

**When a PCB is available:** capture raw ADC values across the full range,
especially 3000+, during a genuine heel strike; compare against the
standalone test page (already verified correct) the same way report 006's
checklist compares light-touch values; and use that to either confirm the
curve fit is sound at the high end or get a corrected calibration blob from
whoever owns that part of the pipeline. This item is closed only once real
data exists there, not once the warning heuristic exists.

---

## 13. Bundle tree-shaking of the BLE stack is non-deterministic — resolve before Capacitor packaging, not before **(found in docs/reports/007-*.md, reconfirmed in docs/reports/008-*.md)**

`WebBleDataSource` and everything it pulls in (`bleProtocol.ts`,
`blePacketParser.ts`, `webBluetooth.d.ts`) are gated behind
`usingWebBle`/`import.meta.env.DEV` in `data/DeviceManager.ts`, with the
intent that a production build never ships any of it. Whether that
actually happens depends on the minifier fully constant-folding
`usingWebBle` through to `bleSources = null` and eliminating everything
only reachable from there — which is NOT guaranteed by this gating
pattern. Observed directly: report 007's build included the whole
`WebBleDataSource` class (~70 kB → ~81 kB); report 008's build, with no
intentional change to the gating logic, excluded it again. Runtime
behavior is unaffected either way — `bleSources` genuinely is `null` in
production, `new WebBleDataSource()` never executes — this is a bundle-size
question, not a correctness one.

**Not a current problem:** testing right now targets a laptop + USB
dongle, not a packaged app, so shipped bundle size doesn't block anything.
**Must be resolved before Capacitor packaging begins** (see CLAUDE.md
"Next phase" and `docs/BACKLOG.md` item 3, which already tracks font
subsetting for the same class of reason — everything in `dist/` ships
inside the APK regardless of whether a given device would ever fetch it).

**Proposed direction, not implemented:** a dynamic `import()` for the BLE
module instead of a static one, which forces bundlers to put it in its own
chunk rather than relying on dead-code elimination to strip it from the
main one — a structural guarantee instead of a minifier heuristic. Not
scoped further here.

---

## 14. Flutter scaffold leftovers (S1B) — RESOLVED

Found in `docs/reports/020-flutter-scaffold.md`. The two items that needed a
decision were decided by the user during S2A and are recorded in
`docs/FLUTTER-PLAN.md` section 2:

- **Screen titles** move from the `AppBar` into the page body, so they scale
  with large text (`AppBar` caps text scaling at 1.34×). Applied when each
  screen is built for real (S5, S6B, S8A, S8B, S8C), not before.
- **Home greeting name** is set in Settings (S8B). When no name is set, Home
  shows just "สวัสดี".

The remaining bullets were never decisions; they are carried by the session
that builds each screen:

- A golden at text scale 2.0 for Home — S5 (the two-column foot buttons are
  the most likely thing to break).
- The English "Placeholder — built in S…" developer line goes away as each
  screen's session builds it.
- Reduce motion re-checked on the emulator — S5, where real animations arrive.

## 15. Variable FSR count is not in the Data Contract yet **(found in S2A)**

FLUTTER-PLAN §5 says a sample is `2N + 12` bytes, with N taken from the
calibration blob, and the Flutter parser supports that (N = 4/6/8 are
tested; see `docs/reports/021-flutter-parser.md`). The Data Contract §3.1
still fixes a 6-FSR, 24-byte sample block and a 200-byte packet. N = 8 makes
a packet 232 bytes, which still fits MTU 247 (244-byte payload), but nothing
in the contract says so. Before any hardware with N ≠ 6 exists, the
contract owner needs to add this to §3.1: the sample size, where N comes
from, and the FSR index → position table for other N (`sensor_layout.json`,
S5). The S2B simulator's `FSR_COUNT` build flag depends on the same
change.

## 16. Variable NTC count has no wire format **(found in S2A)**

FLUTTER-PLAN §2 says NTC may increase to 6 per foot. The temperature packet
(contract §3.2) is a fixed 12 bytes carrying exactly two values (forefoot,
heel), with no count field. The parser handles only that format. A
different NTC count needs a new packet layout in the contract first.

## 17. Simulator: two concurrent centrals (S2C) — RESOLVED

Done in S2C (`docs/reports/023-sim-control.md`). The simulator keeps
advertising while connected, up to 3 centrals (`SessionTable::kMaxSessions`
= NimBLE's default `CONFIG_BT_NIMBLE_MAX_CONNECTIONS`, checked by a
`static_assert`). Verified live with the laptop (bleak) and a Note 10 (nRF
Connect) at the same time: the phone's START, STOP, disconnect and
reconnect left the laptop's 1 896-packet stream without a `seq` gap, and
the phone kept streaming after the laptop's STOP and disconnect. The
phone ran at MTU 120 (4 samples per packet) while the laptop ran at 247 (8):
packets are cut per connection.

What the opcodes mean with several centrals (decided at S2C plan approval):

| Opcode | Scope |
|---|---|
| `START_STREAM`, `STOP_STREAM`, `SYNC_TIME` | The connection that wrote it |
| `SET_RATE`, `TARE`, `REBOOT` | The whole device (every central sees the effect) |

Device Status `state` is 1 while any connection streams. What the app
must do about the device-wide ones is item 21.

## 18. Simulator scenario mode (`0x10 SET_SCENARIO`) **(FLUTTER-PLAN §2, not before the main app)**

The simulator's data comes only from a `DataSource`
(`firmware/simulator/lib/insole_core/src/data_source.h`): pure functions
for the sample, temperature and battery. The default is
`insole::synth::walking()`, chosen in one line in `src/main.cpp`. A scenario
mode adds more `DataSource`s (for example a high-pressure step, ΔT above
threshold, a sensor fault, or `-32768` temperatures) and an opcode to switch
between them. **Low battery comes from here**: `walking()` never drops
below 50 %, so `BATTERY_LOW` (< 15 %) never fires during long test runs.
The opcode isn't in the Data Contract §3.4 yet.

S7 note: a serial-command subset exists now (`n`/`t`/`p`/`?`,
`firmware/simulator/lib/insole_core/src/scenario.*`, for the S7 phone
check), each a pure `DataSource` as planned here. There is still no BLE
opcode, and still no low-battery, sensor-fault or `-32768` scenario.

## 19. `seq` / `t0_ms` behaviour across connections is not in the Data Contract **(found in S2B)**

Contract §3.1 only says `seq` "wraps at 65535, used to detect dropped
packets", and that `t0_ms` is ms since boot. It doesn't say whether `seq`
restarts on `START_STREAM` or runs for the whole boot. The S2B simulator
does this, verified live by `sim_check.py`'s reconnect checks:

- `seq` is per connection and restarts at 0 on every `START_STREAM`
  (each new connection, and each STOP → START on one connection). Since
  S2C, a `START_STREAM` while that connection is already streaming is
  ignored, so a repeated write can't send `seq` back to 0 mid-stream.
- `t0_ms` is ms since boot and never restarts.
- A connection receives no sensor or temperature notification before its
  own `START_STREAM`.

The contract owner should add these three lines to §3.1 so real firmware
behaves the same. The old sibling-repo simulator restarted `t0_ms` on
`START_STREAM` instead (report 015), which contradicts "ms since boot".

## 20. Rule 9 (drop stale packets): design for S3A/S4 **(found in S2B)**

Given item 19's behaviour, the app should drop a stale packet left over
from an earlier connection with two checks, per foot:

1. **Drop any sensor or temperature packet that arrives before this
   connection's `START_STREAM` write is acknowledged.**
2. **`t0_ms` must never go backwards within a connection.** Only within a
   connection: across a `REBOOT` (or a power cycle) `t0_ms` legitimately
   restarts near 0 (S2C verified `t0` 163 106 → 1 536 ms across a REBOOT),
   so comparing against an earlier connection's `t0` would drop real data.

**Optional idea, for S3A to evaluate, not part of the design:** a `seq`
look-ahead. The first real packet has `seq` 0, so a packet with `seq` ≠ 0
followed by `seq` 0 would be stale. This needs look-ahead (hold the first
packet until the second arrives, as report 015 did with `t0`), and it is
fragile if the `seq` 0 packet itself is lost: then the stream starts at
`seq` 1 and the check either drops a real packet or never fires.

Why `seq` must restart rather than run for the whole boot: with a
boot-wide `seq` and `t0`, a stale packet (`seq` k) followed by the new
stream (`seq` k+1) looks continuous, so nothing marks it as stale. A single
counter also can't be shared by two centrals with different MTUs (item 17),
because their packets are cut differently.

The web app's report-015 check only looks for `t0` going backwards. Against
the new simulator, `t0` never goes backwards within a connection, so that
check never fires. That's harmless, because the new simulator sends no
stale packets, but worth knowing in S3B.

**S3A status:** checks 1 and 2 are implemented in
`mobile/lib/ble/ble_data_source.dart` (each connection also gets a
generation number, so a late notification from an older connection is
dropped too). The t0 and temp `t_ms` comparisons are modulo 2³², so the
49.7-day wrap is not "backwards". The `seq` look-ahead was **not**
implemented: it needs a held packet and fails when `seq` 0 is lost (see
report 024). `seq` gaps are only counted; gap handling is S4.

**S4 status:** check 1 changed: the gate now opens when the START write is
**issued**, not when it is acknowledged (item 27). `seq` gaps (with the
65535 wrap) and a lost start of stream are counted by `SeqTracker`
(`mobile/lib/ble/seq_tracker.dart`), and `DeviceManager` drops any batch
from an older session as a second line of defence. See report 026.

## 21. App: guard REBOOT and TARE (S8B Connection/Settings) **(found in S2C)**

`REBOOT` and `TARE` act on the whole insole, not on one connection
(item 17). A `REBOOT` sent from the phone also disconnects the laptop's
research capture. A `TARE` puts calibrating-flag (bit1) packets into the
laptop's stream for one stride and changes `offset_adc` under it (item 23).
The phone app must:

- put both commands behind a confirmation dialog that warns about this;
- make sure no research capture is running before sending either command,
  or hide both commands during the study;
- for `TARE` on real hardware, tell the user to lift the foot off the
  insole first. The simulator's tare takes the minimum over one stride,
  relying on the swing phase. Real firmware cannot rely on that: it
  measures whatever load is on the insole when TARE arrives.

## 22. `SET_RATE` conflicts with rule 1 **(found in S2C, contract owner)**

Contract §3.4 `0x04 SET_RATE` (uint8 Hz, "for testing") changes the sample
rate. The packet has no field for sample spacing, and §3.1 / rule 1 fix
sample i at `t0 + i × 20 ms`. An app reading a 25 Hz stream would put every
sample at the wrong time. The simulator therefore accepts only 50 (a no-op)
and logs and ignores other rates (decided at S2C plan approval). The contract owner
should either drop `SET_RATE`, limit it to 50, or add the spacing to the
packet header.

## 23. No "calibration changed" signal after TARE **(found in S2C, contract owner)**

The Calibration characteristic is Read-only and read once at connect (§5.1).
After a `TARE` from one central, any other connected central keeps the old
`offset_adc` until it reads again. Nothing tells it to. Options: make
Calibration notify, or have the app re-read calibration whenever it sees
flags bit1 go from 1 to 0. Until then, item 21's guard is what keeps a
research capture consistent.

**S3A status:** the app side is done: the Flutter app re-reads calibration
when flags bit1 goes from 1 to 0. Packets keep the old offsets until the
new read returns. The contract-owner question (should Calibration notify?)
is still open.

## 24. Malformed control writes can't be reported **(found in S2C, contract owner)**

Contract §3.4 gives each opcode a payload but says nothing about a write
with the wrong length or an unknown opcode. The simulator requires the
exact length, logs and ignores anything else, and changes no state (a
2-byte `02 02` does *not* stop the stream). The write itself still
succeeds at the ATT level, so the app can't tell its command was ignored.
The contract could add an ATT error response or a status `error_code`.

## 25. Android connection interval is slower than requested **(found in S2C, for S3A)**

The simulator requests a 15–30 ms interval (contract §2.3). The laptop
(BlueZ) got 30 ms. The Note 10 in nRF Connect stayed at 48.75 ms (after a
brief 7.5 ms), with a 5000 ms supervision timeout instead of 4000. The
6.25 Hz stream still arrived in full at 48.75 ms. The Flutter app should
request high connection priority after connecting (Android
`requestConnectionPriority(HIGH)`, which gives 11.25–15 ms) and S3A should
log the interval it actually gets. This matters most for S4's ±10 ms
cross-foot timing check.

**S3A status — partly done.** The Flutter app calls
`requestConnectionPriority(high)` on every connect and reconnect. Android's
public API can't read the interval back, so the interval actually granted
comes from the simulator's serial log (`[ble] conn N: interval …`), which
the Note 10 checklist in report 024 captures.

**Measured at the S3A Note 10 checkpoint (2026-10-21):** after the app's
HIGH request, the Note 10 settled at **11.25 ms** (latency 0, supervision
timeout 5000 ms) on both boards. That held on every connect and reconnect
(first connect, EN reset, replug, Bluetooth off/on). Each connection
briefly passes through 45–48.75 ms and 7.5 ms first. The interval part of
this item is resolved; S4 still has to measure the actual ±10 ms
cross-foot timing.

**S4 status:** the cross-foot measurement is built: the debug screen's
timing check plus `firmware/simulator/tools/timing_check.py` bound each
foot's clock error from the `SYNC_TIME` the board logs (report 026). The
result comes from the S4 Note 10 checkpoint.

**Measured at the S4 Note 10 checkpoint (2026-10-22):**
- L/R alignment was within ±3.4 ms (±3 ms uncertainty) over 10.6 min.
  This used the laptop-clock method, adopted after the run.
- The `SYNC_TIME` write took 29–139 ms to complete on the Note 10, so the
  originally planned write-latency bound couldn't get below 23 ms (left)
  and 51 ms (right).

## 26. Android ≤ 11 location permission and the `permission_handler` pin **(found in S3A)**

- The manifest declares `ACCESS_FINE_LOCATION` (maxSdk 30) for BLE scanning
  on Android 11 and below, but the app only asks for `bluetoothScan` /
  `bluetoothConnect` itself and leaves location to flutter_blue_plus's own
  request. That path is untested: the Note 10 runs Android 12. Test it on
  an Android ≤ 11 phone before release, or ask for location explicitly.
- `permission_handler` is pinned to `^12.0.3` because 13.x
  (`permission_handler_android` 14.1.0) needs compileSdk 37, and AGP 9.1
  supports at most 36. Lift the pin when the Android Gradle plugin is
  upgraded.

## 27. The first packet after START can be dropped as "before START" **(found at the S3A Note 10 checkpoint, for S4)** — RESOLVED

Rule 9 check 1 (item 20) drops sensor/temp packets that arrive before
this connection's `START_STREAM` write is acknowledged. On the Note 10 one
reconnect of the right board showed `dropped before START 1`. The most
likely cause (not proven: the phone log had stopped by then, and the
app's log line doesn't record the `seq`) is that the board starts
notifying as soon as it handles START, and Android delivered the first
notification before the write-response callback. If so, that packet was
genuine (this connection's generation, most likely `seq` 0), so up to 8
samples (160 ms) were lost at the start of the connection. The gap counter
doesn't see it, because `seq` tracking restarts with each connection
(`LinkStats.newSession()`) and the first *accepted* packet becomes the
baseline.

For S4, either:
- open the gate when the START write is **issued**, not when it is
  acknowledged. The generation check already rejects anything from an
  older connection, and this connection's subscriptions are new, so a
  packet of this generation can only come from this connection's stream;
  or
- keep the gate but accept a packet held back until the ack if its `seq`
  is 0 or 1 and its `t0` is plausible.

Either way, count a first accepted `seq` k > 0 as k missing packets, so a
lost start of stream shows up in the gap counter.

**S4 status — fixed in code, pending the S4 Note 10 checkpoint.** The first
option is implemented (`mobile/lib/ble/ble_data_source.dart`). Packets that
arrive between the START write and its ack are counted as
`admittedBeforeAck`. A first accepted `seq` k > 0 is counted as k
`missingAtStart`, kept separate from mid-stream gaps (so real firmware that
doesn't restart `seq`, item 19, shows up as one clear number). Tests: a
packet before the ack is kept, one before the write is still dropped, a
late packet from the old link is still dropped.

**Verified at the S4 Note 10 checkpoint (2026-10-22):**
- The race happened once in the 10 reconnects (5 per foot), on
  the right foot: "a packet arrived before the START ack (kept)".
- That packet was kept. `missing at start` and `dropped before START`
  stayed 0 on both feet.
- Resolved.

## 28. Web-app CSV: resync steps of exactly 160 ms, and no `seq` **(found in S3B; user decided: no web-app change)**

The fallback web app's `tUnixMs` is device time plus an offset that
`WebBleDataSource.syncTime()` re-estimates every 5 minutes as "send time −
device time of the last sample received". The first re-estimate after a
connect gives a step of any size. Every later one is exactly 20 + 160·k ms:
- Chrome's timer sends exactly 300 000 ms apart (the S3B serial log shows
  `d_unix 300000` every time);
- 300 000 ms is exactly 1 875 packets;
- so k only counts how many more or fewer packets had arrived at send time
  than 5 minutes earlier.

Usually k = 0, which is invisible. S3B saw k = +1 once on the right foot in
9 minutes: a 160 ms hole in `tUnixMs` with no data lost, and the L/R
alignment moved from +36 to −124 ms. k = −1 would make `tUnixMs` go
backwards by 140 ms. The CSV has no `seq` column (fixed schema), so a
k ≠ 0 step looks exactly like a lost packet. The dev panel settles it: no
loss when `pkts = seq + 1` and `dropped=0`.

Decided in S3B: no web-app change (fallback only).
- `docs/STUDY-FALLBACK.md` reconnects both feet before each 3-minute trial,
  so no resync falls inside a trial.
- `firmware/simulator/tools/webapp_csv_check.py --assume-no-loss
  --write-corrected` undoes the steps within each take afterwards.

**For S4:** the phone app's 5-minute `SYNC_TIME` must not copy this offset
formula. Anything that anchors "now" to the last packet received is
quantised to the 160 ms packet period. Anchor to each packet's own arrival
time (e.g. a minimum-latency filter), and write `seq` into the S4C CSV.

**S4 status — the app part is done.** `mobile/lib/device/device_clock.dart`
anchors each packet to its own arrival, takes the 30 s minimum as the
offset, and slews toward it by at most 0.25 ms per sample: no steps, never
backwards within a session (tested, including bursty arrivals that gave the
web app its 160 ms steps). `SYNC_TIME` is still sent every 5 minutes but
sets nothing. Writing `seq` into the CSV is S4C. **For the contract owner:**
contract §4 describes the web app's formula; the app deliberately
doesn't follow it.

## 29. Chrome on Linux can't reconnect a remembered insole after about 30 s **(found in S3B)**

The web app's Connect reuses the remembered `BluetoothDevice` without a
new scan. BlueZ deletes an unpaired device `TemporaryTimeout` (30 s) after
it disconnects. After that, `gatt.connect()` fails at once with
"NetworkError: Bluetooth Device is no longer in range", and nothing reaches
the board. **Forget device → Connect → pick the insole** works every time.
That is the step in `docs/STUDY-FALLBACK.md`, so there is no code change.
A one-line web-app fix exists if ever wanted: call `forgetDevice()` when
`gatt.connect()` throws, so the next click opens the picker.

## 30. `thresholds.json` has no battery threshold **(found in S4, for S7)** — RESOLVED (S5)

Resolved in S5: `shared/thresholds.json` has `battery.lowPct` (15), an
additive key noted in `docs/DATA-CONTRACT.md` §8.3 as a local addendum to
v1.5. The app reads it (Home chips, `lowBattery` preset test). S7's
`BATTERY_LOW` rule should read the same key.

Original note:

Contract §8.3 defines `BATTERY_LOW` as below 15 %, but
`shared/thresholds.json` has no battery entry. The S4 `lowBattery` mock
preset (left foot 10 %) and its test cite the contract value directly. S7
should add it to `thresholds.json` (rule 12) and point the test at it.

## 31. How to read the PTI and concentration rules **(found in S4, for S7)** — RESOLVED (S7)

Resolved in S7 (user decision 2026-10-24, `docs/reports/030-*.md`):
- **PTI:** per zone, per walking step, PTI = ∫kPa dt over that stance.
  `PRESSURE_PTI` holds while a zone's **mean per-step PTI over the steps
  of the last `pressure.ptiWindowMin` (60) minutes** is above `ptiKpaS`,
  once the window holds at least `ptiMinSteps` (20) steps, and only while
  the foot is still walking.
- **Concentration:** per walking step, the top zone's peak divided by the
  sum of the six zone peaks is above `concentrationPct`, with the **same
  zone on top for `asymmetry.concentrationSteps` (20) steps in a row**.
  Quiet standing never fires it.
- Steps come from `mobile/lib/rules/step_detector.dart`
  (`steps.contactKpa`, `minStanceMs`, `maxStanceMs`, provisional; the SR
  session checks them against a manual step count).
The mock presets kept the per-step reading, so they needed no change.
Still to confirm with the contract owner (as a local reading, noted in
DATA-CONTRACT §8.3).

Original note:


Contract §8.3 gives `ptiKpaS` and `concentrationPct` without saying what
they are computed over. Read literally:
- an instantaneous concentration (one channel's share of the current
  total) is close to 100 % at every heel strike, so it would fire on every
  step;
- a PTI over a whole hour passes `ptiKpaS` for anyone who walks.

The S4 mock presets assume **per step**: PTI is the area under each
channel's curve (and under the max-over-channels curve) for one stance,
and concentration is the highest channel peak's share of the sum of that
step's channel peaks. The `watch` and `safeOrangeDot` presets and their
band test (`mobile/test/device/mock_data_source_test.dart`) are built on
that reading. S7 must confirm it with the contract owner. If S7 chooses a
different reading, change the presets and the test with it.

## 32. Align the TestProtocol doc with proposal doc 03 **(found in S4C)**

The IRB-approved procedure is proposal doc 03 (Thai). It differs from
`docs/SmartInsole_TestProtocol_v1.md` in two places, and the app follows
doc 03 (S4C plan approval, 2026-10-22):
- **Subject data:** doc 03 approves only sex, an **age range**, foot length
  (under the subject code) and room temperature. TestProtocol §4.1 / §6.2
  also lists exact age, weight, height, dominant side and humidity.
- **Timing:** doc 03 has a demonstration, then **30 s** practice before
  each 3-min recording, and rest **as long as the volunteer wants**.
  TestProtocol has 1 min practice and a fixed 1 min rest.

Update `docs/SmartInsole_TestProtocol_v1.md` to match doc 03 (or mark it
superseded by doc 03), so nobody reads the old values as the procedure.

## 33. Age-range bins to confirm against doc 03 **(found in S4C)** — RESOLVED

Resolved 2026-10-22 (user, from doc 03): doc 03 only admits volunteers
aged 21–30, so `ageRanges` in `mobile/lib/capture/capture_protocol.dart`
is 21–25 / 26–30. Doc 03's foot-length inclusion (25.5–27.5 cm, shoe
size 42) is enforced for `SI-` codes in the same file
(`footLengthEligible`). BACKLOG 32 should add both to TestProtocol_v1.

## 34. The mock can't drop one foot's link mid-recording **(found in S4C)**

The emulator rehearsal could not show the link-lost banner and cue live:
the mock's presets are switched from Settings, which is unreachable while
recording (Back is blocked). The behaviour is covered by tests (seq gap
and link loss with reconnect, the banner widget test, the golden) and is
part of the Note 10 checklist with a real board reset. If a live emulator
check is wanted later, add a debug-only way to drop a mock foot (e.g. a
mock "link drop in N s" option).

## 35. Retire the web app's capture mode after the study **(FLUTTER-PLAN §10, S4C)**

Phone capture (S4C) is the study tool; the web app's capture page stays
only as the fallback in `docs/STUDY-FALLBACK.md`. After the November data
collection, retire it as FLUTTER-PLAN says. The phone CSV format differs
from the web app's (long format, unix time per sample, `seq`, raw ADC,
gaps), so `tools/capture/load_capture.py` does not read web-app exports.


## 36. The study build needs a connect path that isn't the debug screen **(found in S4C)**

Today the only way to connect the insoles is Settings → "BLE debug
(temporary)", which S8B is meant to hide. Research capture's pre-check
and `docs/STUDY-CAPTURE.md` point there for now. Before the study build is
frozen (10 Nov), either Home / Connection must connect both feet, or the
study build keeps the debug screen. Whichever session does the connect
UI (S5 or S8B) should update the pre-check hint in
`mobile/lib/ui/screens/capture/capture_home_screen.dart` and
`docs/STUDY-CAPTURE.md` step 3.

S5 note: Home's No-data card has "เชื่อมต่อแผ่นรองเท้า", but it opens the
Connection placeholder (S8B). Research capture moved behind a 2 s long
press (Settings → "ส่วนผู้วิจัย"); the debug screen is still the only
connect path, so this item stays open for S8B.

## 37. Balance and peak asymmetry: interim definitions **(found in S5, for S7)** — RESOLVED (S7)

Resolved in S7:
- **`ASYMMETRY_PEAK`:** on every completed walking step, with both feet
  usable, PAI of the two feet's latest step peaks (each the highest zone
  of that step; the other foot's step must be recent). It holds after
  `asymmetry.peakSteps` (20) steps in a row above `peakPct`, and clears on
  the first step at or below it or when a foot is unusable. Its side is
  the foot with the higher peak. `PeakAsymmetry` (2 s window) is gone.
- **Balance note:** orange with the `triangle-alert` icon only while
  `ASYMMETRY_PEAK` holds, naming the rule's foot; otherwise `ink` as
  before. The 10 s weight share stays display only; its window moved to
  Home (`balanceWindowMs`), out of `lib/rules/`.
- **`watch` preset:** PEAK fires at once; after 20 steps PTI also holds
  and names the status (order TEMP_DELTA > PTI > PEAK >
  LOAD_CONCENTRATION, user decision), matching board HomeDWatch.
- `safeOrangeDot` also gets the orange note: its PAI (≈ 45 %) is a real
  level-2 `ASYMMETRY_PEAK`; the preset was kept as it is.

Original note:


**Home's balance card (user decision 2026-10-23, replaces the first D6
change).** "{L} : {R}" means weight share:
- each foot's share of the summed kPa over all six zones, as a mean per
  sample over a rolling 10 s window (`mobile/lib/device/rolling_load.dart`,
  `mobile/lib/rules/weight_share.dart`, both marked INTERIM). A mean, so
  lost packets do not make a foot look lighter;
- the note reads "ลงน้ำหนักเท้า{ซ้าย/ขวา}มากกว่า" when the two mean loads
  differ by more than `asymmetry.peakPct` (PAI formula), otherwise
  "ซ้ายและขวาพอ ๆ กัน";
- **until S7 the note is always `ink` with no icon.** There is no orange
  on the balance card before S7. **S7 turns it orange (with the
  `triangle-alert` icon) only while `ASYMMETRY_PEAK` is active**;
- the number keeps its shown value while the share is within 1 point of it
  (`shareDeadband`, display only), so it does not flicker at 10 Hz.

**`ASYMMETRY_PEAK` (S7).** Contract §8.3: "PAI > `asymmetry.peakPct`
sustained for ≥ 20 steps", PAI from §8.2, but the contract does not say
what a foot's peak is. `mobile/lib/rules/asymmetry.dart`
(`PeakAsymmetry`, INTERIM) is the starting point: a foot's peak is its
highest channel over the last 2 s, and there is no step detection or
20-step persistence yet. S7 must settle the peak with the contract owner,
add the persistence, and drive the balance note's orange from the rule.
Both functions share the PAI formula (`paiPercent`).

**Mock `watch` and S7.** To match board HomeDWatch, the `watch` preset's
left first metatarsal head peaks above `alertKpa` (240 kPa), so S7's
`PRESSURE_PEAK` can fire alongside the intended `PRESSURE_PTI` (both level
3). S7 decides which cause the status detail names; the board's detail is
the PTI one ("…รับน้ำหนักมากต่อเนื่องนานเกินไป").

## 38. One foot missing: the connected foot's level 3+ must win **(found in S5, for S7)** — RESOLVED (S7)

Resolved in S7: `AlertEngine.status` picks a level-3+ rule from a usable
foot over No data; otherwise No data names the missing foot
(`PatientStatus.missing`, detail "ยังไม่ได้เชื่อมต่อแผ่นรองเท้า{ขวา}
จึงยังบอกไม่ได้ว่าเท้า{ขวา}ปลอดภัยหรือไม่", draft). Two-foot values stay
"—" (rule 4).

Original note:


S5 shows No data whenever either foot is not usable (decision D7). With
the rules engine (S7): when one foot is missing and the connected foot
has a level 3 or higher status, show that status (max level), not No
data; and the No-data detail text must name which foot is missing
(e.g. "ยังไม่ได้เชื่อมต่อเท้าขวา"). Two-foot values (temperature
difference, balance) stay "—" either way (rule 4).

## 39. Home copy written in S5 that the spec does not give **(found in S5)** — APPROVED

Approved by the user's design review on 2026-10-23.


DESIGN-SPEC §6 does not give these strings; S5 wrote them in the spec's
style. Review with the rest of the draft health copy (Appendix A):

- pressure caption with one foot connected: "แรงกดเท้า{ซ้าย/ขวา}กระจายดี";
- foot map TalkBack label with no data: "เท้า{ซ้าย/ขวา} ยังไม่มีข้อมูล";
- pressure caption with no foot connected: "ยังไม่มีข้อมูล
  ต้องเชื่อมต่อแผ่นรองเท้าก่อน".

Also: the dots show each zone's peak over the last 2 s (the same window
as the balance card), so a zone touched once during a step stays
coloured for 2 s instead of flickering at walking pace.

## 40. Research capture: its alerts go into the export, and leave with it **(user request in S6A, for S7/SR)** — RESOLVED (S7)

Resolved in S7, all three parts:
1. While a session's flow screen is open (`activeCaptureProvider`, set
   by capture home around the push), every alert carries its stamp.
2. The export writes `alerts.csv` (export folder only, hashed in
   `manifest.json`; header only when there are none). Columns: `at_ms`,
   `code`, `level`, `patient_status`, `side`, `zone`, `site`,
   `measured_value`, `threshold`, `gait_class`, `gait_confidence`,
   `read_at_ms`, `details`. The planned "ISO local" column was dropped:
   a local time without its offset is ambiguous, and `at_ms` is exact.
   `tools/capture/load_capture.py` checks it; `--selftest` covers it
   (the shared fixture has one alert).
3. "Delete from phone" deletes the session's alerts too.

Original note:


The warm-compress test (proposal doc 03) needs the alert times of each
study session. S6A stores them: `alerts.capture_stamp` holds the running
capture's time stamp (`captureStampOf(sessionId)`, e.g. `20261110-093000`;
never the subject code), and retention never deletes an alert that has one.
What is still missing:

1. **S7:** while a research capture is running, every alert the AlertEngine
   raises carries that capture's stamp (`NewAlert.captureStamp`).
2. **S7/SR:** the capture export writes the session's alerts
   (`AlertRepository.forCapture(stamp)`: code, level, side, site/zone,
   measured value, threshold, time UTC ms + ISO local) as one file in the
   export bundle. That file is listed in the SHA-256 manifest, and
   `tools/capture/load_capture.py` loads and checks it (and its `--selftest`
   covers it).
3. **"Delete from phone"** (`capture_summary.dart`) also calls
   `AlertRepository.deleteForCapture(captureStampOf(sessionId))`, so the
   alerts go only when their capture goes. Not wired in S6A because the
   capture flow was out of scope; until it is, deleting a capture leaves
   its alerts in the database (harmless, but they are never cleaned up).

## 41. `rotated_foot` has no in/out-toeing direction for the gait note **(found in S7, for S8A)**

Contract §8.3.1 gives the `rotated_foot` note different zones for
in-toeing and out-toeing, but Model A's class is just `rotated_foot`.
`gaitNoteTh` (`mobile/lib/rules/gait_note.dart`) therefore gives no note
for it. When Model A (S8A) or the capture labels provide the direction,
add it to `GaitEstimate` and to the note's zone match.

## 42. The simulator's normal walk is gentler than the app's walking gate **(found in S7)**

The app's gate (contract §8.3.2) is the mean of |‖a‖ − 1 g| over
`motion.walkingWindowMs` ≥ `walkingAccelG` (0.15 g). The simulator's
normal walk (`synth::gaitSample`) gives a lowest window mean of about
0.07 g and a highest of about 0.16 g, so with the simulator the gate is
mostly off: few steps are counted, and `PRESSURE_PEAK`, PTI,
concentration and asymmetry cannot be shown from the normal walk. The
existing native test (`test_accel_moves_enough_to_be_walking`) checks
the standard deviation of ‖a‖ (> 0.15), not the contract's statistic.
S7 worked around it inside its approved scope: the `p` serial scenario
scales the walk's dynamic accel ×4 (lowest window mean > 0.19 g,
`test/test_scenario`). Options, for the user: raise the normal walk's
motion and test it with the contract's statistic (a change to the
simulator's default output), or leave it until real-board data sets
`walkingAccelG` (SR). Real feet move far more at heel strike than the
simulator does, so this is a simulator limit, not evidence the gate is
too strict.

