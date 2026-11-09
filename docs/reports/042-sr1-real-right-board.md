# 042 — SR-1 step 1: the real right insole against DATA-CONTRACT v1.6 (laptop only)

Branch `work/study-readiness` · 2026-11-09 · from main 3511936 (PR #36,
S9-2; PR #37, S10, still open). Laptop only: the Note 10's Bluetooth was
off and no app was installed. Plan approved 2026-11-09 with user decisions
1 (the Espressif device on `ttyACM0` is the right insole; ModemManager
rule), 2a (RESET once on request), 3a (a second run with the app's
SYNC_TIME), 4a (65 s), 5b (raw data outside the repo, short excerpts only,
no MAC address), 6a (the app's own parsers on the capture), 7a (branch from
main). Later decisions are listed under "Decisions (user, 2026-11-09)".

## Summary

- **Answer to step 1: no.** The right board as delivered cannot send v1.6
  data. It runs the hardware team's **hardware self-test sketch**, which
  has no BLE at all. The board did not advertise in a 30 s scan of its own
  address, and nothing near the laptop looked like an insole. Over USB it
  prints a self-test at boot, then a 16-channel `MUX raw ADC` table once a
  second. So none of the BLE checks (calibration, status, sensor and
  temperature packets) could run on it.
- **The board has more than expected:** the boot self-test finds an
  **MPU6050 IMU** (I²C 0x68, `WHO_AM_I 0x68`, PASS) and a working **64 GB SD
  card**. The MPU6050's ±8 g / ±1000 °/s ranges are exactly the contract's
  4096 LSB/g and 32.8 LSB/(°/s). The chip itself is unknown: an ESP32 on
  its own USB-Serial/JTAG port prints its ROM banner before the USB port
  comes up, so no logger can see it.
- **Run 1 reached another board by mistake:** `INSOLE-L-001`, the hardware
  team's own **left** insole, firmware 1.6, advertising within range
  (about −80 dBm). Only START_STREAM and STOP_STREAM were sent to it. Its
  stream follows the v1.6 layout, but the **app would refuse it**: its
  calibration JSON is cut off at 511 bytes. Even uncut, its placeholder
  `offset_adc` 4000 would turn every reading into 0 kPa. See the labelled
  section below. The cause was a fallback in my capture script, now
  removed. The user's rule: do not connect to it again unless the hardware
  team agrees.
- **New plan (user, agreed with the hardware team, 2026-11-09):** each side
  writes its own v1.6 firmware for the real boards, and whichever passes
  first is used on both insoles. Ours is FW-1 (report 043), planned next.
- **Also done:**
  - Read-only tools for real boards (`tools/board_check/`, and
    `mobile/tool/check_capture.dart` with the app's own parsers).
  - A `.gitignore` guard for study data.
  - Two public-repo rules in `mobile/CLAUDE.md`.
  - A contract line: the calibration JSON is sent compact, at most 512
    bytes.
  - A report on how the app picks a board (no code change).

## Hardware and port

| Item | Result |
|---|---|
| Serial port | `/dev/serial/by-id/usb-Espressif_USB_JTAG_serial_debug_unit_<MAC>-if00` → `/dev/ttyACM0`. The ESP32's own USB port (303a:1001), not a CP2102. The Quectel modem stays on `ttyUSB0` and was never opened. |
| ModemManager | It had the port marked as a candidate (`ID_MM_CANDIDATE=1`) and never claimed it: `mmcli -L` lists only the Quectel. The user added `/etc/udev/rules.d/99-esp32-usbjtag-no-modemmanager.rules` (`ID_MM_DEVICE_IGNORE=1`, `OWNER="pumon"`). After the RESET the port showed `ID_MM_DEVICE_IGNORE=1`, owner `pumon`. |
| Reset safety | `serial_read.py` keeps DTR and RTS both asserted, as Linux sets them at open, so the reset combination (RTS asserted without DTR) never occurs. Opening the port did **not** reset the board: no boot output, and its 1 s table just went on. It never writes to the port. |
| Chip | **Unknown.** USB `bcdDevice 0101`, "USB JTAG/serial debug unit": the same on ESP32-C3, S3 and C6. The ROM banner is lost before USB re-enumerates. Asked in FW-1. |
| Restarts | User RESET at 12:01:27. **A second restart at 12:01:39**, with the same self-test output. Did the user press twice? If not, the board restarted by itself (the log gives no reason). |

## Serial log (raw in `~/smartinsole-data/board-checks/042-sr1-right/serial.log`, 7,272 lines, 20 min)

Boot output after RESET (excerpt):

```
--- MPU6050 ---
Address: 0x68 | WHO_AM_I: 0x68
PASS: MPU6050 responds correctly.
--- SD ---
PASS: SD card communication works.
Card size: 64001 MB
--- MUX TEST ---
Raw ADC values alone do not confirm MUX operation.
Connect test channels to known voltages.
```

Then every second:

```
MUX raw ADC:
C00= 907  C01=1057  C02= 466  C03= 458
C04= 924  C05= 971  C06= 971  C07= 913
C08=1148  C09=1022  C10= 966  C11= 740
C12= 948  C13= 697  C14= 512  C15= 413
```

- 1,207 readings of 16 channels, with nothing pressing on the insole. Every
  channel reads between 319 and 1247, and the medians run from 427 to 1204.
  The values drift slowly together.
- With the contract's formula and a 10 kΩ pull-down, an unloaded FSR
  should read near 0. Readings near 1000 at rest suggest floating mux
  inputs, a different circuit, or sensors not yet connected. The sketch
  says as much itself.
- **C05 and C06 read the same value within ±3 ADC in 99 % of readings**
  (exactly equal in 45 %). This needs a hardware-team answer (FW-1
  questions).
- No error, brown-out, watchdog or BLE line in 20 minutes.

## BLE (laptop, bleak, BlueZ)

| Requested check | Result on the right board |
|---|---|
| Scan for SMARTINSOLE-R with the service UUID | **FAIL: not advertising.** In 30 s there was no advert from the board's own BLE address (its base MAC from the USB serial number, +0..3). |
| Anything else near the laptop | 12 advertisers at ≥ −65 dBm: a speaker and phone or watch beacons (Apple, Samsung, Xiaomi, Microsoft). None was Espressif, carried a name like an insole, or carried the service UUID. |
| Calibration (N = 8, JSON saved) | Not possible: no BLE |
| Status packet | Not possible: no BLE |
| START_STREAM, 65 s of sensor packets (length, count, seq from 0, rate, t0 + 160 ms per packet) | Not possible: no BLE |
| Temperature packets (32 bytes, values) | Not possible: no BLE |
| STOP_STREAM | Not possible: no BLE |
| Appendix C byte comparison | Not possible: no packets |

The battery check ("0 % would block a research capture", found while
preparing) does not apply: the board sends no status. **User decision:**
no app change for it. The study boards will have batteries, so a 0 % on a
USB-powered bench board is expected.

## INSOLE-L-001 — the hardware team's own board, contacted by mistake

**Labelled section (user decision 2, 2026-11-09).** This is the hardware
team's left insole, not the board under test. It was reached by mistake.
Only START_STREAM (0x01) and STOP_STREAM (0x02) were written to it. Its raw
data stays in
`~/smartinsole-data/board-checks/042-sr1-right/other-board-SMARTINSOLE-L-run1/`.
**Not to be contacted again unless the user says the hardware team agreed.**

**How it happened.** No advert came from the right board, so
`board_capture.py` fell back to "any board with the service UUID" and
connected to the only one in range. Its data did not match the cabled
board in three ways:
- it has a working IMU;
- it booted about 11:37, while the cabled board re-enumerated at 11:39;
- its FSR values did not match the serial table.

Its address has the same Espressif prefix but belongs to another chip. The
fallback is gone: the script now connects only to the cabled board's own
address (`--usb-mac`), and `--scan-only` scans without connecting.

What it sends, from one 90 s run (`compare.py`, then the app's parsers):

| Item | Result |
|---|---|
| Advertising | `SMARTINSOLE-L`, service UUID advertised, no TX power field |
| GATT | All 5 characteristics with the right properties (control: write + write without response); MTU 247 |
| Status | 8 bytes; foot_side 0 (left, correct for this board); firmware **1.6**; state 0 → 1 after START → 0 after STOP, notified; battery a constant **100 % / 4100 mV** |
| Sensor stream | 562 packets, all **232 bytes**, count 8, **seq from 0 with no gaps**, 6.252 packets/s, nothing before START, nothing after STOP, first packet 303 ms after the START write |
| t0 | **45 of 561 steps are 161 ms** (the rest 160); the device clock runs **+819 ppm** against the laptop |
| Flags | **0x01 (saturated) on every packet**, with ADC at most 307 |
| FSR | At rest: ch0 ≈ 175, ch1 ≈ 176, ch4 ≈ 133, ch5 ≈ 132, ch2/3/6/7 ≈ 0. **ch0 and ch1, and ch4 and ch5, read the same value within ±3 ADC in 98 % of loaded samples** |
| IMU | Working: accel about 1 g (raw −1281, −1388, −3667 on sample 0), gyro small; the walking-gate statistic stays under 0.15 g at rest |
| Temperature | 3 packets, 32 bytes, count 8, reserved 0, quality 0, 31.2–33.7 °C (NTCs appear to be fitted); seq starts at 1; the first came 26.9 s after START; **period 30,015 ms** |
| Calibration | **511 bytes, cut off mid-JSON** (`…"offset_adc":4000` with no closing brackets). Visible part: `device_id "INSOLE-L-001"`, compact, every channel `a 100000, b -1.0000, offset_adc 4000` |
| The app's parsers (`check_capture.dart`) | Sensor 562/562 and temperature 3/3 parse, status 15/15. **Calibration `calibrationNotJson` (Unexpected end of input): the app refuses this insole.** |

Sensor packet 0 against the Appendix C example (excerpt):

```
off   field            board bytes   board  | example bytes  example
0x00  seq              00 00             0  | 6c 00              108
0x02  t0_ms            86 97 04 00  300934  | 50 c3 00 00      50000
0x06  count            08                8  | 08                   8
0x07  flags            01                1  | 00                   0
0x08  fsr[0] hallux    b1 00           177  | 65 0e             3685
0x18  accel x          ff fa         -1281  | 04 f2            -3580
0x1e  gyro x           b2 ff           -78  | e4 01              484
```

Mismatches for the hardware team on this board:

| # | Severity | Contract | Expected | Observed | Effect in the app |
|---|---|---|---|---|---|
| L1 | blocker | §2.2, App. C item 4 | calibration JSON complete, compact, ≤ 512 bytes | cut off at 511 bytes; `-1.0000` costs 5 bytes a channel (`-1` would fit) | `calibrationNotJson`: "calibration rejected", nothing streams |
| L2 | blocker | §5.1 | `offset_adc` = each channel's unloaded reading (TARE); `a`, `b` per sensor | `offset_adc` 4000 and the same `a`/`b` on every channel | `adc − offset_adc` clamps to 0: every zone 0 kPa |
| L3 | issue | §3.1, App. C item 1 | 8 independent FSR channels | ch0 ≈ ch1 and ch4 ≈ ch5 in 98 % of loaded samples | two zones show one sensor (mux address or wiring?) |
| L4 | issue | §3.1 | flags bit0 only when saturated | bit0 on every packet, ADC ≤ 307 | captures mark every sample saturated |
| L5 | issue | §3.1 | t0 + 160 ms per packet exactly | 161 ms in 45 of 561; clock +819 ppm | 1 ms steps; L/R time sync relies on SYNC_TIME every 5 min (§4) |
| L6 | issue | §2.2, §3.2 | temperature every 30 s | 30,015 ms | TEMP_DELTA's pairing drifts slowly |
| L7 | note | §3.3 | battery from a real measurement | constant 100 % / 4100 mV | fine on the bench; must be measured on the study boards |

## How the app picks a board (user request, report only, no code change)

- **Scan:** only by service UUID (`mobile/lib/ble/fbp_central.dart:66-67`).
  Every board advertising it is a candidate.
- **First connect** (Connection › find, `FootFinder.find`,
  `mobile/lib/ble/foot_finder.dart`):
  - Candidates are tried **in the order they were first seen**, not by
    signal strength. Boards the other foot holds are skipped.
  - The first board whose status `foot_side` matches this foot is taken.
  - A board of this foot that cannot stream (calibration rejected, MTU too
    small) is **also kept**, and the search stops there ("connected, no
    data").
  - **Nothing checks which physical board it is:** no expected address, no
    expected calibration `device_id`.
- **After that:** the board's address is remembered per foot
  (`SettingsStore.setBoundInsole`). At app start (`autoConnect`) and after
  a lost link, the app reconnects **only that address**
  (`mobile/lib/ble/ble_data_source.dart:262`), so it never wanders to
  another board.
- **Where the identity shows:** Researcher › Diagnostics shows the address,
  the advertised name and `cal <device_id>` per foot
  (`debug_ble_screen.dart:233`, `:505`). Connection shows only the
  firmware. Each capture session's sidecar records each foot's calibration
  with its `device_id` (`capture_files.dart`, `calibrationJson`), so the
  board can be checked afterwards.
- **Study-day risk:** if another team's insole, or a spare, is on and in
  range during the first connect, the app can bind to whichever matching
  board it sees first. Today `INSOLE-L-001` at −80 dBm would have been
  taken as "the left insole". Once bound wrongly, the app keeps
  reconnecting the wrong board until "ยกเลิกการเชื่อมต่อ" forgets it.
  Options are in BACKLOG 80. **A decision is needed before the study.**
  FW-1's test calibration (`device_id "INSOLE-R-TEST"`, "never for study
  data") makes this more pressing.

## Contract and repo changes

- **DATA-CONTRACT Appendix C item 4** (user decision 3): send the
  calibration JSON compact (no spaces or newlines), at most 512 bytes, the
  GATT value limit. The Appendix C example is 848 bytes as printed and 492
  compact. History row "1.6 addendum, 2026-11-09, SR-1". `INSOLE-L-001`
  shows the failure in practice (L1).
- **`.gitignore` guard** (user decision 1). Blocked: anything named after
  an `SI-` code, `.incoming/`, `smartinsole-data/`, `board-checks/`, and
  the trained `mobile/assets/models/*.tflite` and `normalization.json`.
  Checked with `git check-ignore`:
  - the `TEST-` capture fixtures, the dummy model and the models README
    are not ignored;
  - no tracked file became ignored.
- **`mobile/CLAUDE.md`, "Study data and the public repo"** (user decision
  1):
  - screenshots for reports or the thesis use `TEST-` data only;
  - the trained model files are never committed until the user has checked
    the consent form and IRB;
  - real-board output gets short excerpts only, never a MAC.
  - The `assets/models/README.md` says the same.
- **Could anything study-related still be committed?** Study exports and
  board captures live outside the repo, and the guard catches `SI-` named
  files copied in. What remains depends on care, not on git:
  - Note 10 screenshots of study screens (now a rule);
  - report text quoting a volunteer's numbers or `alerts.csv` lines;
  - thresholds tuned from study data (aggregates, low risk);
  - the model files (now ignored).

## Tools (`tools/board_check/`, README there)

- **`serial_read.py`:** read-only logger for `usb-Espressif_*` ports only.
  - It never writes to the port, and DTR/RTS never take the reset
    combination.
  - It reopens the port after a RESET re-enumerates it.
  - It writes `<log>` and `<log>.raw`.
- **`board_capture.py`:** bleak capture.
  - It scans unfiltered but records only the target, SMARTINSOLE names and
    the service UUID.
  - It records the GATT table, status, calibration, every notification and
    the writes, as JSONL.
  - **Only START_STREAM, STOP_STREAM and (`--app-sequence`) SYNC_TIME can
    be written; anything else is refused in code.**
  - `--usb-mac` connects only to the cabled chip; `--scan-only` never
    connects.
- **`compare.py`:** offline check against v1.6 / Appendix C.
  - It runs `sim_check.py`'s parser selftest first (89 vector cases), so
    the parsers are proven against `shared/test_vectors/`.
  - It judges advertising, GATT, MTU, status, calibration (size, fields,
    N, offsets against readings), the sensor stream (length, count, seq,
    t0, rate, flags, ADC, duplicate channels, channels pressed in time
    order, IMU, the walking-gate statistic) and temperature v2 (`--no-ntc`:
    any number is made up).
  - It prints each first packet next to its Appendix C example.
  - It ends with a blocker / issue / note table, each with its effect in
    the app.
- **`mobile/tool/check_capture.dart`:** runs the app's own Dart parsers
  over a capture and prints what Diagnostics would show, and whether the
  app would refuse the insole.
- All of them refuse an output path inside the repo.

## Checks

| Check | Result |
|---|---|
| `sim_check.py --selftest` (parsers against `shared/test_vectors/`) | pass, 89 cases |
| `compare.py` on synthetic captures built from the vectors | a correct board passes except the 562-byte spaced calibration (the finding behind the Appendix C line); a bad board gets every planted fault: N 6, battery 0, error 1, no temperature, first seq 5, gaps, zero IMU; `offset_adc` 4000 → the 0 kPa blocker |
| `check_capture.dart` on the same captures | correct board: `format N 8 · temperature v2, 8 sites · rejects 0`, accepted; N = 6: refused, `N 6 (needs 8)` |
| `flutter analyze` / `flutter test` | see below (run after the tool and doc changes) |
| Requested BLE checks on the right board | **not possible: no BLE** (table above) |
| Serial log, boot messages, version, errors | done: self-test sketch, no version line, no errors; chip unknown |
| Raw captures saved | yes, outside the repo (`~/smartinsole-data/board-checks/042-sr1-right/`: `serial.log`, `serial.log.raw`, `scan1/`, `other-board-SMARTINSOLE-L-run1/`) |
| No MAC address in the repo | `git grep` for the board's MAC prefix: none |

## Spec review

(spec-reviewer on `git diff main...HEAD`, sections: DATA-CONTRACT §2–§3,
§5.1, Appendix C; FLUTTER-PLAN §6; the session's standing rules.)

## Leftovers

- **Chip type** of the right board: from the hardware team, or a read-only
  `esptool chip_id` (resets the board into its ROM bootloader and back;
  writes nothing). FW-1 question.
- **C05 ≈ C06** on the right board's mux table: hardware-team question
  (FW-1).
- **The second restart at 12:01:39:** a second press, or a self-restart?
- **The app's board selection** (BACKLOG 80): decision before the study.
- `firmware/simulator/tools/serial_log.py` refuses non-CP2102 ports by
  design; the real board has its own logger now. No change.

## Decisions (user, 2026-11-09)

1. `.gitignore` guard, plus `mobile/CLAUDE.md` rules (TEST- screenshots
   only; model files never committed until the consent form and IRB are
   checked). Done.
2. A press test during the run, each sensor 0 → 7 (not run: no BLE).
3. The 512-byte calibration: a hardware-team item and one line in Appendix
   C (done). Battery 0 % → capture blocked: no app change; expected on a
   USB-powered board.
4. `INSOLE-L-001` in this report as a labelled section; raw data outside
   the repo; no further contact without the hardware team's agreement.
5. The app's board selection: report only, no code change yet.
6. New plan: each side writes v1.6 firmware for the real boards; the first
   to pass is used on both. FW-1 (report 043) is ours.
7. Ask before `git push` and before opening the PR.

## Decisions needed

1. **BACKLOG 80:** how the app should make sure it binds the study's own
   two boards. Options there: a procedure only, show `device_id` on
   Connection, pin the expected `device_id`s, prefer the strongest signal,
   refuse a `-TEST` calibration for `SI-` captures.

## Next

- **FW-1 (report 043):** our own v1.6 firmware for the real right board, in
  `firmware/insole/`, reusing the simulator's BLE layer with real sensor
  reads. Plan first: chip, pins and mux mapping questions for the hardware
  team; flashing only after the user confirms the hardware team agreed to
  overwrite their self-test sketch.
- **Step 2** (the app on the Note 10) once a board passes
  `board_capture.py` + `compare.py` with no mismatches and
  `check_capture.dart` shows rejects 0.
