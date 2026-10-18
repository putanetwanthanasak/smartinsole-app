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
| `flutter run -d <device-id>` | Plain debug run (e.g. the Note 10) |
| `dart format lib test test_driver` | Formatting |

## Layout

```
lib/
  main.dart            ProviderScope → SmartInsoleApp
  ble/ device/ rules/ gait/ footcheck/ storage/ notify/ config/
                       empty until their session (see each README.md)
  ui/
    app.dart           MaterialApp, named routes
    routes.dart        route names
    motion.dart        ALL animation durations and curves
    clock.dart         clockProvider (override in tests) + Thai date
    theme/             colors, typography, dimens, app_theme
    shell/             tab shell (IndexedStack) + bottom bar
    screens/           one file per screen
    widgets/           shared widgets
assets/fonts/          IBM Plex Sans Thai + Looped (OFL, bundled)
test/                  flutter_test_config.dart loads the real fonts
test_driver/           main_mcp.dart — driver-enabled entrypoint
```

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
  Fallback screenshot: `adb exec-out screencap -p > shot.png`.
- **Golden tests for every screen state you build.** Goldens render at the
  DESIGN-SPEC reference size 390×844 (dpr 2) with the bundled fonts, so they
  show real Thai glyphs. Goldens are rendered on the Linux dev machine; other
  OSes may differ by a few pixels.
- Use `pumpApp()` in `test/helpers/pump_app.dart`; it fixes the clock and can
  turn on reduce motion. Widgets that tests or the driver tap carry a
  `ValueKey` (`tab-home`, `settings-button`, `foot-left`, …).
- `MockDataSource` presets (from S4) drive every UI state on the emulator.
- **The Note 10 is used only at 4 checkpoints:** after S3A, S4, S8C and S9
  (real Bluetooth / real camera). Write a checklist for the user and wait for
  their results; never mark those checks passed yourself.
