# 008 — Pa→kPa fix confirmed and applied; debug instrumentation removed

Root cause confirmed by the instrumented logging added in report 007: the
"raw-ADC-passthrough anomaly" was never a passthrough or a separate bug —
it was the Pa/kPa gap report 007 §1b flagged, and the STAGE 1/2/3 logs
agreeing on every line ruled out every hypothesis about something
overriding the value between `adcToKpa()` and `onRawSample()`.

---

## The fix

`adcToKpa()` in `src/ts/data/blePacketParser.ts` now divides by 1000:

```
P_kPa = F_newton / A_sensor / 1000
```

(`F_newton / A_sensor`, N/m², is Pascals — the formula never had this step,
in this codebase or in the contract text.)

**Verified against both provided data points, exactly:**

```
rawAdc=345 -> 5.385219160854951   (hand-calc: ~5.41 kPa)
rawAdc=207 -> 2.9562773263992512  (hand-calc: ~2.96 kPa)
```

Both match the logged pre-fix Pa values divided by 1000 exactly (5385.22 →
5.38522, 2956.28 → 2.95628), confirming the fix is the missing step and
nothing else changed in the formula.

## Docs updated to show the step explicitly, not just describe it

Same treatment as the `offset_adc` fix (report 006):

- `docs/DATA-CONTRACT.md` §5.1 — formula block now reads
  `P_kPa = F_newton / A_sensor / 1000`, with a short Thai comment on why.
- `docs/BLE-INTERFACE.md` "FSR scaling" section — same formula update, plus
  a paragraph on what was found and how (instrumented hardware logs, not
  unit analysis alone), and a note that this is the SECOND correction to
  measured values (offset_adc, then this) — anything captured before report
  006 or before this report is stale on two separate axes now.
- `docs/BLE-INTERFACE.md` "What's still open" — new resolved entry.

## Why the reported symptom looked like "raw ADC passed through with a decimal fraction"

It wasn't a coincidence of value, it was a coincidence of *scale*. The
originally-reported ~3107.23 and the confirming samples in this pass
(rawAdc 211/212/214 → Pa outputs 3023/3040/3073) both land in the
low-thousands purely because that's where a resting/light-touch ADC
reading's Pa output happens to fall for this calibration — not because the
output numerically tracked the input. Once divided by 1000, those same
samples read 3.02/3.04/3.07 kPa — a completely different, and plausible,
number.

---

## Was this checked per-channel, or asserted from shared code?

**Asserted from shared code, not re-verified per channel with fresh
instrumentation.** `adcToKpa()` is called identically for all six FSR
channels through the same `.map()` loop in `WebBleDataSource.ts`'s
`handleSensorValue()` — the only thing that varies per channel is the
calibration *data* passed in (`a`, `b`, `offsetAdc`, looked up by index),
never the code path or the formula itself. The missing `/1000` was a fixed
structural omission at the end of the shared function, not something that
could plausibly be channel-specific. Given that, I judged re-instrumenting
a second channel to independently confirm not worth another hardware round
trip — but per your instruction, saying so explicitly rather than implying
all six were individually checked: they weren't. If you want to be certain,
the cheapest check is just looking at the Home screen heatmap after
reconnecting — see the range check below, which already exercises all six
zones simultaneously through the real UI, not the console.

---

## Sanity range check — what I could and could not actually confirm

**What I recomputed, from real data you already provided** (not fabricated,
not a fresh hardware run — I have no hardware access):

```
rawAdc=207 -> 2.956 kPa
rawAdc=211 -> 3.023 kPa
rawAdc=212 -> 3.040 kPa
rawAdc=214 -> 3.074 kPa
rawAdc=345 -> 5.385 kPa
```

All five land in a single-digit kPa range, consistent with light/resting
touch — plausible, not alarming, which is what a properly-converted reading
under light load should look like.

**What I did NOT check, and cannot check myself:** the heel-strike / firm-
press end of the range. I don't have a real raw-ADC sample anywhere near
that load level from you — the five points above are all in the 207-345
raw ADC range (roughly 5-8% of the 0-4095 scale), nowhere close to what a
heel strike would read. I ran the formula against some ILLUSTRATIVE
raw-ADC values of my own choosing (1000/2000/3000/4000) purely to see the
formula's shape, not as a claim about real data:

```
rawAdc=1000 (illustrative, not measured) -> 20.6 kPa
rawAdc=2000 (illustrative, not measured) -> 64.6 kPa
rawAdc=3000 (illustrative, not measured) -> 194.8 kPa
rawAdc=4000 (illustrative, not measured) -> 3067.4 kPa
```

Worth flagging on its own: the curve is steeply non-linear near the top of
the ADC range (the power-law `R_fsr^b` term), so a raw ADC approaching 4095
can produce an implausibly large kPa figure from a small further increase —
this may be an expected property of the fitted curve near sensor
saturation, or it may be worth a plausibility clamp at some point, but I'm
not asserting either without real data at that end of the range. **The
actual sanity check you asked for — real values across light touch through
heel strike — needs you to reconnect and either watch the Home screen
heatmap directly (no console needed, the fix is already live in the
numbers it renders) or capture a few more raw-ADC/kPa pairs at higher load
and share them.**

---

## Debug instrumentation removed

```
$ grep -rn "TEMP DEBUG" src/
(no output, exit code 1)
$ grep -rn "BLE-DEBUG\|debugSamplesLogged\|DEBUG_SAMPLE_LIMIT\|debugThisSample" src/
(no output, exit code 1)
```

All three stages added in report 007 (`WebBleDataSource.ts`'s STAGE 1/2,
`DeviceManager.ts`'s STAGE 3, and their supporting fields/counters) are
removed. `handleSensorValue()`'s sample loop and `DeviceManager.box()`'s
`onSample` handler are back to their report-006 shape, with only the
`/1000` change carried forward in `blePacketParser.ts`.

---

## One more observation, not asked for

This build's bundle again shows the BLE stack fully tree-shaken out
(`grep -c "WebBleDataSource\|requestDevice\|handleSensorValue"
dist/assets/index-*.js` → `0`), unlike report 007's build, which included
it (~81 kB) with no intentional change to the gating logic between the two.
This is exactly the non-determinism report 007 flagged — noted again here
as further evidence, not something fixed in this pass.

---

## Verify

`npm run build` clean (`tsc --noEmit && vite build`) after the formula fix
and again after removing the debug instrumentation. `grep` confirms zero
`TEMP DEBUG` hits (and zero hits for the supporting debug identifiers) in
`src/`.
