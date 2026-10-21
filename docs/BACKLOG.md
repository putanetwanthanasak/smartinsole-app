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

## 27. The first packet after START can be dropped as "before START" **(found at the S3A Note 10 checkpoint, for S4)**

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
