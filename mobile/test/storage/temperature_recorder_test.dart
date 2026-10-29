import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/device_manager.dart';
import 'package:smartinsole/storage/temperature_recorder.dart';
import 'package:smartinsole/storage/temperature_repository.dart';

import '../device/fake_source.dart';
import 'storage_rig.dart';

void main() {
  late StorageRig rig;
  late FakeSource left;
  late FakeSource right;
  late TemperatureRecorder recorder;
  final at = DateTime.utc(2026, 10, 24, 7, 30); // 14:30 Bangkok

  setUp(() {
    rig = StorageRig();
    DateTime now() => at;
    left = FakeSource(FootSide.left, now: now);
    right = FakeSource(FootSide.right, now: now);
    final manager = DeviceManager(left: left, right: right, now: now);
    addTearDown(manager.dispose);
    recorder = TemperatureRecorder(
      manager: manager,
      temperatures: rig.temperatures,
      summaries: rig.summaries,
    )..start();
    addTearDown(recorder.stop);
  });

  test('every reading is stored as it arrives, whatever its quality', () async {
    left
      ..stream()
      ..packet()
      ..temp(30.8, sites: {5: 31.4})
      ..temp(31.5, sites: {0: null}, qualityAt: {0: TempQuality.sensorFault});
    await pumpEventQueue();
    final rows = await rig.temperatures.between(
      0,
      at.millisecondsSinceEpoch * 2,
    );
    expect(rows, hasLength(2));
    expect(rows.first.siteC, sitesC(30.8, {5: 31.4}));
    expect(rows.last.siteC[0], isNull);
    expect(rows.last.siteQuality[0], TempQuality.sensorFault);
    expect(rows.last.quality, TempQuality.sensorFault);
    expect(rows.every((r) => r.localDate == '2026-10-24'), isTrue);
    expect(recorder.written, 2);
    expect(recorder.failed, 0);
  });

  test('one foot alone never sets the day\'s ΔT (rule 4)', () async {
    left
      ..stream()
      ..packet()
      ..temp(30.8, sites: {5: 31.4});
    await pumpEventQueue();
    expect(await rig.summaries.get('2026-10-24'), isNull);
  });

  test('with both feet, the day keeps the largest |ΔT| of the 8 sites '
      'and its site', () async {
    left
      ..stream()
      ..packet()
      ..temp(30.8, sites: {5: 31.4});
    right
      ..stream()
      ..packet()
      ..temp(31.2, sites: {5: 34.0});
    await pumpEventQueue();
    var s = (await rig.summaries.get('2026-10-24'))!;
    expect(s.maxDeltaC, closeTo(2.6, 1e-9));
    expect(s.maxDeltaSite, 5);
    right.temp(31.0, sites: {5: 32.0, 7: 32.5});
    await pumpEventQueue();
    s = (await rig.summaries.get('2026-10-24'))!;
    expect(s.maxDeltaC, closeTo(2.6, 1e-9), reason: 'a smaller one never wins');
    expect(s.maxDeltaSite, 5);
  });

  test(
    'a storage failure is counted, never thrown into the BLE path',
    () async {
      await recorder.stop();
      final failing = TemperatureRecorder(
        manager: recorder.manager,
        temperatures: _FailingTemperatures(),
        summaries: rig.summaries,
      )..start();
      addTearDown(failing.stop);
      left
        ..stream()
        ..packet()
        ..temp(30.8);
      await pumpEventQueue();
      expect(failing.failed, 1);
      expect(failing.written, 0);
    },
  );
}

class _FailingTemperatures implements TemperatureRepository {
  @override
  Future<void> add({
    required FootSide side,
    required int atMs,
    required List<double?> celsius,
    required List<TempQuality> quality,
    required bool timeFromArrival,
  }) => Future.error(StateError('disk full'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
