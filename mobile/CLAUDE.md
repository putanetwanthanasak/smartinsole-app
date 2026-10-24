# mobile/CLAUDE.md

The SmartInsole Android app (Flutter). Read the repo-root `CLAUDE.md` first,
then `docs/FLUTTER-PLAN.md`, `docs/SESSIONS.md` (section 0 is the per-session
workflow) and `docs/design/DESIGN-SPEC.md`. Wire format and thresholds:
`docs/DATA-CONTRACT.md` and `docs/BLE-INTERFACE.md` win over everything else.

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
| … add `--dart-define=MOCK=<preset>` | Same, with `MockDataSource` for both feet (debug builds only): `safe`, `safeOrangeDot`, `watch`, `rest`, `noData`, `oneFootMissing`, `lowBattery`; Settings → "Mock preset (debug)" switches live, and "Seed sample alerts (debug)" stores the design boards' sample alerts (in-memory database) |
| `flutter run -d <device-id>` | Plain debug run (e.g. the Note 10) |
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
                       per-foot BleDataSource, BleHub, BleCentral (S3A)
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
                       placeholder foot layout (S5)
  rules/               AlertEngine (S7): the 8 contract alert rules on
                       the 50 Hz path, walking gate, step detector,
                       status (FLUTTER-PLAN §7), 30-min suppression from
                       the alerts table, plain-Thai copy, gait note (see
                       its README.md); no numeric literals (a test checks)
  storage/             drift database (S6A), schema v1: alerts,
                       temperature readings, daily summary, foot checks;
                       one repository interface each (see its README.md);
                       30-day retention; TemperatureRecorder
  gait/ footcheck/ notify/
                       empty until their session (see each README.md)
  ui/
    app.dart           MaterialApp, named routes
    routes.dart        route names; `/alert` takes the alert id,
                       `/foot-check-found` the foot check id (placeholder
                       until S8C); My feet sub-tabs open through
                       `openMyFeet(context, ref, MyFeetTab.x)`
    motion.dart        ALL animation durations and curves
    clock.dart         clockProvider (override in tests) + Thai date
                       (Buddhist year `thaiDateTimeBE`, `relativeDayTh`)
    theme/             colors, typography, dimens, app_theme
    shell/             4-tab shell (IndexedStack: วันนี้ / เท้าของฉัน /
                       ตรวจเท้า / แจ้งเตือน) + bottom bar with unread badge
    screens/           one file per screen; debug_ble_screen.dart is
                       temporary (Settings → "BLE debug", hidden in S8B);
                       home/ = Home view model and draft copy;
                       capture/ = Settings → hold "ส่วนผู้วิจัย" 2 s
                       (English, researcher-only, release builds too)
    widgets/           shared widgets; S6B added status_tag, new_chip,
                       details_expander (DetailRow), numbered_steps,
                       disclaimer_line, back_link, detail_status_card,
                       temp_site_map; FootMap takes null levels ("not
                       recorded"), `ringChannel` and `pulse`
assets/fonts/          Figtree 600/700, Noto Sans Thai 600/700 (headings);
                       Noto Sans + Noto Sans Thai Looped 400–700 (body);
                       static TTFs, OFL, never downloaded at runtime
assets/config/         thresholds.json, byte-identical copy of
                       shared/thresholds.json (a test checks it)
assets/sounds/         capture cue beeps, made by tool/make_cues.py
test/                  flutter_test_config.dart loads the real fonts
  ble/                 parser tests; test_vectors_test.dart reads
                       ../shared/test_vectors/*.json; fake_ble_central.dart
                       + ble_data_source_test.dart (fake_async)
  capture/             capture tests (fake_async rigs), widget tests, and
                       capture_fixture_test.dart (writes/checks
                       ../shared/capture_fixture/)
  storage/             repository, retention, recorder tests (in-memory
                       database; persistence_test.dart uses a file)
  drift/               schema migration tests (drift_schemas/ holds the
                       committed schema dumps)
test_driver/           main_mcp.dart — driver-enabled entrypoint
```

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
  code and are never hand-edited.

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
- The user's Disconnect sends STOP and never reconnects.

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
  `FakePermissions` and the database with `AppDatabase.memory()` (pass
  your own via `central:` / `permissions:`, and any provider override, e.g. `mockPresetProvider`, via `overrides:`).
  Widgets that tests or the driver tap carry a `ValueKey` (`tab-today`, `tab-myFeet`, `tab-footCheck`, `tab-alerts`, `settings-button`, `foot-left`, `status-card`, `researcher-row`, …).
- `MockDataSource` presets (from S4) drive every UI state on the emulator
  (`--dart-define=MOCK=<preset>`). Their test checks each preset against
  `shared/thresholds.json`; when a threshold changes, fix the preset, not
  the test.
- **The Note 10 is used only at its checkpoints:** after S3A, S4, S4C, S5, SR,
  S8C and S9 (real Bluetooth / real camera; `docs/SESSIONS.md`). Write a checklist for the user and wait for
  their results; never mark those checks passed yourself.
