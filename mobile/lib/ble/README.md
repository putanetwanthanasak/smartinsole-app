# lib/ble/

BLE wire format: packet parsing and unit conversion (S2A). The per-foot BLE
connection is added in S3A.

| File | Contents |
|---|---|
| `ble_protocol.dart` | UUIDs, opcodes, packet layout, scaling constants |
| `parse_result.dart` | `ParseResult` = `Parsed` or `Rejected` (with a `RejectReason`), so nothing is dropped silently |
| `packets.dart` | Parsed packet models and enums |
| `packet_parser.dart` | `parseSensorPacket` (N FSR channels), `parseTempPacket`, `parseStatusPacket` |
| `calibration.dart` | `parseCalibration`; N = number of channels |
| `fsr_conversion.dart` | ADC → kPa, IMU scaling |

These are checked against `shared/test_vectors/`, which are generated from the
web app's TS parser (see that folder's README).
