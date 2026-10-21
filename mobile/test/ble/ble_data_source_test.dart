import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_central.dart';
import 'package:smartinsole/ble/ble_data_source.dart';
import 'package:smartinsole/ble/ble_event_log.dart';
import 'package:smartinsole/ble/ble_hub.dart';
import 'package:smartinsole/ble/ble_protocol.dart';
import 'package:smartinsole/ble/calibration.dart';
import 'package:smartinsole/ble/fsr_conversion.dart';
import 'package:smartinsole/ble/insole_data_source.dart';
import 'package:smartinsole/ble/link_state.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/ble/parse_result.dart';

import 'fake_ble_central.dart';
import 'packet_builder.dart';

/// Both feet against a [FakeBleCentral], under fake time.
class Rig {
  Rig(
    this.async, {
    List<FakeInsole> insoles = const [],
    PermissionStatus permission = PermissionStatus.granted,
  }) : central = FakeBleCentral(insoles: insoles),
       permissions = FakePermissions(permission) {
    final clock = async.getClock(DateTime(2026, 10, 20, 9));
    now = clock.now;
    log = BleEventLog(now: now);
    hub = BleHub(
      central: central,
      permissions: permissions,
      now: now,
      log: log,
    );
    left = BleDataSource(side: FootSide.left, hub: hub, now: now);
    right = BleDataSource(side: FootSide.right, hub: hub, now: now);
    left.frames.listen(leftFrames.add);
    left.temps.listen(leftTemps.add);
    left.states.listen(leftStates.add);
    hub.start();
    settle();
  }

  final FakeAsync async;
  final FakeBleCentral central;
  final FakePermissions permissions;
  late final DateTime Function() now;
  late final BleEventLog log;
  late final BleHub hub;
  late final BleDataSource left;
  late final BleDataSource right;
  final leftFrames = <SensorFrame>[];
  final leftTemps = <TempFrame>[];
  final leftStates = <LinkState>[];

  void settle([Duration d = Duration.zero]) {
    async.elapse(d);
    async.flushMicrotasks();
  }

  FakeLink link(String id) => central.insoles[id]!.link!;

  /// Calls made on [id]'s links, without the id prefix.
  List<String> callsOn(String id) => [
    for (final c in central.calls)
      if (c.startsWith('$id ')) c.substring(id.length + 1),
  ];

  int count(String call) => central.calls.where((c) => c == call).length;

  void connectLeft(String id) {
    left.connectTo(id);
    settle();
  }
}

FakeInsole leftBoard({String id = 'L1', String? name = 'SMARTINSOLE-L'}) =>
    FakeInsole(id: id, name: name, footSide: 0);

FakeInsole rightBoard({String id = 'R1', String? name = 'SMARTINSOLE-R'}) =>
    FakeInsole(id: id, name: name, footSide: 1);

void main() {
  group('connect sequence', () {
    test('runs in the FLUTTER-PLAN §5 order and ends streaming', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');

        expect(rig.central.calls, contains('connect L1'));
        expect(rig.callsOn('L1'), [
          'requestMtu 247',
          'priority high',
          'discover',
          'read status',
          'read calibration',
          'notify status',
          'notify sensor',
          'notify temperature',
          'write control 03+8',
          'write control 01',
        ]);
        final s = rig.left.state as LinkStreaming;
        expect(s.mtu, 247);
        expect(s.samplesPerPacket, 8);
        expect(s.fsrCount, 6);
        expect(s.deviceId, 'L1');
        expect(rig.left.stats.sessions, 1);
      });
    });

    test('SYNC_TIME carries the phone time as little-endian uint64', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        final sync = rig.link('L1').writes.first;
        expect(sync.length, BleOpcode.syncTimeBytes);
        expect(sync[0], BleOpcode.syncTime);
        expect(
          ByteData.sublistView(sync).getUint64(1, Endian.little),
          rig.now().millisecondsSinceEpoch,
        );
      });
    });

    test('emits frames in kPa with the phone arrival time (rules 1, 3)', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        rig.settle(const Duration(seconds: 3));
        final link = rig.link('L1');
        final t0 = link.t0;
        link.sendSensor();
        rig.settle();

        final f = rig.leftFrames.single;
        expect(f.side, FootSide.left);
        expect(f.seq, 0);
        expect(f.receivedAt, rig.now());
        expect(f.samples.map((s) => s.deviceMs), [
          for (var i = 0; i < 8; i++) t0 + i * 20,
        ]);
        final cal = (parseCalibration(
          jsonEncode(calibrationBlob(6)),
        ) as Parsed<Calibration>).value;
        final spec = sampleSpecs(6, 8).first;
        expect(f.samples.first.fsrKpa, [
          for (var ch = 0; ch < 6; ch++)
            adcToKpa(spec.fsr[ch], cal.channels[ch], cal),
        ]);
        expect(f.samples.first.accelG.first, spec.accel.first / 4096);
        expect(rig.left.stats.lastPacketAt, rig.now());
      });
    });

    test('a status notification is emitted, temperature too', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        rig.link('L1')
          ..sendTemp(forefoot: 3180, heel: -32768)
          ..sendStatus();
        rig.settle();
        expect(rig.leftTemps.single.packet.forefootC, 31.8);
        expect(rig.leftTemps.single.packet.heelC, isNull);
        expect(rig.left.stats.lastStatus!.batteryPct, 100);
      });
    });
  });

  group('MTU', () {
    for (final (mtu, n, fit) in [(247, 6, 8), (120, 6, 4), (123, 8, 4)]) {
      test('MTU $mtu with N = $n streams $fit samples/packet', () {
        fakeAsync((async) {
          final rig = Rig(
            async,
            insoles: [FakeInsole(id: 'L1', mtu: mtu, fsrCount: n)],
          );
          rig.connectLeft('L1');
          final s = rig.left.state as LinkStreaming;
          expect(s.mtu, mtu);
          expect(s.samplesPerPacket, fit);
          rig.link('L1').sendSensor(samples: fit);
          rig.settle();
          expect(rig.leftFrames.single.samples, hasLength(fit));
        });
      });
    }

    for (final (mtu, n, min) in [(23, 6, 107), (106, 6, 107), (122, 8, 123)]) {
      test('MTU $mtu with N = $n is a problem: no START, no retry', () {
        fakeAsync((async) {
          final rig = Rig(
            async,
            insoles: [FakeInsole(id: 'L1', mtu: mtu, fsrCount: n)],
          );
          rig.connectLeft('L1');
          final p = rig.left.state as LinkProblem;
          expect(p.kind, ProblemKind.mtuTooSmall);
          expect(p.mtu, mtu);
          expect(p.minMtu, min);
          expect(rig.callsOn('L1'), isNot(contains('write control 01')));
          expect(rig.callsOn('L1'), contains('disconnect'));
          rig.settle(const Duration(minutes: 1));
          expect(rig.count('connect L1'), 1);
        });
      });
    }

    test('an MTU drop mid-stream below the fallback stops with a problem', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        rig.link('L1').changeMtu(120);
        rig.settle();
        expect((rig.left.state as LinkStreaming).samplesPerPacket, 4);
        rig.link('L1').changeMtu(23);
        rig.settle();
        expect((rig.left.state as LinkProblem).kind, ProblemKind.mtuTooSmall);
      });
    });

    test('Retry after an MTU problem runs the whole sequence again', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [FakeInsole(id: 'L1', mtu: 23)]);
        rig.connectLeft('L1');
        expect(rig.left.state, isA<LinkProblem>());
        rig.central.insoles['L1']!.mtu = 247;
        rig.left.connect();
        rig.settle();
        expect(rig.left.state, isA<LinkStreaming>());
        expect(rig.count('L1 requestMtu 247'), 2);
      });
    });
  });

  group('foot side (rule 8)', () {
    test('a right insole in the left slot is rejected before START', () {
      fakeAsync((async) {
        // Named "-L" on purpose: the name is never trusted.
        final rig = Rig(async, insoles: [rightBoard(name: 'SMARTINSOLE-L')]);
        rig.connectLeft('R1');
        final p = rig.left.state as LinkProblem;
        expect(p.kind, ProblemKind.wrongSide);
        expect(p.reportedSide, FootSide.right);
        expect(rig.callsOn('R1'), [
          'requestMtu 247',
          'priority high',
          'discover',
          'read status',
          'disconnect',
        ]);
        rig.settle(const Duration(minutes: 1));
        expect(rig.count('connect R1'), 1, reason: 'no automatic reconnect');
      });
    });

    test('the side comes from foot_side, not from the advertised name', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard(name: 'SMARTINSOLE-R')]);
        rig.connectLeft('L1');
        expect(rig.left.state, isA<LinkStreaming>());
      });
    });

    test('a later status reporting the other side stops the stream', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        rig.link('L1').sendStatus(footSide: 1);
        rig.settle();
        expect((rig.left.state as LinkProblem).kind, ProblemKind.wrongSide);
        expect(rig.callsOn('L1').sublist(10), [
          'write control 02',
          'disconnect',
        ]);
      });
    });

    test('after a rejection the same insole connects in its own slot', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.right.connectTo('L1');
        rig.settle();
        expect((rig.right.state as LinkProblem).kind, ProblemKind.wrongSide);
        rig.connectLeft('L1');
        expect(rig.left.state, isA<LinkStreaming>());
      });
    });

    test('binding another insole starts fresh counters', () {
      fakeAsync((async) {
        final rig = Rig(
          async,
          insoles: [
            leftBoard(),
            leftBoard(id: 'L2'),
          ],
        );
        rig.connectLeft('L1');
        rig.link('L1').sendSensor();
        rig.settle();
        expect(rig.left.stats.packets, 1);
        rig.connectLeft('L2');
        expect(rig.left.state, isA<LinkStreaming>());
        expect(rig.left.stats.packets, 0);
        expect(rig.left.stats.sessions, 1);
        expect(rig.callsOn('L1').last, 'disconnect');
      });
    });

    test('an insole bound to one foot cannot be taken by the other', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        rig.right.connectTo('L1');
        rig.settle();
        expect(
          (rig.right.state as LinkProblem).kind,
          ProblemKind.inUseByOtherFoot,
        );
        expect(rig.left.state, isA<LinkStreaming>());
        expect(rig.count('connect L1'), 1);
      });
    });

    test('both feet stream at the same time', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard(), rightBoard()]);
        rig.left.connectTo('L1');
        rig.right.connectTo('R1');
        rig.settle();
        expect(rig.left.state, isA<LinkStreaming>());
        expect(rig.right.state, isA<LinkStreaming>());
      });
    });

    test('a device without the GATT service is not an insole', () {
      fakeAsync((async) {
        final rig = Rig(
          async,
          insoles: [FakeInsole(id: 'X', hasService: false)],
        );
        rig.connectLeft('X');
        expect((rig.left.state as LinkProblem).kind, ProblemKind.notAnInsole);
      });
    });

    test('a malformed calibration blob is a problem, not a default curve', () {
      fakeAsync((async) {
        final rig = Rig(
          async,
          insoles: [FakeInsole(id: 'L1', calibrationJson: '{"channels": []}')],
        );
        rig.connectLeft('L1');
        final p = rig.left.state as LinkProblem;
        expect(p.kind, ProblemKind.calibrationInvalid);
        expect(p.rejectReason, RejectReason.calibrationMissingField);
        expect(rig.callsOn('L1'), isNot(contains('write control 01')));
      });
    });
  });

  group('stale packets (rule 9)', () {
    test('packets before the START acknowledgement are dropped', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.central.onWrite = (link, value) {
          if (value[0] == BleOpcode.syncTime ||
              value[0] == BleOpcode.startStream) {
            link
              ..sendSensor()
              ..sendTemp();
          }
        };
        rig.connectLeft('L1');
        expect(rig.left.state, isA<LinkStreaming>());
        expect(rig.leftFrames, isEmpty);
        expect(rig.leftTemps, isEmpty);
        expect(rig.left.stats.droppedBeforeStart, 4);

        rig.central.onWrite = null;
        rig.link('L1').sendSensor();
        rig.settle();
        expect(rig.leftFrames, hasLength(1));
      });
    });

    test('t0 must advance within a connection; duplicates are dropped', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        final link = rig.link('L1');
        final specs = sampleSpecs(6, 8);
        Uint8List at(int seq, int t0) =>
            buildSensorPacket(seq: seq, t0Ms: t0, samples: specs);
        link
          ..push(BleUuids.sensorStream, at(0, 5000))
          ..push(BleUuids.sensorStream, at(1, 4840)) // backwards
          ..push(BleUuids.sensorStream, at(2, 5000)) // duplicate
          ..push(BleUuids.sensorStream, at(3, 5160));
        rig.settle();
        expect(rig.leftFrames.map((f) => f.seq), [0, 3]);
        expect(rig.left.stats.droppedNotForward, 2);
      });
    });

    test('temperature t_ms must advance too', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        rig.link('L1')
          ..sendTemp(tMs: 60000)
          ..sendTemp(tMs: 30000)
          ..sendTemp(tMs: 90000);
        rig.settle();
        expect(rig.leftTemps.map((t) => t.packet.tMs), [60000, 90000]);
        expect(rig.left.stats.droppedNotForward, 1);
      });
    });

    test('t0 restarting on a new connection is accepted (REBOOT)', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        rig.link('L1')
          ..t0 = 163106
          ..sendSensor()
          ..drop();
        rig.settle(const Duration(seconds: 1));
        expect(rig.left.state, isA<LinkStreaming>());
        rig.link('L1')
          ..t0 = 1536
          ..sendSensor();
        rig.settle();
        expect(rig.leftFrames.map((f) => f.samples.first.deviceMs), [
          163106,
          1536,
        ]);
        expect(rig.left.stats.droppedNotForward, 0);
      });
    });

    test('the uint32 t0 wrap is not "backwards"', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        rig.link('L1')
          ..t0 = 0xFFFFFFFF - 100
          ..sendSensor()
          ..sendSensor();
        rig.settle();
        expect(rig.leftFrames, hasLength(2));
        expect(rig.leftFrames.last.samples.first.deviceMs, 59);
      });
    });

    test('nothing from an old connection is emitted after a reconnect', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        final old = rig.link('L1')..drop();
        rig.settle(const Duration(seconds: 1));
        final fresh = rig.link('L1');
        expect(identical(old, fresh), isFalse);
        old.push(BleUuids.sensorStream, old.nextSensorPacket());
        fresh.sendSensor();
        rig.settle();
        expect(rig.leftFrames, hasLength(1));
      });
    });

    test('advances() works modulo 2^32', () {
      expect(advances(100, 260), isTrue);
      expect(advances(260, 100), isFalse);
      expect(advances(100, 100), isFalse);
      expect(advances(0xFFFFFF00, 0x60), isTrue);
      expect(advances(0x60, 0xFFFFFF00), isFalse);
    });
  });

  group('rejections and counters', () {
    test('parser rejections are counted by reason, never emitted', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        final link = rig.link('L1');
        final good = link.nextSensorPacket();
        link
          ..push(BleUuids.sensorStream, Uint8List.sublistView(good, 0, 199))
          ..push(
            BleUuids.sensorStream,
            buildSensorPacket(seq: 9, t0Ms: 1, samples: sampleSpecs(8, 6)),
          )
          ..push(BleUuids.temperature, Uint8List(5))
          ..push(BleUuids.deviceStatus, Uint8List(8)..[3] = 7);
        rig.settle();
        expect(rig.leftFrames, isEmpty);
        expect(rig.left.stats.rejects, {
          RejectReason.truncated: 1,
          RejectReason.lengthMismatch: 1,
          RejectReason.tooShort: 1,
          RejectReason.invalidFootSide: 1,
        });
        expect(rig.left.state, isA<LinkStreaming>());
      });
    });

    test('seq gaps are counted, with the wrap at 65535', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        final link = rig.link('L1')..sendSensor();
        link.seq += 3;
        link
          ..sendSensor()
          ..seq = 65535
          ..sendSensor()
          ..sendSensor(); // seq 0
        rig.settle();
        expect(rig.leftFrames.map((f) => f.seq), [0, 4, 65535, 0]);
        expect(rig.left.stats.seqGaps, 2); // 0 -> 4 and 4 -> 65535
        expect(rig.left.stats.seqMissing, 3 + 65530);
      });
    });

    test('calibration is re-read when the TARE flag clears (BACKLOG 23)', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        final insole = rig.central.insoles['L1']!;
        final blob = calibrationBlob(6);
        for (final c in blob['channels']! as List) {
          (c as Map)['offset_adc'] = 19;
        }
        insole.calibrationJson = jsonEncode(blob);
        rig.link('L1')
          ..sendSensor(flags: SensorLayout.flagCalibrating)
          ..sendSensor(flags: SensorLayout.flagCalibrating)
          ..sendSensor();
        rig.settle();
        expect(rig.count('L1 read calibration'), 2);
        expect(rig.left.stats.calibrationRereads, 1);
        expect(rig.left.calibration!.channels.first.offsetAdc, 19);
        expect(rig.leftFrames.map((f) => f.calibrating), [true, true, false]);
      });
    });
  });

  group('reconnect', () {
    test('a lost link reconnects with MTU 247 and the side checked again', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        rig.link('L1').drop();
        rig.settle(const Duration(seconds: 1));
        expect(rig.left.state, isA<LinkStreaming>());
        expect(rig.count('L1 requestMtu 247'), 2);
        expect(rig.count('L1 read status'), 2);
        expect(rig.count('L1 read calibration'), 2);
        expect(rig.count('L1 write control 01'), 2);
        expect(rig.left.stats.linkLosses, 1);
        expect(rig.left.stats.sessions, 2);
      });
    });

    test('a power-cycled board is found again by the scan', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        final insole = rig.central.insoles['L1']!..advertising = false;
        rig.link('L1').drop();
        rig.settle(const Duration(seconds: 20));
        expect(
          rig.left.state,
          anyOf(isA<LinkSearching>(), isA<LinkRetryWait>()),
        );

        insole.advertising = true;
        rig.settle(const Duration(seconds: 6));
        expect(rig.left.state, isA<LinkStreaming>());
        expect(rig.count('L1 requestMtu 247'), 2);
      });
    });

    test('a reflashed board that now reports the other side is rejected', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        rig.central.insoles['L1']!.footSide = 1;
        rig.link('L1').drop();
        rig.settle(const Duration(seconds: 1));
        expect((rig.left.state as LinkProblem).kind, ProblemKind.wrongSide);
      });
    });

    test('failed attempts back off 1, 2, 4, then 5 s', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.central.insoles['L1']!.failConnects = 5;
        rig.connectLeft('L1');

        final waits = <(int, Duration)>[];
        rig.left.states.listen((s) {
          if (s is LinkRetryWait) {
            waits.add((s.attempt, s.retryAt.difference(rig.now())));
          }
        });
        final first = rig.left.state as LinkRetryWait;
        expect(first.attempt, 1);
        expect(first.retryAt.difference(rig.now()), const Duration(seconds: 1));
        rig.settle(const Duration(seconds: 30));
        expect(waits, [
          (2, const Duration(seconds: 2)),
          (3, const Duration(seconds: 4)),
          (4, const Duration(seconds: 5)),
          (5, const Duration(seconds: 5)),
        ]);
        expect(rig.left.state, isA<LinkStreaming>());
        expect(rig.left.stats.failedAttempts, 5);
        expect(rig.central.scanStarts, 1, reason: 'retries reuse the scan');
      });
    });

    test("the user's Disconnect stops the stream and never reconnects", () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        rig.left.disconnect();
        rig.settle();
        expect(rig.callsOn('L1').sublist(10), [
          'write control 02',
          'disconnect',
        ]);
        expect(rig.left.state, isA<LinkIdle>());
        rig.settle(const Duration(minutes: 1));
        expect(rig.count('connect L1'), 1);
      });
    });

    test('Bluetooth off blocks; on again reconnects', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        rig.central.setAdapter(AdapterState.off);
        rig.settle(const Duration(seconds: 1));
        expect(
          (rig.left.state as LinkBlocked).reason,
          BleReadiness.bluetoothOff,
        );
        // The link drop can arrive before the adapter event (as on
        // Android), so one attempt may fail first; after that, nothing.
        final attempts = rig.count('connect L1');
        rig.settle(const Duration(minutes: 1));
        expect(rig.count('connect L1'), attempts, reason: 'none while off');

        rig.central.setAdapter(AdapterState.on);
        rig.settle(const Duration(seconds: 1));
        expect(rig.left.state, isA<LinkStreaming>());
        expect(rig.count('L1 requestMtu 247'), 2);
      });
    });
  });

  group('permissions and scanning', () {
    test('denied permission blocks until granted', () {
      fakeAsync((async) {
        final rig = Rig(
          async,
          insoles: [leftBoard()],
          permission: PermissionStatus.denied,
        );
        expect(rig.permissions.requests, 1, reason: 'asked once at start');
        expect(rig.hub.readiness, BleReadiness.needsPermission);
        rig.connectLeft('L1');
        expect(
          (rig.left.state as LinkBlocked).reason,
          BleReadiness.needsPermission,
        );
        expect(rig.central.calls, isNot(contains('startScan')));

        rig.permissions.answer = PermissionStatus.granted;
        rig.hub.requestPermission();
        rig.settle();
        expect(rig.left.state, isA<LinkStreaming>());
      });
    });

    test('a permanent denial needs the settings page', () {
      fakeAsync((async) {
        final rig = Rig(async, permission: PermissionStatus.permanentlyDenied);
        expect(rig.hub.readiness, BleReadiness.permissionDenied);
        expect(rig.permissions.requests, 0);
      });
    });

    test('no hardware reads as unavailable', () {
      fakeAsync((async) {
        final rig = Rig(async);
        rig.central.setAdapter(AdapterState.unavailable);
        rig.settle();
        expect(rig.hub.readiness, BleReadiness.unavailable);
      });
    });

    test('at most 4 scan starts in 30 s (Android silently blocks the 6th)', () {
      fakeAsync((async) {
        final rig = Rig(async);
        final owner = Object();
        for (var i = 0; i < 6; i++) {
          rig.hub.acquireScan(owner);
          rig.settle();
          rig.hub.releaseScan(owner);
          rig.settle();
        }
        rig.hub.acquireScan(owner);
        rig.settle();
        expect(rig.central.scanStarts, 4);
        expect(rig.central.scanning, isFalse);
        rig.settle(const Duration(seconds: 31));
        expect(rig.central.scanStarts, 5);
        expect(rig.central.scanning, isTrue);
      });
    });

    test('the scan stops once no foot is searching', () {
      fakeAsync((async) {
        final rig = Rig(async, insoles: [leftBoard()]);
        rig.connectLeft('L1');
        expect(
          rig.central.calls,
          containsAllInOrder(['startScan', 'stopScan']),
        );
        expect(rig.central.scanning, isFalse);
        expect(rig.hub.seen.single.deviceId, 'L1');
      });
    });
  });
}
