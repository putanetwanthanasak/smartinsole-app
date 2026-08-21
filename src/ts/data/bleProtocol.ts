// data/bleProtocol.ts — GATT UUIDs, control opcodes, and packet byte-layout
// constants for the SmartInsole BLE interface.
//
// Every value here is copied from docs/BLE-INTERFACE.md (itself an extract
// of Data Contract v1.1 — the contract wins if the two ever disagree). None
// of it is invented; where something the parser needed wasn't specified,
// that's flagged in a comment at the point it matters (see
// blePacketParser.ts's calibration conversion) rather than guessed here.
//
// Per CLAUDE.md convention #6 ("never inline a number that has a name"),
// nothing in WebBleDataSource.ts or blePacketParser.ts should restate any
// of these as a bare literal.

// ─── GATT service & characteristics ─────────────────────────────

export const SERVICE_UUID = 'f0a5c000-9b4d-4e8a-a3c1-72d6e1b45900';

export const CHAR_SENSOR_UUID  = 'f0a5c000-9b4d-4e8a-a3c1-72d6e1b45901';
export const CHAR_TEMP_UUID    = 'f0a5c000-9b4d-4e8a-a3c1-72d6e1b45902';
export const CHAR_STATUS_UUID  = 'f0a5c000-9b4d-4e8a-a3c1-72d6e1b45903';
export const CHAR_CONTROL_UUID = 'f0a5c000-9b4d-4e8a-a3c1-72d6e1b45904';
export const CHAR_CALIB_UUID   = 'f0a5c000-9b4d-4e8a-a3c1-72d6e1b45905';

// ─── Control opcodes (app -> insole, write to CHAR_CONTROL_UUID) ─

export const OP_START_STREAM = 0x01;
export const OP_STOP_STREAM  = 0x02;
export const OP_SYNC_TIME    = 0x03;
// SET_RATE (0x04), TARE (0x05), REBOOT (0x06) are in the contract but unused
// by this adapter — nothing in this app's UI exercises them yet.

// ─── Sensor Stream packet layout (little-endian) ─────────────────
// Header (8 bytes) + N x sample block (24 bytes). N is normally 8
// (SENSOR_SAMPLES_PER_PACKET) but the contract's own MTU-negotiation
// fallback path sends a smaller N (4) in a shorter, still-valid packet —
// see blePacketParser.ts's parseSensorPacket for why the parser reads N
// from the packet's own `count` field rather than assuming 8.

export const SENSOR_HEADER_BYTES = 8;
export const SENSOR_SAMPLE_BLOCK_BYTES = 24;
export const SENSOR_SAMPLES_PER_PACKET = 8;   // the NORMAL case; see above
export const SENSOR_SAMPLE_SPACING_MS = 20;   // fixed: sample i is at t0_ms + i*20
export const SENSOR_FULL_PACKET_BYTES =
  SENSOR_HEADER_BYTES + SENSOR_SAMPLES_PER_PACKET * SENSOR_SAMPLE_BLOCK_BYTES; // 200

// ─── Temperature packet layout (little-endian, 12 bytes) ─────────

export const TEMP_PACKET_BYTES = 12;
/** Sentinel for "could not read" on either temperature channel. */
export const TEMP_UNREADABLE_RAW = -32768;

// ─── Device Status packet layout (little-endian, 8 bytes) ────────

export const STATUS_PACKET_BYTES = 8;

// ─── Scaling factors ──────────────────────────────────────────────

export const ACCEL_LSB_PER_G = 4096;
export const GYRO_LSB_PER_DPS = 32.8;
export const TEMP_RAW_PER_C = 100;

// ─── Timing ────────────────────────────────────────────────────────

/** Contract's clock-sync procedure step 4: "repeat every 5 minutes". */
export const RESYNC_INTERVAL_MS = 5 * 60 * 1000;
/** Contract's acceptance criterion — not enforced in code, recorded so the
 *  number this whole mechanism is aiming for isn't lost. */
export const SYNC_ACCEPTANCE_MS = 10;

// ─── Truncation-detection escalation ────────────────────────────────
// Not from the contract — this project's own choice for hard requirement #2
// (detect, don't silently parse, a packet shorter than its own header says
// it should be). One truncated packet is logged and counted; this many IN A
// ROW is treated as a persistent link problem, not a one-off, and escalates
// the side to 'error'. See WebBleDataSource.ts.
export const CONSECUTIVE_TRUNCATION_ERROR_THRESHOLD = 5;
