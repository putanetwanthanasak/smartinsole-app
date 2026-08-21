# 007 — Raw-ADC-passthrough anomaly: instrumentation added (not diagnosed yet); heatmap label overlap fixed; a bundle-size regression found along the way

Three things. The first is instrumentation only, per instruction — **no fix
proposed, root cause not yet confirmed.** The second is fixed and verified.
The third is a correction to an overstated claim in report 005.

---

## 1. Raw-ADC-passthrough anomaly — instrumented, not diagnosed

**Code review alone does not explain the reported symptom**, which is
itself worth stating precisely before anything else: hand-tracing
`adcToKpa()` with the exact inputs given (rawAdc≈3107, offset_adc=12,
a=123000, b=-1.05, r_pulldown_ohm=10000, sensor_area_m2=0.000113) as the
function is *actually coded* right now gives approximately **224,867**, not
3107.23 and not 226. (Separately — see §1b below — that 224,867 figure is
itself further evidence of a real but different bug: the documented formula
computes Pascals, not kilopascals, and neither this codebase's formula
comment nor `docs/DATA-CONTRACT.md`/`docs/BLE-INTERFACE.md` show a `/1000`
step, though your own hand-calculation applied one to get "~226 kPa
expected.") Since neither "the code is right" (→ ~224,867) nor "the code is
completely bypassed" cleanly explains "~3107 with a decimal fraction," per
instruction I'm not asserting either as the cause — I'm giving you
instrumentation to observe the actual path directly.

### What was added

Three stages, each logging the SAME correlating key (`tUnixMs`), so the
output can be matched line-for-line across files without guessing which
log belongs to which sample:

- **`src/ts/data/WebBleDataSource.ts`, STAGE 1** — inside the `.map()`
  callback that calls `adcToKpa()`, for the hallux channel (index 0) only,
  logs the raw ADC integer, the full calibration inputs used, and
  `adcToKpa()`'s return value **in isolation** — i.e. exactly what the
  function itself produced, before anything else touches it.
- **`src/ts/data/WebBleDataSource.ts`, STAGE 2** — immediately after the
  `SensorSample` object is constructed (same loop iteration), logs
  `sample.fsrKpa[0]` — confirms whether the value assigned into the emitted
  sample matches what STAGE 1 just computed, or diverges.
- **`src/ts/data/DeviceManager.ts`, STAGE 3** — inside `box()`'s
  `source.onSample` handler, logs `s.fsrKpa[0]` (what arrived from the
  source) alongside `b.pressure.hallux` (post `fsrToFootPressure`) — and
  notes explicitly that `b.pressure.hallux` is exactly what `onRawSample()`
  callers receive as `pressure.hallux`, since that's literally what gets
  packed into the `RawPressureSample` a few lines later.

Both are capped at the first **16 samples** (`DEBUG_SAMPLE_LIMIT`) per
connection/session so they don't flood the console indefinitely, and the
`DeviceManager.ts` log is gated behind `import.meta.env.DEV` (the
`WebBleDataSource.ts` logs don't need their own gate — that whole class is
dev-only already, see §3).

All of it is marked `// TEMP DEBUG — see docs/reports/007-*.md` at each
site, meant to be removed once the anomaly is confirmed and fixed, not kept
long-term.

### What to do

1. `npm run dev`, load `?ds=ble`, connect the left side as before.
2. Watch the console for lines tagged `STAGE 1`, `STAGE 2` (from
   `[WebBleDataSource:left]`) and `STAGE 3` (from
   `[BLE-DEBUG:DeviceManager]`).
3. Paste back (or screenshot) the first several lines of each stage for the
   same `tUnixMs` values. That tells us directly:
   - If STAGE 1's `adcToKpa()=` value is already ≈3107 → the bug is inside
     `adcToKpa()` itself (and my hand-trace above is wrong somewhere, or
     the real calibration values you have differ from the four you quoted
     in some way that matters).
   - If STAGE 1's value is NOT ≈3107 (e.g. it's the ~224,867-scale number
     my hand-trace predicts) but STAGE 2's `fsrKpa[0]` IS ≈3107 → something
     between the `adcToKpa()` call and the `SensorSample` construction is
     overriding it (in this codebase, that's a very short gap — worth
     seeing directly rather than assumed).
   - If STAGE 2 already shows ≈3107 but STAGE 1 doesn't → same as above,
     narrowed to that specific gap.
   - If all three stages agree on some value that's neither 226 nor 3107
     nor 224,867 → a fourth possibility I haven't hand-traced, and the
     actual number will say what it is.
4. If you can, also paste `getDiagnostics().calibration` in full (not just
   the four numbers you quoted) — if there's any chance the real values
   differ from what was typed by hand (extra channels, different `index`
   ordering, a decimal typo), that would show up here and change what the
   "expected" 226 kPa hand-calc should actually be.

### §1b — a related but distinct finding: the Pa/kPa unit gap

Flagging this now because it's directly relevant to reading STAGE 1's
numbers, not because I'm proposing to fix it in this pass. The documented
formula (both here and in the contract, even after the `offset_adc` fix)
is:

```
F_newton = a x R_fsr^b
P_kPa = F_newton / A_sensor
```

`F_newton / A_sensor` (N / m²) is Pascals. Labeling that `P_kPa` without a
`/1000` step is a units bug independent of the offset_adc one you already
resolved — it would explain values reading **1000x too high** once/if the
raw-passthrough anomaly above is fixed, but does NOT explain the specific
"near-identity to raw ADC" symptom reported (224,867 is not close to
either 3107 or 226). Not touched in this pass — only noted so it isn't
mistaken for a new, unrelated problem if it shows up once the primary
anomaly is resolved and the debug logs stop looking like ~raw-ADC numbers.

---

## 2. Heatmap zone-label overlap — root cause found and fixed, verified visually

**Root cause:** `css/heatmap.css` already had a comment documenting this
exact class of bug being tuned once before — the danger-tier label
font-size was reduced from 14px to 12px specifically because 3-digit kPa
values ("220") overlapped adjacent metatarsal zones at 14px. That tuning
assumed values never exceed 3 digits. The raw-ADC-scale values from §1
above (up to 4 digits, e.g. "4095") broke that assumption the same way,
between the same pair of zones (`meta1`/`meta3`, which sit closest
together) — which is what produced the garbled six-digit-looking label:
two adjacent 4-digit SVG `<text>` elements overlapping, not one label
containing a wrong number.

**Fix, in `src/ts/heatmap.ts` and `css/heatmap.css`:** rather than hand-tune
a third fixed size (which would just break again at 5+ digits — this
codebase has now hit this twice), the zone's `<text>` element gets a
`wide-value` (4 digits) or `x-wide-value` (5+ digits) class based on the
rounded value's actual digit count, with corresponding smaller font-size
rules in CSS. The combined `.wide-value.danger` / `.x-wide-value.danger`
selectors carry higher specificity than the existing bare `.danger` rule,
so a value that's both wide AND in the alert tier gets the smaller size,
not the larger danger-tier one.

Also fixed the same underlying assumption in the risk-summary's danger-zone
chip (`css/heatmap.css`, `.danger-zone-row .chip`), which had a fixed
`width: 36px` for what's always been a 3-digit alert-tier kPa value — not
reported as broken (it hadn't been visibly triggered), but the same latent
issue, one-line fix (`width` → `min-width` + horizontal padding), low
enough risk to include here rather than leave for the next person to
rediscover.

**Verified in the browser**, not just read — the live mock stream
re-renders at 10 Hz and overwrites any one-off DOM edit within ~100 ms, so
verifying this needed the mock source's own emitter monkey-patched
(`window.__insole.mockSources.left.emitSample = ...`) to continuously push
synthetic values through the REAL rendering path (`Heatmap.setPressure()`,
the exact code being changed) rather than editing the DOM directly:

- Six zones forced to 4-digit values (4095, 3933, 4247, 2500, 1500, 1000):
  all render legibly, no overlap, including the `meta1`/`meta3` pair that
  produced the original bug.
- Six zones forced to 6-digit values (224867, 393312, 424712, 250000,
  150000, 100000 — the scale §1b's Pa/kPa gap would actually produce):
  same result, all legible, no overlap.

Reloaded the page afterward to clear the monkey-patch; the fix itself is
in source, not something that needs the patch to keep working.

---

## 3. Correction to report 005: the production bundle is NOT reliably tree-shaken

Report 005 stated the BLE stack "costs nothing in the shipped app unless a
dev build explicitly opts in," backed by a `grep` showing zero
`WebBleDataSource`/`requestDevice` hits in that build's output. That was
true **for that specific build**, not as a structural guarantee — this
pass's build (same `usingWebBle`/`import.meta.env.DEV` gating, no
intentional change to that logic) shows the opposite:

```
$ grep -c "BLE-DEBUG\|STAGE 3\|WebBleDataSource" dist/assets/index-*.js
1
```

`WebBleDataSource`'s full method bodies (`handleTempValue`,
`handleStatusValue`, `trackSeq`, `connect`, etc.) are present in the
production bundle, and the bundle grew from ~70 kB to ~81 kB accordingly.
Checked that the actual RUNTIME gating still works correctly —
`usingWebBle`/`import.meta.env.DEV`/the `"ds"` query-param string are all
absent from the built output, confirming `bleSources` really does resolve
to `null` in production and `new WebBleDataSource()` never executes — so
this is **not a functional regression**, nothing about `WebBleDataSource`
runs in a shipped build. It's a bundle-size regression: whether the whole
now-unreachable class gets stripped from the output depends on the
minifier successfully constant-folding `usingWebBle` all the way through
to `bleSources = null` and then eliminating everything only reachable from
there — which report 005 got right on that specific build by what now
looks like circumstance rather than something this file's gating pattern
guarantees.

**Not fixed in this pass** — flagged so it isn't silently relied on again.
Report 005's claim should be read as "was true for that build," not as an
ongoing property of `?ds=ble`'s gating. If bundle size before Capacitor
packaging matters (see `docs/BACKLOG.md` item 3, already tracking font
subsetting for the same reason), this needs either a more forceful
exclusion (e.g. a dynamic `import()` for the BLE module, which forces a
separate chunk rather than relying on dead-code elimination) or accepting
the current ~81 kB and revisiting later.

---

## Verify

`npm run build` clean throughout (`tsc --noEmit && vite build`) — after the
debug instrumentation, after the heatmap fix, and at the end. Heatmap fix
verified live in the browser as described above (not by inference). The
raw-ADC anomaly remains unconfirmed — that's the point of this pass; next
step is running the instrumented build against real hardware and reporting
the STAGE 1/2/3 output back.
