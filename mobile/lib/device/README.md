# lib/device/

Both feet combined (S4): unix time per sample, the 50 Hz processing path,
the 10 Hz display path, read-time staleness, ΔT, and the debug-only mock.

| File | Contents |
|---|---|
| `device_clock.dart` | `DeviceClock`: device ms → unix ms per sample, one per foot per session (see below) |
| `foot_sample.dart` | `FootSample` (unixMs, deviceMs, seq, raw ADC, kPa, g, °/s) and `FootBatch` (one per accepted packet, with session and gap info) |
| `model_channels.dart` | The 24 model-input channels in contract §7.1 order; `modelRow(left, right)`. Same list as `shared/model_input.json` (a test checks it) |
| `device_manager.dart` | `DeviceManager(left, right)` over two `InsoleDataSource`s |
| `display_snapshot.dart` | `DisplaySnapshot` / `FootView` / `FootConnection`: what screens read |
| `temp_history.dart` | Per-foot temperature history, 10-min buckets over 24 h (memory only; S6A persists it) |
| `mock_data_source.dart` | `MockInsoles` + `MockDataSource` and the presets; debug builds only |
| `timing_log.dart`, `timing_check.dart` | The S4 timing check (debug screen) |
| `device_providers.dart` | Riverpod providers: BLE or mock source per foot, `deviceManagerProvider`, `displaySnapshotProvider`, `timingCheckProvider` |

## Two paths (rule 10)

- **50 Hz:** `DeviceManager.batches` emits every accepted packet as a
  `FootBatch` at once, unthrottled, unix-timed. S4C (capture) and S7
  (rules) read this. A batch from an older session than the foot's current
  one is dropped (rule 9, defence in depth).
- **10 Hz:** `DeviceManager.snapshots` emits a `DisplaySnapshot` every
  100 ms, only while something listens. Screens read
  `displaySnapshotProvider`.

## Staleness and ΔT (rules 2, 3, 4)

`snapshot()` derives each foot's `FootConnection` when called: streaming
with the last sample older than `staleAfter` (3 s), or streaming with no
sample 3 s after the link came up, is `stale`. Nothing latches it. ΔT
(signed L − R, contract §7.3) is `null` unless both feet are usable and
both temperatures are present with `normal` quality.

## Unix time per sample (`DeviceClock`)

The board's `t0_ms` counts from boot and `SYNC_TIME` changes nothing on the
wire, so the app maps device time to unix time itself:

- each packet gives a candidate offset = its arrival − its last sample's
  device time (anchored to that packet, not to "now", BACKLOG 28);
- the target is the smallest candidate over 30 s (minimum latency);
- the applied offset moves toward it by at most 0.25 ms per sample, so
  sample times are 20 ± 0.25 ms apart and never go backwards within a
  session; a new session gets a new clock.

This deliberately differs from contract §4's resync formula (BACKLOG 28).

## Mock (debug builds only)

`flutter run --dart-define=MOCK=<preset>` replaces both BLE sources with the
mock; release builds ignore the define (`mockPresetFor`, tested). Presets:
`safe`, `safeOrangeDot` (level 2 only), `watch` (level 3 sustained left
forefoot load), `rest` (right forefoot +2.6 °C), `noData`, `oneFootMissing`,
`lowBattery` (left 10 %). Pressure is generated as raw ADC and converted with
the real `sampleKpa`. `test/device/mock_data_source_test.dart` checks each
preset lands in its band against `shared/thresholds.json`, so presets hold no
thresholds. Settings → "Mock preset (debug)" switches presets live.

## Timing check (debug screen)

Start/Stop on the BLE debug screen. While running, `SYNC_TIME` goes out every
10 s, and every send (U, offset) plus per-foot counters every 10 s are
written to `<app documents>/timing/timing-<date>.log`. Pull it from a debug
build with:

```
adb exec-out run-as th.ac.kmutt.smartinsole cat app_flutter/timing/<name> > <name>
```

and check it with `firmware/simulator/tools/timing_check.py` against both
boards' serial logs, logged on one laptop (method in that script's
docstring).
