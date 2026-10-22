# 026 — S4: DeviceManager + timing (Flutter)

Branch `work/flutter-device-manager` · 2026-10-22 · Session S4 (`docs/SESSIONS.md` §3)

**Status: for the 10-minute timing run (2026-10-22), `timing_check.py`
reports PASS. This is with an L/R measurement method changed after the run
(section "Note 10 checkpoint results"); the user's acceptance of that
result is still needed. Checklist step 3 (5× reconnect per foot) is
waiting on the user.** All automated checks pass (242 tests, analyze clean,
mutation checks caught), and the emulator checks are done.

S4's Done-when is "L/R offset ≤ ±10 ms, 20 ms spacing, no lost packets".
In the 10-minute run:
- L/R stayed within ±3.4 ms (±6.4 ms including the method's ±3 ms
  uncertainty);
- the sample spacing stayed within 19.75–20.25 ms;
- 0 packets were lost.

The user accepted the method change before the rerun (see that
section). Accepting the result itself is the user's call.

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

The method below is what the plan approved and what this report ran
first. **It was replaced after the Note 10 run** (see "Note 10 checkpoint
results"). It is kept in `timing_check.py` as a secondary figure.

- **Write-latency bound (planned method, now secondary).**
  - For one foot the app's offset is **A = θ + n**. θ is the true offset
    between the board's clock and the phone's. n ≥ 0 is the smallest
    notification latency the 30 s minimum found.
  - The board logs each `SYNC_TIME` as "unix U at device D". U is the
    phone time the app wrote. So **U − D = θ − w**, where w ≥ 0 is the
    write's latency.
  - So **B = A − (U − D) = n + w ≥ n** bounds the foot's error from
    above, and the L/R error n_L − n_R lies in [−B_R, B_L].
  - The bound needs no shared clock, but it **can't go below the write's
    latency w**.
- **Laptop clock (primary since the Note 10 run).** Both boards' serial
  logs are stamped by one laptop clock, so each `SYNC_TIME` line gives
  that board's offset φ = laptop − D, plus a print/USB delay ≥ 0.
  - **Per board:** fit the crystal drift against the laptop (a line
    through each 120 s window's minimum), remove it, and take the floor
    over ±60 s. That floor is φ with the minimum delay.
  - **For the same instant**, the two feet's app times differ by
    **e = (φ_R − φ_L) + A_L − A_R**. The right foot's φ and A are
    interpolated to each left `SYNC_TIME`.
  - **Pass:** |e| ≤ 10 ms in every 120 s window.
  - **Uncertainty: ±3 ms**, a worst-case sum of four parts:
    - ±1 ms: D is an integer `millis()`;
    - ±1 ms: the laptop's ms stamp and the 1 ms USB frame, as the
      difference between the two boards' minimum delays;
    - ±1 ms: the board stamps sample k as `t0 + 20k`, which can be up to
      1 ms before its `millis()`;
    - 0.03 ms: the two boards' `SYNC_TIME` lines differ in length, at
      115200 baud.
  - **Evidence the USB delay is steady:** in this run each board's
    delay above its floor had a median of 0.6–0.7 ms and a p90 of
    1.0–1.3 ms.
  - The method assumes both boards' serial delays have the same minimum
    (same CP2102 chip, driver and laptop). Any difference between them is
    what the ±1 ms USB term covers.

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
| Note 10, 10-min timing run | **checker: PASS with the laptop-clock method; user acceptance pending** (adopted after the run, accepted by the user): \|L/R\| ≤ 3.38 ms, ±3 ms uncertainty; 0 lost; steps 19.75–20.25 ms; 0 clamps; 0 notify failures. The planned write-latency bound gave 27 / 66 ms (now secondary). |
| Note 10, step 3 (5× reconnect per foot, BACKLOG 27) | **waiting on user** |

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

## Note 10 checkpoint results (2026-10-22)

**Setup:**
- Phone: Note 10 (`RF8M83P4STZ`), debug build.
- Left board `88:57:21:B7:74:9E` on laptop USB port 6 (new cable).
- Right board `38:18:2B:8A:26:D6` on port 7.
- Run: 12:35:13 to 12:45:51, 10.6 min.
- Evidence in `docs/reports/026-flutter-device-manager/`:
  - `note10-timing-20261022-123513.log`: the app's timing log, pulled
    with `adb exec-out run-as`;
  - `note10-serial-left.log` and `note10-serial-right.log`;
  - `note10-timing-check.txt`: the checker's output;
  - `note10-1-timing-after-stop.jpg`: the user's screenshot.

**Serial log setup:**
- The first open of the right board's port read only garbage, even though
  `stty` showed 115200 and no other process had the port open. Probably
  the CP2102 was probed right after it was plugged in (ModemManager is
  active). Killing that logger by PID and reopening it gave a clean log.
  This happened before the phone connected, so the run was not affected.
- The left log starts with buffered garbage and repeated reset banners
  from the cable being plugged in. Both boards then booted cleanly at
  port open (12:20:08 and 12:23:21).

**Result with the planned method: FAIL.** The write-latency bound's worst
2-minute window was 26.95 ms (left) and 66.02 ms (right), against 10 ms.
Behind those numbers:
- **B never got low.** B = n + w had a minimum of 23.2 ms (left) and
  51.0 ms (right) over 63 writes each.
- **The writes were slow.** In the app, each write call took 29–75 ms
  (left) and 57–139 ms (right) to complete.
- **The right foot's writes were slower.** Both feet's `SYNC_TIME`s go
  out within 1 ms of each other. The right foot's write consistently
  takes about 30 ms longer than the left's, most likely because it waits
  behind the left's in Android's BLE stack (not proven).

**So the method, not the timing, was the limit.** The bound can't go
below the write's one-way latency w, which on the Note 10 was about
20 ms or more for the left foot and 45 ms or more for the right (B minus
a few ms of n). A 10 ms limit can't be shown that way on this phone.
The plan didn't foresee it.

**Method change after the run (accepted by the user).** The laptop-clock
comparison above became the primary L/R check. The write-latency bound is
kept as a secondary figure. Both were run on this run's logs; no new run
was made.
- Changed in `timing_check.py`. The self-test now covers:
  - feet 13 ms apart (fails) and 6 ms apart (passes);
  - Note 10 write latency of 29–139 ms (passes);
  - boards drifting +30 / −10 ppm (passes), and the same drift with the
    feet 13 ms apart (fails);
  - USB delay jitter of 1–25 ms (passes);
  - serial lines without laptop time (fails).

**Result with the laptop clock: the checker reports PASS** (for the user
to accept).

| | Left | Right |
|---|---|---|
| Packets (app) / lost | 4 087 / 0 | 4 109 / 0 |
| Sample step | 19.75–20.25 ms | 19.75–20.25 ms |
| Clock clamps | 0 | 0 |
| Board notify failures / mtu-drops | 0 / 0 | 0 / 0 |
| Drift against the laptop | −32.6 ppm | +13.2 ppm |
| Serial delay above floor (median / p90) | 0.7 / 1.0 ms | 0.6 / 1.3 ms |

- **L/R error** e = unix_L − unix_R for one instant, over 62 points:
  min −1.99, median +0.70, max +3.38 ms.
- **Worst |e| per 120 s window:** 2.0, 2.5, 1.6, 2.5, 3.4, 1.6 ms.
- **With the ±3 ms uncertainty:** at most 6.41 ms, inside ±10 ms.

**Drift correction matters.** A first cross-check, done in chat before the
script changed, took only a plain local minimum. It got −1.8 to +7.4 ms
(39 points, joined on identical U only). The left board's −33 ppm drift
biases a plain ±60 s minimum by up to about 2 ms, which is why the script
fits and removes the drift first.

`admitted before START ack` was 0 on both feet, but each foot connected
only once in this run, so BACKLOG 27 is untested until step 3 is done.

## Leftovers

- **BACKLOG 27** is fixed in code. Checklist step 3 (5× reconnect per
  foot) is still to run. `admittedBeforeAck` will show whether the race
  really happens.
- **The L/R check needs both boards logged on one laptop.** Real insoles
  in S9 won't have a serial port, so the same check won't work there. A
  different reference would be needed then, e.g. a shared tap event.
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

The user accepted the method change on 2026-10-22. Still needed:
- the user's acceptance of the timing result;
- the step 3 result.

S5 waits on both.

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

**Pass** (S4 Done-when), as given before the run:
- both feet's clock-error bound is ≤ 10 ms in every 2-minute window, so
  L/R is within ±10 ms. Replaced after the run by the laptop-clock
  check, |e| ≤ 10 ms in every 2-minute window (see the results section);
- every sample step is 20 ± 1 ms;
- 0 lost packets, 0 clamps, 0 board notify failures;
- step 3 counters as listed.

If anything fails, S5 doesn't start. The logs are what I need.
