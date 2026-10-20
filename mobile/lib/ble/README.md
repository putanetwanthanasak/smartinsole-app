# lib/ble/

BLE wire format (S2A) and the per-foot BLE connection (S3A).

| File | Contents |
|---|---|
| `ble_protocol.dart` | UUIDs, opcodes, packet layout, scaling constants |
| `parse_result.dart` | `ParseResult` = `Parsed` or `Rejected` (with a `RejectReason`), so nothing is dropped silently |
| `packets.dart` | Parsed packet models and enums |
| `packet_parser.dart` | `parseSensorPacket` (N FSR channels), `parseTempPacket`, `parseStatusPacket` |
| `calibration.dart` | `parseCalibration`; N = number of channels |
| `fsr_conversion.dart` | ADC → kPa, IMU scaling |
| `control_commands.dart` | START / STOP / SYNC_TIME bytes |
| `ble_central.dart` | `BleCentral` / `BleLink`: our own thin BLE interface, so the plugin can be swapped and tests run on a fake |
| `fbp_central.dart` | `flutter_blue_plus` adapter (`License.nonprofit`), no logic |
| `handler_permissions.dart` | Runtime permissions via `permission_handler` |
| `insole_data_source.dart` | `InsoleDataSource` (one per foot) and the frames it emits |
| `link_state.dart` | Sealed `LinkState`, `ProblemKind`, `ConnectStep`, `BleReadiness` |
| `link_stats.dart` | Per-foot counters for the debug screen |
| `ble_event_log.dart` | Ring buffer of BLE events (debug screen, "Copy log") |
| `ble_hub.dart` | Shared by both feet: readiness, one shared scan, sightings, which foot owns which insole, one setup at a time |
| `ble_data_source.dart` | `BleDataSource`: connect sequence, wrong side (rule 8), MTU fit, stale-packet drops (rule 9), reconnect |
| `ble_providers.dart` | Riverpod providers; tests override the central and permissions |

These are checked against `shared/test_vectors/`, which are generated from the
web app's TS parser (see that folder's README).

The connect sequence runs in full on every connect and every reconnect:
connect → request MTU 247 → priority HIGH → discover → read status → check
`foot_side` → read calibration → MTU fit check → subscribe → SYNC_TIME →
START. Tests: `test/ble/ble_data_source_test.dart` against
`test/ble/fake_ble_central.dart`.
