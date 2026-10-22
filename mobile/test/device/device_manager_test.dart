import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/link_state.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/device/device_manager.dart';
import 'package:smartinsole/device/display_snapshot.dart';
import 'package:smartinsole/device/foot_sample.dart';

import 'fake_source.dart';

class Rig {
  Rig(this.async) {
    now = async.getClock(DateTime(2026, 10, 22, 9)).now;
    left = FakeSource(FootSide.left, now: now);
    right = FakeSource(FootSide.right, now: now);
    manager = DeviceManager(left: left, right: right, now: now);
    manager.batches.listen(batches.add);
  }

  final FakeAsync async;
  late final DateTime Function() now;
  late final FakeSource left;
  late final FakeSource right;
  late final DeviceManager manager;
  final batches = <FootBatch>[];

  void elapse(Duration d) {
    async.elapse(d);
    async.flushMicrotasks();
  }

  /// Time passes and the left board keeps sampling (its t0 moves on too).
  void walkLeft(Duration d) {
    elapse(d);
    left.t0 += d.inMilliseconds;
  }

  /// Both feet streaming with one packet and one temperature each.
  void bothStreaming({double l = 31.8, double r = 31.5}) {
    left
      ..stream()
      ..packet()
      ..temp(l, 30.0);
    right
      ..stream()
      ..packet()
      ..temp(r, 30.4);
  }
}

void main() {
  group('staleness (rule 2)', () {
    test('is derived at read time, with no timer running', () {
      fakeAsync((async) {
        final rig = Rig(async)..bothStreaming();
        expect(rig.manager.displayTicking, isFalse);
        expect(
          rig.manager.snapshot().left.connection,
          FootConnection.streaming,
        );

        // No tick, no listener: only the clock moves.
        rig.elapse(const Duration(milliseconds: 3000));
        expect(
          rig.manager.snapshot().left.connection,
          FootConnection.streaming,
        );
        rig.elapse(const Duration(milliseconds: 1));
        final s = rig.manager.snapshot();
        expect(s.left.connection, FootConnection.stale);
        expect(s.left.usable, isFalse);
        expect(s.left.kpa, isNull, reason: 'stale values are not shown');
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a fresh packet makes a stale foot streaming again', () {
      fakeAsync((async) {
        final rig = Rig(async)..bothStreaming();
        rig.elapse(const Duration(seconds: 10));
        expect(rig.manager.snapshot().left.connection, FootConnection.stale);
        rig.left.packet();
        expect(
          rig.manager.snapshot().left.connection,
          FootConnection.streaming,
        );
      });
    });

    test('streaming but no packet yet: connecting, then stale', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.left.stream();
        expect(
          rig.manager.snapshot().left.connection,
          FootConnection.connecting,
        );
        rig.elapse(const Duration(seconds: 4));
        expect(rig.manager.snapshot().left.connection, FootConnection.stale);
      });
    });

    test('link states map to what the UI may say', () {
      fakeAsync((async) {
        final rig = Rig(async);
        FootConnection c() => rig.manager.snapshot().left.connection;
        expect(c(), FootConnection.notConnected);
        rig.left.set(const LinkSearching(deviceId: 'X'));
        expect(c(), FootConnection.connecting);
        rig.left.set(
          const LinkProblem(
            deviceId: 'X',
            kind: ProblemKind.wrongSide,
            detail: '',
          ),
        );
        expect(c(), FootConnection.problem);
      });
    });

    test('a dropped link takes its values with it', () {
      fakeAsync((async) {
        final rig = Rig(async)..bothStreaming();
        rig.left.status(battery: 55);
        expect(rig.manager.snapshot().left.batteryPct, 55);
        rig.left.set(const LinkSearching(deviceId: 'X'));
        final s = rig.manager.snapshot().left;
        expect(s.batteryPct, isNull);
        expect(s.kpa, isNull);
        expect(s.temp, isNull);
        expect(s.lastSampleAt, isNull);
      });
    });

    test('the status read while connecting is kept', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.left
          ..set(const LinkConnecting(deviceId: 'X', step: ConnectStep.status))
          ..status(battery: 70)
          ..set(
            const LinkConnecting(deviceId: 'X', step: ConnectStep.calibration),
          )
          ..stream()
          ..packet();
        expect(rig.manager.snapshot().left.batteryPct, 70);
      });
    });
  });

  group('ΔT (rule 4)', () {
    test('is left minus right when both feet are usable', () {
      fakeAsync((async) {
        final rig = Rig(async)..bothStreaming(l: 31.0, r: 33.6);
        final s = rig.manager.snapshot();
        expect(s.deltaForefootC, closeTo(-2.6, 1e-9));
        expect(s.deltaHeelC, closeTo(-0.4, 1e-9));
      });
    });

    test('is null with one foot missing', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.left
          ..stream()
          ..packet()
          ..temp(31, 30);
        final s = rig.manager.snapshot();
        expect(s.left.usable, isTrue);
        expect(s.deltaForefootC, isNull);
        expect(s.deltaHeelC, isNull);
      });
    });

    test('is null when one foot is stale', () {
      fakeAsync((async) {
        final rig = Rig(async)..bothStreaming();
        rig.elapse(const Duration(seconds: 2));
        rig.left.packet();
        rig.elapse(const Duration(seconds: 2)); // right silent 4 s
        expect(rig.manager.snapshot().deltaForefootC, isNull);
      });
    });

    test('is null for a reading that is not normal quality', () {
      for (final q in [TempQuality.poorContact, TempQuality.sensorFault]) {
        fakeAsync((async) {
          final rig = Rig(async)..bothStreaming();
          rig.right.temp(31.5, 30.4, quality: q);
          expect(rig.manager.snapshot().deltaForefootC, isNull);
        });
      }
    });

    test('is null when a value could not be read', () {
      fakeAsync((async) {
        final rig = Rig(async)..bothStreaming();
        rig.right.temp(null, 30.4);
        final s = rig.manager.snapshot();
        expect(s.deltaForefootC, isNull);
        expect(s.deltaHeelC, closeTo(30.0 - 30.4, 1e-9));
      });
    });

    test('is null before both feet have sent a temperature', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.left
          ..stream()
          ..packet()
          ..temp(31, 30);
        rig.right
          ..stream()
          ..packet();
        expect(rig.manager.snapshot().deltaForefootC, isNull);
      });
    });

    test('an old connection\'s temperature does not survive a reconnect', () {
      fakeAsync((async) {
        final rig = Rig(async)..bothStreaming();
        rig.right
          ..set(const LinkSearching(deviceId: 'X'))
          ..stream()
          ..packet();
        expect(rig.manager.snapshot().deltaForefootC, isNull);
      });
    });
  });

  group('temperature events', () {
    test('are unix-timed on the session clock, after its first packet', () {
      fakeAsync((async) {
        final rig = Rig(async);
        final temps = <FootTemp>[];
        rig.manager.temps.listen(temps.add);
        rig.left
          ..stream()
          ..packet();
        final lastSample = rig.batches.last.samples.last;
        rig.elapse(const Duration(seconds: 1));
        rig.left.temp(31.0, 30.0);
        expect(temps.single.fromArrival, isFalse);
        expect(temps.single.session, 1);
        // On the device clock: the last sample's time + the device time since.
        expect(
          temps.single.unixMs - lastSample.unixMs,
          closeTo(rig.left.deviceNow - lastSample.deviceMs, 0.01),
        );
      });
    });

    test('use arrival time before the session has a packet', () {
      fakeAsync((async) {
        final rig = Rig(async)..bothStreaming();
        final temps = <FootTemp>[];
        rig.manager.temps.listen(temps.add);
        rig.left
          ..set(const LinkSearching(deviceId: 'X'))
          ..stream()
          ..temp(32.0, 30.0);
        expect(temps.single.fromArrival, isTrue);
        expect(temps.single.session, 2);
        expect(temps.single.unixMs, rig.now().microsecondsSinceEpoch / 1000);
      });
    });

    test('a reading sent before the first packet is kept for the display', () {
      fakeAsync((async) {
        final rig = Rig(async)..bothStreaming();
        rig.right
          ..set(const LinkSearching(deviceId: 'X'))
          ..stream()
          ..temp(31.9, 30.4)
          ..packet();
        expect(rig.manager.snapshot().deltaForefootC, closeTo(-0.1, 1e-9));
      });
    });
  });

  group('50 Hz path (rule 10)', () {
    test('every packet is a batch at once, unix-timed, 20 ms apart', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.left.stream();
        for (var i = 0; i < 20; i++) {
          rig.left.packet();
        }
        expect(rig.batches, hasLength(20));
        final unix = [
          for (final b in rig.batches)
            for (final s in b.samples) s.unixMs,
        ];
        for (var i = 1; i < unix.length; i++) {
          expect(unix[i] - unix[i - 1], inInclusiveRange(19.75, 20.25));
        }
        expect(rig.batches.first.samples.first.fsrAdc, hasLength(6));
      });
    });

    test('a batch from an older session is dropped (rule 9)', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.left
          ..stream()
          ..packet()
          ..stream()
          ..packet()
          ..packet(sessionOverride: 1);
        expect(rig.batches.map((b) => b.session), [1, 2]);
        expect(rig.manager.timing(FootSide.left).droppedOldSession, 1);
      });
    });

    test('lost packets are carried on the batch and counted', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.left
          ..stream()
          ..packet()
          ..packet(missingBefore: 2);
        expect(rig.batches.last.missingBefore, 2);
        expect(rig.manager.snapshot().left.lostPackets, 2);
        expect(rig.manager.timing(FootSide.left).lost, 2);
      });
    });

    test('a new session starts a new clock', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.left.stream();
        rig.left.packet();
        rig.elapse(const Duration(seconds: 5));
        // REBOOT: t0 restarts near 0 on the new connection.
        rig.left
          ..stream()
          ..t0 = 1536
          ..packet();
        final b = rig.batches.last;
        final expected = rig.now().millisecondsSinceEpoch - (1536 + 140);
        expect(b.samples.first.unixMs - b.samples.first.deviceMs, expected);
      });
    });
  });

  group('10 Hz display path', () {
    test('the ticker runs only while someone listens', () {
      fakeAsync((async) {
        final rig = Rig(async)..bothStreaming();
        final got = <DisplaySnapshot>[];
        final a = rig.manager.snapshots.listen(got.add);
        final b = rig.manager.snapshots.listen((_) {});
        expect(rig.manager.displayTicking, isTrue);
        rig.elapse(const Duration(seconds: 1));
        expect(got, hasLength(10));
        a.cancel();
        expect(rig.manager.displayTicking, isTrue);
        b.cancel();
        expect(rig.manager.displayTicking, isFalse);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('50 Hz input is not throttled by the display', () {
      fakeAsync((async) {
        final rig = Rig(async);
        final snaps = <DisplaySnapshot>[];
        rig.manager.snapshots.listen(snaps.add);
        rig.left.stream();
        for (var i = 0; i < 25; i++) {
          rig.left.packet();
          rig.elapse(const Duration(milliseconds: 40));
        }
        expect(rig.batches, hasLength(25));
        expect(snaps, hasLength(10));
      });
    });
  });

  group('temperature history', () {
    test('one point per 10-minute bucket, latest wins, normal only', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.left
          ..stream()
          ..packet()
          ..temp(31.0, 30.0);
        rig.walkLeft(const Duration(minutes: 3));
        rig.left
          ..packet()
          ..temp(31.4, 30.2)
          ..temp(40, 40, quality: TempQuality.sensorFault);
        rig.walkLeft(const Duration(minutes: 10));
        rig.left
          ..packet()
          ..temp(31.9, 30.5);
        final points = rig.manager.history(FootSide.left).points(rig.now());
        expect(points.map((p) => p.forefootC), [31.4, 31.9]);
      });
    });

    test('points older than 24 h fall out', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.left
          ..stream()
          ..packet()
          ..temp(31.0, 30.0);
        rig.elapse(const Duration(hours: 25));
        expect(rig.manager.history(FootSide.left).points(rig.now()), isEmpty);
      });
    });
  });
}
