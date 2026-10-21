# firmware/simulator/

ESP32 BLE simulator of one SmartInsole foot, built to `docs/BLE-INTERFACE.md`
(Data Contract §2–3). PlatformIO + NimBLE-Arduino 2.5.1 on an ESP32-DevKitC
(`esp32dev`). Session S2B (core) and S2C (control + two centrals); see
`docs/SESSIONS.md`.

The earlier simulator the web app was tested against lives outside this
repository and is not moved here.

## Build, test, flash

From this directory:

```
pio run -e left -e right            # build both feet (FOOT_SIDE = 0 / 1)
pio test -e native                  # host tests, no board needed
pio run -e left -t upload           # flash the left foot
pio device monitor                  # serial log, 115200
pio run -e left -t erase            # wipe flash, incl. the NVS offset_adc
```

On this Linux laptop, opening the serial port resets the board
(`POWERON_RESET` in the log), even from pyserial with DTR/RTS set low
before opening. That drops every central, so start the serial log before
connecting centrals, not during a test.

`upload_port`/`monitor_port` point at the CP2102 bridge's
`/dev/serial/by-id/usb-Silicon_Labs_CP2102_…` path. On the dev laptop the
other `ttyUSB` device is the LTE modem, so never flash by `/dev/ttyUSB*`
number.

| Env | Flags | Use |
|---|---|---|
| `left`, `right` | `FOOT_SIDE=0/1`, `FSR_COUNT=6` | Flash these |
| `left_fsr8` | `FSR_COUNT=8` | Build check only. N ≠ 6 follows FLUTTER-PLAN's `2N + 12` sample layout, which isn't in the Data Contract yet (BACKLOG 15) |
| `native` | — | Unity tests of `lib/insole_core` |

`FSR_COUNT` can be 1–8. A `static_assert` keeps 8 samples within one
MTU-247 notification.

## Live check from the laptop (bleak)

```
python3 -m venv tools/.venv && tools/.venv/bin/pip install -r tools/requirements.txt
tools/.venv/bin/python tools/sim_check.py --selftest
tools/.venv/bin/python tools/sim_check.py --side L --duration 600
```

The script first checks its own parsers against `shared/test_vectors/`,
then runs the connect sequence: scan by service UUID, read status (checks
`foot_side`), read calibration (N), subscribe, `START_STREAM`, stream,
`STOP_STREAM`. It checks exact packet sizes, `seq` continuity, the 160 ms
`t0` step, the 6.25 Hz rate, temperature every 30 s, status, and that the
stream stops. Then it reconnects twice (`--reconnects`) and checks that
each new connection gets nothing before START, starts at `seq` 0, and that
`t0` keeps counting from boot. Then it exercises every control opcode on
a fresh connection (skip with `--no-control`): `SYNC_TIME`, malformed
writes, `SET_RATE` 50 and 25, unknown opcodes `0x10`/`0x7f`, a repeated
`START_STREAM`, `TARE` (the bit1 window and the new `offset_adc`), and
last `REBOOT` (clean disconnect, advertising again, `offset_adc` kept in
NVS, `t0` restarted, `seq` 0). It exits non-zero on any failure.

Two centrals: with another central (e.g. a phone in nRF Connect) connected,
run with `--two-central`. Device Status `state` is device-wide, so the
idle/streaming state checks are then reported, not judged. `--stop-file
PATH` ends the stream early when that file appears, for tests coordinated
with the other central:

```
tools/.venv/bin/python tools/sim_check.py --two-central --duration 1800 \
    --reconnects 0 --no-control --stop-file /tmp/stop
```

## Serial log and web-app capture check

Opening the CP2102 port resets the board, so start the logs before any
central connects. Use the `/dev/serial/by-path/` name: the script refuses
bare `ttyUSB` names and the LTE modem. Both scripts run on
`/usr/bin/python3` (pyserial; the check needs only the standard library):

```
/usr/bin/python3 tools/serial_log.py /dev/serial/by-path/pci-0000:00:14.0-usb-0:6:1.0-port0 left.log
/usr/bin/python3 tools/webapp_csv_check.py --selftest
/usr/bin/python3 tools/webapp_csv_check.py ~/Downloads/<sessionId>_samples.csv \
    --serial-left left.log --serial-right right.log --single-take
```

`webapp_csv_check.py` checks a CSV exported by the laptop web app's
research capture (the study fallback, `docs/STUDY-FALLBACK.md`). The CSV
has no `seq` column, so it infers lost packets from the 20 ms `tUnixMs`
spacing. It matches the web app's 5-minute clock steps to the logged
`SYNC_TIME`s (BACKLOG 28). It also checks both feet and 50 Hz.
`--assume-no-loss --write-corrected OUT` undoes those clock steps within
each take.

## Behaviour

- **Advertising:** service UUID in the advertisement, `SMARTINSOLE-L`/`-R`
  in the scan response (both don't fit in 31 bytes). 100 ms, 0 dBm. Keeps
  advertising while connected, up to 3 centrals at once (NimBLE's default
  `CONFIG_BT_NIMBLE_MAX_CONNECTIONS`; a `static_assert` checks it).
  Each connection has its own stream session: one central's STOP or
  disconnect never touches another's stream.
- **Sensor stream** (`…01`): 50 Hz samples, 8 per packet at 6.25 Hz. Every
  notification is exactly `8 + count × (2N + 12)` bytes (200 for N = 6),
  never padded or truncated. If the link MTU can't fit 8 samples it sends 4
  (contract fallback); if it can't fit 4 it sends nothing and logs it.
  `seq` is per connection and restarts at 0 on each `START_STREAM`;
  `t0_ms` is ms since boot and never restarts. A new connection gets
  nothing before its own `START_STREAM` (BACKLOG 19, 20).
- **Temperature** (`…02`): one packet at `START_STREAM`, then every 30 s.
- **Synthetic walking** stays below the app's watch level: zone peaks about
  18–60 kPa (heel ~60) against `watchKpa` 75. A host test reads
  `shared/thresholds.json` to enforce it; the firmware does not read it.
- **Status** (`…03`): read + notify on a state or battery change. Battery
  drains 1 % every 6 min and stops at 50 %, so `BATTERY_LOW` never fires on
  its own.
- **Control** (`…04`): every write must have its opcode's exact length;
  a wrong length or an opcode outside the contract (incl. `0x10
  SET_SCENARIO`, BACKLOG 18) is logged and ignored, with no state change.
  The contract has no way to report the error back.

  | Opcode | Scope | Simulator behaviour |
  |---|---|---|
  | `0x01 START_STREAM` | connection | `seq` 0, temperature at once. Ignored while already streaming (no `seq` reset) |
  | `0x02 STOP_STREAM` | connection | Stops this connection's stream only |
  | `0x03 SYNC_TIME` | connection | 8-byte unix ms, logged. `t0`/`t_ms` stay ms since boot (contract §4: the app computes the offset) |
  | `0x04 SET_RATE` | device | Only 50 Hz accepted (no-op). Other rates are logged and ignored: rule 1 fixes 20 ms spacing (BACKLOG 22) |
  | `0x05 TARE` | device | Each channel's minimum over one stride (55 samples); packets in that window carry flags bit1. Result stored in NVS and served as `offset_adc` |
  | `0x06 REBOOT` | device | 300 ms later: stop advertising, disconnect every central, restart |
- **Calibration** (`…05`): JSON for N channels using the contract §5.1
  example coefficients (381 bytes for N = 6, so it is a long read).
  `offset_adc` is 12 until a TARE, then the tared value from NVS (survives
  REBOOT and power cycles). Centrals already connected see a new value
  only when they read again (BACKLOG 23).

## Layout

- `lib/insole_core/`: plain C++, no Arduino or NimBLE, built for the board
  and the host. `packets` (encoders), `stream_session` (per-connection
  streaming state), `synth` (pure synthetic walking, temperature, battery),
  `calibration`, `control` (opcode parsing), `tare`, `protocol` (UUIDs,
  sizes).
- `src/`: `ble_server` (NimBLE glue) and `main` (50 Hz tick).
- Data generation is reached only through a `DataSource`
  (`data_source.h`), so a scenario mode can swap it out (BACKLOG 18).
  Streaming state is per connection (BACKLOG 17, done in S2C).
