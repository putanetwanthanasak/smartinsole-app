# 035 — S8B: Connection, Settings and Researcher

Branch `work/flutter-connect-settings` · 2026-10-25 · DESIGN-SPEC §9, §10.1,
§10.2, with the §14 proposed defaults.

## Summary

- **Connection (§9):** the patient connects each foot from this screen alone.
  Every card state is built: not connected, searching (ripple), connecting
  (step bar), connected (pop and check draw), wrong side (rule 8), not found
  after 20 s, and connected but no data. Also built: the Bluetooth-off and
  permission panels, and "เสร็จแล้ว กลับหน้าวันนี้" (back to the Today tab).
  Each foot's insole is remembered and reconnected at app start.
  "ยกเลิกการเชื่อมต่อ" forgets it.
- **Settings (§10.1):** every group is built. Settings are stored in
  SharedPreferences, apart from the database, so they survive a restart
  and the test-data clear. Name, text size, sound, reminder and time are
  stored. Text size is 22/18 or 26/18 times the phone's scale, never
  clamped. Delete photos empties `foot_photos/` and nulls the photo
  columns. Version is the real app version + " · รุ่นทดสอบงานวิจัย". The
  BLE debug button is gone.
- **Researcher (§10.2):** opened by holding the row 2 s. It has:
  - readiness checks (both connected; battery ≥ 80 %; ≥ 49 samples/s per
    foot over 10 s). A failed check disables "เริ่มเก็บข้อมูลวิจัย".
  - "เริ่มเก็บข้อมูลวิจัย" opens the unchanged S4C capture flow. The
    export row always opens it.
  - TARE and reboot behind TARE-pattern sheets, disabled and refused while
    a capture session is open (BACKLOG 21).
  - device info.
  - **Diagnostics**: the old debug screen, renamed, in release builds too,
    with a new Reconnects card (BACKLOG 45).
- `flutter analyze` is clean and `flutter test` passes 786 tests. The emulator checks pass. The spec review found 1 major and
  3 minor issues; all are fixed or explained below.
- **Note 10 checkpoint: waiting on user** (checklist below).

## What changed

Seven commits (`git log main..HEAD`):

| Area | Files |
|---|---|
| Settings store | `mobile/lib/settings/` (new): `AppSettings`, `TextSizeOption`, `SettingsStore` (`PrefsSettingsStore`, `MemorySettingsStore`), `settingsProvider`, `AppTextScaler`; `pubspec.yaml` adds `shared_preferences`; `main.dart` opens the store before `runApp`; `app.dart` applies the scaler; Home greeting "สวัสดี คุณ{name}" |
| Finder | `lib/ble/foot_connector.dart`, `lib/ble/foot_finder.dart` (new): per-foot find on top of `BleDataSource.connectTo` (connect sequence unchanged), wrong side, not found, remember / forget, `autoConnect()`, `ReconnectStats`; `lib/device/mock_connector.dart`; `lib/ui/auto_connect_host.dart` |
| Connection | `lib/ui/screens/connection/` (new: model, providers, widgets), `connection_screen.dart` rewritten; `widgets/info_box.dart`; `motion.dart` gains the ripple, check-draw and done-button timings |
| Settings screen | `settings_screen.dart` rewritten; `widgets/list_row.dart` (`SettingsGroup`, `ListRow`, `AppSwitch`), `widgets/confirm_sheet.dart`; `storage/foot_photos.dart`; `typography.dart` adds `textSizePreview` |
| Researcher | `researcher_screen.dart`, `screens/researcher/` (model, providers, sheets); `routes.dart` `/researcher` |
| Commands | `ble/insole_control.dart` (new interface), `ble/control_commands.dart` (`tareCommand`, `rebootCommand`), `BleDataSource` and `MockDataSource` implement it; `device/insole_commands.dart` (guarded TARE / REBOOT); `device/sample_rate_meter.dart` |
| Capture | `capture_protocol.dart`: `CaptureTimings.minSampleRateHz = 49.0`, `sampleRateWindow = 10 s` (readiness only); `capture_home_screen.dart`: the pre-check hint now points to Settings → เชื่อมต่อแผ่นรองเท้า. Nothing else in capture changed. |
| Diagnostics | `debug_ble_screen.dart`: title "Diagnostics", new Reconnects card |
| Driver | `test_driver/main_mcp.dart`: `BLE_SCENARIO` = `both`, `rightOnly`, `none`, `mtu23`, `oneBoard`, `btOff` |
| Docs | `docs/STUDY-CAPTURE.md` (connect step, Researcher, Diagnostics path), `docs/SESSIONS.md` (SR and S9 steps), DESIGN-SPEC §10.1 and §14, `mobile/CLAUDE.md`, BACKLOG 21 and 36 resolved, 45 note, 52–54 new |

## Decisions and how they were applied

| # | Decision | Applied |
|---|---|---|
| 1A | `shared_preferences` | `PrefsSettingsStore`; keys in `SettingsKeys` (`settings.*`, `insole.bound.left/right`). `clearTestData` touches only the database and photos; a test checks that settings survive it. |
| 2A | Remember each foot's insole, auto-reconnect at start; "ยกเลิกการเชื่อมต่อ" forgets | `FootFinder.remember` on the first stream; `autoConnectProvider` at start (BLE only); disconnect clears `insole.bound.<side>`. |
| 3A | 20 s window; wrong side once seen and no other candidate within 3 s | `FootFinder.window`, `wrongSideGrace`. |
| 4A | Permission panel, draft copy | "แอปยังไม่ได้รับอนุญาตให้ใช้บลูทูธ" / "อนุญาตให้แอปค้นหาอุปกรณ์ใกล้เคียง แล้วค่อยเชื่อมต่อแผ่นรองเท้า" / "อนุญาตให้ใช้บลูทูธ" or "เปิดการตั้งค่า"; cards "รออนุญาตให้ใช้บลูทูธ". |
| 5A | Stale / MTU too small / calibration rejected → connected, no data; retry wait → searching; "เชื่อมต่อใหม่" = disconnect + find | `cardStateOf` in `connection_model.dart`. |
| 6A | ≥ 49 samples/s per foot over 10 s, constant next to `minBatteryPct`; export row always opens capture | `CaptureTimings.minSampleRateHz`; `SampleRateMeter` reads the 50 Hz path at read time; it shows "(กำลังวัด)" for the first 10 s. |
| 7A | Debug screen → "Diagnostics", only from Researcher | Settings has no link; `Routes.bleDebug` is pushed only by Researcher's Diagnostics row. |
| 8A | Sound and reminder stored only; delete photos; real version | As listed. The reminder notification itself is S8C/S9. |

Not designed, built from §5 components with draft copy (listed in §14):
the name editor sheet, the reminder time picker (platform, 24 h), TARE in
progress / done / failed, the reboot sheet, the delete-photos sheet, and
the "ทำไม่ได้ตอนนี้" sheet for a command refused after the sheet opened.

Found and fixed while testing:
- **Researcher row hit testing.** Holding the empty part of the
  "ส่วนผู้วิจัย" row did nothing, because its gesture detector deferred to
  the text. It is now opaque. The capture test caught it, and the emulator
  confirms a hold on the blank right side opens Researcher.
- **TalkBack on text-size options.** `excludeSemantics` had hidden the tap
  action of the text-size options. They now carry `onTap`, and a test
  checks it.
- **Switch rows at large text.** Above text scale 1.3, a switch moves under
  its row title. Before, at 1.3 × ใหญ่มาก, the title wrapped one word per
  line.

## Independent review (spec vs implementation)

`spec-reviewer` on `git diff main...HEAD` (§5, §9, §10, §12.2, §12.3, §13,
§14; FLUTTER-PLAN §6 rules 2, 5, 8, 12, 16). Table as returned, plus a
resolution column:

| # | Severity | File:line | Spec | Mismatch | Resolution |
|---|---|---|---|---|---|
| 1 | major | `mobile/lib/ui/widgets/confirm_sheet.dart:13` | DESIGN-SPEC §12.3; FLUTTER-PLAN §6 rule 16; mobile/CLAUDE.md motion rules | `showConfirmSheet` calls `showModalBottomSheet` without a `sheetAnimationStyle`; Flutter's bottom sheet never checks `disableAnimations`, so the TARE, reboot, delete-photos and name sheets still slide under reduce motion. | **Fixed** (94c4db9): `sheetAnimationStyle: AnimationStyle.noAnimation` when `Motion.reduced`. Test: the name sheet is at its final position one frame after the tap under reduce motion, and moves without it. |
| 2 | minor | `mobile/lib/ui/screens/settings_screen.dart:286` | mobile/CLAUDE.md theme rules; §10.1 | The text-size preview sets `fontSize: 18` / `height: 1.3` in the screen. | **Fixed:** `AppText.textSizePreview` in `typography.dart`. |
| 3 | minor | `mobile/lib/ui/screens/settings_screen.dart:417` | §10.1 "เกี่ยวกับแอป" | The spec shows "0.9.0 · …"; the screen shows "1.0.0+1 · …" (`version+buildNumber`). | **Kept, by user decision 8A** (real app version via `appVersionProvider`, pubspec `1.0.0+1`). The board's "0.9.0" is a sample. If the build suffix should go, it's a one-line change; see Decisions needed. |
| 4 | minor | `mobile/lib/ui/screens/connection_screen.dart:142` | §3 "Gap between sections 24" | Connection used 16 between sections; Settings and Researcher use 24. | **Fixed:** `Dimens.sectionGap`. The 16 had no recorded reason, and §3 is explicit. Connection goldens regenerated and reviewed. |

The reviewer also listed spec gaps:

- **Disabled TARE/REBOOT rows had no disabled state for TalkBack.** Fixed:
  `ListRow(enabled: false)` adds `Semantics(enabled: false)`, and a test
  checks it.
- **The running TARE sheet could be closed.** Now back and the scrim don't
  close it (`PopScope`). A drag still can, which is harmless: the TARE goes
  on.
- **"ตรวจสอบระบบ" and "เชื่อมต่อแผ่นรองเท้าก่อน" were not listed as
  draft.** Both are now in §14's S8B draft copy list.
- **The permission panel hides the info box.** Kept, and written into §14:
  like Bluetooth off, the panel is the one instruction that matters.

What the reviewer confirmed:
- connect from Connection alone;
- rule 8 (the side is checked before MTU and calibration, and never
  remembered);
- Diagnostics only from Researcher, with storage, Gait model, timing and
  Reconnects;
- TARE/REBOOT guarded twice;
- capture unchanged except the hint and the readiness constants;
- settings outside the database;
- text-size factors, switch off state, readiness, device info.

## Verify

- `flutter analyze`: no issues.
- `flutter test`: **786 passed**. New in S8B:
  - `settings_test` (7): defaults, persistence across a new store, and
    `clearTestData` keeps settings.
  - `foot_finder_test` (13).
  - `connection_screen_test` (10).
  - `settings_screen_test` (12): switches persist and announce their
    state; text size gives 18 → 22 → 26 and announces it; the name sheet
    saves and cancels; the delete-photos sheet with its count; version;
    insole row → Connection; 24 h picker; no debug button; sheet motion
    with and without reduce motion.
  - `researcher_screen_test` (8):
    - readiness waits 10 s, then passes;
    - battery 10 % disables start, and the export row still opens capture;
    - TARE and reboot are disabled and announced disabled during capture;
    - TARE sheet confirm → running (no buttons) → done;
    - a capture opened under the sheet makes TARE refused;
    - reboot drops and restores both links;
    - device info rows.
  - `insole_commands_test` (6): refused during capture and when nothing
    streams; TARE done or no response; REBOOT to every streaming foot;
    `SampleRateMeter` waits a full window and falls when the stream
    stops.
  - `foot_photos_test` (2): photos and columns cleared, answers and
    capture data kept.
- **Goldens** (390 wide, dpr 2, reviewed by eye):
  - `connect_*` (14): every §9 state; done and not found at 100 / 200 /
    130xl.
  - `settings_100`, `settings_switch_off_100`, `settings_130xl`.
  - `researcher_ready_100`, `researcher_capture_open_100`,
    `researcher_130xl`.
  - `sheet_name`, `sheet_delete_photos`, `sheet_tare`,
    `sheet_tare_running`, `sheet_tare_done`, `sheet_reboot`.
  - `home_safe_130xl`, `home_rest_130xl` (phone 1.3 × "ใหญ่มาก", with a
    name).
  - Regenerated for intended changes: `connection`, `settings`,
    `settings_mock`, `capture_home`, `capture_home_precheck_fail`, and
    `ble_debug_*` (title "Diagnostics", Reconnects card).
- **Emulator** (`emulator-5554`, `test_driver/main_mcp.dart`, `BLE_FAKE`,
  Dart MCP and adb). Screenshots are in `docs/reports/035-flutter-connect-settings/`.
  1. `BLE_SCENARIO=both`: Home → Connection → "เชื่อมต่อเท้าซ้าย", then
     "เชื่อมต่อเท้าขวา". Both green with battery and firmware, and the
     done button shows (`emulator-connect-done.png`, compare ConnectDDone).
     "เสร็จแล้ว กลับหน้าวันนี้" returns to Today.
  2. Settings (`emulator-settings.png`, SettingsD). Set name "สมชาย",
     "ใหญ่", sound off (`emulator-settings-switch-off-large.png`).
  3. Researcher hold. A tap and a 1 s hold change nothing; a 2.5 s hold on
     the blank right side opens Researcher. All three checks pass at 50/s
     (`emulator-researcher.png`). Device card and info show "247" and
     "50 ครั้ง/วินาที ต่อข้าง" (`emulator-researcher-device.png`).
  4. "เริ่มเก็บข้อมูลวิจัย" opens Research capture unchanged, with the new
     hint (`emulator-capture-home-hint.png`). Diagnostics opens from
     Researcher, and its log shows the connects.
  5. Force-stop and relaunch (a real restart). Home reads "สวัสดี คุณสมชาย"
     in "ใหญ่", and both feet reconnect on their own: "auto-reconnect #1
     (app start) … → streaming after 0.1 s (0 failed tries)"
     (`emulator-restart-autoreconnect.png`).
  6. `BLE_SCENARIO=btOff` with remembered insoles. Panel and "รอเปิดบลูทูธ"
     on both cards, no info box (`emulator-connect-bt-off.png`,
     ConnectDBtOff). "เปิดบลูทูธ" → both reconnect, logged "→ streaming
     after 24.2 s".
- **FLUTTER-PLAN §6:**
  - Rule 2: the readiness rate is read at read time, and the reconnect
    record is not latched.
  - Rule 5: the no-data and locked rows use No-data colours.
  - Rule 8: wrong side is never remembered (finder tests).
  - Rule 12: no thresholds added. 49 samples/s is a protocol constant next
    to `minBatteryPct`, as decided.
  - Rule 16: the ripple becomes still rings, the sheets jump, and the pop
    and check are skipped.
- The release APK builds: `build/app/outputs/flutter-apk/app-release.apk`,
  87.9 MB (84.6 MB in S8A, +3.3 MB).

## Note 10 checkpoint — **waiting on user**

**What to plug in, before starting:**
- The Note 10 (`RF8M83P4STZ`) by USB, unlocked, with USB debugging allowed.
  It isn't attached right now.
- Both ESP32 simulator boards, running the current `firmware/simulator/`
  build: LEFT and RIGHT, each on its own USB port. I start the serial
  loggers on `/dev/serial/by-id/usb-Silicon_Labs_CP2102…` before the phone
  connects. Opening a port resets that board.

I install the release build with `adb install -r` only (no uninstall, no
`pm clear`; the phone keeps the study data). Then, on the phone:

1. **Connect from Connection alone.** Home → a foot tile → "เชื่อมต่อเท้าซ้าย",
   then "เชื่อมต่อเท้าขวา". Both turn green, and "เสร็จแล้ว กลับหน้าวันนี้"
   goes to Today. Screenshot at 100 % text vs **ConnectD** (while searching)
   and **ConnectDDone**.
2. **Wrong side.** "ยกเลิกการเชื่อมต่อ" on both feet. Unplug the LEFT
   board and keep only the RIGHT board powered, then tap
   "เชื่อมต่อเท้าซ้าย". Expect the wrong-side message within ~3 s.
   Screenshot vs **ConnectDWrong**.
3. **Not found.** One board unplugged, "เชื่อมต่อ…" for that foot → after
   20 s, "ไม่พบแผ่นรองเท้า" with the 3 steps. Screenshot vs
   **ConnectDNotFound**.
4. **Bluetooth off.** Turn Bluetooth off in quick settings while on
   Connection → the panel, and both cards read "รอเปิดบลูทูธ". "เปิดบลูทูธ"
   → the system prompt → both reconnect. Screenshot vs **ConnectDBtOff**.
5. **Restart.** Close the app from Recents and open it → both feet
   reconnect on their own. In Settings → hold "ส่วนผู้วิจัย" 2 s →
   Diagnostics → Reconnects, read the duration.
6. **TARE on a simulator board.** Researcher → "ตั้งค่าศูนย์เซนเซอร์ (TARE)"
   → the sheet → "ตั้งค่าศูนย์" → "กำลังตั้งค่าศูนย์…" → "ตั้งค่าศูนย์เสร็จแล้ว"
   (the simulator's one-stride window). The serial log shows the TARE.
   Screenshot vs **SettingsDTare**. Then open Research capture, start a
   session screen, go back to Researcher: TARE and reboot are disabled.
7. **Text size.** Settings → "ใหญ่" and "ใหญ่มาก": every screen grows, and
   switches move under their titles at "ใหญ่มาก". Settings persist after
   a restart.
8. **Screenshots at 100 % text** of Settings vs **SettingsD**, and
   Researcher vs **SettingsDResearch**.
9. The release build stays on the phone.

## Leftovers and notes for the next sessions

- **BACKLOG 52 (S9):** auto-reconnect scans with no time limit (the S3A
  retry loop). Measure the battery cost.
- **BACKLOG 53:** the Diagnostics "Connect as" path does not remember the
  insole. Researchers should use Connection.
- **BACKLOG 54 (S10):** at 1.3 × ใหญ่มาก, Home's foot tiles stay
  side by side and the tab labels wrap to two lines. Nothing clips.
- **BACKLOG 45 (S9):** the Reconnects card is ready for the reset test.
- **BACKLOG 21 note:** a *laptop* capture is invisible to the phone. Only
  the sheet's warning guards it.
- The wrong side also shows when the other foot's own insole advertises,
  including that foot's "connected, no data" insole. This is accepted
  behaviour (connection test).
- Sound and reminder are stored only. The notification is S8C/S9.
- The permission panel's button labels are drafts.
- The MCP driver tool has no `request_data`, so the runtime toggles in
  `main_mcp.dart` (bt-off / unplug-left) work only from `flutter drive`.
  Use `BLE_SCENARIO` instead.

## Decisions needed

1. **Version line.** Keep "1.0.0+1 · รุ่นทดสอบงานวิจัย" (version + build,
   as now), or show only "1.0.0"?

## Next session

S8C: Daily foot check (§11), after this Note 10 checkpoint is accepted.
