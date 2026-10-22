import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_data_source.dart';
import 'package:smartinsole/ble/ble_event_log.dart';
import 'package:smartinsole/ble/ble_hub.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/device_manager.dart';
import 'package:smartinsole/device/timing_log.dart';

import '../ble/fake_ble_central.dart';

Map<String, String> fields(String line) => {
  for (final kv in line.split(' ').skip(1))
    if (kv.contains('=')) kv.split('=')[0]: kv.split('=')[1],
};

void main() {
  test('logs every SYNC_TIME with U and the offset, and both feet', () {
    fakeAsync((async) {
      final now = async.getClock(DateTime(2026, 10, 22, 9)).now;
      final central = FakeBleCentral(
        insoles: [
          FakeInsole(id: 'L1', footSide: 0),
          FakeInsole(id: 'R1', footSide: 1),
        ],
      )..autoStreamPeriod = const Duration(milliseconds: 160);
      final hub = BleHub(
        central: central,
        permissions: FakePermissions(),
        now: now,
        log: BleEventLog(now: now),
      );
      final sources = {
        FootSide.left: BleDataSource(side: FootSide.left, hub: hub, now: now),
        FootSide.right: BleDataSource(side: FootSide.right, hub: hub, now: now),
      };
      final manager = DeviceManager(
        left: sources[FootSide.left]!,
        right: sources[FootSide.right]!,
        now: now,
      );
      hub.start();
      async.flushMicrotasks();
      sources[FootSide.left]!.connectTo('L1');
      sources[FootSide.right]!.connectTo('R1');
      async.elapse(const Duration(seconds: 2));

      final lines = <String>[];
      final log = TimingLog(
        manager: manager,
        sources: sources,
        now: now,
        write: lines.add,
      )..start();
      expect(sources[FootSide.left]!.syncInterval, TimingLog.probeInterval);
      async.elapse(const Duration(seconds: 60));
      log.stop();
      expect(
        sources[FootSide.left]!.syncInterval,
        BleDataSource.defaultSyncInterval,
      );

      final syncs = lines.where((l) => l.startsWith('SYNC ')).toList();
      expect(syncs, hasLength(12)); // 6 per foot in 60 s
      final s = fields(syncs.first);
      expect(int.parse(s['U']!), greaterThan(0));
      expect(double.tryParse(s['A']!), isNotNull);

      final feet = lines.where((l) => l.startsWith('FOOT ')).toList();
      expect(feet, hasLength(14)); // 6 ticks + the final one, both feet
      final f = fields(feet.last);
      expect(f['state'], 'streaming');
      expect(f['lost'], '0');
      expect(f['clamps'], '0');
      expect(int.parse(f['pkts']!), greaterThan(370));
      // The last periodic line (60 s) holds the step range; the line at
      // Stop, in the same instant, has no samples since.
      final tick = fields(feet[feet.length - 4]);
      expect(double.parse(tick['stepMin']!), greaterThanOrEqualTo(19.75));
      expect(double.parse(tick['stepMax']!), lessThanOrEqualTo(20.25));
      expect(lines.first, startsWith('# smartinsole timing log v1'));
      expect(lines.last, startsWith('STOP '));

      // Stopped: no more lines, and SYNC_TIME back to every 5 min.
      final n = lines.length;
      async.elapse(const Duration(seconds: 30));
      expect(lines, hasLength(n));
      for (final s in sources.values) {
        s.dispose();
      }
      manager.dispose();
      hub.dispose();
    });
  });
}
