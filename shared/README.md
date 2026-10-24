# shared/

Files shared between the Flutter app (`mobile/`) and the new simulator
(`firmware/simulator/`). See `docs/FLUTTER-PLAN.md` section 3.

- **`thresholds.json`** — the source-of-truth threshold file for the Flutter
  app. It started as a byte-for-byte copy of `public/thresholds.json`.
  Later additions, all additive with `"version"` 1 (DATA-CONTRACT §8.3
  addenda): `battery` (S5); in S7 `pressure.ptiWindowMin` / `ptiMinSteps`
  / `peakHoldMs`, `asymmetry.peakSteps` / `concentrationSteps`, `device`,
  `alerts` and `steps` (step detection, provisional). The app bundles a
  byte-identical copy (`mobile/assets/config/`, a test checks it); the
  simulator's native tests read this file directly.
- **`test_vectors/`** — BLE wire-format test vectors generated from the web
  app's TS parser; the Flutter parser is tested against them. See
  `test_vectors/README.md` (regenerate with
  `node shared/test_vectors/generate.mjs`).
- **`model_input.json`** — Model A's 24 input channels (DATA-CONTRACT §7.1)
  in order, with their units (FSR kPa, accel g, gyro °/s), the 50 Hz rate
  and the 100-sample window / 50-sample stride. The app's
  `mobile/lib/device/model_channels.dart` must match it (a Dart test checks
  this), and the training scripts read the same order. Never reorder.
  Its `pairing` entry is the rule that pairs a left and a right sample
  into one row (left is the time base; nearest right sample within
  ±10 ms). The app (`pairFeet`) and `tools/capture/load_capture.py`
  implement the same rule.
- **`capture_fixture/`** — one rehearsal capture session written by the
  app's own capture code, with its export `manifest.json`, plus
  `expected.json` (the 24-channel rows the app's `pairFeet` + `modelRow`
  make), and since S7 the export's `alerts.csv` with one alert.
  `mobile/test/capture/capture_fixture_test.dart` checks the code
  still writes exactly these files; `load_capture.py --selftest` must
  reproduce `expected.json` from them. Regenerate only after an intended
  format change: `UPDATE_CAPTURE_FIXTURE=1 flutter test
  test/capture/capture_fixture_test.dart` (in `mobile/`).
- `sensor_layout.json` — not yet created (planned with the heatmap, S5).

## The web app still uses `public/thresholds.json`

The web app is **frozen** — do not edit it, and do not edit
`public/thresholds.json`. It keeps loading its own copy from `public/` at
runtime. The two copies are intentionally not linked (no symlink, no build
step), so a change to `shared/thresholds.json` does **not** reach the web app,
and the two files may diverge from here on.
