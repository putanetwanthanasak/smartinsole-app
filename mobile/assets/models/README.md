# assets/models/ — the Model A slot

Put exactly these two files here (DATA-CONTRACT v1.6 §7, `lib/gait/README.md`):

- `model_a.tflite` — input `[1, 100, 28]` float32 (8 FSR + 6 IMU per foot;
  channel order and units
  of `shared/model_input.json`), outputs `[1, 5]` (`gait_probs`, softmax in
  the class order of contract §7.2) and `[1, 32]` (`gait_embedding`).
  TFLite builtin ops only.
- `normalization.json` — `{"version": 2, "channels": [28 names, same order
  as shared/model_input.json], "mean": [28], "std": [28]}`, the training
  set's z-score parameters. `"version"` must equal
  `shared/model_input.json`'s (2 since contract v1.6; a version-1,
  24-channel file from the 6-FSR insole is refused).

With neither file the app classifies gait with its rules ("โมเดล AI ยัง
ไม่พร้อม"). With one file missing or wrong, it does the same and the BLE
debug screen's "Gait model" section says why. Nothing else changes.
