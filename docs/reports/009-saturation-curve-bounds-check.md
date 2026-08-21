# 009 — Saturation-curve sanity warning (stopgap); two BACKLOG items added

Follow-up to report 008. Two of the three items from that review; the third
(the per-channel assertion) needed no action, confirmed by the user as
correct reasoning.

---

## 1. Saturation-curve sanity warning added

Report 008's illustrative (not measured) numbers showed something worth
taking seriously even without real heel-strike data: a 33%
`adc_corrected` increase (3000→4000) produced a 15x kPa increase
(195→3067). That's either a real property of the fitted FSR curve near
saturation, or a sign the curve fit is poor at the high end — and the high
end is exactly where `PRESSURE_ALERT_KPA` (200 kPa) matters most.

**Not resolvable with real data this pass** — no PCB, no real ADC samples
anywhere near saturation. Added a cheap heuristic instead, per instruction:
flag the pattern, don't clamp or reject the value, since silently trusting
a possibly-bad curve fit at the alert threshold is worse than a noisy
warning.

### What was added

- **`src/ts/data/blePacketParser.ts`**:
  - `correctAdc(rawAdc, offsetAdc)` — extracted the zero-point correction
    (`max(0, adc_raw - offset_adc)`) out of `adcToKpa()` into its own pure,
    exported function. Needed because the sanity check has to reason about
    `adc_corrected` as an intermediate value, and duplicating that one-line
    clamp at the call site would create a second copy of logic that could
    drift from `adcToKpa()`'s own. `adcToKpa()` now calls it internally
    too — no behavior change there.
  - `isSuspiciousKpaJump(prevAdc, prevKpa, nextAdc, nextKpa, adcRatioThreshold=1.5, kpaRatioThreshold=5)`
    — pure function, no side effects. Returns true when
    `nextAdc/prevAdc < 1.5` (less than a 50% increase) AND
    `nextKpa/prevKpa > 5` (more than a 5x increase) — exactly the pattern
    from the illustrative example. Doesn't know or claim what a "correct"
    ceiling is; it only detects the shape of a suspicious jump between two
    consecutive readings of the same channel.
- **`src/ts/data/WebBleDataSource.ts`**:
  - `prevChannelReading` — a 6-entry array (one per FSR channel, indexed
    like `FSR_CHANNEL_ORDER`) holding the previous `{adcCorrected, kpa}`
    per channel for the current connection. Reset in
    `resetPerConnectionState()`, so a reconnect starts fresh rather than
    comparing against a reading from a previous session.
  - `checkSaturationCurve(channelIndex, adcCorrected, kpa)` — called once
    per channel per sample, right after `adcToKpa()`. Dev-only
    (`import.meta.env.DEV` guarded, though the whole class is already only
    reachable in dev builds — kept explicit anyway as a second, cheap
    safety net). Logs a `console.warn` naming the zone (via
    `FSR_CHANNEL_ORDER`), both adc_corrected values, both kPa values, and
    both ratios, with a note that this is likely the curve's known
    non-linearity, not necessarily a bug. **Not throttled** — a sustained
    bad region firing on every sample is the signal, not noise to
    suppress, per instruction.

### Verified against report 008's own numbers (not fresh hardware — same illustrative values, checked the heuristic behaves correctly)

```js
isSuspiciousKpaJump(2988, 194.815, 3988, 3067.373)  // 3000->4000 raw ADC, offset=12 -> true (fires)
isSuspiciousKpaJump(1000, 20, 2000, 40)              // proportionate 2x/2x jump -> false (does not fire)
isSuspiciousKpaJump(207, 2.956, 214, 3.074)          // real light-touch samples from report 008 -> false (does not fire)
```

Fires on the exact pattern it's meant to catch, stays silent on a
proportionate jump and on the real (small) samples already in hand — as
close to a confirmation as possible without real saturation-range hardware
data.

---

## 2. Per-channel assertion — no action needed

Confirmed correct by the user: `adcToKpa()`'s call site is structurally
identical across all six channels (one `.map()` loop, only calibration
*data* varies per channel), so the missing-`/1000` bug from report 008
could not have been channel-specific. Nothing to add here.

---

## 3. `docs/BACKLOG.md` — two items added

- **Item 12** — the saturation-curve validation gap itself: what was
  observed, why it can't be resolved without a PCB, what the stopgap does
  and doesn't do (the 5x/50% thresholds are a heuristic choice, not a
  validated boundary — may need retuning once real data exists), and what
  "done" looks like (real saturation-range data compared against the
  already-verified standalone test page, the same way report 006's
  checklist compares light-touch values).
- **Item 13** — the bundle tree-shaking non-determinism from reports
  007/008, explicitly scoped as "resolve before Capacitor packaging
  begins, not before" per instruction, cross-referenced to item 3 (font
  subsetting, blocked on the same kind of "everything in `dist/` ships in
  the APK" reasoning). Proposed direction recorded (dynamic `import()` to
  force a separate chunk) but not implemented.

---

## Verify

`npm run build` clean (`tsc --noEmit && vite build`) after the heuristic
was added. No screen touched; `docs/BACKLOG.md` is docs-only.
