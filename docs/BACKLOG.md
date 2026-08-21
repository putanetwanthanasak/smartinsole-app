# Backlog

Deferred work, with enough context to act on each item without re-deriving it.
Ordered roughly by what blocks what. Items marked **(assistant-flagged)** were
raised by Claude during earlier passes rather than requested by the user —
worth knowing which is which when prioritizing.

---

## 1. Gait screen pass — DECIDED, ready to implement

The gait screen currently shows nothing real: the classification card's
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
window, which `DeviceManager` already computes per side. So this is not a
stand-in awaiting IMU work — it is the metric. When stride segmentation
eventually lands, the window definition changes from "2 s wall-clock" to "1
stride" and the metric formula survives unchanged.

**Requirements (not suggestions):**
- Surface the computed PAI number on screen, not just the bars — it is a
  contract metric, not a decorative chart.
- The PAI watch threshold goes in `constants.ts`, named, not inlined —
  follow the pattern of `PRESSURE_WATCH_KPA` / `PRESSURE_ALERT_KPA`.
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

## 4. `PRESSURE_WATCH_KPA = 75` is provisional

Documented in a comment at its declaration in `constants.ts`, repeating here
so it's not missed: published peak plantar pressures for normal barefoot gait
routinely exceed 75 kPa, so taken at face value this threshold would flag
healthy walking as a concern. Simultaneously, this build's six discrete FSRs
per foot (vs. a full pressure mat) will systematically under-read the true
peak, since a sensor rarely sits exactly on it. Those two errors push in
opposite directions and neither is quantified. **Do not tune this value
against the mock `PRESETS`** — it needs recalibration against real hardware
data once the ESP32 simulator or real insoles are feeding the pipeline.

---

## 5. Settings sensitivity slider — inert, proposed mapping not implemented

`settings.ts`'s "Alert sensitivity" slider writes to in-memory `state` and
drives nothing. Proposed mapping, not implemented: it should scale
`PRESSURE_WATCH_KPA` and the ΔT alert margin within clinician-set bounds, so a
patient can make the app more or less talkative — but it must not be able to
move the contract-fixed values themselves (`PRESSURE_ALERT_KPA` / 200 kPa,
`TEMP_DELTA_THRESHOLD` / 2.2 °C). Those are clinical thresholds from the Data
Contract, not user preferences, and the slider must not be able to disable
them.

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
