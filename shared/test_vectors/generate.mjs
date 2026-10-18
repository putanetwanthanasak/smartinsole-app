#!/usr/bin/env node
// generate.mjs — builds shared/test_vectors/*.json from the web app's TS
// parser (src/ts/data/blePacketParser.ts), so the Flutter parser can be
// checked against the exact numbers the hardware-verified TS code produces.
//
// The TS source is compiled read-only into a temporary directory with the
// repo's own tsc; nothing under src/ is touched. Every input is fixed (no
// randomness), so re-running produces byte-identical files.
//
// Usage (from the repo root, after `npm ci`):
//   node shared/test_vectors/generate.mjs           write the vector files
//   node shared/test_vectors/generate.mjs --check   fail if they are out of date

import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '../..');
const CHECK = process.argv.includes('--check');

// ─── Load the TS parser ──────────────────────────────────────────

const ts = await loadTsParser();

async function loadTsParser() {
  const tsc = join(ROOT, 'node_modules/.bin/tsc');
  if (!existsSync(tsc)) throw new Error('node_modules/.bin/tsc not found — run `npm ci` in the repo root first');
  const out = mkdtempSync(join(tmpdir(), 'smartinsole-vectors-'));
  try {
    execFileSync(tsc, [
      join(ROOT, 'src/ts/data/blePacketParser.ts'),
      '--outDir', out, '--rootDir', join(ROOT, 'src/ts'),
      '--module', 'es2022', '--moduleResolution', 'bundler', '--target', 'es2022',
      '--lib', 'es2022,dom', '--skipLibCheck', '--strict',
    ], { stdio: 'inherit' });
    writeFileSync(join(out, 'package.json'), '{ "type": "module" }\n');
    return await import(pathToFileURL(join(out, 'data/blePacketParser.js')).href);
  } finally {
    rmSync(out, { recursive: true, force: true });
  }
}

// ─── Wire constants (docs/BLE-INTERFACE.md) ──────────────────────

const HEADER_BYTES = 8;
const IMU_BYTES = 12;
const SAMPLE_SPACING_MS = 20;
const blockBytes = (n) => 2 * n + IMU_BYTES;

// ─── Packet builders ─────────────────────────────────────────────

/**
 * samples: [{ fsr: number[n], accel: [x,y,z], gyro: [x,y,z] }]
 * count defaults to samples.length; truncateTo / extraBytes shape the
 * byte length independently of what the header claims.
 */
function sensorBytes({ seq, t0, flags = 0, n, samples, count = samples.length, truncateTo, extraBytes = 0 }) {
  const full = HEADER_BYTES + samples.length * blockBytes(n) + extraBytes;
  const dv = new DataView(new ArrayBuffer(full));
  dv.setUint16(0, seq, true);
  dv.setUint32(2, t0, true);
  dv.setUint8(6, count);
  dv.setUint8(7, flags);
  samples.forEach((s, i) => {
    const base = HEADER_BYTES + i * blockBytes(n);
    s.fsr.forEach((v, ch) => dv.setUint16(base + ch * 2, v, true));
    s.accel.forEach((v, k) => dv.setInt16(base + 2 * n + k * 2, v, true));
    s.gyro.forEach((v, k) => dv.setInt16(base + 2 * n + 6 + k * 2, v, true));
  });
  for (let i = full - extraBytes; i < full; i++) dv.setUint8(i, 0xa5);
  const bytes = new Uint8Array(dv.buffer);
  return truncateTo === undefined ? bytes : bytes.slice(0, truncateTo);
}

function tempBytes({ seq, tMs, forefoot, heel, quality, reserved = 0, length = 12 }) {
  const dv = new DataView(new ArrayBuffer(12));
  dv.setUint16(0, seq, true);
  dv.setUint32(2, tMs, true);
  dv.setInt16(6, forefoot, true);
  dv.setInt16(8, heel, true);
  dv.setUint8(10, quality);
  dv.setUint8(11, reserved);
  return new Uint8Array(dv.buffer).slice(0, length);
}

function statusBytes({ pct, mv, side, fwMajor, fwMinor, state, error, length = 8 }) {
  const dv = new DataView(new ArrayBuffer(8));
  dv.setUint8(0, pct);
  dv.setUint16(1, mv, true);
  dv.setUint8(3, side);
  dv.setUint8(4, fwMajor);
  dv.setUint8(5, fwMinor);
  dv.setUint8(6, state);
  dv.setUint8(7, error);
  return new Uint8Array(dv.buffer).slice(0, length);
}

const hex = (bytes) => Buffer.from(bytes).toString('hex');
const dataView = (bytes) => new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);

/** Deterministic sample values: spread over the whole ADC range, varied per channel and sample. */
function syntheticSamples(n, count, seed) {
  return Array.from({ length: count }, (_, i) => ({
    fsr: Array.from({ length: n }, (_, ch) => (seed * 131 + i * 977 + ch * 523 + 17) % 4096),
    accel: [((seed + i) * 311) % 8192 - 4096, ((seed + i) * 197) % 8192 - 4096, 4096 - i * 37],
    gyro: [((seed + i) * 53) % 2000 - 1000, -((seed + i) * 71 % 1500), i * 13],
  }));
}

// ─── Calibrations ────────────────────────────────────────────────

/** Calibration blob as it appears on the wire (snake_case JSON). */
function calBlob(deviceId, channels) {
  return {
    device_id: deviceId,
    r_pulldown_ohm: 10000,
    sensor_area_m2: 0.000113,
    channels: channels.map(([a, b, offset], index) => ({ index, a, b, offset_adc: offset })),
  };
}

const CALIBRATIONS = {
  // Contract §5.1 example values, repeated across 6 channels, with the example's offset_adc.
  contract_example: calBlob('INSOLE-L-001', Array(6).fill([1.23e5, -1.05, 12])),
  // Per-channel variation, including offset 0 and a large offset.
  varied: calBlob('INSOLE-R-002', [
    [1.23e5, -1.05, 12], [9.8e4, -1.02, 0], [1.41e5, -1.10, 40],
    [1.05e5, -0.98, 100], [8.7e4, -1.07, 7], [1.6e5, -1.12, 250],
  ]),
  zero_offset: calBlob('INSOLE-L-003', Array(6).fill([1.23e5, -1.05, 0])),
};

/** Mirrors the TS Calibration shape for N ≠ 6, which parseCalibrationJSON refuses. */
function tsCalibrationFromBlob(blob) {
  return {
    deviceId: blob.device_id,
    rPulldownOhm: blob.r_pulldown_ohm,
    sensorAreaM2: blob.sensor_area_m2,
    channels: blob.channels.map((c) => ({ index: c.index, a: c.a, b: c.b, offsetAdc: c.offset_adc })),
  };
}

function checkFinite(values, where) {
  for (const v of values) if (!Number.isFinite(v)) throw new Error(`non-finite value in ${where}`);
  return values;
}

// ─── Sensor vectors ──────────────────────────────────────────────

function sampleExpectation(s, i, t0, cal, where) {
  return {
    t_ms: t0 + i * SAMPLE_SPACING_MS,
    fsr_adc: s.fsrAdc,
    adc_corrected: s.fsrAdc.map((raw, ch) => ts.correctAdc(raw, cal.channels[ch].offsetAdc)),
    kpa: checkFinite(s.fsrAdc.map((raw, ch) => ts.adcToKpa(raw, cal.channels[ch], cal)), where),
    accel_raw: s.accelRaw,
    accel_g: s.accelRaw.map(ts.accelRawToG),
    gyro_raw: s.gyroRaw,
    gyro_dps: s.gyroRaw.map(ts.gyroRawToDps),
  };
}

/** N = 6: every expected value comes from the TS parser. */
function tsSensorCase(name, calName, spec) {
  const bytes = sensorBytes({ n: 6, ...spec });
  const cal = ts.parseCalibrationJSON(JSON.stringify(CALIBRATIONS[calName]));
  const parsed = ts.parseSensorPacket(dataView(bytes));
  let expected;
  if (parsed === null) {
    expected = { rejected: 'tooShort' };
  } else if (parsed.truncated) {
    expected = { rejected: 'truncated', expected_bytes: parsed.expectedBytes, actual_bytes: parsed.actualBytes };
  } else {
    const h = parsed.header;
    expected = {
      rejected: null,
      expected_bytes: parsed.expectedBytes,
      actual_bytes: parsed.actualBytes,
      header: { seq: h.seq, t0_ms: h.t0Ms, count: h.count, saturated: h.saturated, calibrating: h.calibrating },
      samples: parsed.samples.map((s, i) => sampleExpectation(s, i, h.t0Ms, cal, name)),
    };
  }
  return { name, reference: 'ts-parser', fsr_count: 6, calibration: calName, hex: hex(bytes), expected };
}

/**
 * N ≠ 6: the TS parser only reads 6 channels, so raw values are the inputs
 * the packet was built from; kPa / g / dps still come from the TS functions.
 */
function constructedSensorCase(name, n, blob, spec) {
  const bytes = sensorBytes({ n, ...spec });
  const cal = tsCalibrationFromBlob(blob);
  const samples = spec.samples.map((s) => ({ fsrAdc: s.fsr, accelRaw: s.accel, gyroRaw: s.gyro }));
  return {
    name, reference: 'constructed+ts-adcToKpa', fsr_count: n, calibration: blob.device_id, hex: hex(bytes),
    expected: {
      rejected: null,
      expected_bytes: HEADER_BYTES + samples.length * blockBytes(n),
      actual_bytes: bytes.length,
      header: { seq: spec.seq, t0_ms: spec.t0, count: samples.length, saturated: false, calibrating: false },
      samples: samples.map((s, i) => sampleExpectation(s, i, spec.t0, cal, name)),
    },
  };
}

function sensorFile() {
  const offsetSample = {
    // varied offsets: [12, 0, 40, 100, 7, 250] → below, at zero, equal, above, far above
    fsr: [5, 0, 40, 101, 4095, 249], accel: [0, 0, 4096], gyro: [0, 0, 0],
  };
  const cases = [
    tsSensorCase('normal_8_samples_200_bytes', 'contract_example',
      { seq: 1234, t0: 98765, samples: syntheticSamples(6, 8, 1) }),
    tsSensorCase('normal_varied_calibration', 'varied',
      { seq: 1235, t0: 98925, samples: syntheticSamples(6, 8, 2) }),
    tsSensorCase('count_4_mtu_fallback', 'contract_example',
      { seq: 7, t0: 1000, samples: syntheticSamples(6, 4, 3) }),
    tsSensorCase('count_1', 'contract_example',
      { seq: 8, t0: 1160, samples: syntheticSamples(6, 1, 4) }),
    tsSensorCase('count_0_header_only', 'contract_example',
      { seq: 9, t0: 1200, samples: [] }),
    tsSensorCase('adc_all_0', 'zero_offset',
      { seq: 10, t0: 2000, samples: [{ fsr: Array(6).fill(0), accel: [0, 0, 0], gyro: [0, 0, 0] }] }),
    tsSensorCase('adc_all_4095', 'zero_offset',
      { seq: 11, t0: 2020, samples: [{ fsr: Array(6).fill(4095), accel: [0, 0, 0], gyro: [0, 0, 0] }] }),
    tsSensorCase('adc_0_and_4095_with_offsets', 'varied',
      { seq: 12, t0: 2040, samples: [
        { fsr: [0, 4095, 0, 4095, 0, 4095], accel: [1, 2, 3], gyro: [4, 5, 6] },
        { fsr: [4095, 0, 4095, 0, 4095, 0], accel: [-1, -2, -3], gyro: [-4, -5, -6] },
      ] }),
    tsSensorCase('offset_adc_below_equal_above', 'varied',
      { seq: 13, t0: 3000, samples: [offsetSample] }),
    tsSensorCase('offset_adc_contract_example_345', 'contract_example',
      { seq: 14, t0: 3020, samples: [{ fsr: Array(6).fill(345), accel: [0, 0, 4096], gyro: [0, 0, 0] }] }),
    tsSensorCase('flags_saturated', 'contract_example',
      { seq: 15, t0: 4000, flags: 0b01, samples: syntheticSamples(6, 2, 5) }),
    tsSensorCase('flags_calibrating', 'contract_example',
      { seq: 16, t0: 4040, flags: 0b10, samples: syntheticSamples(6, 2, 6) }),
    tsSensorCase('flags_both', 'contract_example',
      { seq: 17, t0: 4080, flags: 0b11, samples: syntheticSamples(6, 2, 7) }),
    tsSensorCase('imu_int16_extremes', 'contract_example',
      { seq: 18, t0: 5000, samples: [
        { fsr: Array(6).fill(2048), accel: [-32768, 32767, 0], gyro: [32767, -32768, -1] },
      ] }),
    tsSensorCase('seq_and_t0_max', 'contract_example',
      { seq: 65535, t0: 4294967295 - 140, samples: syntheticSamples(6, 8, 8) }),
    tsSensorCase('extra_trailing_bytes', 'contract_example',
      { seq: 19, t0: 6000, samples: syntheticSamples(6, 2, 9), extraBytes: 3 }),
    tsSensorCase('truncated_header_says_8', 'contract_example',
      { seq: 20, t0: 7000, samples: syntheticSamples(6, 8, 10), truncateTo: 104 }),
    tsSensorCase('truncated_one_byte_short', 'contract_example',
      { seq: 21, t0: 7160, samples: syntheticSamples(6, 8, 11), truncateTo: 199 }),
    tsSensorCase('shorter_than_header', 'contract_example',
      { seq: 22, t0: 8000, samples: [], truncateTo: 7 }),
    tsSensorCase('empty', 'contract_example',
      { seq: 23, t0: 8000, samples: [], truncateTo: 0 }),
  ];
  return {
    description: 'Sensor Stream packets with 6 FSR channels. Expected values are the output of the TS parser '
      + '(src/ts/data/blePacketParser.ts). "rejected": "tooShort" = TS returned null; "truncated" = TS set truncated.',
    calibrations: CALIBRATIONS,
    cases,
  };
}

function sensorNFile(n) {
  const blob = calBlob(`INSOLE-N${n}-TEST`, Array.from({ length: n }, (_, ch) => [1.0e5 + ch * 7.5e3, -1.0 - ch * 0.02, ch * 9]));
  const cases = [
    constructedSensorCase(`n${n}_8_samples`, n, blob, { seq: 100 + n, t0: 50000, samples: syntheticSamples(n, 8, 20 + n) }),
    constructedSensorCase(`n${n}_count_4`, n, blob, { seq: 200 + n, t0: 50160, samples: syntheticSamples(n, 4, 30 + n) }),
    constructedSensorCase(`n${n}_adc_extremes`, n, blob, { seq: 300 + n, t0: 50240, samples: [
      { fsr: Array.from({ length: n }, (_, ch) => (ch % 2 ? 4095 : 0)), accel: [-32768, 32767, 0], gyro: [1, -1, 0] },
    ] }),
  ];
  return {
    description: `Sensor Stream packets with ${n} FSR channels (sample block = 2N + 12 = ${blockBytes(n)} bytes). `
      + 'The TS parser only reads 6 channels, so raw values are the inputs the packet was built from; '
      + 'adc_corrected, kpa, accel_g and gyro_dps come from the TS functions.',
    calibrations: { [blob.device_id]: blob },
    cases,
  };
}

// ─── Temperature vectors ─────────────────────────────────────────

function tempCase(name, spec) {
  const bytes = tempBytes(spec);
  const p = ts.parseTempPacket(dataView(bytes));
  const expected = p === null
    ? { rejected: 'tooShort' }
    : { rejected: null, seq: p.seq, t_ms: p.tMs, forefoot_c: p.forefootC, heel_c: p.heelC, quality: p.quality };
  return { name, reference: 'ts-parser', hex: hex(bytes), expected };
}

function temperatureFile() {
  return {
    description: 'Temperature packets (12 bytes). Expected values are the output of the TS parser. '
      + 'null temperature = wire value -32768 ("could not read").',
    cases: [
      tempCase('normal', { seq: 1, tMs: 30000, forefoot: 3180, heel: 3025, quality: 0 }),
      tempCase('negative_and_fractional', { seq: 2, tMs: 60000, forefoot: -105, heel: 1, quality: 0 }),
      tempCase('int16_max', { seq: 3, tMs: 90000, forefoot: 32767, heel: -32767, quality: 0 }),
      tempCase('unreadable_forefoot', { seq: 4, tMs: 120000, forefoot: -32768, heel: 3100, quality: 0 }),
      tempCase('unreadable_heel', { seq: 5, tMs: 150000, forefoot: 3100, heel: -32768, quality: 0 }),
      tempCase('unreadable_both', { seq: 6, tMs: 180000, forefoot: -32768, heel: -32768, quality: 2 }),
      tempCase('quality_1_poor_contact', { seq: 7, tMs: 210000, forefoot: 3050, heel: 2990, quality: 1 }),
      tempCase('quality_2_sensor_fault', { seq: 8, tMs: 240000, forefoot: 3050, heel: 2990, quality: 2 }),
      tempCase('seq_and_t_max', { seq: 65535, tMs: 4294967295, forefoot: 3300, heel: 3300, quality: 0 }),
      tempCase('short_11_bytes', { seq: 9, tMs: 270000, forefoot: 3000, heel: 3000, quality: 0, length: 11 }),
    ],
  };
}

// ─── Status vectors ──────────────────────────────────────────────

function statusCase(name, spec) {
  const bytes = statusBytes(spec);
  const p = ts.parseStatusPacket(dataView(bytes));
  const expected = p === null
    ? { rejected: 'tooShort' }
    : {
      rejected: null, battery_pct: p.batteryPct, battery_mv: p.batteryMv, foot_side: p.footSide,
      fw_major: p.fwMajor, fw_minor: p.fwMinor, state: p.state, error_code: p.errorCode,
    };
  return { name, reference: 'ts-parser', hex: hex(bytes), expected };
}

function statusFile() {
  const base = { pct: 87, mv: 3987, side: 0, fwMajor: 1, fwMinor: 4, state: 1, error: 0 };
  return {
    description: 'Device Status packets (8 bytes). Expected values are the output of the TS parser.',
    cases: [
      statusCase('left_streaming', base),
      statusCase('right_streaming', { ...base, side: 1 }),
      statusCase('state_idle', { ...base, state: 0 }),
      statusCase('state_error', { ...base, state: 2, error: 1 }),
      ...[1, 2, 3, 4, 5].map((e) => statusCase(`error_code_${e}`, { ...base, state: 2, error: e })),
      statusCase('battery_bounds_low', { ...base, pct: 0, mv: 0 }),
      statusCase('battery_mv_little_endian', { ...base, pct: 100, mv: 0x1234 }),
      statusCase('battery_mv_max', { ...base, pct: 100, mv: 65535 }),
      statusCase('firmware_255', { ...base, fwMajor: 255, fwMinor: 255 }),
      statusCase('short_7_bytes', { ...base, length: 7 }),
    ],
  };
}

// ─── Calibration vectors ─────────────────────────────────────────

/** reason: the Dart RejectReason this malformed blob must produce (TS only throws a message). */
function calibrationCase(name, text, reason) {
  let expected;
  try {
    const c = ts.parseCalibrationJSON(text);
    if (reason) throw new Error(`${name}: TS accepted a blob labelled ${reason}`);
    expected = {
      rejected: null, device_id: c.deviceId, r_pulldown_ohm: c.rPulldownOhm, sensor_area_m2: c.sensorAreaM2,
      channels: c.channels.map((ch) => ({ index: ch.index, a: ch.a, b: ch.b, offset_adc: ch.offsetAdc })),
    };
  } catch (e) {
    if (!reason) throw e;
    // JSON.parse's own error text varies by Node version; keep only TS's prefix so --check is stable.
    expected = { rejected: reason, ts_message: e.message.replace(/^(Calibration blob is not valid JSON):.*$/s, '$1') };
  }
  return { name, reference: 'ts-parser', text, expected };
}

function calibrationFile() {
  const ok = CALIBRATIONS.varied;
  const without = (key) => { const c = structuredClone(ok); delete c[key]; return JSON.stringify(c); };
  const withField = (key, value) => JSON.stringify({ ...ok, [key]: value });
  const channelWith = (key, value) => {
    const c = structuredClone(ok);
    if (value === undefined) delete c.channels[2][key]; else c.channels[2][key] = value;
    return JSON.stringify(c);
  };
  return {
    description: 'Calibration blobs (JSON text, read from the Calibration characteristic). Valid cases are the '
      + 'output of the TS parser. For malformed blobs the TS parser throws; "rejected" is the RejectReason the Dart '
      + 'parser must return and "ts_message" is what TS threw.',
    cases: [
      calibrationCase('contract_example_6_channels', JSON.stringify(CALIBRATIONS.contract_example)),
      calibrationCase('varied_6_channels', JSON.stringify(ok)),
      calibrationCase('pretty_printed_with_extra_field', JSON.stringify({ ...ok, fw: '1.4' }, null, 2)),
      calibrationCase('not_json', '{"device_id": "INSOLE-L-001",', 'calibrationNotJson'),
      calibrationCase('empty_text', '', 'calibrationNotJson'),
      calibrationCase('json_null', 'null', 'calibrationNotObject'),
      calibrationCase('json_number', '42', 'calibrationNotObject'),
      calibrationCase('missing_device_id', without('device_id'), 'calibrationMissingField'),
      calibrationCase('device_id_not_string', withField('device_id', 7), 'calibrationMissingField'),
      calibrationCase('missing_r_pulldown_ohm', without('r_pulldown_ohm'), 'calibrationMissingField'),
      calibrationCase('r_pulldown_ohm_string', withField('r_pulldown_ohm', '10000'), 'calibrationMissingField'),
      calibrationCase('missing_sensor_area_m2', without('sensor_area_m2'), 'calibrationMissingField'),
      calibrationCase('missing_channels', without('channels'), 'calibrationMissingField'),
      calibrationCase('channels_not_array', withField('channels', {}), 'calibrationMissingField'),
      calibrationCase('channel_not_object', JSON.stringify({ ...ok, channels: [...ok.channels.slice(0, 5), 3] }),
        'calibrationMissingField'),
      calibrationCase('channel_missing_a', channelWith('a'), 'calibrationMissingField'),
      calibrationCase('channel_b_null', channelWith('b', null), 'calibrationMissingField'),
      calibrationCase('channel_missing_offset_adc', channelWith('offset_adc'), 'calibrationMissingField'),
      calibrationCase('channel_index_string', channelWith('index', '2'), 'calibrationMissingField'),
    ],
  };
}

// ─── Output ──────────────────────────────────────────────────────

/** JSON with 2-space indent, but arrays of plain numbers/strings/null kept on one line. */
function format(value) {
  const text = JSON.stringify(value, null, 2);
  return text.replace(/\[\s+((?:-?[\d.eE+-]+|null|true|false|"[^"\n]*")(?:,\s+(?:-?[\d.eE+-]+|null|true|false|"[^"\n]*"))*)\s+\]/g,
    (_, inner) => `[${inner.split(/,\s+/).join(', ')}]`) + '\n';
}

const FILES = {
  'sensor.json': sensorFile(),
  'sensor_n4.json': sensorNFile(4),
  'sensor_n8.json': sensorNFile(8),
  'temperature.json': temperatureFile(),
  'status.json': statusFile(),
  'calibration.json': calibrationFile(),
};

let stale = 0;
for (const [file, content] of Object.entries(FILES)) {
  const path = join(HERE, file);
  const text = format(content);
  if (CHECK) {
    const current = existsSync(path) ? readFileSync(path, 'utf8') : null;
    if (current !== text) { console.error(`out of date: shared/test_vectors/${file}`); stale++; }
  } else {
    writeFileSync(path, text);
    console.log(`wrote shared/test_vectors/${file} (${content.cases.length} cases)`);
  }
}
if (CHECK) {
  if (stale) { console.error(`${stale} file(s) out of date — run node shared/test_vectors/generate.mjs`); process.exit(1); }
  console.log('test vectors up to date');
}
