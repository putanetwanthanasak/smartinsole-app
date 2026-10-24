import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/insole_data_source.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/device_manager.dart';
import 'package:smartinsole/rules/alert_engine.dart';
import 'package:smartinsole/rules/gait_note.dart';
import 'package:smartinsole/storage/alert_repository.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/models.dart';

import '../device/fake_source.dart';
import '../helpers/pump_app.dart';
import '../storage/storage_rig.dart';

/// One foot's synthetic walk: [kpa] on every channel through each stance,
/// nothing in the swing. While [walking] the IMU reads 1.3 g (a 0.3 g
/// deviation, well above the gate); otherwise a still 1 g.
class Gait {
  const Gait({
    this.strideMs = 1000,
    this.stanceMs = 600,
    this.kpa = const [10, 10, 10, 10, 10, 10],
    this.walking = true,
    this.phaseMs = 0,
  });

  /// Standing still with [kpa] under the foot all the time.
  const Gait.standing(this.kpa)
    : strideMs = 1,
      stanceMs = 1,
      walking = false,
      phaseMs = 0;

  final int strideMs;
  final int stanceMs;
  final List<double> kpa;
  final bool walking;

  /// Shifts this foot's stride (the other foot walks half a stride later).
  final int phaseMs;

  bool inStance(int deviceMs) => (deviceMs + phaseMs) % strideMs < stanceMs;

  List<double> kpaAt(int deviceMs) =>
      inStance(deviceMs) ? kpa : List.filled(kpa.length, 0);

  List<double> get accel => walking ? const [0, 0, 1.3] : const [0, 0, 1];
}

/// Two fake feet, a DeviceManager and an AlertEngine on an in-memory
/// database, on a hand-moved clock. Packets arrive exactly every 160 ms
/// with the board clock in step, so sample times are whole milliseconds
/// and every boundary can be hit exactly.
class RulesRig {
  RulesRig({AppDatabase? db, DateTime? start, this.capture, this.gait})
    : _now = start ?? DateTime.utc(2026, 10, 24, 7) {
    this.db = db ?? (AppDatabase.memory()..closeOnTearDown());
    left = FakeSource(FootSide.left, now: now)..t0 = 0;
    right = FakeSource(FootSide.right, now: now)..t0 = 0;
    manager = DeviceManager(left: left, right: right, now: now);
    alerts = DriftAlertRepository(this.db, bangkok);
    engine = newEngine();
    addTearDown(manager.dispose);
  }

  DateTime _now;
  DateTime now() => _now;

  late final AppDatabase db;
  late final FakeSource left;
  late final FakeSource right;
  late final DeviceManager manager;
  late final AlertRepository alerts;
  late AlertEngine engine;

  String? Function()? capture;
  GaitEstimateSource? gait;

  /// A fresh engine on the same database: an app restart.
  AlertEngine newEngine() {
    final e = AlertEngine(
      manager: manager,
      thresholds: testThresholds,
      alerts: alerts,
      captureStamp: () => capture?.call(),
      gait: (side) => gait?.call(side),
      // Tests call check() themselves; the 50 Hz path checks anyway.
      checkEvery: const Duration(days: 1),
    )..start();
    addTearDown(e.stop);
    return e;
  }

  /// Both feet (or [feet]) start a streaming session.
  void stream([List<FootSide> feet = FootSide.values]) {
    for (final f in feet) {
      source(f).stream();
    }
  }

  FakeSource source(FootSide side) => side == FootSide.left ? left : right;

  /// [d] of packets, every 160 ms, from the feet that have a gait.
  void run(Duration d, {Gait? left, Gait? right}) {
    for (var t = 0; t < d.inMilliseconds; t += 160) {
      _now = _now.add(const Duration(milliseconds: 160));
      for (final (src, g) in [(this.left, left), (this.right, right)]) {
        if (g == null) continue;
        src.packet(
          sample: (i, ms) => SensorSample(
            deviceMs: ms,
            fsrAdc: List.filled(6, 1000),
            fsrKpa: g.kpaAt(ms),
            accelG: g.accel,
            gyroDps: const [0, 0, 0],
          ),
        );
      }
    }
  }

  /// Both feet walk the same [gait], the right half a stride later.
  void walkBoth(Duration d, Gait gait, {Gait? right}) => run(
    d,
    left: gait,
    right:
        right ??
        Gait(
          strideMs: gait.strideMs,
          stanceMs: gait.stanceMs,
          kpa: gait.kpa,
          walking: gait.walking,
          phaseMs: gait.strideMs ~/ 2,
        ),
  );

  /// Time passes with no packets; the boards' clocks keep running.
  void pause(Duration d) {
    _now = _now.add(d);
    left.t0 += d.inMilliseconds;
    right.t0 += d.inMilliseconds;
  }

  /// One temperature reading from [side].
  void temp(
    FootSide side,
    double? forefoot,
    double? heel, {
    TempQuality quality = TempQuality.normal,
  }) => source(side).temp(forefoot, heel, quality: quality);

  /// Every alert raised so far, stored.
  Future<List<StoredAlert>> stored() async {
    engine.check();
    await engine.flush();
    return alerts.since(0);
  }

  Future<List<AlertKind>> storedKinds() async => [
    for (final a in await stored()) a.kind,
  ];

  RulesView view() => engine.view(manager.snapshot());
}

extension on AppDatabase {
  void closeOnTearDown() => addTearDown(close);
}
