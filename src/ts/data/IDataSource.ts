// data/IDataSource.ts — one source per foot.
//
// Deliberately NOT one source for both feet. The two insoles are independent BLE
// peripherals: one can be connected while the other is absent, stale or dropped,
// and the UI has to be able to say which. A both-feet source cannot express that
// without inventing a combined state that does not exist in hardware.
//
// Implementations: MockDataSource today; a WebBluetoothDataSource and a
// Capacitor-native one later. Nothing above this interface may know which.

import type { FootSide } from '../types.js';
import type {
  ConnectionState, Unsubscribe, SensorSample, TempReading, DeviceStatus,
} from './types.js';

export interface IDataSource {
  readonly side: FootSide;

  /** Resolves once the link is up; sets state to 'error' and rejects on failure. */
  connect(): Promise<void>;
  disconnect(): Promise<void>;

  getState(): ConnectionState;

  /**
   * Every subscribe returns its own unsubscribe. Screens MUST call these in
   * unmount() — unlike the one-shot DOM listeners elsewhere in this app, these
   * fire continuously, so a leaked subscription keeps an unmounted screen's
   * closure alive and doing work forever.
   */
  onSample(cb: (s: SensorSample) => void): Unsubscribe;
  onTemp(cb: (t: TempReading) => void): Unsubscribe;
  onStatus(cb: (d: DeviceStatus) => void): Unsubscribe;
  onStateChange(cb: (s: ConnectionState) => void): Unsubscribe;
}
