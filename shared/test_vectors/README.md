# shared/test_vectors/

Byte-level test vectors for the BLE wire format (`docs/BLE-INTERFACE.md`,
`docs/DATA-CONTRACT.md` §3 and §5). They let the Flutter parser
(`mobile/lib/ble/`) prove it gives the same numbers as the web app's
hardware-verified TS parser (`src/ts/data/blePacketParser.ts`). The
vectors are checked by `mobile/test/ble/test_vectors_test.dart`.

**Generated files. Don't edit the JSON by hand.**

## Regenerate

From the repo root, after `npm ci`:

```
node shared/test_vectors/generate.mjs           # write the files
node shared/test_vectors/generate.mjs --check   # fail if they are out of date
```

The script compiles the TS parser into a temporary directory using the
repo's own `tsc`, then calls it. The web app's source is only read, never
changed. Every input is fixed, so running the script again produces
byte-identical files.

## Files

| File | Contents |
|---|---|
| `sensor.json` | Sensor Stream packets, 6 FSR channels: the normal 200-byte packet, `count` < 8, `count` 0, ADC 0/4095, `offset_adc`, flags, IMU extremes, truncated, too short |
| `sensor_n4.json`, `sensor_n8.json` | Sensor Stream packets with 4 or 8 FSR channels (sample block = `2N + 12` bytes) |
| `temperature.json` | Temperature packets: normal, negative, `-32768` (→ `null`), quality 0/1/2, too short |
| `status.json` | Device Status packets: every state, both feet, error codes 0–5, too short |
| `calibration.json` | Calibration blobs: valid ones, plus malformed ones together with the reason they must be rejected |

Each file is `{ "description", "cases": [...] }`. Sensor files also carry
`"calibrations"`, a map of blob name → calibration JSON. Each sensor case
names its blob in `"calibration"`. Packets are lowercase hex strings.
Doubles are written at full JS precision; the Dart tests compare them to 3
decimal places, and integers exactly.

`expected.rejected` is either `null` (parsed) or the name of the Dart
`RejectReason`:

- `tooShort`: TS returned `null` because the packet was shorter than its
  header or its fixed size.
- `truncated`: TS set `truncated: true`, meaning the header's `count` needs
  more bytes than arrived. `expected_bytes` and `actual_bytes` are included.
- `calibration*`: TS threw. `ts_message` is what it threw.

`dart_rejected`, when present, marks a case where the Dart parser
deliberately rejects a packet that TS accepts. `expected` still records
what TS returned. There is one such case, `extra_trailing_bytes`, where the
packet is longer than `count` accounts for. The Dart parser also rejects
out-of-range foot side, state and quality bytes, which TS masks into range.
The vectors only contain valid enum bytes, so those rejections are covered
by Dart-only tests instead.

## Where expected values come from

Each case has a `"reference"`:

- `ts-parser`: every expected value is the TS parser's own output.
- `constructed+ts-adcToKpa` (the N = 4 and N = 8 files only): the TS
  parser can only read 6 channels, so the raw ADC and IMU values are the
  inputs the packet was built from. `adc_corrected`, `kpa`, `accel_g` and
  `gyro_dps` still come from the TS functions.

Sample time is `t0_ms + i × 20` (FLUTTER-PLAN rule 1).

`2N + 12` is FLUTTER-PLAN's extension. The Data Contract §3.1 still fixes
a 6-FSR, 24-byte sample block (see `docs/BACKLOG.md`).
