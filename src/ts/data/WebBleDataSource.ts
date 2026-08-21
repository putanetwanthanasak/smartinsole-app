// data/WebBleDataSource.ts — IDataSource backed by Web Bluetooth, talking to
// the ESP32 insole simulator / real hardware described in
// docs/BLE-INTERFACE.md and docs/DATA-CONTRACT.md (contract wins if they
// disagree — nothing here should invent a value either document should
// have supplied; see blePacketParser.ts's adcToKpa for the one place that
// turned out to matter).
//
// One instance per foot, same as MockDataSource — `side` here is the SLOT
// this instance is plugged into in this app's UI (left insole vs right),
// which is NOT confirmed to match the physical device's own foot_side until
// the first Device Status packet arrives — see the mismatch check below.
//
// GATT orchestration lives here; wire-format parsing does not — see
// blePacketParser.ts for why that split exists.

import type { FootSide } from '../types.js';
import type { IDataSource } from './IDataSource.js';
import type {
  ConnectionState, Unsubscribe, SensorSample, TempReading, DeviceStatus,
} from './types.js';
import {
  SERVICE_UUID, CHAR_SENSOR_UUID, CHAR_TEMP_UUID, CHAR_STATUS_UUID, CHAR_CONTROL_UUID, CHAR_CALIB_UUID,
  OP_START_STREAM, OP_SYNC_TIME,
  SENSOR_SAMPLE_SPACING_MS, RESYNC_INTERVAL_MS, CONSECUTIVE_TRUNCATION_ERROR_THRESHOLD,
} from './bleProtocol.js';
import {
  parseSensorPacket, parseTempPacket, parseStatusPacket, parseCalibrationJSON, adcToKpa,
  accelRawToG, gyroRawToDps,
} from './blePacketParser.js';
import type { Calibration, CalibrationChannel, ParsedStatusPacket } from './blePacketParser.js';

type Listener<T> = (v: T) => void;
function emitter<T>() {
  const ls = new Set<Listener<T>>();
  return {
    add(cb: Listener<T>): Unsubscribe { ls.add(cb); return () => { ls.delete(cb); }; },
    emit(v: T) { for (const cb of [...ls]) cb(v); },
  };
}

/** foot_side, per docs/BLE-INTERFACE.md Device Status packet: 0 = left, 1 = right. */
const EXPECTED_FOOT_SIDE: Record<FootSide, 0 | 1> = { left: 0, right: 1 };

/**
 * Thrown when a connected device's own `foot_side` doesn't match the slot
 * it was connected into (hard requirement: "detect the mismatch and say so
 * rather than accepting it — silently mislabelled sides would corrupt
 * every bilateral metric in the app").
 */
export class BleSideMismatchError extends Error {
  constructor(readonly expectedSide: FootSide, readonly reportedFootSide: 0 | 1) {
    super(
      `Connected device reports foot_side=${reportedFootSide} `
      + `(${reportedFootSide === 0 ? 'left' : 'right'}), but was connected into the ${expectedSide} slot.`,
    );
    this.name = 'BleSideMismatchError';
  }
}

/** BLE-only diagnostics — deliberately NOT on IDataSource, same reasoning as MockDataSource's setPreset/getPreset/subscriberCount: a real IDataSource consumer above the data seam must not depend on this existing. */
export interface BleDiagnostics {
  totalPackets: number;
  droppedPackets: number;
  truncatedPackets: number;
  unparseablePackets: number;
  lastSeq: number | null;
  timeOffsetMs: number | null;
  /** Full parsed blob (not just the device_id) — see docs/BLE-TEST-CHECKLIST.md, which inspects this directly from the console to confirm a calibration read actually succeeded and looks right, not just that it didn't throw. */
  calibration: Calibration | null;
}

export class WebBleDataSource implements IDataSource {
  readonly side: FootSide;

  private state: ConnectionState = 'disconnected';
  private device: BluetoothDevice | null = null;
  private gatt: BluetoothRemoteGATTServer | null = null;

  private sensorChar: BluetoothRemoteGATTCharacteristic | null = null;
  private tempChar: BluetoothRemoteGATTCharacteristic | null = null;
  private statusChar: BluetoothRemoteGATTCharacteristic | null = null;
  private controlChar: BluetoothRemoteGATTCharacteristic | null = null;

  private calibration: Calibration | null = null;
  private calibByIndex = new Map<number, CalibrationChannel>();

  /** unix_ms - device_ms for THIS connection. Null until the first estimate lands — see toUnixMs(). */
  private timeOffsetMs: number | null = null;
  /** Most recent raw device-clock value seen from ANY packet — what syncTime()'s offset calc subtracts from. */
  private lastKnownDeviceMs: number | null = null;
  private resyncTimer: ReturnType<typeof setInterval> | null = null;
  private intentionalDisconnect = false;

  private lastSeq: number | null = null;
  private totalPackets = 0;
  private droppedPackets = 0;
  private truncatedPackets = 0;
  private unparseablePackets = 0;
  private consecutiveTruncations = 0;

  private samples = emitter<SensorSample>();
  private temps = emitter<TempReading>();
  private statuses = emitter<DeviceStatus>();
  private states = emitter<ConnectionState>();

  // Bound once so add/removeEventListener refer to the same function identity.
  private readonly onSensorNotify = (ev: Event): void =>
    this.handleSensorValue((ev.target as BluetoothRemoteGATTCharacteristic).value!);
  private readonly onTempNotify = (ev: Event): void =>
    this.handleTempValue((ev.target as BluetoothRemoteGATTCharacteristic).value!);
  private readonly onStatusNotify = (ev: Event): void =>
    this.handleStatusValue((ev.target as BluetoothRemoteGATTCharacteristic).value!);
  private readonly onGattDisconnected = (): void => this.handleUnexpectedDisconnect();

  constructor(side: FootSide) { this.side = side; }

  // ─── IDataSource ────────────────────────────────────────────

  getState(): ConnectionState { return this.state; }
  onSample(cb: (s: SensorSample) => void): Unsubscribe { return this.samples.add(cb); }
  onTemp(cb: (t: TempReading) => void): Unsubscribe { return this.temps.add(cb); }
  onStatus(cb: (d: DeviceStatus) => void): Unsubscribe { return this.statuses.add(cb); }
  onStateChange(cb: (s: ConnectionState) => void): Unsubscribe { return this.states.add(cb); }

  getDiagnostics(): BleDiagnostics {
    return {
      totalPackets: this.totalPackets,
      droppedPackets: this.droppedPackets,
      truncatedPackets: this.truncatedPackets,
      unparseablePackets: this.unparseablePackets,
      lastSeq: this.lastSeq,
      timeOffsetMs: this.timeOffsetMs,
      calibration: this.calibration,
    };
  }

  /**
   * Drops the remembered `BluetoothDevice` so the NEXT connect() prompts a
   * fresh picker instead of reconnecting to the same one — e.g. after a
   * BleSideMismatchError (already forgotten automatically, see below), or
   * if a UI ever wants a "forget this device" action. Not wired to
   * anything yet — see docs/reports/005-web-ble-datasource.md.
   */
  forgetDevice(): void {
    this.device?.removeEventListener('gattserverdisconnected', this.onGattDisconnected);
    this.device = null;
  }

  /**
   * Resolves once fully connected AND streaming (calibration loaded,
   * foot_side confirmed, SYNC_TIME sent, START_STREAM written and
   * acknowledged). Rejects and sets state 'error' on any failure in that
   * sequence — EXCEPT the user cancelling the device picker, which is not
   * an error: state returns to 'disconnected' and connect() resolves
   * normally with nothing connected. This is a deliberate difference from
   * IDataSource's generic doc comment ("rejects on failure"), specific to
   * this implementation — MockDataSource has no equivalent case.
   */
  async connect(): Promise<void> {
    if (this.state === 'connected' || this.state === 'connecting') return;
    if (!navigator.bluetooth) {
      this.setState('error');
      throw new Error('Web Bluetooth is not available in this browser.');
    }

    this.setState('connecting');
    this.resetPerConnectionState();

    try {
      // Reconnecting the SAME device after a normal disconnect does not
      // need a new requestDevice() prompt — only requestDevice() itself
      // requires a user gesture, gatt.connect() on an already-granted
      // device does not. Two DIFFERENT insoles still means two SEPARATE
      // requestDevice() prompts, the first time each is paired — that
      // requirement is untouched, this only removes a redundant repeat
      // prompt for reconnecting the one already granted.
      if (!this.device) {
        try {
          this.device = await navigator.bluetooth.requestDevice({
            filters: [{ services: [SERVICE_UUID] }],
            optionalServices: [SERVICE_UUID],
          });
        } catch (err) {
          if (isUserCancellation(err)) {
            this.setState('disconnected');
            return;
          }
          throw err;
        }
        this.device.addEventListener('gattserverdisconnected', this.onGattDisconnected);
      }

      this.intentionalDisconnect = false;
      const gatt = await this.device.gatt!.connect();
      this.gatt = gatt;
      const service = await gatt.getPrimaryService(SERVICE_UUID);

      // Device Status FIRST — read once and check foot_side before
      // spending any more of the connection on a device that turns out to
      // be the wrong slot.
      this.statusChar = await service.getCharacteristic(CHAR_STATUS_UUID);
      const initialStatusValue = await this.statusChar.readValue();
      const initialStatus = parseStatusPacket(initialStatusValue);
      if (initialStatus && initialStatus.footSide !== EXPECTED_FOOT_SIDE[this.side]) {
        const mismatch = new BleSideMismatchError(this.side, initialStatus.footSide);
        await this.teardownGatt();
        this.forgetDevice();   // wrong physical device — don't silently reconnect to it next time
        this.setState('error');
        throw mismatch;
      }
      if (initialStatus) this.emitStatusPacket(initialStatus);

      // Calibration — hard requirement: read once at connect; any failure
      // here (missing characteristic, malformed JSON, wrong channel count)
      // fails connect() outright. No default curve, ever.
      const calibChar = await service.getCharacteristic(CHAR_CALIB_UUID);
      const calibValue = await calibChar.readValue();
      const calibText = new TextDecoder('utf-8').decode(calibValue);
      this.calibration = parseCalibrationJSON(calibText);
      this.calibByIndex = new Map(this.calibration.channels.map(c => [c.index, c]));

      // Subscribe BEFORE writing START_STREAM, so nothing sent immediately
      // after the write is missed.
      this.statusChar.addEventListener('characteristicvaluechanged', this.onStatusNotify);
      await this.statusChar.startNotifications();   // notifies regardless of streaming state

      this.sensorChar = await service.getCharacteristic(CHAR_SENSOR_UUID);
      this.sensorChar.addEventListener('characteristicvaluechanged', this.onSensorNotify);
      await this.sensorChar.startNotifications();

      this.tempChar = await service.getCharacteristic(CHAR_TEMP_UUID);
      this.tempChar.addEventListener('characteristicvaluechanged', this.onTempNotify);
      await this.tempChar.startNotifications();

      this.controlChar = await service.getCharacteristic(CHAR_CONTROL_UUID);

      // Time sync BEFORE start-stream, per the contract's own procedure —
      // but no data has flowed yet at this exact point, so this first call
      // writes SYNC_TIME without yet being able to compute an offset (see
      // syncTime()/toUnixMs() for how the gap until the first packet is
      // handled honestly rather than trusting an un-synced device clock).
      await this.syncTime();
      this.resyncTimer = setInterval(() => { void this.syncTime(); }, RESYNC_INTERVAL_MS);

      // START_STREAM — the gate. A failed write here must fail connect(),
      // not leave a device that looks connected and sends nothing.
      await this.controlChar.writeValueWithResponse(new Uint8Array([OP_START_STREAM]));

      this.setState('connected');
    } catch (err) {
      await this.teardownGatt();
      this.setState('error');
      throw err;
    }
  }

  async disconnect(): Promise<void> {
    this.intentionalDisconnect = true;
    await this.teardownGatt();
    this.setState('disconnected');
  }

  // ─── Connect/disconnect internals ────────────────────────────

  private resetPerConnectionState(): void {
    this.timeOffsetMs = null;
    this.lastKnownDeviceMs = null;
    this.lastSeq = null;
    this.totalPackets = 0;
    this.droppedPackets = 0;
    this.truncatedPackets = 0;
    this.unparseablePackets = 0;
    this.consecutiveTruncations = 0;
    this.calibration = null;
    this.calibByIndex.clear();
  }

  private async teardownGatt(): Promise<void> {
    if (this.resyncTimer) { clearInterval(this.resyncTimer); this.resyncTimer = null; }
    for (const [char, listener] of [
      [this.sensorChar, this.onSensorNotify],
      [this.tempChar, this.onTempNotify],
      [this.statusChar, this.onStatusNotify],
    ] as const) {
      if (!char) continue;
      try { await char.stopNotifications(); } catch { /* already gone — fine */ }
      char.removeEventListener('characteristicvaluechanged', listener);
    }
    this.sensorChar = null;
    this.tempChar = null;
    this.statusChar = null;
    this.controlChar = null;
    if (this.gatt?.connected) {
      try { this.gatt.disconnect(); } catch { /* already disconnected — fine */ }
    }
    this.gatt = null;
  }

  private handleUnexpectedDisconnect(): void {
    if (this.intentionalDisconnect) return;   // our own disconnect() already set state
    console.error(`[WebBleDataSource:${this.side}] unexpected GATT disconnect`);
    void this.teardownGatt();
    this.setState('error');
  }

  private setState(s: ConnectionState): void {
    if (this.state === s) return;
    this.state = s;
    this.states.emit(s);
  }

  // ─── Time sync (docs/BLE-INTERFACE.md "Clock synchronization") ──

  private async syncTime(): Promise<void> {
    if (!this.controlChar) return;
    const sendUnixMs = Date.now();
    const buf = new ArrayBuffer(9);
    const dv = new DataView(buf);
    dv.setUint8(0, OP_SYNC_TIME);
    dv.setBigUint64(1, BigInt(sendUnixMs), true);
    try {
      await this.controlChar.writeValueWithResponse(buf);
    } catch (err) {
      console.error(`[WebBleDataSource:${this.side}] SYNC_TIME write failed`, err);
      return;   // not fatal on its own — keep whatever offset we already had
    }
    // Contract's own formula: offset = unix_time_at_send - most_recently_received_t_ms.
    if (this.lastKnownDeviceMs !== null) {
      this.timeOffsetMs = sendUnixMs - this.lastKnownDeviceMs;
    }
  }

  /**
   * Converts a device-clock ms value to unix ms using the current offset.
   * Falls back to arrival time (Date.now()) for the brief window before
   * ANY offset exists yet — the contract's own sync formula needs a
   * previously-received t_ms to subtract from, so the very first call to
   * syncTime() (made before any packet has arrived) cannot compute one.
   * This fallback is what runs for that gap; handleSensorValue/
   * handleTempValue immediately compute a real offset from the first
   * packet's own arrival, so the gap is at most one packet.
   *
   * This is a SensorSample.tUnixMs concern only — DeviceManager's own
   * lastSampleAt (Convention #5 in CLAUDE.md) always uses arrival time
   * regardless of this, unaffected either way.
   */
  private toUnixMs(deviceMs: number): number {
    if (this.timeOffsetMs === null) return Date.now();
    return deviceMs + this.timeOffsetMs;
  }

  // ─── Notification handlers ─────────────────────────────────────

  private handleSensorValue(dv: DataView): void {
    const parsed = parseSensorPacket(dv);
    if (!parsed) {
      this.unparseablePackets++;
      console.error(
        `[WebBleDataSource:${this.side}] sensor packet too short to read its own header `
        + `(${dv.byteLength} bytes)`,
      );
      return;
    }

    this.totalPackets++;
    this.trackSeq(parsed.header.seq);

    if (parsed.truncated) {
      this.truncatedPackets++;
      this.consecutiveTruncations++;
      console.error(
        `[WebBleDataSource:${this.side}] TRUNCATED sensor packet: seq=${parsed.header.seq} `
        + `expected ${parsed.expectedBytes}B for count=${parsed.header.count}, got ${parsed.actualBytes}B`,
      );
      if (this.consecutiveTruncations >= CONSECUTIVE_TRUNCATION_ERROR_THRESHOLD) {
        console.error(
          `[WebBleDataSource:${this.side}] ${this.consecutiveTruncations} consecutive truncated `
          + 'packets — treating as a link error, not a one-off',
        );
        this.setState('error');
      }
      return;   // do not parse/emit anything from a packet that can't be trusted
    }
    this.consecutiveTruncations = 0;

    if (!this.calibration) {
      // Should be unreachable — calibration is read before notifications
      // are ever enabled — but a defensive check costs nothing next to the
      // alternative (a wrong kPa number silently reaching the UI).
      console.error(`[WebBleDataSource:${this.side}] sensor packet arrived before calibration was loaded — dropped`);
      return;
    }
    const calibration = this.calibration;

    this.lastKnownDeviceMs = parsed.header.t0Ms + (parsed.header.count - 1) * SENSOR_SAMPLE_SPACING_MS;
    if (this.timeOffsetMs === null) this.timeOffsetMs = Date.now() - this.lastKnownDeviceMs;

    // Unpack every sample in the packet individually — hard requirement #3.
    // Feeding one SensorSample per PACKET would silently produce a 6.25 Hz
    // stream where 50 Hz is expected, with nothing downstream flagging it.
    for (let i = 0; i < parsed.samples.length; i++) {
      const raw = parsed.samples[i];
      const deviceMs = parsed.header.t0Ms + i * SENSOR_SAMPLE_SPACING_MS;
      const fsrKpa = raw.fsrAdc.map((adc, ch) => {
        const channel = this.calibByIndex.get(ch);
        if (!channel) throw new Error(`No calibration channel for FSR index ${ch}`);
        return adcToKpa(adc, channel, calibration);
      });
      const sample: SensorSample = {
        tUnixMs: this.toUnixMs(deviceMs),
        side: this.side,
        fsrKpa,
        accelG: raw.accelRaw.map(accelRawToG) as [number, number, number],
        gyroDps: raw.gyroRaw.map(gyroRawToDps) as [number, number, number],
      };
      this.samples.emit(sample);
    }
  }

  private handleTempValue(dv: DataView): void {
    const parsed = parseTempPacket(dv);
    if (!parsed) {
      console.error(`[WebBleDataSource:${this.side}] temperature packet too short (${dv.byteLength} bytes)`);
      return;
    }
    this.lastKnownDeviceMs = parsed.tMs;
    if (this.timeOffsetMs === null) this.timeOffsetMs = Date.now() - parsed.tMs;
    const reading: TempReading = {
      tUnixMs: this.toUnixMs(parsed.tMs),
      side: this.side,
      forefootC: parsed.forefootC,
      heelC: parsed.heelC,
      quality: parsed.quality,
    };
    this.temps.emit(reading);
  }

  private handleStatusValue(dv: DataView): void {
    const parsed = parseStatusPacket(dv);
    if (!parsed) {
      console.error(`[WebBleDataSource:${this.side}] device status packet too short (${dv.byteLength} bytes)`);
      return;
    }
    if (this.state === 'connected' && parsed.footSide !== EXPECTED_FOOT_SIDE[this.side]) {
      // A device that passed the connect-time check should not change its
      // reported side mid-connection. If it does, this is not a state this
      // app can trust bilateral metrics from — disconnect rather than
      // silently keep rendering under the now-wrong slot.
      console.error(
        `[WebBleDataSource:${this.side}] device status now reports foot_side=${parsed.footSide} — `
        + 'mismatched mid-connection, disconnecting',
      );
      void this.disconnect();
      return;
    }
    this.emitStatusPacket(parsed);
  }

  private emitStatusPacket(parsed: ParsedStatusPacket): void {
    const status: DeviceStatus = {
      side: this.side,
      batteryPct: parsed.batteryPct,
      connected: this.state === 'connected',
      firmware: `v${parsed.fwMajor}.${parsed.fwMinor}`,
      errorCode: parsed.errorCode,
    };
    this.statuses.emit(status);
  }

  private trackSeq(seq: number): void {
    if (this.lastSeq !== null) {
      const expected = (this.lastSeq + 1) & 0xffff;
      if (seq !== expected) {
        const gap = (seq - expected + 0x10000) & 0xffff;
        this.droppedPackets += gap;
      }
    }
    this.lastSeq = seq;
  }
}

function isUserCancellation(err: unknown): boolean {
  return err instanceof DOMException && err.name === 'NotFoundError';
}
