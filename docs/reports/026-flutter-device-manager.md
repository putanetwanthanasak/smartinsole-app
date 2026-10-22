# 026 — S4: DeviceManager + timing (Flutter)

Branch `work/flutter-device-manager` · 2026-10-22 · Session S4 (`docs/SESSIONS.md` §3)

**Status: code done, waiting on the Note 10 checkpoint.** All automated
checks pass (242 tests, analyze clean, mutation checks caught). The
emulator checks are done too. S4's Done-when has not been checked yet:
L/R offset ≤ ±10 ms, 20 ms spacing and no lost packets over 10 minutes
can only be measured on the Note 10 with both boards. **Do not start S5
until that checkpoint passes.** The checklist is at the end.

## What was done

1. **`docs/SESSIONS.md` → v2.3** (`9f321c7`, verbatim from
   `~/Downloads`). The diff against main loses nothing that was merged.
   Two text fixes followed in `8d9cfa8`:
   - the title now says v2.3;
   - the S4C "+ one JSON sidecar" clause is moved back after "flags)".
2. **BLE layer** (`f5167e1`, `mobile/lib/ble/`):
   - **BACKLOG 27:** the rule-9 gate now opens when the START write is
     **issued**, not when it is acknowledged.
     - Packets that arrive between the write and its ack are kept and
       counted as `admittedBeforeAck`.
     - A packet before the write is still `droppedBeforeStart`.
     - A late packet from an older link is still dropped by the
       connection generation.
   - **`SeqTracker`:** gaps, including the 65535 → 0 wrap.
     - A first accepted `seq` k > 0 counts as k `missingAtStart`, kept
       apart from mid-stream gaps (BACKLOG 19: real firmware might not
       restart `seq`).
   - **`SensorFrame`** gains `session` and `missingBefore`.
     **`SensorSample`** keeps the raw ADC (`fsrAdc`) next to kPa, for
     S4C.
   - **`SYNC_TIME` every 5 min** while streaming (the interval is
     settable; the timing check uses 10 s). It is published on `syncs`.
     It is sent and logged only.
3. **Device layer** (`5805270`, `mobile/lib/device/`; full description in
   `lib/device/README.md`):
   - **`DeviceClock`: unix time per sample** (BACKLOG 28).
     - Each packet's candidate offset is its own arrival minus its last
       sample's device time. The target is the minimum over 30 s.
     - The applied offset moves toward the target by at most 0.25 ms per
       sample. So samples are 20 ± 0.25 ms apart, with no 160 ms steps
       and nothing ever backwards in a session.
     - It handles the uint32 wrap of `deviceMs`.
     - A defensive clamp is counted (`clamps`, expected 0).
   - **`DeviceManager`:**
     - **50 Hz path** (rule 10): `batches` emits one `FootBatch` per
       accepted packet, unthrottled and unix-timed. Batches from an older
       session are dropped.
     - **10 Hz path:** `snapshots` emits a `DisplaySnapshot` every
       100 ms, and only while something listens.
     - **Staleness** (rule 2) is derived when the snapshot is read
       (3 s).
     - **ΔT** (signed L−R) is `null` unless both feet are usable and
       both temperatures are present with normal quality (rule 4).
     - **Temperature history:** 10-min buckets over 24 h.
   - **Model channels:** 24 channels in contract §7.1 order (FSR kPa,
     accel g, gyro °/s; L then R). `modelRow()` gives the row, and new
     `shared/model_input.json` is the shared list; a test checks they
     match.
   - **`MockDataSource`** (debug builds only, `--dart-define=MOCK=`):
     - Presets: `safe`, `safeOrangeDot`, `watch`, `rest`, `noData`,
       `oneFootMissing`, `lowBattery`.
     - The data is real-shaped: 8 samples per 160 ms packet, separate
       boot clocks per foot, a gait waveform generated as ADC and
       converted with the real `sampleKpa`, and an IMU jolt at heel
       strike.
     - A band test checks every preset against
       `shared/thresholds.json`, so the presets hold no thresholds
       (rule 12).
4. **Timing check and preset picker** (`60ee4d8`):
   - **Timing check card** on the BLE debug screen. While it runs, it:
     - sends `SYNC_TIME` every 10 s;
     - writes each send (U, offset A) and both feet's counters every
       10 s to `app_flutter/timing/timing-<date>.log` (new dependency
       `path_provider`).
   - **Debug-only Settings button** "Mock preset (debug)" switches the
     preset live.
5. **`firmware/simulator/tools/timing_check.py`** (`5e5ef49`, `7f56cca`;
   stdlib only, `--selftest`). It joins the app's log with both boards'
   serial logs (see "How L/R ±10 ms is measured" below) and also checks
   lost packets, 20 ± 1 ms steps, clamps, and the boards' notify failures
   and mtu-drops. Without serial logs it fails, unless `--app-only` is
   given.
6. **Docs** (`f3eb9e3`):
   - `lib/device/README.md`, `lib/ble/README.md` and `mobile/CLAUDE.md`
     (layout, the `MOCK` define, BLE rules);
   - BACKLOG status for items 20, 25, 27 and 28, plus new items 30 and
     31.

### Mock presets, measured (65 s runs, left foot unless noted)

| Preset | Peak kPa | Step PTI kPa·s (max-ch / per-ch) | Concentration | Intended |
|---|---|---|---|---|
| `safe` | ~60 | 21.5 / 9.4 | 24 % | nothing; walking by §8.3.2 (mean \|a−1 g\| 0.23) |
| `safeOrangeDot` | 95.1 | 28.8 / — | 31.8 % | level 2 only: peak > `watchKpa`, below every level-3 rule |
| `watch` | 150 | 128 / 119.4 (meta1) | 29.4 % | level 3 `PRESSURE_PTI`: sustained left forefoot load |
| `rest` | safe | | | right forefoot +2.6 °C on every reading (> `deltaC`, ≥ 2 consecutive) |
| `lowBattery` | safe | | | left battery 10 % (< contract `BATTERY_LOW` 15 %) |
| `noData` / `oneFootMissing` | — | | | both idle / left streaming, right idle |

### How L/R ±10 ms is measured

The two boards and the phone share no clock. The method works per foot:

1. **The app's offset.** For one foot the app's offset is **A = θ + n**.
   θ is the true offset between the board's clock and the phone's. n ≥ 0
   is the smallest notification latency the 30 s minimum found.
2. **What the board logs.** The board logs each `SYNC_TIME` it handles as
   "unix U at device D". U is the phone time the app wrote. So
   **U − D = θ − w**, where w ≥ 0 is the write's latency.
3. **The bound.** Subtracting gives **B = A − (U − D) = n + w ≥ n**. So B
   bounds that foot's error from above, and the L/R alignment error
   n_L − n_R lies in [−B_R, B_L].
4. **Windows.** w changes from write to write, so the script takes the
   smallest B in each 120 s window. A 10-minute run gives 5 windows and
   about 60 brackets per foot. **Pass when every window's bound is
   ≤ 10 ms for both feet.**

U is what joins the two logs.

Caveat: the board stamps sample k at `epoch + 20k` (its 50 Hz task), while
D is `millis()`. If a sample's real time can be up to about 1 ms before
its stamp, the bound is off by up to about 1 ms. The script fails any B
below −1 ms, which would show this.

## Checks

| Check | Result |
|---|---|
| `flutter analyze` | **pass**, no issues |
| `dart format` | **pass** |
| `flutter test` | **pass**, 242 tests (51 new in `test/device/`, 2 in `test/mock_preset_settings_test.dart`, more in `test/ble/`) |
| SESSIONS Verify list | **pass:** stale (read-time), ΔT null (one foot missing, stale, bad quality, null value), stale packet (before START, old link, old session), `seq` wrap 65535, `deviceMs` uint32 wrap |
| BACKLOG 28 regression | **pass:** bursty arrivals (the web app's 160 ms case) give no step; a ±500 ms phone wall-clock step is absorbed; 40 ppm drift is tracked |
| Mutations (each applied alone, then restored) | **all caught:** gate back at the ack → 2 tests fail (first packet before the ack, late old-link packet); slew unbounded → 7 fail; ΔT ignoring staleness → fails; no uint32 unwrap → fails |
| `timing_check.py --selftest` | **pass**, 9 cases (clean, n too large, write jitter only, 40 ppm drift, lost packet, step out of range, too short, unmatched SYNC, missing serial log) |
| Web app untouched | **pass:** `git diff main --stat -- index.html src css public package*.json vite.config.ts tsconfig.json` is empty |
| Rules 1–4, 9, 10, 12 | **pass**, checked against the diff (rule 12: the presets and their test read `thresholds.json`; the clock constants are technical, not clinical) |
| Emulator, mock | **pass:** `MOCK=safe`, every one of the 7 presets switched live from Settings, no runtime errors from the app |
| Emulator, fake BLE | **pass:** both feet streaming, timing check started, file written, pulled with `adb exec-out run-as`, parsed by `timing_check.py --app-only` (0 lost, steps 19.75–20.09 ms, clamps 0) |
| Goldens | new `settings_mock`; `ble_debug_*` regenerated at 390×2000 for the timing card |
| **Note 10 checkpoint** | **waiting on user** (checklist below) |

During the emulator run, `get_runtime_errors` showed one
"Guarded function conflict" from the Flutter Driver. I had sent several
driver taps at once. When the taps were sent one at a time, no error came
back. It was not an app error.

### Screenshots (`docs/reports/026-flutter-device-manager/`)

| File | What it shows |
|---|---|
| `1-mock-preset-picker.png` | Settings → mock preset sheet (7 presets, current ticked) |
| `2-mock-one-foot-missing-timing-card.png` | `oneFootMissing`: left session 1 streaming, right nothing; Start disabled in mock mode |
| `3-mock-low-battery-both-feet.png` | after switching to `lowBattery`: both feet streaming, steps 19.75–20.00 ms, clamps 0 |
| `4-fake-ble-timing-running.png` | `BLE_FAKE`: timing check running, SYNC_TIME every 10 s, file path, both feet lost 0 |

No screen shows the presets' Home states yet: Home is wired to
`displaySnapshotProvider` in S5. The presets' data is checked by the
band test instead.

## Leftovers

- **BACKLOG 27** is fixed in code, pending the Note 10 result.
  `admittedBeforeAck` will show whether the race really happens.
- **BACKLOG 28**: the app part is done. S4C still has to write `seq` into
  the CSV.
- **Contract §4 deviation, for the contract owner:** §4 describes the web
  app's resync formula. The app deliberately doesn't use it.
- **BACKLOG 30** (new): `thresholds.json` has no battery value. The
  `lowBattery` preset cites contract §8.3 directly (for S7).
- **BACKLOG 31** (new): the contract doesn't say what PTI and concentration
  are computed over. The presets assume per step; S7 must confirm with the
  contract owner.
- **BACKLOG 19** risk: real firmware may not restart `seq` at
  `START_STREAM`. If not, `missingAtStart` will show one large number on
  connect, not a stream of gaps.
- **The timing check is debug-only tooling.** It lives on the temporary
  debug screen, which S8B hides.

## Decisions needed

None for code. After the checkpoint, whether S5 may start depends on its
result.

## Next session

S5 (Home + mock-driven UI), once the Note 10 checkpoint passes. S4C reads
`DeviceManager.batches` and `shared/model_input.json`.

## Note 10 checkpoint — checklist

Phone: Note 10 (`RF8M83P4STZ`), debug build. Boards: left
`88:57:21:B7:74:9E` (new cable), right `38:18:2B:8A:26:D6`. 📋 = please send
me a screenshot.

0. **Before you start:**
   - Set the phone's screen timeout to 10 minutes and turn Bluetooth on.
   - Plug both boards into the laptop by USB and tell me.
   - I'll then:
     - match each `/dev/serial/by-path/…` to its CP2102 with `udevadm`
       (never the Quectel modem);
     - start `serial_log.py` for both boards **before** the phone
       connects (opening a port resets the board);
     - confirm both logs show the board streaming lines.
   - Wait for my "logs running".
1. In `mobile/` with the phone on USB: `flutter run -d RF8M83P4STZ`. If the
   phone isn't found, run `adb kill-server` and try again.
2. Settings (gear) → "BLE debug (temporary)" → **Scan**. Connect
   `88:57:21:B7:74:9E` as **LEFT** and `38:18:2B:8A:26:D6` as **RIGHT**.
   Both cards should show `STREAMING · MTU 247 · 8/pkt · N 6`.
3. **BACKLOG 27:** on the LEFT card, tap **Disconnect** then **Connect**,
   5 times, waiting for STREAMING each time. Do the same on the RIGHT card.
   📋 Both foot cards should show:
   - `dropped before START 0` and `old conn 0`;
   - `missing at start 0`, and seq gaps 0;
   - `sessions 6`;
   - `admitted before ack` with whatever number it shows (that's the
     answer to BACKLOG 27).
4. Scroll down to **Timing check** and tap **Start**.
   - Leave both boards and the phone still, about 1 m apart, for
     **10 minutes**.
   - Tap the screen every few minutes so it doesn't sleep.
   - Don't touch Connect/Disconnect during the run.
5. After 10 minutes or more, tap **Stop**. 📋 The Timing check card, plus
   both foot cards (packets, seq gaps, last packet, link losses).
6. Tell me "done". I'll then:
   - pull the file (the path is on the card);
   - stop both serial loggers by PID;
   - run `timing_check.py <file> --serial-left … --serial-right …` and
     send you the result.

**Pass** (S4 Done-when):
- both feet's clock-error bound is ≤ 10 ms in every 2-minute window, so
  L/R is within ±10 ms;
- every sample step is 20 ± 1 ms;
- 0 lost packets, 0 clamps, 0 board notify failures;
- step 3 counters as listed.

If anything fails, S5 doesn't start. The logs are what I need.
