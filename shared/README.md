# shared/

Files shared between the Flutter app (`mobile/`) and the new simulator
(`firmware/simulator/`). See `docs/FLUTTER-PLAN.md` section 3.

- **`thresholds.json`** — the source-of-truth threshold file for the Flutter
  app. It started as a byte-for-byte copy of `public/thresholds.json`.
  Later additions, all additive with `"version"` 1 (DATA-CONTRACT §8.3
  addenda): `battery` (S5); in S7 `pressure.ptiWindowMin` / `ptiMinSteps`
  / `peakHoldMs`, `asymmetry.peakSteps` / `concentrationSteps`, `device`,
  `alerts` and `steps` (step detection, provisional); in S8A
  `model.highConfidence` and `gait` (rule-based gait classes,
  provisional); in S6B `sources`,
  the "ที่มา" column of §8.3 word for word, keyed by wire code ("—" =
  none; the alert detail's "ที่มาของเกณฑ์" row, hidden for "—"). The
  PTI source does not confirm its value (BACKLOG 43). The app bundles a
  byte-identical copy (`mobile/assets/config/`, a test checks it); the
  simulator's native tests read this file directly.
- **`test_vectors/`** — BLE wire-format test vectors generated from the web
  app's TS parser; the Flutter parser is tested against them. See
  `test_vectors/README.md` (regenerate with
  `node shared/test_vectors/generate.mjs`).
- **`model_input.json`** — Model A's 28 input channels (DATA-CONTRACT v1.6 §7.1; version 2 since S8D, version 1 had 24 for the 6-FSR insole)
  in order, with their units (FSR kPa, accel g, gyro °/s), the 50 Hz rate
  and the 100-sample window / 50-sample stride. The app's
  `mobile/lib/device/model_channels.dart` must match it (a Dart test checks
  this), and the training scripts read the same order. Never reorder.
  Its `pairing` entry is the rule that pairs a left and a right sample
  into one row (left is the time base; nearest right sample within
  ±10 ms). The app (`pairFeet`) and `tools/capture/load_capture.py`
  implement the same rule.
  The app bundles a byte-identical copy (`mobile/assets/config/`, a test
  checks it and its pubspec entry) and reads the window and stride for
  Model A from it (S8A).
- **`capture_fixture/`** — rehearsal capture sessions written by the
  app's own capture code, each with its export `manifest.json`,
  `alerts.csv` and `expected.json` (the model rows the app's `pairFeet` +
  `modelRow` make):
  - `schema2/` (S8D, capture schema 2, 8 FSR + 8 temperature sites):
    28-channel rows, two temperature readings per foot (one site that
    could not be read, one with poor contact) and a `TEMP_DELTA` with its
    `temp_sites`. `mobile/test/capture/capture_fixture_test.dart` checks
    the code still writes exactly these files. Regenerate only after an
    intended format change: `UPDATE_CAPTURE_FIXTURE=1 flutter test
    test/capture/capture_fixture_test.dart` (in `mobile/`; writes
    `schema2/` only).
  - `schema1/` (frozen, never regenerated): the 6-FSR schema-1 session
    from before S8D, 24-channel rows. It keeps old files loadable.
  `load_capture.py --selftest` must reproduce both `expected.json` files.
- **`sensor_layout.json`** (S8D, DATA-CONTRACT v1.6 §3.1) — the 8 sites per
  foot in wire order (index = FSR channel = temperature site; NTC i sits
  next to FSR i): stable id, English and Thai name, region and the
  position in mm (left foot; the right foot mirrors), plus the display
  transform that places a site on the app's 120×268 foot map. Ids 0–5 are
  the ids stored alerts and capture files already use. The app mirrors it
  in `mobile/lib/config/foot_layout.dart` (`test/config/foot_layout_test.dart`
  keeps them identical); `tools/capture/load_capture.py` reads its ids.

## The web app still uses `public/thresholds.json`

The web app is **frozen** — do not edit it, and do not edit
`public/thresholds.json`. It keeps loading its own copy from `public/` at
runtime. The two copies are intentionally not linked (no symlink, no build
step), so a change to `shared/thresholds.json` does **not** reach the web app,
and the two files may diverge from here on.
