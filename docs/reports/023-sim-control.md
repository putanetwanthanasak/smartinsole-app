# 023 — S2C: Simulator control, calibration, two centrals

Branch `work/sim-control` · 2026-10-18 · Session S2C (`docs/SESSIONS.md` §3)

## What was done

1. **Control parsing** (`lib/insole_core/src/control.{h,cpp}`, new, pure
   C++). Every contract §3.4 opcode has one exact length (`SYNC_TIME` 9
   bytes, `SET_RATE` 2, the others 1). A wrong length is `Malformed`; an
   opcode outside the contract (incl. `0x10 SET_SCENARIO`) is `Unknown`.
   Both are logged and ignored with no state change.
2. **Opcodes**, with the scope decided at plan approval:

   | Opcode | Scope | Behaviour |
   |---|---|---|
   | `START_STREAM` | connection | As S2B. **Changed:** ignored while already streaming, so a repeated write can't reset `seq` mid-stream |
   | `STOP_STREAM` | connection | As S2B |
   | `SYNC_TIME` | connection | 8-byte unix ms logged with the device time. `t0`/`t_ms` stay ms since boot (contract §4) |
   | `SET_RATE` | device | 50 → no-op; other rates logged and ignored (rule 1; your decision) |
   | `TARE` | device | Per-channel minimum over one stride (55 samples) (your decision). flags bit1 on the packets in that window. Stored in NVS (`Preferences`), served as `offset_adc` |
   | `REBOOT` | device | 300 ms later: stop advertising, disconnect every central, `esp_restart()` |
3. **TARE** (`lib/insole_core/src/tare.{h,cpp}`, new). `buildCalibrationJson`
   now takes per-channel offsets. `StreamSession::addSample` takes a
   `calibrating` mark and ORs bit1 into the packet.
4. **Two centrals.** The simulator keeps advertising while fewer than 3
   centrals are connected. `static_assert`s: ≥ 2 sessions, and ≤ NimBLE's
   `CONFIG_BT_NIMBLE_MAX_CONNECTIONS` (3).
5. **`tools/sim_check.py`**:
   - The main run now sends `SYNC_TIME` before `START_STREAM` (the full
     FLUTTER-PLAN §5 connect sequence).
   - A new opcode phase (`--no-control` skips it).
   - `--two-central`: device-wide `state` is reported, not judged.
   - `--stop-file`: ends the stream when that file appears.
6. **Docs:**
   - BACKLOG **17** resolved. BACKLOG **20** revised as you asked: checks 1
     and 3 are the design; the `seq` look-ahead is now an optional S3A idea.
   - New BACKLOG items **21–25**. 21 is the S8B item you asked for.
   - README and the `BLE-INTERFACE.md` simulator notes updated.

The web app, `mobile/` and `shared/` are untouched (`git diff main` over
those paths is empty). The normal walk stays below `watchKpa` and the
battery floor at 50 %, both as in S2B and still tested.

### Found and fixed during Verify

- **REBOOT took 4.3 s to be noticed.** With a bare `esp_restart()` the
  central only learned of the drop at the 4 s supervision timeout. REBOOT
  now disconnects every central first, and the drop is seen in **0.37 s**.
- **REBOOT re-advertised the old boot.** `advertiseOnDisconnect` restarted
  advertising in the 200 ms before the restart, so a scan could find the
  board before it rebooted. It is now turned off in the reboot task. After
  the fix the scan found the board 1.6 s after the write, after the new
  boot's advertising line (+1.35 s).

## Checks

| Check | Result |
|---|---|
| `pio run -e left -e right -e left_fsr8` | **Pass**: RAM 11.9 %, flash 47.4 % |
| `pio test -e native` | **Pass**: 34/34 (24 from S2B + 10 new: `test_control` 7, `test_session` 2, `test_synth` 1) |
| Encoders vs `shared/test_vectors/` | **Pass**: unchanged 33/33 byte-for-byte (inside the 34) |
| `sim_check.py --selftest` | **Pass**: 69/69 |
| Live, single central, full (120 s stream, 2 reconnects, opcode phase, REBOOT) | **Pass**: 56/56 checks (after the clean-disconnect fix) |
| Live, 15 s stream + 1 reconnect + opcode phase, after both fixes | **Pass**: 52/52 |
| Two centrals (laptop + Note 10), laptop side | **Pass**: 22/22, 4 device-wide state checks reported only. Details below |
| Two centrals, phone side, from the serial log | **Pass**. Details below |
| Two centrals, what you saw on the phone | **Pass** (your report): at MTU 120 the `…45901` value looked shorter (the 104-byte length itself comes from the serial log: MTU 120 → 4 samples/packet), and it kept changing after the laptop stopped |
| FLUTTER-PLAN §6 rules | 1 ✓ the t0 step stays 160 ms through `SET_RATE 25` and after REBOOT. 8 ✓ `foot_side` checked after REBOOT. 9 ✓ no stale packets: nothing arrives before START, per-connection `seq`, BACKLOG 20 revised. 12 ✓ no thresholds in the firmware; `sim_check` reads `watchKpa` from `shared/thresholds.json`. The other rules are app-side |
| Emulator / Note 10 checkpoint | Not applicable: no UI. The phone was a test central only |

### Opcode phase, live (one connection, 85 packets)

- **`seq` and timing:** `seq` 0…84 with no gaps or resets; the `t0` step is
  always 160 ms; 6.251 Hz across all the writes below.
- **Writes ignored as designed:** a 7-byte `SYNC_TIME`, `SET_RATE 25`,
  `0x10`, `0x7f`, a 2-byte `02 02` and a second `START` changed nothing. The
  serial log shows each one ignored with its reason. A real `STOP` still
  stops the stream.
- **TARE flag:** one contiguous run of 8 packets with bit1 set (1.1 s of
  samples, spread over 8 packets), none before the write, clear afterwards,
  no other flag bits.
- **TARE offsets:** `offset_adc` went from 12 (default) to
  `[18, 18, 20, 18, 20, 19]` on the first tare. The walking peak with the
  new offsets was 57.0 kPa, below `watchKpa` 75. The NVS write took 1–6 ms.
- **REBOOT:** the write was acknowledged in 0.036 s; clean disconnect at
  0.37 s; `rst:0xc (SW_CPU_RESET)` 307 ms after the write. After the
  restart: idle, `foot_side` 0, `offset_adc` identical (from NVS), `t0`
  163 106 → 1 536 ms, `seq` 0, no gaps.

### Two centrals, live

The phone (Note 10, nRF Connect) connected as conn 1 while the laptop
(bleak, conn 0) was already streaming, so advertising while connected
works. Timeline from the serial log (laptop stream 18:57:50 → 19:02:53):

| Time | Phone (conn 1) | Laptop (conn 0) |
|---|---|---|
| 18:57:59 | connects, MTU 23 | streaming |
| 18:58:37 | `START` at MTU 23 → 0 samples/packet, nothing sent, drops counted (never truncated) | streaming |
| 18:59:04 | a second `START` → "already streaming, ignored" | streaming |
| 19:00:40 | MTU 247 → 8 samples/packet, packets flow | streaming |
| 19:01:26 | `STOP` | streaming |
| 19:01:52 | disconnects | streaming |
| 19:01:53 | reconnects; MTU **120 → 4 samples/packet** | streaming |
| 19:02:27 | `START`; 12.5 packets/s (= 50 Hz) | streaming |
| 19:02:53 / 19:02:58 | **keeps streaming**: +125 packets per 10 s, 0 notify failures | `STOP` / disconnect |

- **Laptop result:** 1 896 packets, all 200 bytes, `count` 8, `seq` with no
  gaps, 6.250 Hz over 303.2 s, temperature every 30 s.
- **Device state:** `state` stayed 1 after the laptop's STOP, because the
  phone was streaming. Correct for a device-wide field; reported, not judged.
- **MTU 120 check (your addition):** the first live check of the
  contract's 4-sample MTU fallback (S2B tested it on the host only). The
  4-sample packets went to the phone while the laptop got 8-sample packets
  at the same time.
- **Throughout:** heap steady at 218 292 B (one dip to 214 844 B during the
  REBOOT task); 0 notify failures in the whole log.

## Observations

- **Opening the serial port resets the board.** `POWERON_RESET` appears
  every time the logger opens the CP2102, even with pyserial's DTR/RTS set
  low before opening. At 18:57:39 this ended a phone stream that was
  already running. Start the serial log before connecting centrals
  (README).
- **The CP2102 re-enumerated by itself at 18:48** and the two `ttyUSB`
  numbers swapped: the CP2102 became `ttyUSB0` and the Quectel modem
  `ttyUSB1`. The `setfacl` you had run on `ttyUSB1` then applied to the
  modem. Nothing here opens a port by number; flashing and logging use the
  `/dev/serial/by-id/…CP2102…` path, so the modem was never opened. The
  cause of the re-enumeration is unknown. **This Claude Code process lacks
  the `dialout` group**, although `/etc/group` lists you in it; log out and
  back in so the ACL workaround isn't needed.
- **Android kept a 48.75 ms connection interval** (a brief 7.5 ms) and a
  5 s supervision timeout, against the requested 15–30 ms and 4 s. The
  stream still arrived in full. BACKLOG 25 has the S3A follow-up
  (`requestConnectionPriority(HIGH)`).
- **A START at MTU 23 streams nothing until the MTU rises.** The session
  is "streaming" but every sample is dropped (0 samples fit). Once the MTU
  rose, packets started at `seq` 0, because no packet had been cut yet. An
  app that forgets `requestMtu` gets silence, not truncated packets.

## Leftovers (BACKLOG)

- **21.** The app must guard REBOOT/TARE (device-wide) in S8B: a
  confirmation dialog, no research capture running (or hide them during
  the study), and lift the foot before a real TARE.
- **22.** `SET_RATE` vs rule 1 (contract owner).
- **23.** No "calibration changed" signal after TARE (contract owner).
- **24.** Malformed control writes can't be reported back (contract owner).
- **25.** Android connection interval (S3A).
- **15, 18, 19** still open, as in S2B.

## Decisions needed

1. ~~Phone-side confirmation~~ — answered: (a) the value looked shorter at
   MTU 120, (b) it kept changing after the laptop stopped at 19:02:53.
2. **Optional:** remove the stray ACL from the modem:
   `sudo setfacl -x u:pumon /dev/ttyUSB1`, after checking with
   `ls -l /dev/serial/by-id/` that `ttyUSB1` is still the Quectel.

## Next session

S3A (BLE, both feet) needs S2A and S2C merged and **both boards flashed**
(`pio run -e left -t upload`, then the second board with `-e right`).
Things S3A should bring in from here:
- the BACKLOG 20 design (drop before the START ack; `t0` per connection);
- `requestConnectionPriority(HIGH)` (BACKLOG 25);
- re-reading calibration if bit1 is seen (BACKLOG 23).
