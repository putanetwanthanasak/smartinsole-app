import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:smartinsole/ble/calibration.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/capture/capture_protocol.dart';
import 'package:smartinsole/capture/capture_session.dart';
import 'package:smartinsole/capture/cues.dart';
import 'package:smartinsole/device/device_manager.dart';

import '../device/fake_source.dart';

class FakeCues implements CaptureCues {
  final played = <Cue>[];
  @override
  void play(Cue cue) => played.add(cue);
  @override
  void dispose() {}
}

Calibration fakeCalibration(String id) => Calibration(
  deviceId: id,
  rPulldownOhm: 10000,
  sensorAreaM2: 0.000113,
  channels: [
    for (var i = 0; i < 6; i++)
      CalibrationChannel(index: i, a: 1.23e5, b: -1.05, offsetAdc: 12),
  ],
);

/// Two fake insoles streaming through a real DeviceManager into a capture
/// session, on fake time. [skew] moves the wall clock without firing
/// timers (a starved timer).
class CaptureRig {
  CaptureRig(this.async, {String code = 'TEST-001'}) {
    final clock = async.getClock(DateTime(2026, 11, 10, 9));
    now = () => clock.now().add(skew);
    left = FakeSource(FootSide.left, now: now)
      ..calibration = fakeCalibration('L-001');
    right = FakeSource(FootSide.right, now: now)
      ..calibration = fakeCalibration('R-001');
    manager = DeviceManager(left: left, right: right, now: now);
    root = Directory.systemTemp.createTempSync('capture_test_');
    left
      ..stream()
      ..status(battery: 90);
    right
      ..stream()
      ..status(battery: 85);
    // A first packet each, so both feet are streaming (as after pre-check).
    left.packet();
    async.elapse(const Duration(milliseconds: 7));
    right.packet();
    session = CaptureSession.create(
      deps: CaptureDeps(
        manager: manager,
        sources: {FootSide.left: left, FootSide.right: right},
        cues: cues,
        now: now,
        appVersion: '1.0.0+1',
      ),
      researchRoot: root,
      subject: SubjectInfo(
        code: SubjectCode.parse(code)!,
        sex: Sex.female,
        ageRange: '26-30',
        footLengthCm: {FootSide.left: 26.5, FootSide.right: 26.0},
      ),
      roomTempC: 25.5,
      seed: 7,
    );
  }

  final FakeAsync async;
  Duration skew = Duration.zero;
  late final DateTime Function() now;
  late final FakeSource left;
  late final FakeSource right;
  late final DeviceManager manager;
  late final Directory root;
  late final CaptureSession session;
  final cues = FakeCues();

  bool leftOn = true;
  bool rightOn = true;

  /// Both feet send a packet every 160 ms (8 samples = 50 Hz); right 7 ms
  /// after left, so the feet's sample instants differ as on real boards.
  void walk(Duration d) {
    final steps = d.inMilliseconds ~/ 160;
    for (var k = 0; k < steps; k++) {
      async.elapse(const Duration(milliseconds: 153));
      if (leftOn) left.packet();
      async.elapse(const Duration(milliseconds: 7));
      if (rightOn) right.packet();
    }
    async.flushMicrotasks();
  }

  void dispose() {
    session.dispose();
    manager.dispose();
    root.deleteSync(recursive: true);
  }
}

/// A CSV as header → column index plus rows.
class Csv {
  Csv(File f) {
    final lines = f.readAsLinesSync();
    header = lines.first.split(',');
    rows = [for (final l in lines.skip(1)) l.split(',')];
  }

  late final List<String> header;
  late final List<List<String>> rows;

  int col(String name) => header.indexOf(name);
  List<List<String>> side(String s) => [
    for (final r in rows)
      if (r[col('side')] == s) r,
  ];
  double num(List<String> r, String name) => double.parse(r[col(name)]);
}
