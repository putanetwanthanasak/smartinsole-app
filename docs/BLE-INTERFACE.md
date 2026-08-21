# BLE Interface — working summary

**STATUS: WORKING SUMMARY, NOT AUTHORITATIVE.** `docs/DATA-CONTRACT.md` is
the source of truth for all of this once it is filled in — see the banner at
the top of that file. Until then, this document exists so that whoever
starts `WebBleDataSource` (see "Next phase" in `CLAUDE.md`) isn't blocked on
having the sibling test-page project at hand. Every UUID, offset, opcode, and
scaling factor below is a **placeholder**, marked `TODO`. Nothing in this
file has been invented or reconstructed from memory — where a value isn't
known, it is left blank rather than guessed. Fill these in from the Data
Contract, not from re-deriving them off the simulator or test page.

Two sibling projects (outside this repo, see `CLAUDE.md`) already implement
this interface end to end and are verified working: an ESP32 BLE simulator
(NimBLE-Arduino 2.x, advertises as `SMARTINSOLE-L`) and a standalone Web
Bluetooth test page. Neither is checked into this repo.

---

## GATT service

| Field | Value |
| --- | --- |
| Device name (advertised) | `SMARTINSOLE-L` (left insole — confirm right-side naming convention) |
| Service UUID | `TODO` |

## Characteristics

| Characteristic | UUID | Properties | Notes |
| --- | --- | --- | --- |
| Sensor data (pressure + IMU) | `TODO` | `TODO` (expected: Notify) | 200-byte packet, see layout below |
| Temperature | `TODO` | `TODO` (expected: Notify) | see layout below |
| Device status | `TODO` | `TODO` (expected: Notify) | notifies regardless of streaming state — see behavioural facts below |
| Control | `TODO` | `TODO` (expected: Write) | opcodes below |
| Calibration blob | `TODO` | `TODO` | confirmed present and parsed by the test page; shape not yet recorded here |
| (6th characteristic — CLAUDE.md's data seam notes lists six total) | `TODO` | `TODO` | identify and fill in |

---

## Sensor packet layout (200 bytes, little-endian)

`TODO` — byte offsets for every field below. The test page parses this
packet correctly; port its offset table here field by field, don't
re-derive it from scratch.

| Offset | Length | Field | Type | Scaling factor | Notes |
| --- | --- | --- | --- | --- | --- |
| `TODO` | `TODO` | `tUnixMs` (device clock, unsynced until `SYNC_TIME`) | `TODO` | — | see Conventions #5 in `CLAUDE.md` — never trust this for staleness |
| `TODO` | `TODO` | `fsrKpa[6]` (pressure, 6 channels) | `TODO` | `TODO` | channel order below |
| `TODO` | `TODO` | IMU fields | `TODO` | `TODO` | axes / units not yet recorded |
| `TODO` | `TODO` | (remaining fields to fill from the 200-byte layout) | | | |

### FSR channel order

`TODO` — confirm this matches `FSR_CHANNEL_ORDER` in `src/ts/constants.ts`
(`['hallux', 'meta1', 'meta3', 'meta5', 'midfoot', 'heel']`) before
`DeviceManager` maps indexed `fsrKpa[6]` to the name-keyed `FootPressure`
object. If the wire order differs from that array, one of the two must
change — don't let them silently disagree.

---

## Temperature packet layout

`TODO` — byte offsets, little-endian, scaling factor(s), units.

## Device status packet layout

`TODO` — byte offsets, encoding of connection/battery/worn-state fields,
mapping (if any) to the UI's `RiskStatus` `0`–`5` scale.

---

## Control opcodes

| Opcode | Value | Direction | Effect |
| --- | --- | --- | --- |
| `START_STREAM` | `0x01` | App → device, write to Control characteristic | Device begins sending sensor + temperature notifications. See behavioural fact below — required after every connect. |
| `STOP_STREAM` | `TODO` | | |
| `SYNC_TIME` | `TODO` | | Synchronizes the device's onboard clock — see Conventions #5 in `CLAUDE.md` for why this matters and why the app must never trust `tUnixMs` before this has happened. |
| (other opcodes) | `TODO` | | |

---

## Behavioural facts (verified against real hardware — easy to lose, expensive to rediscover)

- **The device streams nothing until the app writes `START_STREAM` (`0x01`)
  to the Control characteristic, after connecting.** Device status notifies
  regardless of this write; sensor and temperature notifications do not
  start until `START_STREAM` is sent. `WebBleDataSource.connect()` must
  perform this write as part of its connect sequence, not treat it as
  optional or implicit.
- **MTU must be negotiated to 247 before enabling notifications**, or
  packets arrive truncated. This has been verified working end-to-end with
  the actual hardware and a BLE dongle via the standalone test page. Request
  the MTU negotiation before calling
  `BluetoothRemoteGATTCharacteristic.startNotifications()` on any of the
  three notifying characteristics.

---

## To fill this in

Paste the relevant sections of the Data Contract (service/characteristic
UUIDs, packet layouts, opcodes, scaling factors) here, replacing the `TODO`
markers above. Once `docs/DATA-CONTRACT.md` itself is filled in, this file
should be re-checked against it rather than treated as a second source of
truth — the contract wins if they ever disagree.
