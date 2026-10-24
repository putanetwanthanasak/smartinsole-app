# lib/config/

- `thresholds.dart` — loads `assets/config/thresholds.json` (a copy of
  `shared/thresholds.json`) at startup; `thresholdsProvider` (rule 12).
- `foot_layout.dart` — foot outline, FSR channel → zone mapping and
  positions. **Placeholder** (DESIGN-SPEC §5) until
  `shared/sensor_layout.json` exists; replace `footLayout` then.

When `shared/thresholds.json` changes, copy it to
`mobile/assets/config/thresholds.json` (`test/config/thresholds_test.dart`
fails if the two differ).
