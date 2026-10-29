# BLE Interface — working summary

**STATUS: FILLED IN FROM DATA CONTRACT v1.1.** `docs/DATA-CONTRACT.md` is the
source of truth — this file is a convenience extract of the BLE-relevant
sections (2, 3, 4, 5.1, part of 8) for whoever implements
`WebBleDataSource`, so they don't have to keep the full contract open. If the
two ever disagree, the contract wins and this file is what's wrong; re-check
this file against it, not the other way around.

Two sibling projects (outside this repo, see `CLAUDE.md`) already implement
this interface end to end and are verified working against real hardware: an
ESP32 BLE simulator (NimBLE-Arduino 2.x, advertises as `SMARTINSOLE-L`) and a
standalone Web Bluetooth test page. Neither is checked into this repo.

**v1.6 (2026-10-29, S8D): 8 FSR + 8 NTC per foot.** The wire sections
below are updated to DATA-CONTRACT v1.6 (§3.1, §3.2, §5.1, Appendix C):
28-byte samples and 232-byte sensor packets at N = 8, a 32-byte
temperature packet with 8 sites, a calibration JSON with exactly 8
channels. The Flutter app (`mobile/lib/ble/`) implements v1.6; the frozen
web app (`src/ts/`) still implements v1.5 and cannot read v1.6 boards
(report 037).

---

## Advertising

| Field | Value |
| --- | --- |
| Device name (left) | `SMARTINSOLE-L` |
| Device name (right) | `SMARTINSOLE-R` |
| Advertising interval | 100 ms (while unconnected) |
| TX power | 0 dBm |

**Scan/filter by Service UUID, not device name** — the OS can cache a
device's advertised name incorrectly; the name is not reliable for
filtering.

## GATT service

**Service UUID:** `f0a5c000-9b4d-4e8a-a3c1-72d6e1b45900`

## Characteristics

All characteristic UUIDs share the service's prefix; only the last two hex
digits differ.

| Characteristic | UUID | Properties | Frequency | Size |
| --- | --- | --- | --- | --- |
| Sensor Stream | `f0a5c000-9b4d-4e8a-a3c1-72d6e1b45901` | Notify | 6.25 Hz (8 samples/packet → 50 Hz effective sample rate) | 232 bytes at N = 8 (v1.6) |
| Temperature | `f0a5c000-9b4d-4e8a-a3c1-72d6e1b45902` | Notify | 1/30 Hz | 32 bytes (v2, v1.6) |
| Device Status | `f0a5c000-9b4d-4e8a-a3c1-72d6e1b45903` | Read, Notify | on change | 8 bytes |
| Control | `f0a5c000-9b4d-4e8a-a3c1-72d6e1b45904` | Write | on demand | 1–16 bytes |
| Calibration | `f0a5c000-9b4d-4e8a-a3c1-72d6e1b45905` | Read | once, at connect | up to 512 bytes |

That's five characteristics. The first version of this file (written before
the contract landed) guessed there might be a sixth, unidentified one — there
isn't; five is the full set per the contract.

## Connection parameters

| Parameter | Target | Fallback |
| --- | --- | --- |
| MTU | 247 bytes | if negotiation fails → drop to 4 samples/packet |
| Connection interval | 15–30 ms | — |
| Slave latency | 0 | — |
| Supervision timeout | 4000 ms | — |

At N = 8 a full packet is 232 bytes (fits MTU 247); the 4-sample fallback
needs 120 bytes, i.e. MTU ≥ 123. The app treats a smaller MTU as a visible
`mtuTooSmall` problem.

**Android must call `requestMTU(247)` after connecting and *before* enabling
notifications.** iOS negotiates MTU automatically. This is the same fact
already verified against real hardware — see "Behavioural facts" below.

---

## Sensor Stream packet (232 bytes at N = 8, little-endian)

One packet carries **8 samples**, sent at 6.25 Hz → 50 Hz effective sample
rate. Samples are 20 ms apart, fixed: sample `i`'s time is `t0_ms + (i × 20)`.
A packet is `8 + count × (2N + 12)` bytes, N from the calibration JSON; v1.6
requires N = 8.

### Header (8 bytes)

| Offset | Length | Type | Field | Description |
| --- | --- | --- | --- | --- |
| 0 | 2 | uint16 | `seq` | Packet sequence number, wraps at 65535 — used to detect dropped packets |
| 2 | 4 | uint32 | `t0_ms` | Time of the first sample in this packet, ms since device boot (NOT unix time — see SYNC_TIME below) |
| 6 | 1 | uint8 | `count` | Sample count in this packet (normally 8) |
| 7 | 1 | uint8 | `flags` | bit0 = saturated reading, bit1 = calibration in progress |

**`seq` and `t0_ms` across connections: not in the contract yet** (BACKLOG
19). The contract only says `seq` wraps at 65535. The new simulator
(`firmware/simulator/`, S2B) does this: `seq` is per connection and
restarts at 0 on every `START_STREAM`; `t0_ms` is ms since boot and never
restarts. A new connection receives nothing before its own `START_STREAM`.
The old sibling-repo simulator instead restarted `t0_ms` on each
`START_STREAM` (report 015). How the app uses this to drop stale packets
(rule 9) is BACKLOG 20. A `REBOOT` restarts `t0_ms` near 0, so "`t0` never
goes backwards" holds only within one connection.

### Sample block (28 bytes × 8 at N = 8, immediately following the header)

| Offset (within block) | Length | Type | Field | Unit / scaling |
| --- | --- | --- | --- | --- |
| +0 | 16 | uint16 × 8 | `fsr[0..7]` | raw ADC, 0–4095 (see FSR scaling below — device sends raw, app computes kPa) |
| +16 | 6 | int16 × 3 | `accel[x,y,z]` | 4096 LSB/g |
| +22 | 6 | int16 × 3 | `gyro[x,y,z]` | 32.8 LSB/(°/s) |

### Sensor sites (v1.6; index must match on both feet)

FSR i and NTC i sit together: index i is FSR channel i and temperature
site i. Positions in mm (left foot from above, x from the lateral edge,
y from the back of the heel; the right foot mirrored) are in
DATA-CONTRACT §3.1 and `shared/sensor_layout.json`.

| Index | Site | App id |
| --- | --- | --- |
| 0 | Hallux | `hallux` |
| 1 | 1st metatarsal head (MTH1) | `meta1` |
| 2 | 2nd–3rd metatarsal heads (MTH2–3) | `meta3` |
| 3 | 5th metatarsal head (MTH5) | `meta5` |
| 4 | Lateral midfoot | `midfoot` |
| 5 | Heel centre | `heel` |
| 6 | Medial arch (new in v1.6) | `medialArch` |
| 7 | Lateral heel (new in v1.6) | `lateralHeel` |

Indexes 0–5 keep their v1.5 meaning. The frozen web app's
`FSR_CHANNEL_ORDER` (`src/ts/constants.ts`) has only 0–5.

---

## Temperature packet v2 (32 bytes, little-endian, v1.6)

| Offset | Length | Type | Field | Unit |
| --- | --- | --- | --- | --- |
| 0 | 2 | uint16 | `seq` | — |
| 2 | 4 | uint32 | `t_ms` | ms since device boot |
| 6 | 1 | uint8 | `count` | number of sites, must be 8 |
| 7 | 1 | uint8 | `reserved` | = 0, ignored |
| 8 | 16 | int16 × 8 | `temp[0..7]` | 0.01 °C (e.g. 3180 = 31.80 °C), site i = §3.1 index i |
| 24 | 8 | uint8 × 8 | `quality[0..7]` | per site: 0 = normal, 1 = poor contact, 2 = sensor fault |

**`-32768` means "could not read"** — the app must render that as a
no-data state, never as a number (`TempPacket.celsius[i]` is null in the
Flutter app).

The Flutter app rejects and counts, per foot on Diagnostics: any length
other than 32, including the v1.5 12-byte packet (`tempLength`); a count
other than 8 (`tempCount`); a quality byte above 2 (`invalidQuality`).
The v1.5 12-byte layout (`temp_forefoot`, `temp_heel`, one `quality`) is
kept only in `shared/test_vectors/temperature.json`, as the record of v1.

---

## Device Status packet (8 bytes, little-endian)

| Offset | Length | Type | Field | Description |
| --- | --- | --- | --- | --- |
| 0 | 1 | uint8 | `battery_pct` | 0–100 |
| 1 | 2 | uint16 | `battery_mv` | actual voltage, mV |
| 3 | 1 | uint8 | `foot_side` | 0 = left, 1 = right |
| 4 | 1 | uint8 | `fw_major` | firmware version |
| 5 | 1 | uint8 | `fw_minor` | — |
| 6 | 1 | uint8 | `state` | 0 = idle, 1 = streaming, 2 = error |
| 7 | 1 | uint8 | `error_code` | 0 = none, see error codes below |

### Error codes (`error_code`)

| Code | Meaning |
| --- | --- |
| 0 | Normal |
| 1 | IMU not responding |
| 2 | NTC (thermistor) read failure |
| 3 | ADC saturated (suspected short circuit) |
| 4 | Battery voltage critically low |
| 5 | Internal storage full |

---

## Control opcodes (App → Insole, write to Control characteristic)

| Opcode | Name | Payload | Effect |
| --- | --- | --- | --- |
| `0x01` | `START_STREAM` | — | Begin sending sensor + temperature data |
| `0x02` | `STOP_STREAM` | — | Stop sending (enters power-save mode) |
| `0x03` | `SYNC_TIME` | uint64 (unix ms) | Set the device's time reference from the phone — see clock sync below |
| `0x04` | `SET_RATE` | uint8 (Hz) | Change sample rate (for testing) |
| `0x05` | `TARE` | — | Zero the FSR baseline |
| `0x06` | `REBOOT` | — | Restart the device |

**Simulator behaviour (S2C, not in the contract):** `START`/`STOP`/`SYNC_TIME`
act on the connection that wrote them; `SET_RATE`/`TARE`/`REBOOT` act on
the whole device, so with two centrals both see them (BACKLOG 17, 21).
Every write must be its opcode's exact length (`SYNC_TIME` 9 bytes,
`SET_RATE` 2, others 1); anything else is ignored (BACKLOG 24).
`SET_RATE` accepts only 50 Hz (BACKLOG 22). See
`firmware/simulator/README.md`.

---

## Clock synchronization between the two feet

The two ESP32s free-run independent clocks — `t_ms`/`t0_ms` in every packet
is milliseconds since that device's own boot, not unix time, and the two
feet's boots don't align. Comparing raw `t_ms` across feet directly breaks
symmetry and CoP calculations.

**Procedure:**
1. On successful connect, write `SYNC_TIME` with the current unix timestamp
   to **both** feet.
2. Store `offset = unix_time_at_send − most_recently_received_t_ms`,
   per side, independently.
3. Convert every sample to unix time as `t_unix = t_ms + offset`.
4. Repeat every 5 minutes to correct for clock drift.

**Acceptance criterion:** cross-foot timing error must stay within **±10 ms**
(half a sample interval).

This is the wire-level justification for Convention #5 in `CLAUDE.md`
("`lastSampleAt` is arrival time, never the device's own `tUnixMs`") — until
`SYNC_TIME` has actually been exchanged for a given connection, that device's
`t_ms` has no known relationship to unix time at all, let alone a
drift-corrected one.

---

## FSR scaling — raw ADC → kPa

**Device sends raw ADC; the app computes kPa.** The calibration table
(per-channel curve-fit coefficients) lives on the insole itself (ESP32 NVS),
read once at connect via the Calibration characteristic
(`...b45905`) — this is what lets a patient swap insoles or phones without
re-entering calibration data.

```
adc_corrected = max(0, adc − offset_adc)   // offset_adc = the zero-point reading (no load), per channel
V_out         = (adc_corrected / 4095) × 3.3
R_fsr         = R_pulldown × (3.3 − V_out) / V_out
F_newton      = a × R_fsr^b        // a, b are per-channel, from the calibration blob
P_kPa         = F_newton / A_sensor / 1000   // F_newton / A_sensor is Pa, not kPa — the /1000 is required
```

**`offset_adc` — resolved, was an open gap through report 005:** it's the
raw ADC reading from that channel under no load, i.e. the stored result of
a TARE (control opcode `0x05`, "ปรับ zero-point ของ FSR" — the contract
defines no second zero-point mechanism, so TARE's result and this field are
the same concept). Subtracted from the raw reading before anything else,
clamped at 0 — a reading below the channel's own zero-point means drift or
sensor noise, not negative pressure.

**`/1000` — resolved, was an open gap through report 007:** `F_newton /
A_sensor` (N / m²) is Pascals, not kilopascals — this formula never showed
the conversion despite the field being called `P_kPa`. Confirmed against
instrumented hardware logs, not just unit analysis: reported "raw-ADC-
passthrough" readings that looked like the raw ADC value with a decimal
fraction attached were this bug, not a separate one — e.g. rawAdc=345
produced 5411 Pa by hand and 5385.22 Pa logged; both are ≈1000x the ≈5.41
kPa a patient's foot would actually be reading.

**This changes measured kPa values, twice over.** `adcToKpa()` in
`src/ts/data/blePacketParser.ts` did not apply the `offset_adc` subtraction
before report 006, and did not apply this `/1000` before report 008 —
anything computed before report 006 reads high by `offset_adc`; anything
computed before report 008 reads ~1000x too high on top of that. If you're
comparing against numbers captured earlier, re-capture rather than trust
the old ones.

Calibration blob shape (JSON, read from the Calibration characteristic):

```json
{
  "device_id": "INSOLE-L-001",
  "r_pulldown_ohm": 10000,
  "sensor_area_m2": 0.000113,
  "channels": [
    { "index": 0, "a": 1.23e5, "b": -1.05, "offset_adc": 12 }
  ]
}
```

`channels[i].index` corresponds to the sensor site table above. v1.6: the
list must have exactly 8 channels with indexes 0–7; the Flutter app
refuses an insole with any other count ("calibration rejected", reject
`calibrationFsrCount`).

### IMU scaling

```
accel_g  = raw / 4096.0
gyro_dps = raw / 32.8
```

### Temperature scaling

```
temp_c = raw / 100.0     // per site (v1.6: 8 sites)
```

(The ESP32 has already applied the Steinhart-Hart conversion from the NTC's
raw reading — no per-unit calibration needed on the app side for
temperature.)

---

## Behavioural facts (verified against real hardware — easy to lose, expensive to rediscover)

- **The device streams nothing until the app writes `START_STREAM` (`0x01`)
  to the Control characteristic, after connecting.** Device status notifies
  regardless of this write; sensor and temperature notifications do not
  start until `START_STREAM` is sent. `WebBleDataSource.connect()` must
  perform this write as part of its connect sequence, not treat it as
  optional or implicit. Confirmed by the contract's own packet cadence table
  (Sensor Stream / Temperature are Notify-only, Device Status is Read +
  Notify) — status is readable/notifying independent of streaming state,
  the other two are not.
- **MTU must be negotiated to 247 before enabling notifications**, or
  packets arrive truncated (the contract's own fallback path, "4
  samples/packet," is what happens if this negotiation fails — a smaller
  sensor packet, not a crash). Verified working end-to-end with real
  hardware and a BLE dongle via the standalone test page. Request the MTU
  negotiation before calling
  `BluetoothRemoteGATTCharacteristic.startNotifications()` on any of the
  three notifying characteristics; on Android this means calling
  `requestMTU(247)` explicitly — iOS does this automatically.

---

## What's still open

Updated after implementing `WebBleDataSource` (`docs/reports/005-web-ble-datasource.md`),
the contract owner's follow-up (`docs/reports/006-*.md`), and the raw-hardware
debugging pass that found and fixed the Pa/kPa unit gap
(`docs/reports/007-*.md`, `docs/reports/008-*.md`).

- **RESOLVED**: the FSR scaling formula's missing Pa→kPa conversion. Found
  via instrumented logging against real hardware, not code review alone —
  see the "FSR scaling" section above and `docs/reports/008-*.md` for the
  confirming data points. `adcToKpa()` now divides by 1000.
- **RESOLVED**: `WebBleDataSource` pointed at the ESP32 simulator IS this
  app's answer to the contract's `SimulatorDataSource` — there is no
  separate simulator-only implementation, and none seems warranted: the
  simulator and real hardware are electrically identical BLE peripherals
  from this app's side of the link (same service, same characteristics,
  same packet formats), so one adapter class serves both. Not confirmed
  with the hardware/contract team, just the position this implementation
  took — revisit if that turns out to be wrong.
- **NARROWED, not fully resolved**: the calibration blob's byte-level
  framing. `WebBleDataSource` reads it with a single
  `characteristic.readValue()` call and decodes the result as UTF-8 JSON —
  no manual chunking logic was written, relying on Web Bluetooth's
  underlying GATT stack to transparently perform the standard "Read Long
  Characteristic Value" procedure for any value exceeding the negotiated
  MTU in one exchange (standard GATT behavior, not something the app has to
  implement). This has NOT been verified against the real simulator's
  actual calibration characteristic — only reasoned from how Web
  Bluetooth/GATT reads are generally supposed to behave. See
  `docs/BLE-TEST-CHECKLIST.md` for how to check this against real hardware.
- **RESOLVED by the contract owner**: `offset_adc` is the zero-point ADC
  reading under no load — the stored result of a TARE (opcode `0x05`).
  Subtracted from the raw ADC before the rest of the FSR scaling formula,
  clamped at 0. See the "FSR scaling" section above and
  `docs/DATA-CONTRACT.md` §5.1, both updated to show it explicitly, and
  `adcToKpa()` in `src/ts/data/blePacketParser.ts`. **This changed measured
  kPa values** — anything computed before this fix reads high by whatever
  the offset was for that channel.
