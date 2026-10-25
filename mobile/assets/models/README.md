# assets/models/ — the Model A slot

Put exactly these two files here (DATA-CONTRACT §7, `lib/gait/README.md`):

- `model_a.tflite` — input `[1, 100, 24]` float32 (channel order and units
  of `shared/model_input.json`), outputs `[1, 5]` (`gait_probs`, softmax in
  the class order of contract §7.2) and `[1, 32]` (`gait_embedding`).
  TFLite builtin ops only.
- `normalization.json` — `{"version": 1, "channels": [24 names, same order
  as shared/model_input.json], "mean": [24], "std": [24]}`, the training
  set's z-score parameters.

With neither file the app classifies gait with its rules ("โมเดล AI ยัง
ไม่พร้อม"). With one file missing or wrong, it does the same and the BLE
debug screen's "Gait model" section says why. Nothing else changes.
