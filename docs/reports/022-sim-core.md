# 022 — S2B: New simulator, core

Branch `work/sim-core` · 2026-10-18 · Session S2B (`docs/SESSIONS.md` §3)

## What was done

1. **Verify lines changed** (your decision, a separate commit): S2B and S2C
   in `docs/SESSIONS.md` now verify with a laptop bleak script and the
   test vectors, not the web app. The web app first connects to the new
   simulator in S3B.
2. **PlatformIO project** `firmware/simulator/`: `espressif32@7.1.3`
   (Arduino core 2.0.17), `NimBLE-Arduino@2.5.1`, board `esp32dev`. The
   flash reported an ESP32-D0WD-V3 rev 3.1. Envs: `left`, `right`
   (`FOOT_SIDE` 0/1, `FSR_COUNT` 6), `left_fsr8` (build check only) and
   `native` (host tests). The port is the CP2102's full
   `/dev/serial/by-id/…` path. PlatformIO's port wildcards only match
   `/dev/tty*` names, so a glob is not possible. The Quectel modem was never
   touched.
3. **`lib/insole_core/`**: plain C++ with no Arduino or NimBLE, built for
   both the board and the host.
   - `packets`: encoders that write exactly the contract's bytes.
   - `synth`: pure functions for walking gait, temperature and battery.
   - `data_source.h`: the only interface the BLE code reads data through.
   - `stream_session`: streaming state per connection.
   - `calibration`: the calibration JSON for N channels.
4. **`src/`**: NimBLE glue (`ble_server`) and a 50 Hz tick (`main`,
   `vTaskDelayUntil`, sample k at `epoch + k × 20 ms`).
   - **Advertising:** UUID in the advertisement, name in the scan response.
     The two together are over 31 bytes. 100 ms interval, 0 dBm, MTU 247.
     It requests a 15–30 ms interval, latency 0 and a 4 s timeout.
   - **Characteristics:** all 5.
   - **Control:** minimal `START_STREAM`/`STOP_STREAM` (your choice at plan
     approval). Other opcodes are logged and ignored until S2C.
5. **`tools/sim_check.py`** (bleak 3.0.2): self-tests its parsers against
   all 69 vector cases, then runs the connect sequence and checks the live
   stream. It exits non-zero on any failure.
6. README rewritten. BACKLOG **17** (two centrals) and **18** (scenario
   mode) added.
7. **After review** (your two follow-ups, see "Review follow-ups" below):
   normal walking scaled below `watchKpa`, and `seq`/`t0` behaviour across
   connections documented and checked live (BACKLOG 19, 20).

### Your additional requirements

| Requirement | How |
|---|---|
| Exact length, never pad (`lengthMismatch` kept) | Each packet is sized when its first sample arrives: 8 samples if they fit `mtu − 3`, else 4 (contract fallback), else none (logged). A packet is never padded. If the MTU shrinks mid-packet, that packet is dropped and its `seq` is skipped, so the app sees the loss instead of a truncated packet. NimBLE's per-peer `notify` checks neither MTU nor subscription, so the glue checks both itself |
| Battery ≥ 50 % | Drains 1 % per 6 min, floor 50 % (3900 mV). A 48 h host test confirms it never goes lower |
| Pure data functions, swappable | `DataSource` struct of 3 function pointers. `main.cpp` picks `synth::walking()` on one line. BACKLOG 18 |
| S2C: one central's STOP or disconnect must not stop the other | `SessionTable` of `StreamSession`s. STOP and disconnect touch only their own session. Each session has its own `seq`, MTU and subscriptions. Status `state` = any session streaming. Host-tested (`test_sessions_are_independent`). What's left for S2C is in BACKLOG 17 |

## Checks

| Check | Result |
|---|---|
| `pio run -e left -e right -e left_fsr8` | **Pass**: RAM 11.8 %, flash 47.0 % |
| `pio test -e native` | **Pass**: 24/24 test cases (23 + the `watchKpa` test added after review) |
| Encoders vs `shared/test_vectors/` | **Pass**: 33/33 encodable cases byte-for-byte (sensor N = 6: 15, N = 4: 3, N = 8: 3; temperature 9; status 13). The 7 parser-reject cases are excluded and listed in the test |
| The tests catch real encoder bugs | **Pass**: a wrong reserved byte and a wrong `t0` high half both failed the vector tests, then were reverted |
| `sim_check.py --selftest` | **Pass**: 69/69 cases, including kPa against the TS values |
| **Live, left, 600 s** | **Pass**, 0 failures. Details below |
| Live, right, 120 s | **Pass**: `foot_side` 1, name `SMARTINSOLE-R` |
| Live, left, 60 s, scaled walk (after review) | **Pass**: peaks hallux 39.7, meta1 49.8, meta3 44.8, meta5 31.8, midfoot 17.9, heel 59.6 kPa |
| Reconnect × 2 (after review) | **Pass**: each new connection got 0 packets before START, first `seq` 0, `t0` continued from boot (488 285 → 495 765 → 505 345 ms), no gaps |
| Wrong side is caught | **Pass**: `--side R` against the left board fails on `foot_side` |
| Serial log | Clean boot. MTU 247 → 8 samples/packet; interval 30 ms, latency 0, timeout 4000 ms; 0 notify failures; heap steady at 218 512 B |
| Web app, `mobile/`, `shared/` untouched | **Pass**: `git diff main` over those paths is empty |
| FLUTTER-PLAN §6 rules | 1 ✓ sample i = `t0 + i × 20` (tick and vectors). 8 ✓ `foot_side` set from the build flag and verified live. 12 ✓ no thresholds in the firmware. The 50 % battery floor is simulator behaviour, not an app threshold. The other rules are app-side |
| Emulator / Note 10 | Not applicable: no UI, no checkpoint in S2B |

Details of the 600 s left-foot run:

- **Sensor packets:** 3 750, every one exactly 200 bytes with `count` 8.
- **Sequence:** `seq` 0 → 3749 with no gaps, and the `t0` step is always 160 ms.
- **Rate:** 6.250 Hz over 599.8 s.
- **Temperature:** 21 packets. The first came 0.05 s after START, then one every 30 000 ms of device time, with `seq` 0…20 and quality 0.
- **Status:** notified state 1 after START and state 0 after STOP. Battery went 100 → 98 %.
- **After STOP:** no sensor or temperature packets.
- **Calibration:** a 381-byte long read, N = 6.

**Done when:** the bleak script passes a 10-minute live run, and the
encoder tests match every test vector. **Met.**

## Observations

- **BlueZ caches the device name.** After the same board was reflashed from
  `right` to `left`, the laptop kept showing `SMARTINSOLE-R` for that
  address on the first scan. This is the contract §2.1 warning, seen for
  real. `sim_check.py` now picks the device by service UUID and judges
  only by `foot_side`; the name is reported for information. S3A must do
  the same (rule 8).
- **bleak reports MTU 23 on BlueZ** unless it fetches the MTU first. The
  script does that; the link was 247.
- **Arrival vs `t0` jitter** over 10 min was −20 … +90 ms relative to the
  first packet, with no net drift (the last packet was −17 ms). That is BLE
  batching plus the laptop clock. S4 does the real ±10 ms cross-foot check.
- The ArduinoJson 7.4 host tests store short decimals like `0.000113` as
  float. That only affects test parsing, not the served text, so the test
  checks the text.

## Review follow-ups

1. **Normal walk scaled below the watch level (your decision).** The
   heel used to peak at about 125 kPa, above `watchKpa` 75. Peaks were
   rechosen against `pressure.watchKpa` in `shared/thresholds.json`,
   using the served calibration: hallux 40, meta1 50, meta3 45, meta5 32,
   midfoot 18, heel 60 kPa (N ≠ 6: 45 kPa). These include the baseline and
   noise. The firmware does not read the file. A host test
   (`test_normal_walk_stays_below_watch_kpa`) reads it and fails if any
   zone reaches 85 % of `watchKpa` (63.75 kPa) over 10 minutes, for N =
   4/6/8 and both feet. With the old heel value it fails at 124.4 kPa.
   Higher pressure belongs to scenario mode (BACKLOG 18). The 60 s live run
   matched the targets.
2. **`seq` across connections (your question).** `seq` is per connection
   and restarts at 0 on every `START_STREAM`. This is what the approved
   plan said, though the earlier report didn't spell it out. `t0_ms` is ms
   since boot and never restarts. The contract only says `seq` wraps at
   65535, so both readings comply. Recorded as a contract gap in BACKLOG
   **19** and noted in `docs/BLE-INTERFACE.md` and the README.
   - The stale packet from report 015 can't come from this simulator. It
     came from the old simulator's global stream still running after a
     disconnect. Here the session closes on disconnect, and notifications
     are per connection. Checked live by the new reconnect checks.
   - Rule 9 stays an app job: BACKLOG **20** has the S3A/S4 design (drop
     anything before START is acknowledged; the first real packet is
     `seq` 0, so a non-zero packet followed by 0 is stale; `t0` never goes
     backwards).
   - A `seq` that ran for the whole boot would hide a stale packet:
     `seq` k followed by k+1 looks continuous.
   - The web app's report-015 check looks only at `t0` going backwards, so
     it never fires against the new simulator. That's harmless, since no
     stale packets come from it, but worth knowing in S3B.

## Leftovers

- BACKLOG **17**: what S2C still needs for two centrals: advertise while
  connected, and decide what device-wide opcodes mean with two centrals.
- BACKLOG **18**: scenario mode, now also the source of low battery.
- BACKLOG **19**: contract owner to define `seq`/`t0_ms` across
  connections. BACKLOG **20**: rule 9 design for S3A/S4.
- BACKLOG **15** still applies: `FSR_COUNT` ≠ 6 builds, but the
  contract doesn't define it yet.
- The 4-sample MTU fallback is tested only on the host. BlueZ always
  negotiated 247, so it wasn't seen live.

## Next session

S2C: the remaining opcodes (`SYNC_TIME`, `SET_RATE`, `TARE`, `REBOOT`),
TARE → `offset_adc` in NVS, and a second concurrent central. Extend
`sim_check.py` for these. A second connection can come from another
adapter or a phone running nRF Connect.
