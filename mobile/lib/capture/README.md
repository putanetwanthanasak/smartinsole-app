# lib/capture/

Research capture (S4C): the study's recording tool, researcher-only, from
Settings → "Research capture" (release builds too). The study-day steps
are in `docs/STUDY-CAPTURE.md`; the decisions are in
`docs/reports/027-flutter-capture.md`.

| File | Contents |
|---|---|
| `capture_protocol.dart` | Doc 03 protocol: `GaitClass` (contract §7.2 ids and model indices), `Rotation`, `SubjectCode` (`SI-nnn` / `TEST-nnn` only; pain side by parity), `Sex`, `ageRanges`, `trialOrder(seed)`, `CaptureTimings` (study and rehearsal) |
| `capture_files.dart` | File format: CSV columns and rows, file names, calibration JSON, atomic JSON writes. `captureSchema` versions it |
| `trial_recorder.dart` | `TrialRecorder`: one attempt from `DeviceManager.batches` / `temps` to a CSV; gaps, invalid segments, per-foot counts |
| `capture_session.dart` | `CaptureSession`: the state machine, `session.json`, sidecars, redo, resume; `precheckIssues`; `listSessions` |
| `cues.dart` | `Cue` (sound + vibration pattern), `CaptureCues`, `DeviceCues` (audioplayers + vibration) |
| `export.dart` | `stageExport`: copy + `manifest.json` (SHA-256) to the app-specific external folder |
| `capture_providers.dart` | Platform seams: research root, export root, app version, cues, wakelock, `captureDepsProvider` |

Screens: `lib/ui/screens/capture/` (home, flow, summary, `HoldButton`).

## Rules

- **The 50 Hz path only** (rule 10): rows come from `DeviceManager.batches`
  with `DeviceClock` unix time. Nothing here reads the 10 Hz snapshot,
  except link status and battery for the cues and the pre-check.
- **Deadlines, not ticks.** Every time limit is a `DateTime` compared with
  the clock on a 250 ms tick. The recorder writes only samples inside
  `[start, end)` of that deadline, so a late or starved timer can delay a
  cue but never changes what is recorded. A grace period after the
  deadline lets packets already in flight land.
- **Never lose or overwrite an attempt.** A redo or an interrupted
  recording marks the old sidecar `valid: false` with a reason; files are
  only removed by the user's twice-confirmed "Delete from phone", after an
  export.
- **File and sidecar always agree.** A marked segment's edges and an early
  stop's cut never fall at or before a row already written.
- **IRB:** codes only, coded data only (no free text), private storage
  until export.
- **One conversion code path:** kPa / g / °/s come from the app's parser
  (checked against `shared/test_vectors/`). The Python loader never
  converts again.
- `shared/capture_fixture/` is written by this code
  (`test/capture/capture_fixture_test.dart`); after an intended format
  change, regenerate it with `UPDATE_CAPTURE_FIXTURE=1` and bump
  `captureSchema` and `tools/capture/load_capture.py` `SCHEMA`.
