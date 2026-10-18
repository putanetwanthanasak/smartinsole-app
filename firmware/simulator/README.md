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
```

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
stream stops. It exits non-zero on any failure.

## Behaviour

- **Advertising:** service UUID in the advertisement, `SMARTINSOLE-L`/`-R`
  in the scan response (both don't fit in 31 bytes). 100 ms, 0 dBm. One
  central at a time until S2C.
- **Sensor stream** (`…01`): 50 Hz samples, 8 per packet at 6.25 Hz. Every
  notification is exactly `8 + count × (2N + 12)` bytes (200 for N = 6),
  never padded or truncated. If the link MTU can't fit 8 samples it sends 4
  (contract fallback); if it can't fit 4 it sends nothing and logs it.
  `seq` restarts at 0 on each `START_STREAM`.
- **Temperature** (`…02`): one packet at `START_STREAM`, then every 30 s.
- **Status** (`…03`): read + notify on a state or battery change. Battery
  drains 1 % every 6 min and stops at 50 %, so `BATTERY_LOW` never fires on
  its own.
- **Control** (`…04`): only `0x01 START_STREAM` and `0x02 STOP_STREAM` so
  far, each applying to the connection that wrote it. Other opcodes are
  logged and ignored until S2C.
- **Calibration** (`…05`): static JSON for N channels using the contract
  §5.1 example coefficients (381 bytes for N = 6, so it is a long read).
  TARE and NVS storage come in S2C.

## Layout

- `lib/insole_core/`: plain C++, no Arduino or NimBLE, built for the board
  and the host. `packets` (encoders), `stream_session` (per-connection
  streaming state), `synth` (pure synthetic walking, temperature, battery),
  `calibration`, `protocol` (UUIDs, sizes).
- `src/`: `ble_server` (NimBLE glue) and `main` (50 Hz tick).
- Data generation is reached only through a `DataSource`
  (`data_source.h`), so a scenario mode can swap it out (BACKLOG 18).
  Streaming state is per connection, ready for two centrals (BACKLOG 17).
