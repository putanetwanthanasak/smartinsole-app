# lib/gait/

Gait classification (DATA-CONTRACT §7) and the Gait tab's figures (S8A).
Nothing here sets a level: the gait result is never a risk level (rule 11).

- `gait_class.dart` — the 5 classes in contract §7.2 index order;
  `GaitResult` (class, confidence and probabilities for the model, source,
  why the rules were used, sample time).
- `gait_classifier.dart` — `GaitClassifier`, `ModelRunner` interfaces.
- `rule_based_classifier.dart` — the provisional rules (§7.5): toe / heel
  share of step PTI, stance-time PAI; every boundary from `gait.*` in
  `thresholds.json`; never `rotated_foot`.
- `model_spec.dart` — `model_input.json` (window, stride, channel order)
  and `normalization.json` (validated against it).
- `model_window.dart` — the 50 Hz path → `pairFeet` → the newest 100
  consecutive raw rows.
- `preprocess.dart` (S9) — preprocessing "ทางเอ" (contract §7.1,
  `shared/model_preprocess.json`): per-foot median baseline, then
  `((x − baseline) − min) / (max − min)` → `[1,100,28]` `Float32List`, the
  same float32 bits as `tools/model/preprocess.py`
  (`shared/test_vectors/model_preprocess/`); `modelBaselineOf` finds the
  connected insoles' stored baselines.
- `baseline_window.dart` (S9-2, BACKLOG 74) — `FootBaselineWindow`, the
  one baseline function: the first `baselineSeconds` × 50 samples per foot
  that pass, or a named `BaselineFailure` (reconnected, lost packets,
  TARE, marked invalid, not 8 FSR, moved, not loaded, too short). Capture
  trial 00 (`capture/trial_baseline.dart`) and the recorder below both use
  it; `tools/model/preprocess.py foot_baseline_window` is its port,
  matched on `shared/test_vectors/baseline/`.
- `baseline_recorder.dart` (S9) — the researcher's 30 s quiet-standing
  recording on the 50 Hz path, each sample through `FootBaselineWindow`;
  stored by `storage/baseline_repository.dart`.
- `model_classifier.dart` — the model slot: `assets/models/` (release,
  empty until after data collection, late Nov) or `assets/models_dummy/`
  (debug/profile with `--dart-define=GAIT_MODEL=dummy`); `ModelMissing` / `ModelInvalid` /
  `ModelReady`; queued runs, inference timing; `runModelCheck` against a
  slot's optional `check.json`.
- `tflite_classifier.dart` — the only file that imports `tflite_flutter`:
  a long-lived isolate owning the interpreter (not `IsolateInterpreter`,
  which crashed in the S8A spike); checks the tensor shapes.
- `demo_model_runner.dart` — debug-only `GAIT_MODEL=demo-toe` stand-in.
- `gait_estimator.dart` — every `model_input.json` stride of sample time:
  the model when ready, both connected insoles have a baseline (S9;
  otherwise the rules with `RulesBecause.noBaseline`) and it is confident
  (≥ `model.minConfidence`), the rules otherwise; current and last result; `modelEstimateFor(side)` for the
  alert engine's gait note (fresh model results only).
- `step_counter.dart` — "ก้าววันนี้", stored in `daily_summary.steps`.
- `cop.dart`, `pti_asymmetry.dart` — the Gait tab's details.
- `gait_timing.dart` — technical constants (not thresholds); skipped by
  the no-literal test, as is the demo runner.
- `gait_providers.dart` — providers; `StorageHost` keeps the estimator and
  step counter alive.

To drop in Model A, put `model_a.tflite` and `normalization.json` in
`mobile/assets/models/` (see its README.md). No code changes. The
researcher records each insole pair's baseline once (Researcher ›
"บันทึกค่ายืนนิ่ง 30 วินาที"); until then the rules classify.
