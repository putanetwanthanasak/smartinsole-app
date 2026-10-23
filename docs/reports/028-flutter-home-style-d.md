# 028 — S5: Home in style D (Flutter)

Branch `work/s5-home-style-d` · 2026-10-23 · Session S5 (`docs/SESSIONS.md` §3)
Spec: `docs/design/DESIGN-SPEC.md` v2 §1–§6, §12, §13.

**Status: waiting for the Note 10 checkpoint.** Automated checks and the
emulator pass. Nobody has run the phone checklist at the end of this report
yet. S5 is not done until the user runs it and reports back.

> **Level 3 is not checked until S7.** In S5, Home's "ควรระวัง" (Be
> careful) state only appears from the `watch` mock preset. No rule
> evaluates `PRESSURE_PEAK`, `PRESSURE_PTI` or `LOAD_CONCENTRATION` yet.
> **With real insoles, Home can show "ตอนนี้เท้าปลอดภัย" while a level-3
> condition is true.** "ควรพักเท้าตอนนี้" (Rest, `TEMP_DELTA`) is computed
> from real data. Decision D1; `mobile/lib/rules/interim_status.dart`.

## Summary

- **Automated:** `flutter analyze` is clean. All **373 tests pass**,
  including 36 goldens (14 of them new Home goldens). `dart format` is clean.
- **Emulator** (`emulator-5554`, `MOCK=…`): Safe, Rest and one-foot-missing
  were shown live, plus 200 % system text. There were no runtime errors.
  Screenshots are below.
- **Release APK:** 56,401,033 bytes, against 55,010,586 on `main`, so
  **+1,390,447 bytes (+1.33 MiB)**. See "Fonts".
- **Untouched:** the web app, `firmware/`, `mobile/lib/capture/` and
  `tools/capture/` (`git diff main --stat` is empty for all of them). The
  capture screens only had theme tokens renamed (checked by diff). All
  capture tests pass.

## What changed

| Area | Files |
|---|---|
| Spec | `docs/design/DESIGN-SPEC.md` replaced by v2 (style D) |
| "9 alert rules" → 8 | `docs/SESSIONS.md`, `docs/FLUTTER-PLAN.md`, `mobile/lib/rules/README.md` |
| Fonts | `mobile/assets/fonts/` (see "Fonts"); IBM Plex removed |
| Thresholds | `shared/thresholds.json` + `battery.lowPct`; bundled copy `mobile/assets/config/thresholds.json`; `lib/config/thresholds.dart` loads it before `runApp` |
| Theme | `lib/ui/theme/` (style D tokens; no shadows), `lib/ui/motion.dart` (exact cubic-béziers) |
| Navigation | `lib/ui/shell/` — 4 tabs วันนี้ / เท้าของฉัน / ตรวจเท้า / แจ้งเตือน, unread badge |
| Home | `lib/ui/screens/home_screen.dart`, `home/home_model.dart` (pure `homeViewOf`), `home/home_copy.dart` (draft copy) |
| Shared widgets | `lib/ui/widgets/` — `PageTitle`, `AppCard`, buttons, `FootMap` + legend, `StatusCard`, `FootCheckCard`, `AnimatedNumber`, `StaggeredEntrance`, `PlaceholderBody` |
| Rules (S5 part) | `lib/rules/` — `alert_code.dart` (8 codes), `pressure_level.dart`, `asymmetry.dart`, `patient_status.dart`, `interim_status.dart` |
| Foot geometry | `lib/config/foot_layout.dart`: placeholder outline, positions, and channel → zone, all in one file |
| 50 Hz peaks | `lib/device/rolling_peaks.dart` (2 s window, 100 ms buckets) |
| Placeholders | `my_feet_screen.dart`, `foot_check_screen.dart`, `alerts_screen.dart` (title + "กำลังพัฒนา"); the old gait/temperature screens were deleted |
| Researcher entry | Settings → "สำหรับผู้วิจัย" → hold **ส่วนผู้วิจัย** for 2 s → Research capture (D3) |
| Docs | `mobile/CLAUDE.md`, `docs/STUDY-CAPTURE.md` (step 4, resume), `docs/DATA-CONTRACT.md` §8.3, `docs/BACKLOG.md` 30 resolved, 36 note, new 37–39 |

## Decisions applied (from plan approval)

- **D1** Interim status: No data / Safe / Rest come from real data. Be
  careful comes only from a mock preset. See the box at the top.
- **D2** Debug build for preset switching on the Note 10, plus a jank check
  in **profile mode with the performance overlay on the Note 10**
  (checklist item 6).
- **D3** Settings row with a 2 s long press. It opens the S4C flow directly
  and is a `LongPressGestureRecognizer` with a 2 s duration. TalkBack gets
  the long-press action through `Semantics(onLongPress)`. The old
  "Research capture" button was removed.
- **D5** `battery.lowPct: 15` was added to `shared/thresholds.json`. The web
  app reads its own `public/thresholds.json` (`src/ts/data/thresholds.ts`),
  which was not changed. The simulator reads keys by name, so the extra key
  is safe. Contract versioning: §8.3 now notes "`battery` added 2026-10-23
  (S5), a local addendum to v1.5", and the history table has a "1.5
  addendum" row. The contract owner should fold it into the next version.
- **D6** One asymmetry definition: `PeakAsymmetry` in
  `lib/rules/asymmetry.dart` holds the balance numbers ("71 : 29") and the
  orange note. PAI = |L − R| / ((L + R)/2) × 100 (contract §8.2). The
  contract does not say what a foot's "peak" is taken over, so S5 uses the
  highest channel over the last 2 s. This is marked **INTERIM** in code and
  in **BACKLOG 37** for S7 (per-step peaks, "≥ 20 steps" persistence). S7
  must reuse this function.
- **D7** Home shows No data when either foot is missing. **BACKLOG 38**
  (for S7): the connected foot's level 3+ must win over No data, and the
  detail text must name the missing foot.
- The foot-check card is always shown until S8C. The greeting is "สวัสดี".

## Safety rules, and how they are checked

| Rule | Check |
|---|---|
| 4: two-foot values need both feet | `homeViewOf` returns null ΔT/balance unless both are usable. Cards show "—" + "ต้องเชื่อมต่อทั้งสองข้าง" (`test/home/home_test.dart`, one-foot-missing goldens) |
| 5: No data never green | Status card colour test for `noData`, `oneFootMissing` and "no insole at all" (real BLE stack, nothing connected) |
| 6: ΔT on 2 consecutive readings | `test/rules/interim_status_test.dart`: one pair is not enough, a pair at or below the limit resets, one foot reading twice is not a pair |
| 12: thresholds from file | dot levels, ΔT, battery and asymmetry all read `Thresholds`. A test fails if the bundled copy differs from `shared/` by one byte |
| 16: reduce motion | Home entrance and foot-map pulse/tween are off under `disableAnimations` (`home_test.dart`, `test/widgets/foot_map_test.dart`) |
| No kPa / ΔT / PAI on Home | every Text under Home is checked in all 7 presets |

**Bug found and fixed while testing:** ΔT at exactly the limit was compared
as a float, so 33.20 − 31.00 = 2.2000000000000028 counted as "above 2.2".
`deltaAbove()` now compares at the sensor's 0.01 °C resolution, and both
the status and the temperature card's note use it.

**Second fix:** the foot-map dots restarted their 300 ms tween on every
10 Hz rebuild, because each rebuild made a new list. They now compare by
value, and a test checks that a same-level update starts no animation.

## Accessibility (§13)

- The status card is a **polite live region** (tested via semantics flags).
  Its title, detail and advice are read together.
- The Alerts tab label is "แจ้งเตือน", or "แจ้งเตือน มี {n} รายการที่ยังไม่ได้อ่าน"
  when there are unread alerts. The badge number is not read separately
  (tested for 0 and 3). `unreadAlertCountProvider` is fixed at 0 until S6B.
- Each foot map has a label, e.g. "เท้าซ้าย ปลายเท้ารับน้ำหนักปานกลาง".
- Icon-only buttons have Thai tooltips (settings: "ตั้งค่า").
- **200 % text:** no overflow in any of the 7 presets (test plus goldens).
  The two small cards stack above text scale 1.3, and the tab labels wrap.
  Checked on the emulator at system font scale 2.0.

## Motion (§12)

All durations and curves live in `lib/ui/motion.dart`, as exact
`Cubic(...)` values from the boards, not `Curves.easeInCubic` and similar:
exit 200 ms `Cubic(0.32, 0, 0.67, 0)`, enter 300 ms `Cubic(0.33, 1, 0.68,
1)`, value 400 ms, pop 300 ms `Cubic(0.34, 1.3, 0.64, 1)`, 40 ms stagger,
1600 ms pulse. `test/motion_test.dart` checks each value. Everything
resolves to zero or still under reduce motion. A high dot then shows a
still ring instead of the pulse.

The 10 Hz path does not rebuild Home unless something visible changes:
`HomeView` is rounded to what is drawn and compared by value. A test
streams for 5 s and counts at most 2 rebuilds. Real frame timing is
checklist item 6.

## Fonts

Static TTFs, unmodified, OFL (licences in `mobile/assets/fonts/OFL-*.txt`).
Only the listed weights are bundled, and nothing is downloaded at runtime.
Latin figures are tabular (`tnum`).

| Family | Use | Weights | Bytes |
|---|---|---|---|
| Figtree | headings, Latin | 600, 700 | 115,256 |
| Noto Sans Thai | headings, Thai | 600, 700 | 76,344 |
| Noto Sans | body, Latin | 400, 500, 600, 700 | 2,498,084 |
| Noto Sans Thai Looped | body, Thai | 400, 500, 600, 700 | 219,840 |
| **Total** | | | **2,909,524** (IBM Plex removed: 852,692) |

In the release APK the net change is **+1,390,447 bytes** (assets are
compressed). Most of the size is Noto Sans, at about 620 KB per weight,
because it covers Greek, Cyrillic and more. If size matters, subsetting
Noto Sans to Latin would save about 2 MB raw. I did not subset the fonts,
because the brief said to bundle them unmodified. Figtree was added as the
last body fallback because Noto Sans lacks "→" and "≥", which the capture
pre-check hint uses.

## Goldens

All goldens use the bundled fonts (real Thai glyphs). Home goldens are
390 px wide and tall enough to show the whole scrolling page.
`test/goldens/home_golden_test.dart`, in `test/goldens/screens/`:

| Preset | 100 % text | 200 % text |
|---|---|---|
| safe | `home_safe_100.png` | `home_safe_200.png` |
| safeOrangeDot | `home_safeOrangeDot_100.png` | `home_safeOrangeDot_200.png` |
| watch | `home_watch_100.png` | `home_watch_200.png` |
| rest | `home_rest_100.png` | `home_rest_200.png` |
| noData | `home_noData_100.png` | `home_noData_200.png` |
| oneFootMissing | `home_oneFootMissing_100.png` | `home_oneFootMissing_200.png` |
| lowBattery | `home_lowBattery_100.png` | `home_lowBattery_200.png` |

All other goldens were regenerated for the new theme (`my_feet`,
`foot_check`, `alerts`, `settings`, `settings_mock`, `connection`, 5 ×
`ble_debug_*`, 11 × `capture_*`), and I reviewed them. `home.png`,
`gait.png` and `temperature.png` were removed.

Safe (100 %) · Be careful (100 %) · Rest (200 % text):

<img src="028-flutter-home-style-d/golden_home_safe_100.png" width="240"> <img src="028-flutter-home-style-d/golden_home_watch_100.png" width="240"> <img src="028-flutter-home-style-d/golden_home_rest_200.png" width="160">

## Emulator

Taken from `flutter run -t test_driver/main_mcp.dart --dart-define=MOCK=…`.
Presets were switched live from Settings → Mock preset (debug). These are
adb screenshots, because the driver's screenshot returned a stale frame
after navigation.

| Safe | Rest (after 2 reading pairs) | One foot missing | …scrolled | …at 200 % system text |
|---|---|---|---|---|
| <img src="028-flutter-home-style-d/emu_home_safe.png" width="150"> | <img src="028-flutter-home-style-d/emu_home_rest.png" width="150"> | <img src="028-flutter-home-style-d/emu_home_onefoot_top.png" width="150"> | <img src="028-flutter-home-style-d/emu_home_onefoot_scrolled.png" width="150"> | <img src="028-flutter-home-style-d/emu_home_onefoot_text200.png" width="150"> |

## Known gaps (deliberate)

- Level 3 is not evaluated (see the top box; S7).
- The foot geometry is a placeholder until `shared/sensor_layout.json`
  exists (DESIGN-SPEC decision 3). It is held in one file.
- Each dot shows that zone's peak over the last 2 s, so it does not flicker
  at walking pace (BACKLOG 39).
- Three strings the spec does not give were written in its style (BACKLOG
  39). All Home health copy is still **draft** (Appendix A).
- "เชื่อมต่อแผ่นรองเท้า" opens the Connection placeholder (S8B). The only
  way to connect is still BLE debug (BACKLOG 36).
- The unread count is always 0 until Alerts exists (S6B).
- `tools/capture/export_capture.py`'s help text still says "Settings ->
  Research capture". I left it, to keep `tools/capture/` unchanged. The
  real path is in `docs/STUDY-CAPTURE.md`.

## Note 10 checkpoint — for the user (not run yet)

Phone `RF8M83P4STZ`; both ESP32 simulator boards. I will install the
builds once the phone and boards are plugged in.

1. **Mock presets (debug build, `MOCK=safe`):** Settings → Mock preset →
   go through all 7 presets. Each matches the goldens above. `rest` needs
   about 1 minute before it shows "ควรพักเท้าตอนนี้".
2. **Tab bar:** all 4 tabs switch. The icon pops on the active tab. The
   placeholder tabs show their title and "กำลังพัฒนา". The foot-check card
   and "ดูเพิ่ม" switch to their tabs.
3. **Thai fonts:** headings are Noto Sans Thai, and body text is the looped
   Thai face. No tofu boxes, and no clipped tone marks (e.g. "น้ำ", "ปู่").
4. **Motion:** with the system "Remove animations" off, Home fades and
   rises in on launch, and dots tween when a preset changes. With it on,
   everything appears at once and nothing pulses.
5. **TalkBack:** focus the status card; it reads title + detail (+ advice).
   Switch preset while TalkBack is on; the change is announced once
   (polite live region). The Alerts tab reads "แจ้งเตือน".
6. **Jank (profile build):** `flutter run --profile`, performance overlay
   on, Home with both simulators streaming for 30 s. Both bars stay under
   16 ms; no red frames during the 10 Hz updates.
7. **Two ESP32 simulators (release build):** connect both through BLE
   debug. Home shows both chips connected with battery, the foot map moves,
   and the temperature and balance cards show values. Unplug one board:
   within a few seconds Home shows No data, and that foot's chip, map and
   the two small cards show "—".
8. **Research capture is still reachable (release build):** Settings → hold
   "ส่วนผู้วิจัย" 2 s → Research capture opens. A short tap does nothing.
   Run a **30 s trial** with subject code **TEST-003**. Summary → "Export
   for USB (adb)". On the laptop, run
   `python3 tools/capture/export_capture.py --dest <folder> --serial RF8M83P4STZ --session <id>`.
   Its built-in checks must PASS. Then run
   `python3 tools/capture/load_capture.py check <folder>/<id>`, which must
   also PASS.

Results go in a "Note 10 checkpoint results" section of this report.
