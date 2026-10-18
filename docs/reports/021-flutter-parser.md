# 021 — S2A: Parser + test vectors

Branch `work/flutter-parser` · 2026-10-18 · Session S2A (`docs/SESSIONS.md` §3)

## What was done

1. **S1B decisions recorded** (a separate commit, `baeb189`). Added two rows
   to `docs/FLUTTER-PLAN.md` §2: screen titles move into the page body
   (applied in S5, S6B, S8A, S8B and S8C), and the greeting name is set in
   Settings (S8B), with a plain "สวัสดี" when no name is set. BACKLOG item 14
   is marked resolved. Its three non-decision bullets are carried by their
   sessions.
2. **Test-vector generator** `shared/test_vectors/generate.mjs`. It
   compiles the web app's `blePacketParser.ts` with the repo's own `tsc`
   into a temp dir (read-only; `src/` is unchanged), feeds it fixed inputs,
   and writes 69 cases in 6 files. Coverage: the normal 200-byte packet,
   `count` = 4/1/0, ADC 0/4095, `offset_adc` below, equal to and above the
   raw value, every flag, int16 IMU extremes, max `seq`/`t0`, truncated,
   too short, extra bytes; temperature `-32768` (forefoot, heel, both),
   quality 0/1/2; status state 0/1/2, both feet, error codes 0–5; 3 valid
   and 16 malformed calibration blobs; N = 4 and N = 8 packets. `--check`
   fails if the committed files are stale. See
   `shared/test_vectors/README.md`.
3. **Dart parser** `mobile/lib/ble/`: protocol constants, packet models,
   `parseSensorPacket(bytes, fsrCount: N)` with a `2N + 12`-byte sample
   block, temperature and status parsers, `parseCalibration` (N =
   `channels.length`, indexes must be exactly 0..N−1, stored sorted), and
   ADC → kPa / IMU conversion. The arithmetic runs in the same order as TS.
4. **Rejections are never silent** (the user's addition at plan approval).
   Every parser returns a sealed `ParseResult` = `Parsed` | `Rejected`.
   `Rejected` carries a `RejectReason` (12 values), a detail string, and
   expected/actual byte counts for length problems, so S3A/S4 can count
   and log per foot.
5. **Tests** (`mobile/test/ble/`, 112 tests): one test per vector case, a
   check that every vector file is known and non-empty, N = 4/6/8 round
   trips, wrong-N detection in both directions, and one test per
   `RejectReason`, with a final test that fails if any reason has no test.

## Checks

| Check | Result |
|---|---|
| `node shared/test_vectors/generate.mjs --check` | **Pass** — the vectors reproduce byte-for-byte from the TS code |
| `flutter analyze` | **Pass** — no issues |
| `dart format` | **Pass** — clean |
| `flutter test` (whole app) | **Pass** — 129/129, including the S1B goldens and navigation tests |
| 100% of test vectors pass | **Pass** — 69/69 |
| N = 4/6/8 pass | **Pass** |
| kPa matches TS to 3 decimal places | **Pass** — largest kPa difference is 7.3 × 10⁻¹² (on values up to about 37 000 kPa at ADC 4095). `adc_corrected`, `accel_g`, `gyro_dps` and `temp_c` match exactly (difference 0.0) |
| Tests catch real regressions | **Pass** — removing the `/1000` or the `max(0, …)` offset clamp in Dart makes the vector tests fail; both changes were reverted |
| Web app untouched | **Pass** — `git diff main` over `index.html src css public package*.json vite.config.ts tsconfig.json` is empty |
| 16 rules (relevant ones) | 1 ✓ `deviceMs = t0 + i × 20`. 8 ✓ foot side is never masked: an invalid byte is rejected, so S3A can refuse the connection. 12 ✓ no thresholds involved. 2, 3, 9 don't apply to the parser (they belong to S3A/S4); the rest are UI or rules work |
| Emulator / Dart MCP UI check | **Not applicable** — this session has no UI |
| Note 10 checkpoint | **Not applicable** — none scheduled for S2A |

**Done when** ("Dart and TS give identical values for every case"): met,
with two deliberate exceptions. In both, Dart rejects input that TS accepts
(below), and that is recorded in the vectors.

## Deliberate differences from the TS parser (decision for you)

Both are stricter than TS. Each one is a single `if` and easy to undo.

1. **Out-of-range enum bytes are rejected, not masked.** TS does
   `foot_side & 1`, `state & 3`, `quality & 3`, so `foot_side = 2` reads as
   "left", which defeats rule 8. This was in the approved plan.
2. **A sensor packet longer than its `count` accounts for is rejected**
   (`lengthMismatch`). *Not in the approved plan; I added it while writing
   the tests.* If extra bytes are accepted (as TS does), an N = 8 packet
   parsed as N = 6 is not flagged: it would parse into wrong values on the
   wrong zones without any error. With this check, a wrong N is caught in
   both directions (`truncated` or `lengthMismatch`). The single TS vector
   with extra trailing bytes is marked `dart_rejected: lengthMismatch`.
   **Please confirm you want this.**

Also added beyond the plan: `calibrationInvalidValue`, which rejects
`r_pulldown_ohm` ≤ 0 or `sensor_area_m2` ≤ 0. TS accepts those, and a zero
area turns every kPa into infinity.

## Observations

- **Zero load reads about 0.01 kPa, not 0.** This is inherited from TS:
  `adcToKpa` clamps `adc_corrected` to at least 1 to avoid dividing by
  zero. It is far below any threshold, so not a clinical issue, but a
  "0 kPa" display would need rounding. Dart matches TS on purpose.
- **ADC 4095 gives about 37 000 kPa** (the `R_fsr` clamp at 10⁻⁶ Ω). This
  is the saturation behaviour BACKLOG item 12 already tracks. The parser
  passes it through unchanged, as TS does, and the `saturated` flag is
  exposed.
- `deviceMs` is `t0 + i × 20` without uint32 wrap-around. The device clock
  wraps after about 49.7 days of uptime. That is not a parser concern;
  S3A/S4 should handle it alongside clock sync.

## Leftovers

- BACKLOG **15**: the variable FSR count (`2N + 12`) isn't in the Data
  Contract yet. The contract owner needs to add it before any N ≠ 6
  hardware exists. S2B's `FSR_COUNT` flag depends on this too.
- BACKLOG **16**: a variable NTC count (up to 6 per foot) has no wire
  format. The temperature packet is fixed at 2 values.
- `sensor_layout.json` was not created; it isn't in S2A's "Do" list. It
  will be needed with the heatmap (S5).

## Decisions needed

1. Keep the `lengthMismatch` rejection (see above)? Recommended: yes.

## Next session

S2B: new simulator core. It needs PlatformIO and at least one ESP32, and
its `FSR_COUNT` build flag depends on BACKLOG 15. The simulator can be
checked against `shared/test_vectors/` by comparing its packet bytes with
the vector hex.
