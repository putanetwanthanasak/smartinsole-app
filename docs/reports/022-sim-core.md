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
| `pio test -e native` | **Pass**: 23/23 test cases |
| Encoders vs `shared/test_vectors/` | **Pass**: 33/33 encodable cases byte-for-byte (sensor N = 6: 15, N = 4: 3, N = 8: 3; temperature 9; status 13). The 7 parser-reject cases are excluded and listed in the test |
| The tests catch real encoder bugs | **Pass**: a wrong reserved byte and a wrong `t0` high half both failed the vector tests, then were reverted |
| `sim_check.py --selftest` | **Pass**: 69/69 cases, including kPa against the TS values |
| **Live, left, 600 s** | **Pass**, 0 failures. Details below |
| Live, right, 120 s | **Pass**: `foot_side` 1, name `SMARTINSOLE-R` |
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

## Decision needed

1. **The synthetic heel peaks at about 125 kPa** (ADC 2630). The other
   zones peak at 19–75 kPa. That puts the heel above the app's
   `watchKpa` 75 on every step, though below `alertKpa` 200. Realistic
   heel pressure in walking is often higher still, but it means the
   simulator never shows an all-"Safe" Home. Keep it, or scale the normal
   walk to stay under 75 kPa and leave higher pressure to scenario mode
   (BACKLOG 18)? Either is one constant in `synth.cpp`.

## Leftovers

- BACKLOG **17**: what S2C still needs for two centrals: advertise while
  connected, and decide what device-wide opcodes mean with two centrals.
- BACKLOG **18**: scenario mode, now also the source of low battery.
- BACKLOG **15** still applies: `FSR_COUNT` ≠ 6 builds, but the
  contract doesn't define it yet.
- The 4-sample MTU fallback is tested only on the host. BlueZ always
  negotiated 247, so it wasn't seen live.

## Next session

S2C: the remaining opcodes (`SYNC_TIME`, `SET_RATE`, `TARE`, `REBOOT`),
TARE → `offset_adc` in NVS, and a second concurrent central. Extend
`sim_check.py` for these. A second connection can come from another
adapter or a phone running nRF Connect.
