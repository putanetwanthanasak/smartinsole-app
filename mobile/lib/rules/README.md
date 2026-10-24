# lib/rules/

The alert rules (S7): DATA-CONTRACT v1.5 §8.3's 8 codes, their internal
level 1–5, and the mapping to the patient's 3 levels (FLUTTER-PLAN §7).
Every number comes from `shared/thresholds.json` through `Thresholds`
(rule 12): `test/rules/no_threshold_literals_test.dart` fails on any
numeric literal here other than 0, 0.5, 1, 100 and 1000 (comments and
string text are skipped; `alert_code.dart`, the contract's level column,
is the one file it skips).

| File | What it holds |
|---|---|
| `alert_code.dart` | The 8 codes and their levels; `carefulLevel` (3) and `restLevel` (4) |
| `patient_status.dart` | `PatientLevel`, `PatientStatus` (with `missingSide`), `StatusCause`, `patientLevelFor`, `alertKey` |
| `alert_engine.dart` | `AlertEngine`: the rules, the status, raising and storing alerts; `deltaAbove` |
| `alert_providers.dart` | `alertEngineProvider` (kept alive by `StorageHost`), `gaitEstimateProvider` (null until S8A) |
| `walking_gate.dart` | Contract §8.3.2's walking gate, per foot |
| `step_detector.dart` | Walking steps per foot: stance limits, per-zone peak and PTI |
| `alert_copy.dart` | Plain-Thai copy for every code (rule 13; DRAFT health copy) |
| `gait_note.dart` | Contract §8.3.1's gait note (never changes a level) |
| `asymmetry.dart` | PAI (`paiPercent`, `PeakAsymmetry`) |
| `weight_share.dart` | Home's balance card share (display only, not a rule) |
| `pressure_level.dart` | Foot-map dot level |

## How the engine works

- **Inputs.** `DeviceManager.batches` (50 Hz, rule 10) feeds each foot's
  gate, step detector, peak holds and PTI window; `DeviceManager.temps`
  forms reading pairs for `TEMP_DELTA`. A 1 s timer only asks the rules
  again, for `DEVICE_LOST`, which needs no new data.
- **Conditions, not latches.** `conditions(snapshot)` derives which rules
  hold from timestamps each time it is asked (rule 2). Home reads
  `view(snapshot)` at 10 Hz.
- **Alerts.** A rule that starts to hold raises one alert, unless the same
  key (code + side + zone or site) was raised in the last
  `alerts.repeatMin` minutes. Exactly `repeatMin` later is allowed. On
  start the engine reads that memory back from the alerts table, so it
  holds across a restart. Each stored alert has the patient level shown at
  that moment, the numbers for the detail rows, the gait estimate
  (pressure codes only) and the open research capture's stamp.
- **Status.** Both feet unusable → No data. Otherwise the best level-3+
  rule names the card: higher level first, then TEMP_DELTA > PTI > PEAK >
  LOAD_CONCENTRATION, then the one furthest past its threshold. A
  connected foot's level 3+ wins over a missing foot (BACKLOG 38);
  otherwise a missing foot is No data naming it. Levels 1–2 never change
  the card; `ASYMMETRY_PEAK` (level 2) turns Home's balance note orange.

| Code | Holds while (per foot, and per zone or site) |
|---|---|
| `TEMP_DELTA` (4) | `consecutiveReadings` reading pairs in a row with \|ΔT\| > `deltaC` at one site; a pair with no ΔT resets the run, a missed reading does not. Both feet usable. Side = the warmer foot |
| `PRESSURE_WATCH` (2) | A sample above `watchKpa` in the last `peakHoldMs` |
| `PRESSURE_PEAK` (3) | A sample above `alertKpa` **while the gate is on** in the last `peakHoldMs` (rule 7) |
| `PRESSURE_PTI` (3) | Mean per-step PTI over the last `ptiWindowMin` > `ptiKpaS`, ≥ `ptiMinSteps` steps, still walking |
| `LOAD_CONCENTRATION` (3) | Top zone's share of the step's zone peaks > `concentrationPct`, same zone `concentrationSteps` steps in a row, still walking |
| `ASYMMETRY_PEAK` (2) | PAI of the two feet's latest step peaks > `peakPct` for `peakSteps` steps in a row; both feet usable. Side = the higher foot |
| `DEVICE_LOST` (1) | A foot that streamed this run has had no data for > `lostAfterMin`, and the user did not disconnect it |
| `BATTERY_LOW` (1) | Usable and battery < `lowPct` |
