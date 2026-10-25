import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/insole_control.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/foot_sample.dart';
import 'package:smartinsole/device/insole_commands.dart';
import 'package:smartinsole/device/sample_rate_meter.dart';

class FakeControl implements InsoleControl {
  FakeControl({this.canCommand = true});

  @override
  bool canCommand;
  int tares = 0;
  int reboots = 0;

  @override
  Future<void> sendTare() async => tares++;

  @override
  Future<void> sendReboot() async => reboots++;
}

FootBatch batch(
  FootSide side, {
  bool calibrating = false,
  int samples = 8,
  DateTime? at,
}) => FootBatch(
  side: side,
  session: 1,
  seq: 0,
  missingBefore: 0,
  receivedAt: at ?? DateTime(2026),
  saturated: false,
  calibrating: calibrating,
  samples: [
    for (var i = 0; i < samples; i++)
      FootSample(
        unixMs: i * 20.0,
        deviceMs: i * 20,
        fsrAdc: const [0],
        fsrKpa: const [0],
        accelG: const [0, 0, 1],
        gyroDps: const [0, 0, 0],
      ),
  ],
);

void main() {
  late StreamController<FootBatch> batches;
  late Map<FootSide, FakeControl> controls;
  var captureOpen = false;

  InsoleCommands commands() => InsoleCommands(
    controls: controls,
    batches: batches.stream,
    captureOpen: () => captureOpen,
  );

  setUp(() {
    batches = StreamController<FootBatch>.broadcast(sync: true);
    controls = {for (final s in FootSide.values) s: FakeControl()};
    captureOpen = false;
  });

  group('refused (BACKLOG 21)', () {
    test('while a research capture session is open: nothing is sent', () {
      captureOpen = true;
      final c = commands();
      expect(c.refusal, CommandRefusal.captureOpen);
      expect(c.tare, throwsA(isA<CommandRefused>()));
      expect(c.reboot, throwsA(isA<CommandRefused>()));
      for (final f in controls.values) {
        expect(f.tares + f.reboots, 0);
      }
    });

    test('when no foot streams', () {
      for (final f in controls.values) {
        f.canCommand = false;
      }
      expect(commands().refusal, CommandRefusal.notConnected);
      expect(commands().reboot, throwsA(isA<CommandRefused>()));
    });
  });

  test('TARE is done once each foot flags calibrating and then clears', () {
    fakeAsync((async) {
      Map<FootSide, TareOutcome>? result;
      commands().tare().then((r) => result = r);
      async.flushMicrotasks();
      expect(controls.values.every((f) => f.tares == 1), isTrue);
      for (final s in FootSide.values) {
        // A packet before the window opens does not count as done.
        batches.add(batch(s));
        batches.add(batch(s, calibrating: true));
      }
      async.flushMicrotasks();
      expect(result, isNull);
      for (final s in FootSide.values) {
        batches.add(batch(s));
      }
      async.flushMicrotasks();
      expect(result, {
        FootSide.left: TareOutcome.done,
        FootSide.right: TareOutcome.done,
      });
    });
  });

  test('TARE goes only to the streaming foot; no window → no response', () {
    fakeAsync((async) {
      controls[FootSide.right]!.canCommand = false;
      Map<FootSide, TareOutcome>? result;
      commands().tare().then((r) => result = r);
      async.flushMicrotasks();
      expect(controls[FootSide.right]!.tares, 0);
      async.elapse(InsoleCommands.defaultTareTimeout);
      expect(result, {FootSide.left: TareOutcome.noResponse});
    });
  });

  test('REBOOT goes to every streaming foot', () async {
    expect(await commands().reboot(), FootSide.values);
    expect(controls.values.every((f) => f.reboots == 1), isTrue);
  });

  group('SampleRateMeter', () {
    test('null until a whole window is watched, then samples per second', () {
      var now = DateTime(2026);
      final meter = SampleRateMeter(batches: batches.stream, now: () => now);
      // 50 Hz on the left (8-sample packets every 160 ms), nothing right.
      for (var ms = 0; ms < 10000; ms += 160) {
        now = DateTime(2026).add(Duration(milliseconds: ms));
        batches.add(batch(FootSide.left, at: now));
        expect(meter.rate(FootSide.left), isNull);
      }
      now = DateTime(2026).add(const Duration(seconds: 10));
      expect(meter.rate(FootSide.left), closeTo(50, 0.5));
      expect(meter.rate(FootSide.right), 0);
      // The stream stops: the rate falls when read later (rule 2).
      now = now.add(const Duration(seconds: 5));
      expect(meter.rate(FootSide.left), lessThan(30));
      meter.dispose();
    });
  });
}
