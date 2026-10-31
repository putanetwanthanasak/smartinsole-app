# mobile/CLAUDE.md

The SmartInsole Android app (Flutter). Read the repo-root `CLAUDE.md` first,
then `docs/FLUTTER-PLAN.md`, `docs/SESSIONS.md` (section 0 is the per-session
workflow) and `docs/design/DESIGN-SPEC.md`. Wire format and thresholds:
`docs/DATA-CONTRACT.md` and `docs/BLE-INTERFACE.md` win over everything else.
Start each session with `/session <ID> [notes]` (`.claude/skills/session/SKILL.md`).

## Ground rules

- **Do not touch the web app** (`index.html`, `src/`, `css/`, `public/`, web
  build config) unless the user asks because of a bug that affects data
  capture.
- **English only** for code, comments, commits, reports and docs. Thai appears
  only in quoted UI strings.
- App id `th.ac.kmutt.smartinsole`; Dart package `smartinsole`
  (`import 'package:smartinsole/...'`).

## The 16 rules that must never be broken

From `docs/FLUTTER-PLAN.md` section 6:

1. Sample i time = `t0 + i × 20 ms`
2. Staleness is derived from timestamps at read time, never latched by a timer
3. `lastSampleAt` = time the phone received the data
4. Two-foot metrics (ΔT, PAI) are "no data" if either foot is missing
5. "No data" must always look different from "Safe" (never green)
6. ΔT must exceed the threshold on 2 consecutive readings
7. 200 kPa peak alerts only while walking
8. Wrong foot side → reject the connection
9. Drop a stale packet left over from a previous connection
10. 50 Hz processing path is separate from the 10 Hz display path
11. Gait result is not a risk level
12. Thresholds are read from `thresholds.json`, never hardcoded
13. Every alert carries plain-Thai advice
14. **The app never says a foot is "normal" from a photo.** Only the user's
    answers count, and "not sure" counts as abnormal.
15. **Foot photos stay on the device.** Never send them anywhere unless the
    user explicitly does so.
16. **Respect the system "reduce motion" setting** — disable animations when
    it is on.

## Commands (run in `mobile/`)

| Command | Use |
|---|---|
| `flutter analyze` | Must report no issues |
| `flutter test` | Unit, widget and golden tests |
| `flutter test --update-goldens test/goldens` | Regenerate goldens after an intended UI change; review the PNG diff before committing |
| `flutter run -d <emulator-id> -t test_driver/main_mcp.dart --print-dtd` | Run on the emulator with the Flutter Driver extension, for Dart MCP UI checks |
| … add `--dart-define=BLE_FAKE=true` | Same, with the scripted fake BLE (two streaming insoles plus one with MTU 23) instead of the real plugin |
| … add `--dart-define=MOCK=<preset>` | Same, with `MockDataSource` for both feet (debug builds only): `safe`, `safeOrangeDot`, `watch`, `rest`, `noData`, `oneFootMissing`, `lowBattery`, and for the Gait tab `standing` (still IMU, both feet loaded) and `toeWalk` (no heel load); Settings → "Mock preset (debug)" switches live, "Seed sample alerts (debug)" stores the design boards' sample alerts, and "Seed sample day (debug)" stores today's temperature readings from 08:00 shaped by the preset (one period above ΔT, one connection gap; `lib/storage/sample_day.dart`). Both write only to the in-memory database |
| … add `--dart-define=GAIT_MODEL=dummy` | Debug/profile only: load the untrained dummy Model A from `assets/models_dummy/` (shapes, channel order, timing; Researcher › Diagnostics › "Gait model" shows the check). `GAIT_MODEL=demo-toe` instead fakes a model answering toe walking at 78 % (the FeetDGaitToe board). Release builds ignore the define |
| `uv run tools/model/make_dummy_model.py` (repo root) | Regenerate the dummy model, its `normalization.json` and `check.json` (TensorFlow via uv's cache, not the repo) |
| `flutter run -d <device-id>` | Plain debug run (e.g. the Note 10) |
| `flutter build apk --release && tool/check_release_resources.sh` | Release APK for the phone. The check must pass before the APK goes on the Note 10: it fails if the APK lacks a resource the app looks up by name at runtime (see Release resources below) |
| `dart format lib test test_driver` | Formatting |
| `dart run build_runner build` | Regenerate drift code (`lib/storage/database.g.dart`) after a table change |
| `dart run drift_dev make-migrations` | After bumping `schemaVersion`: dump the schema, write migration steps and tests |
| `node shared/test_vectors/generate.mjs [--check]` (repo root, after `npm ci`) | Regenerate / check the BLE test vectors from the web app's TS parser |

## Layout

```
lib/
  main.dart            runSmartInsole(): ProviderScope → SmartInsoleApp
  ble/                 wire format: parser (N FSR channels), ParseResult /
                       RejectReason, calibration, ADC → kPa (S2A);
                       per-foot BleDataSource, BleHub, BleCentral (S3A);
                       contract v1.6 (S8D): temperature v2 (8 sites), an
                       insole with N ≠ 8 refused
  device/              DeviceManager (S4): DeviceClock (unix time per
                       sample), 50 Hz FootBatch stream, 10 Hz
                       DisplaySnapshot, read-time staleness, ΔT,
                       model channels + pairFeet, temperature events,
                       mock presets, timing check
  capture/             research capture (S4C): protocol (doc 03), trial
                       recorder on the 50 Hz path, session state machine,
                       cues, export staging with alerts.csv (see its
                       README.md and docs/STUDY-CAPTURE.md)
  config/              thresholds.json loader (thresholdsProvider) and the
                       foot layout (foot_layout.dart mirrors
                       shared/sensor_layout.json: 8 sites per foot, ids,
                       names, mm positions; a test keeps them identical)
  rules/               AlertEngine (S7): the 8 contract alert rules on
                       the 50 Hz path, walking gate, step detector,
                       status (FLUTTER-PLAN §7), 30-min suppression from
                       the alerts table, plain-Thai copy, gait note (see
                       its README.md); no numeric literals (a test checks)
  storage/             drift database (S6A), schema v2 (S8D): alerts,
                       temperature readings, daily summary, foot checks;
                       one repository interface each (see its README.md);
                       30-day retention; TemperatureRecorder
  gait/                Gait (S8A): rule-based classifier, Model A slot
                       (tflite_flutter in its own isolate, only in
                       tflite_classifier.dart), estimator on a 1 s stride
                       of sample time, step counter (daily_summary.steps),
                       CoP, PTI asymmetry (see its README.md); never sets
                       a level (rule 11); no numeric literals (a test
                       checks)
  settings/            Settings (S8B): AppSettings, SettingsStore over
                       shared_preferences (name, text size, sound,
                       reminder, each foot's remembered insole), text
                       scaler (factor × phone scale); see its README.md
  footcheck/           Daily foot check (S8C): FootCamera (only
                       plugin_foot_camera.dart imports `camera`), photo
                       processor (true view, 1600 px, q85, no metadata),
                       photo session, flow controller, compare source,
                       history, orphan sweep (see its README.md)
  notify/              Evening reminder (S8C): reminder plan in the
                       phone's time zone, ReminderService, the only
                       flutter_local_notifications importer (see its
                       README.md); android_resources.dart names every
                       resource looked up by name at runtime
  ui/
    app.dart           MaterialApp, named routes
    foot_check_host.dart  start-up sweeps, reminder service, resume
                       refresh, the one-time notification prompt
    routes.dart        route names; `/alert` takes the alert id,
                       `/foot-check-found` the foot check id,
                       `/foot-check/photo` a PhotoViewerArgs;
                       `appNavigatorKey`; My feet sub-tabs open through
                       `openMyFeet(context, ref, MyFeetTab.x)`
    motion.dart        ALL animation durations and curves
    clock.dart         clockProvider (override in tests) + Thai date
                       (Buddhist year `thaiDateTimeBE`, `relativeDayTh`)
    theme/             colors, typography, dimens, app_theme
    shell/             4-tab shell (IndexedStack: วันนี้ / เท้าของฉัน /
                       ตรวจเท้า / แจ้งเตือน) + bottom bar with unread badge
    screens/           one file per screen; debug_ble_screen.dart is
                       "Diagnostics", only from Researcher (S8B);
                       connection/ = Connection (S8B): view model
                       (CardKind per §9), providers, foot card, panels;
                       researcher/ + researcher_screen.dart = §10.2
                       (readiness, TARE/REBOOT sheets, device info);
                       settings_screen.dart = §10.1;
                       home/ = Home view model and draft copy;
                       my_feet/ = My feet (S6B part 2): view model
                       (MyFeetController: 2 s peaks + engine figures),
                       copy, chart model (pairing, gaps, summary),
                       Pressure and Temperature tabs; S8A added the
                       Gait tab (gait_model, gait_copy, gait_tab);
                       capture/ = Researcher › "เริ่มเก็บข้อมูลวิจัย"
                       (English, researcher-only, release builds too)
                       foot_check/ = Daily foot check (S8C): Start,
                       Capture, Compare & answer, Saved / found-today,
                       photo history and viewer, copy (all strings);
                       foot_check_screen.dart = the tab,
                       foot_check_found_screen.dart = Something found
    widgets/           shared widgets; S6B added status_tag, new_chip,
                       details_expander (DetailRow), numbered_steps,
                       disclaimer_line, back_link, detail_status_card,
                       temp_site_map; FootMap takes null levels ("not
                       recorded"), `ringChannel` and `pulse`; S6B part 2
                       added summary_banner, segmented_tabs,
                       temp_delta_chart (CustomPainter, draw-in); S8A
                       added estimate_chip, confidence_segments,
                       balance_bar, cop_foot; S8B added list_row
                       (SettingsGroup, ListRow, AppSwitch), confirm_sheet
                       (showConfirmSheet, the TARE pattern), info_box
assets/fonts/          Figtree 600/700, Noto Sans Thai 600/700 (headings);
                       Noto Sans + Noto Sans Thai Looped 400–700 (body);
                       static TTFs, OFL, never downloaded at runtime
assets/config/         thresholds.json and model_input.json, byte-identical
                       copies of the shared/ files (tests check both)
assets/models/         the Model A slot: README only until the AI team's
                       model_a.tflite + normalization.json arrive
                       (after data collection, late Nov); dropping them
                       in is the whole change
assets/models_dummy/   untrained dummy + check.json (dev only, see
                       GAIT_MODEL above)
assets/sounds/         capture cue beeps, made by tool/make_cues.py
test/                  flutter_test_config.dart loads the real fonts
  footcheck/           foot-check unit and widget tests;
                       foot_check_rig.dart (FootCheckRig, settleIo for
                       real file and database I/O)
  notify/              reminder plan tests (Asia/Bangkok);
                       android_resources_test.dart (runtime resource
                       names are kept, no literal names in lib/)
  helpers/             pumpApp, FakeFootCamera, FakeReminderNotifier
  ble/                 parser tests; test_vectors_test.dart reads
                       ../shared/test_vectors/*.json; fake_ble_central.dart
                       + ble_data_source_test.dart (fake_async)
  capture/             capture tests (fake_async rigs), widget tests, and
                       capture_fixture_test.dart (writes/checks
                       ../shared/capture_fixture/)
  gait/                gait unit tests; gait_rig.dart (steps, windows,
                       fake model runner)
  my_feet/             My feet unit and widget tests; my_feet_rig.dart
                       (pumpMyFeet: mock preset + optional sample day)
  storage/             repository, retention, recorder tests (in-memory
                       database; persistence_test.dart uses a file)
  drift/               schema migration tests (drift_schemas/ holds the
                       committed schema dumps)
test_driver/           main_mcp.dart — driver-enabled entrypoint
tool/                  make_cues.py; check_release_resources.sh (release
                       APK has every kept runtime resource)
```

## Release resources

The release build shrinks resources: anything no code references by R id
is removed. Debug builds (`flutter run`, the MCP driver build) keep
everything, so a resource looked up only by name at runtime works on the
emulator and is missing from the release APK. This happened in S8C: the
reminder icon was gone and reminder setup failed on the Note 10 with
"invalid_icon" (report 036).

- Every name passed to a plugin that looks resources up by name
  (notification icons, notification sounds, `getIdentifier`) is a constant
  in `lib/notify/android_resources.dart`, never a string literal.
- Each one is listed in `android/app/src/main/res/raw/keep.xml`
  (`tools:keep`).
- `test/notify/android_resources_test.dart` checks both;
  `tool/check_release_resources.sh` checks the built release APK. S9's
  alert notifications add their icons and sounds the same way.

Research capture tools live at the repo root: `tools/capture/load_capture.py`
(loader, checks, `--selftest`) and `tools/capture/export_capture.py` (adb
pull + SHA-256 + checks). Any change to the capture file format must keep
`load_capture.py --selftest` passing.

## BLE parsing rules

- Every parser returns `ParseResult` (`Parsed` or `Rejected` with a
  `RejectReason`). Never turn a rejection into a silent drop; count/log it
  per foot.
- The Dart parser is stricter than the web app's TS parser in two places:
  out-of-range foot side / state / quality bytes are rejected (not masked),
  and a sensor packet longer than its `count` accounts for is rejected
  (`lengthMismatch`, catches a wrong FSR count).
- Any change to parsing or unit conversion must keep
  `test/ble/test_vectors_test.dart` passing. The vectors come from the TS
  code and are never hand-edited (`temperature_v2.json` and the N = 8 /
  N = 4 sensor files are constructed by `generate.mjs`, since the frozen
  TS parser has no v1.6).
- Contract v1.6 (S8D): the temperature packet is exactly 32 bytes with
  count 8 (`tempLength`, `tempCount`; the old 12-byte packet is
  rejected), and an insole whose calibration has N ≠ 8 is refused
  (`calibrationFsrCount`, "calibration rejected"). Diagnostics shows each
  foot's `format` line (`N 8 · temperature v2, 8 sites · rejects 0` on a
  correct board): the SR first-connection check reads it.

## BLE connection rules

- All BLE goes through `BleCentral` (`lib/ble/ble_central.dart`). Only
  `fbp_central.dart` imports `flutter_blue_plus`.
- Insoles are found by service UUID. The side comes only from the status
  `foot_side` byte, never from the advertised name (Android caches names).
  A wrong side is a `problem`, with no START and no auto-reconnect (rule 8).
- Every connect and reconnect runs the full sequence: MTU 247 is requested
  each time and checked against N; a link that can't fit 4 samples is a
  visible `mtuTooSmall` problem, never a silent link with no data.
- Rule 9: packets from an older connection, packets before this
  connection's START is written, and t0 / temp t_ms not moving forward
  (mod 2³²) are dropped and counted. The gate opens at the START write,
  not its ack (BACKLOG 27); `admittedBeforeAck` counts the race.
- Sample unix time comes only from `DeviceClock` (`lib/device/`): never
  "send time − last received sample" (BACKLOG 28), never a step, never
  backwards within a session.
- Screens read `displaySnapshotProvider` (10 Hz); anything per-sample
  (capture, rules, model input) reads `DeviceManager.batches` (50 Hz).
- Retry waits and the debug screen's tick are timers; connection state and
  "last packet X s ago" are not latched by them (rule 2).
- The user's Disconnect sends STOP and never reconnects; on Connection,
  "ยกเลิกการเชื่อมต่อ" also forgets the remembered insole (S8B).
- Patients connect through `FootFinder` (`lib/ble/foot_finder.dart`, one
  per foot, on top of `BleDataSource.connectTo`; the connect sequence is
  unchanged). It remembers each foot's insole and reconnects it at app
  start, and logs every automatic reconnect (BACKLOG 45).
- TARE and REBOOT go only through `InsoleCommands`, which refuses them
  while a research capture session is open (BACKLOG 21).

## Theme rules

- Colours, type, spacing and radii come only from `lib/ui/theme/`. Never write
  a hex colour or font size in a screen.
- Status is always icon + text + colour. "No data" uses `StatusColors.noData`
  / `FootDotColors.noData`, never a green (rule 5).
- Theme files hold colours only; the kPa boundaries that choose a foot-dot
  colour come from `shared/thresholds.json` (rule 12).
- Text scaling comes from `MediaQuery.textScaler`; never clamp it. Layouts
  must survive large text.
- Every icon-only button has a Thai `tooltip` (TalkBack label).

## Motion rules

- Every `Duration`/`Curve` used for animation is defined in
  `lib/ui/motion.dart`. Most animations are 200–400 ms; no fast flashing.
- Resolve durations through `Motion.duration(context, ...)` so they become
  zero under reduce motion. For `flutter_animate`, skip or zero the effect
  when `Motion.reduced(context)` is true.
- Page transitions are the `animations` package's shared-axis transition,
  wrapped so they are skipped under reduce motion (`app_theme.dart`).
- 10 Hz data updates must not restart animations or stutter.

## Testing approach

- **You check the UI, not the user.** Run the app on the Android emulator,
  use the Dart & Flutter MCP server (`dtd` connect, `flutter_driver_command`
  tap/screenshot, `widget_inspector`, `get_runtime_errors`), compare against
  DESIGN-SPEC, and put the screenshots in the session report. The MCP
  runtime tools need `flutter run` in a separate terminal (see Commands).
  Fallback screenshot: `adb exec-out screencap -p > shot.png`. On the BLE
  debug screen the 4 Hz tick keeps frames pending, so call
  `set_frame_sync enabled=false` before driver taps; items scrolled out of
  the lazy list can't be found, so scroll first (or tap with
  `adb shell input tap`).
- **Golden tests for every screen state you build.** Goldens render at the
  DESIGN-SPEC reference size 390×844 (dpr 2) with the bundled fonts, so they
  show real Thai glyphs. Goldens are rendered on the Linux dev machine; other
  OSes may differ by a few pixels.
- Use `pumpApp()` in `test/helpers/pump_app.dart`; it fixes the clock, can
  turn on reduce motion, and always replaces BLE with `FakeBleCentral` /
  `FakePermissions`, the database with `AppDatabase.memory()`, and the
  foot check's camera and reminders with `FakeFootCamera` /
  `FakeReminderNotifier` and temp photo folders (pass your own via
  `central:` / `permissions:` / `camera:` / `reminders:` / `photoDir:`, and
  any provider override, e.g. `mockPresetProvider`, via `overrides:`).
  Real file and database I/O only finishes inside `tester.runAsync`; the
  foot-check tests alternate it with frames (`settleIo`).
  Widgets that tests or the driver tap carry a `ValueKey` (`tab-today`, `tab-myFeet`, `tab-footCheck`, `tab-alerts`, `settings-button`, `foot-check-start-photos`, `foot-check-answer-only`, `capture-shutter`, `capture-skip`, `capture-switch`, `capture-timer`, `capture-cancel`, `answer-<question>-<answer>`, `compare-save`, `foot-left`, `status-card`, `researcher-row`, `back-link`, `connect-action-left`, `connect-done`, `researcher-tare`, `diagnostics-row`, `sheet-confirm`, `sheet-cancel`, …). Researcher and Connection use `pumpResearcher` / `pumpConnection` (`test/researcher/`, `test/connection/`).
- `MockDataSource` presets (from S4) drive every UI state on the emulator
  (`--dart-define=MOCK=<preset>`). Their test checks each preset against
  `shared/thresholds.json`; when a threshold changes, fix the preset, not
  the test.
- **The Note 10 is used only at its checkpoints:** after S3A, S4, S4C, S5, SR,
  S8C and S9 (real Bluetooth / real camera; `docs/SESSIONS.md`). Write a checklist for the user and wait for
  their results; never mark those checks passed yourself.
