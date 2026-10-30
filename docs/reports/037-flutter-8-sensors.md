# 037 — S8D-1: 8 FSR + 8 NTC per foot (data path)

Branch `work/flutter-8-sensors` · 2026-10-29 to 2026-10-30 · DATA-CONTRACT
v1.6 (written in this session), the user's S8D decisions of 2026-10-29 and
the approved plan. S8D is split: S8D-1 (this report) is the data path,
S8D-2 (`work/flutter-8-sensors-ui`, report 038) is the UI.

## Summary

- **The contract is v1.6.** The insole has 8 FSR and 8 NTC per foot, and
  NTC i sits next to FSR i:
  - 28-byte samples and 232-byte sensor packets;
  - temperature v2: 32 bytes with a `count` byte (= 8), 8 temperatures and
    8 quality bytes;
  - a calibration that lists exactly 8 FSR channels.

  Channel order: 0 hallux, 1 MTH1, 2 MTH2–3, 3 MTH5, 4 lateral midfoot,
  5 heel centre, 6 medial arch (new), 7 lateral heel (new). Zone ids 0–5
  keep their meaning. Appendix C is a page for the hardware team; its hex
  examples are taken from the test vectors.
- **The app refuses what it cannot read, and shows it.** A calibration
  with N ≠ 8 ("calibration rejected"), the old 12-byte temperature packet
  (`tempLength`) and a temperature `count` ≠ 8 (`tempCount`) are each
  counted per foot. Diagnostics shows one line per foot for the SR
  first-connection check: on a correct board it reads
  `N 8 · temperature v2, 8 sites · rejects 0`.
- **Everything downstream works at 8 zones and 8 sites:**
  - ΔT per site, null unless both feet are usable and both sites are
    readable (rule 4);
  - TEMP_DELTA per site: one alert per warmer foot, naming the site with
    the largest |ΔT| and listing every qualifying site;
  - peak, PTI, load concentration and asymmetry over 8 zones;
  - rule-based gait (heel = 5 + 7, forefoot = 0–3) and CoP;
  - storage schema v2, additive: nothing on the phone is deleted;
  - capture schema 2: old schema-1 files still load;
  - the Model A slot is `[1, 100, 28]`.
- **Simulator:** 8 FSR and temperature v2 by default. `t` warms site 1
  (MTH1) by 3 °C. Both boards were reflashed and pass `sim_check.py`
  56/56.
- **Interim UI until S8D-2:**
  - the maps draw 8 zones;
  - the temperature tab shows two of the 8 sites;
  - the alert detail lists every qualifying site.
- **The laptop web fallback cannot capture from 8-sensor boards.** That is
  a finding, not a change: the web app is frozen. The user decides before
  S9 (BACKLOG 63).
- Checks: `flutter analyze` clean, 952 tests, vectors, loader and
  `sim_check` selftests, simulator native tests 42/42, three firmware
  builds, release drop-in of the dummy model, emulator screenshots, both
  boards live (56/56 each). The spec review found no blocker or major
  issue; its 4 minor findings are fixed, and its 5 spec gaps are fixed,
  documented or noted (see below). **The Note 10 checkpoint was run on
  2026-10-31** (driven over adb at the user's request): all 9 items met
  their pass criteria. It is **waiting on the user's sign-off**.

## What changed

| Commit | What |
|---|---|
| a1efd2a | `docs/SESSIONS.md` v2.6: the S8D section, the S8D-1 / S8D-2 split, the schedule to the 12 Nov study start, the SR first-connection check against Appendix C, status rows |
| 80d7f28 | `shared/sensor_layout.json` (8 sites: id, Thai and English names, region, mm position, the display transform); `lib/config/foot_layout.dart` mirrors it. A test checks JSON identity, that every centre is inside the outline, and the mirroring |
| 78ee674 | Wire v1.6: temperature v2 parser and rejections; N = 8 test vectors (`temperature_v2.json` is constructed by `generate.mjs`: the frozen TS parser has no v2); N ≠ 8 calibration refused; `LinkStats.calibrationFsrCount`. Also contains the `git mv` of the old capture fixture to `schema1/` |
| 35d9d71 | Simulator: 8 FSR and temperature v2 by default (a `left_fsr6` build-only env stays), an anatomical 8-channel synth, 8 site temperatures, `t` warms site 1; `sim_check.py --fsr-count 8`; 42/42 native tests |
| 655e4c8 | Device layer: `DisplaySnapshot.deltaC` per site, temperature history and mock presets at 8 sites |
| af55e21 | Storage schema v2 (additive) with a v1 → v2 migration test that keeps every v1 row; `appendTempSite`; sample day and sample alerts at 8 sites |
| 9bd05ce | Rules and gait over 8 zones; TEMP_DELTA per site with `details.tempSites`, and sites that qualify during suppression appended to the open alert |
| 2211b6d | Capture schema 2 (`fsr0..7`, `temp0..7_c/_q`, per-site start temperatures), the `alerts.csv` `temp_sites` column, a schema-2 fixture with temperature readings and a TEMP_DELTA; `load_capture.py` reads schema 1 and 2 |
| 6ba78ef | Model A slot `[1, 100, 28]`: `model_input.json` v2, dummy model / normalization / check regenerated; a version-1 normalization is refused |
| 8f13529 | Interim UI at 8 sites; Diagnostics format line; 51 goldens regenerated and reviewed |
| ee9bcd2 | Docs: DATA-CONTRACT v1.6 with Appendix C, BLE-INTERFACE, FLUTTER-PLAN, STUDY-CAPTURE, STUDY-FALLBACK warning, READMEs, `mobile/CLAUDE.md`; BACKLOG 15 and 16 resolved, 63–67 added |
| f1261ea | The screenshots in `037-flutter-8-sensors/` |
| 35df06e | Spec-review fixes (table below) |
| 57ef40e | `test_driver/main_mcp.dart`: a debug-only `BLE_SCENARIO=fsr6`, not in the release APK |

## Decisions and how they were applied

User decisions of 2026-10-29 (plan questions):

| # | Decision | Applied |
|---|---|---|
| 1 | Temperature tab = layout A (map with 8 dots per foot, top 3 sites, one chart line of the largest \|ΔT\|, details table) | S8D-2. S8D-1 keeps the old widgets with two sites (see "Interim UI") |
| 2 | TEMP_DELTA: one alert per warmer foot, suppression key `TEMP_DELTA\|side`; every qualifying site in `details.tempSites` and in `alerts.csv` `temp_sites`; a site qualifying during suppression is appended | `alert_engine.dart` (`_addTempSites`), `AlertRepository.appendTempSite`, `alerts_csv.dart`. Tests: a second site during suppression is appended; the same site is not duplicated; after 30 min a new alert is raised; it survives a restart via the seeded memory |
| 3 | Zone names (draft): 5 กลางส้นเท้า, 6 อุ้งเท้า, 7 ส้นเท้าด้านนอก; heel group = 5 + 7 | `foot_layout.dart`, `sensor_layout.json`; gait classifier and the heel-walking note |

Fixed in the plan (stated, not asked):

- **The old 12-byte temperature packet is not kept.** It is rejected as
  `tempLength`, counted and shown, never misread.
- **N ≠ 8 is refused** with a visible "calibration rejected" problem. The
  parser stays N-generic (the N = 4 / 6 / 8 vectors still pass).
- **Storage v2 is additive.** Old TEMP_DELTA alerts keep their
  forefoot / heel site (`LegacyTempSite`) and show no map. Old 6-entry
  pressure maps draw zones 6–7 as "not recorded". Old temperature rows
  keep their two values.
- **`concentrationPct` stays 40 %**, now over 8 zones; flagged for SR
  (BACKLOG 64). The same goes for `steps.contactKpa` and the gait PTI
  shares (BACKLOG 65).
- **Model input v2**, 28 channels; temperature stays out of Model A.
  Model B's features are left for later (BACKLOG 66).
- **Capture schema 2.** A schema-1 trial loads with its own 24-channel
  model layout, never padded to 28.
- **The web app is untouched.**

## The laptop web fallback cannot capture from 8-sensor boards

Checked by reading the frozen TS code (`src/ts/data/blePacketParser.ts`,
`bleProtocol.ts`), without changing it:

1. **Connect fails.** `parseCalibrationJSON` throws unless the calibration
   lists exactly `FSR_CHANNEL_ORDER.length` (6) channels
   (`blePacketParser.ts:179`), so a v1.6 board never gets past the
   calibration read.
2. **Past that, samples would be garbage, with no error.** The sensor
   parser reads each sample at a fixed 24-byte stride and 6 channels
   (`blePacketParser.ts:63–72`). It only flags a packet that is *shorter*
   than expected, so a 232-byte packet with `count` 8 parses as 8 wrong
   samples.
3. **Temperature would read 0.08 °C.** `parseTempPacket` only needs
   ≥ 12 bytes (`blePacketParser.ts:101`). It reads `temp_forefoot` from
   bytes 6–7, which are now `count` (8) and `reserved` (0), so 0.08 °C.
   `temp_heel` comes from site 0 (hallux), and quality from a temperature
   byte.

**Nothing usable can be captured,** so the study has no laptop fallback
for the real boards. `docs/STUDY-FALLBACK.md` now opens with that warning:
its steps work only with v1.5 boards, and `left_fsr6` is not one (it
still sends temperature v2). The choice goes to the user before S9
(BACKLOG 63):

- (a) phone capture only;
- (b) a second Android phone with the app;
- (c) a user-requested web-app fix.

## Interim UI (until S8D-2)

- **Maps** draw the 8 zones at the layout's positions: Home, My feet
  pressure, alert detail, and the 8 dashed no-data dots for a missing
  foot. At My feet size, the left MTH1 and MTH2–3 dots touch when one is
  high (screenshot `13`). Dot sizes are S8D-2 step 3.
- **Temperature tab:** the two cards and chart lines show two sites. The
  pick order is: the alerting site, then the largest |ΔT|, then MTH1 /
  heel centre. Before the warm period, both lines of the seeded day are
  equal, so they overlap (screenshot `06`).
- **Home ΔT tile** shows the site with the largest |ΔT|.
- **Alert detail (TEMP_DELTA):**
  - the body names the site: "กลางส้นเท้าขวาอุ่นกว่ากลางส้นเท้าซ้าย 2.6
    องศา ติดต่อกันมาสักพัก";
  - the map marks only the named site (marking every qualifying site is
    S8D-2);
  - the details have a new row, 'จุดที่เกินเกณฑ์': "กลางส้นเท้า 2.6 ·
    ส้นเท้าด้านนอก 2.3 °C".
- **Draft strings** added in S8D-1, to be reviewed with Appendix A in
  S8D-2:
  - 'จุดที่เกินเกณฑ์';
  - the TalkBack label 'เท้าซ้าย จุดวัดความอุ่นทั้ง 8 จุด';
  - the site names in the temperature cards.
- **The `rest` preset is now heel centre** (+2.6 °C) and lateral heel
  (+2.3 °C) on the right foot. This matches the design boards' "ส้นเท้า"
  example. The old preset warmed the forefoot.
- **Copy mismatch:** the board example reads "ส้นเท้าขวาอุ่นกว่าส้นเท้าซ้าย
  2.6 องศา", while zone 5 is now named กลางส้นเท้า. S8D-2 updates
  Appendix A and the examples.

## Other notes

- **Seed-queue fix (found while writing the suppression tests).** After a
  restart, the engine reloads its suppression memory (the open alert's row
  id) asynchronously. A site that qualified before that finished would
  have been dropped. Such sites are now queued (`_sitesBeforeSeed`) and
  appended once the memory is loaded. The test "survives an app restart
  (memory from the alerts table)" (`alert_engine_test.dart`) feeds both
  readings straight after the restart, before the memory has loaded, and
  expects the second site in the same alert.
- **Mixed-schema sessions.** A session started on the old app and
  finished on the new one has schema-1 and schema-2 trials. The loader
  reads each trial by its own schema; the selftest covers a mixed session.
  STUDY-CAPTURE says to clear test data before 12 Nov, so study sessions
  are schema 2 only.
- **Old 6-entry stored maps** are padded to 8 with "not recorded" when
  shown (`pressureMapOf`); the stored JSON is not changed. The migration
  test checks that the stored map keeps its 6 entries.
- The `schema1/` fixture rename landed in the wire commit (78ee674)
  rather than the capture commit. Harmless.
- **Appendix C hex** was generated from the named vector cases
  (`sensor_n8.json` → `n8_8_samples`, `temperature_v2.json` →
  `quality_mixed` / `unreadable_one_site` / `legacy_v1_12_bytes`,
  `status.json` → `left_streaming`, the `INSOLE-N8-TEST` calibration). It
  can be re-derived from those files; the one-off generator script was
  not committed.

## Independent review (spec vs implementation)

`spec-reviewer` on `git diff main...HEAD` (2026-10-30, after the board
checks). Scope given to it:
- DATA-CONTRACT v1.6 §2.2–2.3, §3.1, §3.2, §5, §6, §7.1, §8.2, §8.3
  (with §8.3.1 and the addenda), §8.5 and Appendix C;
- `sensor_layout.json` and `foot_layout.dart`;
- FLUTTER-PLAN §2, §5 and §6 rules 4/5/6/9/12;
- BLE-INTERFACE v1.6;
- STUDY-CAPTURE schema 2 and `load_capture.py`;
- DESIGN-SPEC §5/§7.3/§8.2, for interim breakage only.

It found no blocker or major issue. The findings are copied as returned,
with a resolution column added.

| # | Severity | File:line | Spec | Mismatch | Resolution |
|---|---|---|---|---|---|
| 1 | minor | `mobile/lib/ui/screens/alerts/alert_view.dart:272-282` (with `:332`) | DESIGN-SPEC §7.3 map labels; `mobile/lib/rules/README.md` ("A map stored before S8D has 6 entries; zones 6–7 draw as not recorded") | Old pressure alerts with a 6-entry `details.map` now get `null` for zones 6–7. `_footMapView` returns a no-data view whenever `levels.contains(null)`, so the other foot's TalkBack label becomes "เท้าขวา ยังไม่มีข้อมูล" even though zones 0–5 were recorded. Before this branch it gave a real label (e.g. "แรงกดกระจายดี"). This only affects alerts stored before S8D, but the label says "no data" for a foot that has data. | **Fixed in 35df06e.** "No data" now only when every zone is null; an unrecorded zone counts as low for the label. `alert_view_test` "a map stored before the 8 zones" now gives the other foot a 6-entry map and expects 'เท้าขวา ส้นเท้ารับน้ำหนักปานกลาง'. The drawn map is unchanged (zones 6–7 still "not recorded"). |
| 2 | minor | `shared/sensor_layout.json:3`, `shared/README.md:57` vs `tools/capture/load_capture.py:110` | `shared/sensor_layout.json` is the machine-readable source (DATA-CONTRACT §3.1) | Both docs say `load_capture.py` "reads the ids" from `sensor_layout.json`. It doesn't: `ZONES` is a hardcoded 8-tuple, and no test keeps it in step with the JSON (the Dart side has `foot_layout_test.dart`). The values match today. | **Fixed in 35df06e.** `ZONES` is read from `shared/sensor_layout.json` (as the loader already reads `model_input.json`), so the docs are now true. Selftest PASS. |
| 3 | minor | `docs/STUDY-CAPTURE.md:239` | STUDY-CAPTURE output-files section | The new "Capture schema 2" paragraph was inserted in the middle of a sentence. "It pairs the feet by the same rule the app uses … and drops rows marked invalid" now follows "study sessions are schema 2 only", so "It" no longer refers to `model_matrix`. | **Fixed in 35df06e.** The sentence is back after the `model_matrix` sentence. |
| 4 | minor | `docs/DATA-CONTRACT.md:662`, `:668` | DATA-CONTRACT v1.6 header and revision history; SESSIONS.md:36 (study starts 2026-11-12) | Line 662 was edited on this branch but still says SR tunes the `gait.*` values "before 2026-11-10". SESSIONS now says the study starts on 12 Nov (STUDY-CAPTURE.md:142 also still says 10 Nov). Line 668 still calls this document "(v1.5)". | **Fixed in 35df06e.** Both dates are now 2026-11-12 (and BACKLOG 49's title); line 668 says v1.6. The header status line (spec gap 5) now says the file was extended in this repo to v1.5 and v1.6. |

Spec gaps it raised (no code mismatch, the spec is silent):

| Gap | Resolution |
|---|---|
| A site that qualifies after `repeatMin` while the foot's condition holds without a break is added to the open alert; no new alert is raised. | **Documented (35df06e), behaviour kept.** Every rule raises when its condition *starts* to hold, never again while it holds (contract §8.5, unchanged since S7), so one unbroken warm period is one alert and every site that joins it is listed. DATA-CONTRACT §8.3's v1.6 paragraph now says so. |
| After a restart, if the newest `TEMP_DELTA` inside the suppression window was stored before schema v2, sites that qualify during its suppression are only logged. | **Documented (35df06e).** It can only happen in the first 30 minutes after the update, with an alert stored by the old app. Test data is cleared before 12 Nov (STUDY-CAPTURE), so study data never meets it. |
| `startDeltaC` in `session.json` pairs each foot's first normal reading per site, which may come from different readings. | **Documented (35df06e)** in STUDY-CAPTURE's `session.json` row: up to 30 s apart. This is how main did it per foot before S8D; per site now. It is a calibration summary only; no rule or alert uses it. |
| Appendix C's rejection table does not list `tooShort`. | **Fixed (35df06e):** a row for a sensor packet shorter than its header or a status packet shorter than 8 bytes. |
| DATA-CONTRACT §9 Firebase `hourly` (`avgTempForefootL/R`) and the header status line still describe 2 sites / v1.4. | Header fixed (35df06e). §9 left as is: Firebase is outside v1's scope (FLUTTER-PLAN), and it gets redefined if it is ever built. |

Areas it checked and found clean:
- the Appendix C hex against the vectors (all six byte for byte);
- the §3.1 site table across the three files;
- the §3.2 parser;
- the §5 refusal path (no stream, no auto-reconnect, the format line, a
  TARE re-read that changes N fails the link);
- rules 4, 5, 6, 9 and 12;
- §8.3 TEMP_DELTA (naming, `tempSites`, the key, appending);
- §8.3.1 and the gait regions;
- §7.1 (`model_input.json` v2, the dummy normalization, `modelFsrCount`);
- the additive storage migration;
- capture schema 2 (columns, unchanged timing and recording, loader and
  fixtures, `temp_sites`);
- the simulator;
- the interim UI.

## Verify

### Static checks and tests

- `flutter analyze`: no issues. `dart format`: clean.
- `flutter test`: **952 passed**. Rerun on 2026-10-30 after resuming:
  the branch already contained PR #32's merge (bf4b986), and `main` had
  not moved, so no rebase was needed.
- `node shared/test_vectors/generate.mjs --check`: up to date.
- `python3 tools/capture/load_capture.py --selftest`: PASS (schema 1,
  schema 2, a mixed session, a schema-1 CSV labelled schema 2 is refused).
- `python3 firmware/simulator/tools/sim_check.py --selftest`: 89 vector
  cases, PASS.
- `pio test -e native`: 42/42. `pio run` for `left`, `right` and
  `left_fsr6`: SUCCESS (each 47.5 % flash, 11.9 % RAM).
- Goldens: 51 regenerated and reviewed (maps at 8 zones, the temperature
  tab with site names, the alert detail).

### Rules (FLUTTER-PLAN §6)

| Rule | Check |
|---|---|
| 4 | `DeviceManager._delta` is null unless both feet are usable and both sites have a value with `normal` quality (`usableC`), per site. Screens: one foot missing shows "—" / "ต้องเชื่อมต่อทั้งสองข้าง" on Home and on the temperature tab (screenshots `17`, `18`). |
| 5 | No-data zones are dashed grey at 8 zones (`16`, `19`); no-data never green. |
| 6 | Per-site consecutive counters; a site alerts only after `consecutiveReadings` pairs above `deltaC`. On the emulator, `rest` turned Home to Rest only after the second reading. |
| 7 | The `PRESSURE_PEAK` walking gate is unchanged (`walkingPeaks` only fed while walking). |
| 9 | The stale-packet gates (before START, old connection, t0 not forward) are untouched by the diff. |
| 10 | The 50 Hz / 10 Hz split is untouched. |
| 12 | No threshold literals: the numbers added in `lib/` are mock and sample data only (presets, seeded alerts, sample day). `no_threshold_literals_test` (rules, gait) passes. |

### Model A drop-in (emulator, release build)

- I copied the dummy `model_a.tflite`, `normalization.json` and
  `check.json` into `mobile/assets/models/` (not committed).
  `flutter build apk --release` built 93.4 MB, installed with `-r`.
- Diagnostics › Gait model:
  - "ready (assets/models)";
  - inference 3.08 ms;
  - "check: PASSED", on the 28-channel window (screenshot `01`).
- Then I replaced `normalization.json` with main's version-1 (24-channel)
  file and removed `check.json`. Result: "invalid in assets/models:
  normalization.json version is 1, model_input.json 2" (screenshot `02`).
- The copies were then removed; `mobile/assets/models/` holds only its
  README.

### Emulator (Pixel 7 AVD, API 37; driver build with `MOCK=`, then `BLE_FAKE=true`)

| Screenshot | What it shows |
|---|---|
| `03`, `04` | `rest`: Home "ควรพักเท้าตอนนี้", "เท้าขวาอุ่นกว่าเท้าซ้าย 2.6 องศา"; 8-dot maps; the ΔT tile 2.6° |
| `05`, `06` | `rest`: temperature tab with กลางส้นเท้า 2.6° and ส้นเท้าด้านนอก 2.3°, both "ขวาอุ่นกว่า"; the chart with both lines above the band |
| `08`–`10` | The live TEMP_DELTA: body naming กลางส้นเท้า, 8-site map, details with both qualifying sites |
| `11`–`13` | `watch`: Home "ควรระวัง"; the pressure map at 8 zones with MTH1 high; the top-zones list |
| `14`, `15` | `watch`: Gait "เดินกะเผลก", balance 79 : 21 (main's golden: 80 : 20, the two new zones are low); CoP from the 8 positions |
| `16`–`18` | `oneFootMissing`: the right foot's 8 dashed dots; ΔT "—" on Home and on the temperature tab |
| `19` | `noData`: both feet dashed, "ยังไม่มีข้อมูล" |
| `20` | `safe`: Home "ตอนนี้เท้าปลอดภัย" |
| `21` | `BLE_FAKE`, scenario `fsr6`: the left insole with 6 FSR is refused: "calibration lists 6 FSR channels, needs 8", format `N 6 (needs 8) · no temperature packet yet · rejects 1`, rejects `calibrationFsrCount 1` |
| `22` | `BLE_FAKE`: the right insole: `N 8 · temperature v2, 8 sites · rejects 0`, 8 kPa and 8 temperatures |

`test_driver/main_mcp.dart` gained the `fsr6` scenario for `21`
(57ef40e). It cannot reach a release build:
- it is a separate `-t` entry point;
- it imports `flutter_driver` (a dev dependency) and
  `test/ble/fake_ble_central.dart`;
- nothing in `lib/` imports it.

In the final release APK, `libapp.so` for arm64-v8a, armeabi-v7a and
x86_64 contains none of `BLE_SCENARIO`, `fsr6`, `rightOnly`,
`FakeInsole`, `FakeBleCentral`, `main_mcp`, `flutter_driver`,
`enableFlutterDriverExtension` or `unplug-left`. The controls
"temperature v2, " and "calibration lists" (app strings) are found once
each.

### Simulator boards (laptop, 2026-10-30)

Both CP2102 boards report USB serial `0001`, so `/dev/serial/by-id/` can
address only one board at a time. Each board was therefore done alone:

1. plugged in;
2. flashed through the by-id port;
3. serial log started on the same port before any central connected;
4. `?` sent to confirm the normal-walk scenario;
5. `sim_check.py --side L|R --duration 300`.

| Board | Firmware | Boot line | `sim_check` |
|---|---|---|---|
| Left (MAC 88:57:21:b7:74:9c) | `-e left` | `side L, fsr_count 8` | **56 PASS, 0 FAIL**: 1 874 sensor packets, all 232 bytes, `count` 8, 0 seq gaps, 6.250 Hz; 10 temperature v2 packets every 30 s, all 8 sites quality 0 (31.0–32.5 °C); calibration N = 8 (479 bytes, long read); reconnects, control opcodes, TARE, REBOOT |
| Right (MAC 38:18:2b:8a:26:d4) | `-e right` | `side R, fsr_count 8` | **56 PASS, 0 FAIL**: 1 875 packets, all 232 bytes, 0 gaps, 6.250 Hz; 10 temperature packets, all 8 sites quality 0; `foot_side` 1 |

- **First left run: 2 FAIL, explained, then a clean rerun.** "State 0
  after STOP_STREAM" and "status notifies state 0 after STOP" failed.
  4.5 minutes into the run, a phone (random address 57:96:3c:7a:ca:04)
  connected and started its own stream. It was most likely the Note 10's
  S8C app reconnecting to the left insole it remembers. The streaming
  state is device-wide by design (BACKLOG 17), so the board correctly
  stayed streaming. With the Note 10's Bluetooth off, the rerun passed
  56/56, and the serial log shows only the laptop connected.
- **The old S8C app on the Note 10 and a v1.6 board.** That build parses
  any temperature packet of ≥ 12 bytes with the v1 offsets. The byte it
  takes as quality is the low byte of site 1's temperature, so it rejects
  the packet unless site 1 reads 30.72–30.74 °C. In that case it would
  store forefoot 0.08 °C and heel = site 0. During `sim_check`, the left
  board's site 1 read 31.75–31.85 °C, and the simulator drifts slowly, so
  the phone most likely rejected every packet in its connection
  (16:21–16:48) and stored no reading. Confirmed on the phone on
  2026-10-31 from the old app's own screens (checkpoint item 9): no
  temperature row after 25 Oct, and its event log shows the packet
  rejected as `invalidQuality` (byte 99).
- The right board's first upload stopped partway ("Packet content
  transfer stopped"), right after it was plugged in. The second upload
  verified every segment.

### Final release build

- `flutter build apk --release` from 35df06e (57ef40e changes only
  `test_driver/`). The model slot is empty: `mobile/assets/models/` holds
  only its README, and `git status` shows nothing under `assets/`.
- `mobile/build/app/outputs/flutter-apk/app-release.apk`: 93.2 MB
  (93 227 470 bytes; 92.8 MB after S8C). SHA-256 begins
  `26e02270c792b29f`.
- `tool/check_release_resources.sh`: `ok drawable/ic_stat_foot_check`,
  all 1 runtime resource present.

## Note 10 checkpoint — run 2026-10-31, **waiting on user sign-off**

Before the run:
1. Leave the Note 10's Bluetooth **off** until item 1 is done: its
   current S8C build should not meet a v1.6 board (see "Simulator
   boards").
2. "Plug the Note 10 into the laptop by USB, unlock it, allow USB
   debugging." Confirm it with `adb devices -l` (serial `RF8M83P4STZ`).
3. Install with `adb install -r` only. No uninstall, no `pm clear`: the
   phone holds study data.

Both boards already run the v1.6 firmware (flashed and checked on
2026-10-30). Only the board that gets the `t` command needs to be on the
laptop; with both plugged in, `/dev/serial/by-id/` cannot tell them apart.
Steps for the boards:
- Plug the **left** board into the laptop and the **right** one into a
  USB charger.
- On the laptop, start the left board's log **before the phone
  connects**:

```
/usr/bin/python3 firmware/simulator/tools/serial_log.py \
  /dev/serial/by-id/usb-Silicon_Labs_CP2102_USB_to_UART_Bridge_Controller_0001-if00-port0 \
  left.log --commands left.cmd
echo '?' > left.cmd        # expect "[scenario] n (normal walk)"
```

| # | Check | How | Pass when |
|---|---|---|---|
| 1 | Install and migration | From `mobile/`: `adb install -r build/app/outputs/flutter-apk/app-release.apk` (SHA-256 begins `26e02270c792b29f`); open the app; then turn Bluetooth back on | The app opens; existing alerts, foot checks and settings are still there (storage v1 → v2 on the phone's real data) |
| 2 | Connect both feet | Settings → "เชื่อมต่อแผ่นรองเท้า" (or it reconnects by itself to the remembered insoles) | Home shows both feet connected |
| 3 | Format line | Settings → "ส่วนผู้วิจัย" (hold 2 s) → "ตรวจสอบระบบ"; wait 30 s for the first temperature packet | Each foot: `format N 8 · temperature v2, 8 sites · rejects 0` |
| 4 | 5-minute stream | Leave both feet streaming 5 minutes, phone unlocked | Diagnostics, each foot: `seq … · gaps 0 (0 missing)` and `rejects 0`; about 6.2 packets/s each; My feet pressure shows 8 zones moving on both feet |
| 5 | TEMP_DELTA from `t` | `echo t > left.cmd`; wait 60–90 s (2 temperature readings) | An alert for the **left** foot naming โคนนิ้วหัวแม่เท้า (MTH1), about 2.5 °C (+3.0 °C minus the boards' baseline difference at that site); Home turns "ควรพักเท้าตอนนี้"; the alert's "ตำแหน่งที่พบ" and "ดูตัวเลขละเอียด" name โคนนิ้วหัวแม่เท้า ('จุดที่เกินเกณฑ์' is listed only when 2 or more sites qualify, `alert_view.dart:454`; corrected on 2026-10-31). Then `echo n > left.cmd` |
| 6 | Short capture | Researcher → "เริ่มเก็บข้อมูลวิจัย" with a new `TEST-` code; record the calibration trial (or one short trial) | The pre-checks pass with 8 FSR channels; the trial saves |
| 7 | Export and load | On the laptop: `python3 tools/capture/export_capture.py --dest ~/smartinsole-data` (decide yourself whether to remove the staged copy when it asks), then `python3 tools/capture/load_capture.py check <session folder>` | `check` ends in `PASS` (50 Hz steps, no missing packets) |
| 8 | 28 channels | `python3 -c "import sys, pathlib; sys.path.insert(0, 'tools/capture'); import load_capture as lc; s = lc.load_session(pathlib.Path(sys.argv[1])); [print(t.name, 'schema', t.schema, 'channels', len(lc.model_matrix(t)[0][0])) for t in s.trials]" <session folder>` | Every trial: `schema 2`, `channels 28` |
| 9 | Old-app window (added 2026-10-31) | Before item 1's Bluetooth step, with the old S8C build: Alerts list and Diagnostics → Storage / Event log | No TEMP_DELTA or pressure alert, and no bogus temperature row, from the 30 Oct window when the old app met the reflashed left board |

Afterwards, stop the logger by PID (`pgrep -f serial_log.py`), not with
`pkill -f`. The `TEST-` session is test data; it is cleared with the rest
before 12 Nov.

### Results of the run (2026-10-31, 01:23–01:55)

The user set up the hardware: the Note 10 on USB, the left board on the
laptop, the right board on a USB charger. The user turned Bluetooth on
after item 1. Claude drove the phone over adb (taps, screenshots,
`dumpsys`) and changed no phone settings. The left board's serial log
(`left_n10.log`, kept in the session scratchpad) ran from 01:23:16, before
any phone connected. Screenshots 23–37 are in `037-flutter-8-sensors/`.

| # | Result | Evidence |
|---|---|---|
| 9 | **Met.** The old app holds one alert from 30 Oct: DEVICE_LOST (left) at 16:53:12, 5 minutes after Bluetooth was switched off at 16:48:12 (`dumpsys bluetooth_manager`). There is no TEMP_DELTA and no pressure alert. Storage: LEFT 125 rows (latest 10/25 22:20:12), RIGHT 128 rows (latest 10/25 22:20:17), so **no temperature row was stored on 30 Oct**. The old app's event log shows `16:47:58.776 L rejected (invalidQuality #1): temperature quality byte 99`. It accepted the 8-channel calibration (`N = 8`) and streamed 84 packets, 0 lost, before Bluetooth went off | 23, 24 |
| 1 | **Met.** `adb install -r` at 01:34:25 succeeded, and `firstInstallTime` stayed 2026-10-18. After the v1 → v2 migration, Storage is identical: LEFT 125 and RIGHT 128 rows with the same latest times, 10 alerts, latest DEVICE_LOST 10/30 16:53:12, 7 unread | 25 |
| 2 | **Met.** The left foot auto-reconnected at 01:38:22 (board log), and so did the right. Home showed both feet connected (battery 97 % / 88 %) | 33 |
| 3 | **Met.** Each foot: `format N 8 · temperature v2, 8 sites · rejects 0`, STREAMING, MTU 247, 8 samples per packet. Left sites 30.71–32.11 °C, right 31.53–32.93 °C, all quality normal | 26–28 |
| 4 | **Met.** From 01:41:19 to 01:47:00: left 1161 → 3286 packets, seq 3285, `gaps 0 (0 missing)`, rejects 0, link losses 0, 6.30/s. Right 1190 → 3315 packets, gaps 0, rejects 0, link losses 0, 6.30/s. My feet: 8 dots per foot. Its "ดูตัวเลขละเอียด" table lists all 8 zones per foot, with 2 s peaks changing from frame to frame (e.g. lateral heel 49 / 48, medial arch 16 / 16 kPa). All dots stay in the low tier under the `n` walk | 29–32 |
| 5 | **Met.** `t` at 01:49:17.555. The alert was raised at 01:49:54, and Home turned "ควรพักเท้าตอนนี้ / เท้าซ้ายอุ่นกว่าเท้าขวา 2.5 องศา" at 01:49:55, after 2 readings. Detail: "โคนนิ้วหัวแม่เท้าซ้ายอุ่นกว่าโคนนิ้วหัวแม่เท้าขวา"; `TEMP_DELTA`; โคนนิ้วหัวแม่เท้า left 34.7 °C, right 32.2 °C; ผลต่าง 2.5 °C (เกณฑ์ 2.2 °C); 2 consecutive readings; level 4 of 5. Only one site qualified, so there is no 'จุดที่เกินเกณฑ์' row (by design; item wording corrected above). `n` was sent at 01:51:17 | 33–35 |
| 6 | **Met.** Pre-check: both feet streaming, battery ≥ 80 %, firmware and calibration read. `TEST-004`, calibration trial (10 s rehearsal timer): "Saved TEST-004_00_calibration_a1 · completed", left 500 / right 500 samples, no gaps | 36, 37 |
| 7 | **Met.** In the app, "Export for USB (adb)" staged 4 files plus the manifest. `export_capture.py --dest ~/smartinsole-data --session TEST-004_20261031-015248`: every SHA-256 matches; L 500 samples, steps 20 ± 0.02 ms; R 500, steps 20 ± 0.25 ms; `alerts.csv` 0 alerts; **PASS**. Asked about removing the staged copy, the answer was "no": both `TEST-003_…` and `TEST-004_…` are still staged on the phone. `load_capture.py check` gives the same lines and ends in **PASS**. The WARN lines are the 5 trials not recorded | — |
| 8 | **Met.** `TEST-004_00_calibration_a1 schema 2 channels 28`. The CSV header has `fsr0..7_adc/kpa` and `temp0..7_c/_q` | — |

Also seen during the run:

- **The old app's process was not running from 16:23 to 16:47 on 30 Oct.**
  Its event log starts with "auto-reconnect #1 (app start)" at 16:47:54.
  That is why no DEVICE_LOST followed the 16:23 disconnect. The board log
  shows three old-app connections: 16:21:34–16:22:27, 16:22:29–16:23:09
  and 16:47:56–16:48:12 (random addresses 57:96:3c:7a:ca:04 and
  67:61:40:f5:1a:b8).
- **Home's date line was stale after midnight.** At 00:36 on 31 Oct the
  old app's Home read "วันศุกร์ 30 ตุลาคม": its process had been running
  since 16:47 with nothing rebuilding Home. The current code reads the
  clock the same way, so this is BACKLOG 68, not an S8D change.
- **App notifications are switched off on the Note 10.**
  `dumpsys notification` shows `allowNoti=false` for
  `th.ac.kmutt.smartinsole`, so the TEMP_DELTA alert at 01:49 raised no
  system notification. It is unknown whether this predates the run. No
  setting was changed. Decision for the user below.
- **One harness slip, no effect on the run.** A plain `open()` of the
  left board's port (to test access) left the board in its bootloader
  (DTR/RTS). An RTS pulse with DTR low booted it normally
  (`side L, fsr_count 8`) before any phone connected. Open the CP2102
  only through `serial_log.py`, which holds DTR and RTS low.

## Leftovers and notes for the next sessions

- **S8D-2:**
  - the layout-A temperature tab;
  - the alert-detail map marking every qualifying site;
  - dot sizes at 8 zones (MTH1 / MTH2–3 touch at My feet size);
  - zone names and Appendix A examples across the copy;
  - DESIGN-SPEC.
- **BACKLOG 63 (user, before S9):** the web fallback cannot capture from
  v1.6 boards.
- **BACKLOG 64, 65 (SR):** concentration 40 % over 8 zones;
  `steps.contactKpa` and the gait PTI shares now sum 8 zones.
- **BACKLOG 66:** Model B's temperature features name the old 2 sites.
- **BACKLOG 67 (user, before ~8 Nov):** send DATA-CONTRACT v1.6
  Appendix C to the hardware team and ask them to confirm the
  Appendix B items.
- **BACKLOG 68 (S9 or S10):** Home's date line can stay on yesterday
  after midnight.
- **Two boards on one laptop:** with both plugged in, by-id cannot tell
  them apart. For the checkpoint's `t` step, only the board that gets `t`
  needs to be on the laptop; the other can run from a USB charger.

## Decisions needed

1. **BACKLOG 63, before S9 (1 Nov):** the study-day fallback. Options:
   phone only, a second phone with the app, or a web-app fix.
2. **BACKLOG 67:** send Appendix C to the hardware team (user action).
3. **Note 10 checkpoint sign-off:** all 9 items met their pass criteria
   (run 2026-10-31, results above).
4. **App notifications are off on the Note 10** (`allowNoti=false`).
   Switch them back on in Android settings if the study phone should show
   alerts, or say if it was deliberate.

## Next session

The user's sign-off on the Note 10 checkpoint, then S8D-2 (UI) on
`work/flutter-8-sensors-ui` once this PR is merged.
