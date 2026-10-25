import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_central.dart';
import 'package:smartinsole/ble/ble_data_source.dart';
import 'package:smartinsole/ble/ble_event_log.dart';
import 'package:smartinsole/ble/ble_hub.dart';
import 'package:smartinsole/ble/foot_connector.dart';
import 'package:smartinsole/ble/foot_finder.dart';
import 'package:smartinsole/ble/link_state.dart';
import 'package:smartinsole/ble/packets.dart';

import 'fake_ble_central.dart';

/// Both feet's finders against a [FakeBleCentral], under fake time.
class FinderRig {
  FinderRig(
    this.async, {
    List<FakeInsole> insoles = const [],
    this.bound = const {},
  }) : central = FakeBleCentral(insoles: insoles) {
    final clock = async.getClock(DateTime(2026, 10, 25, 9));
    now = clock.now;
    log = BleEventLog(now: now, capacity: 1000);
    hub = BleHub(
      central: central,
      permissions: FakePermissions(),
      now: now,
      log: log,
    );
    remembered = {...bound};
    for (final side in FootSide.values) {
      sources[side] = BleDataSource(side: side, hub: hub, now: now);
      finders[side] = FootFinder(
        source: sources[side]!,
        hub: hub,
        now: now,
        recall: () => remembered[side],
        remember: (id) async {
          if (id == null) {
            remembered.remove(side);
          } else {
            remembered[side] = id;
          }
        },
      );
    }
    settle();
  }

  final FakeAsync async;
  final FakeBleCentral central;
  final Map<FootSide, String> bound;
  late final Map<FootSide, String> remembered;
  late final DateTime Function() now;
  late final BleEventLog log;
  late final BleHub hub;
  final sources = <FootSide, BleDataSource>{};
  final finders = <FootSide, FootFinder>{};

  FootFinder get left => finders[FootSide.left]!;
  FootFinder get right => finders[FootSide.right]!;
  BleDataSource get leftSource => sources[FootSide.left]!;
  BleDataSource get rightSource => sources[FootSide.right]!;

  void settle([Duration d = Duration.zero]) {
    async.elapse(d);
    async.flushMicrotasks();
  }

  /// Every call on [id]'s links, without the id prefix.
  List<String> callsOn(String id) => [
    for (final c in central.calls)
      if (c.startsWith('$id ')) c.substring(id.length + 1),
  ];

  List<String> logLines() => [for (final e in log.entries) e.message];
}

FakeInsole leftBoard({String id = 'L1', int mtu = 247}) =>
    FakeInsole(id: id, name: 'SMARTINSOLE-L', footSide: 0, mtu: mtu);

FakeInsole rightBoard({String id = 'R1'}) =>
    FakeInsole(id: id, name: 'SMARTINSOLE-R', footSide: 1);

const startWrite = 'write control 01';

void main() {
  test('both insoles on: each foot finds its own and remembers it', () {
    fakeAsync((async) {
      // The right board first in the list, so the left foot meets it first.
      final rig = FinderRig(async, insoles: [rightBoard(), leftBoard()]);
      rig.left.find();
      rig.right.find();
      rig.settle(const Duration(seconds: 3));

      expect(rig.leftSource.state, isA<LinkStreaming>());
      expect(rig.leftSource.state.deviceId, 'L1');
      expect(rig.rightSource.state, isA<LinkStreaming>());
      expect(rig.rightSource.state.deviceId, 'R1');
      expect(rig.left.state, isA<FinderIdle>());
      expect(rig.right.state, isA<FinderIdle>());
      expect(rig.remembered, {FootSide.left: 'L1', FootSide.right: 'R1'});
      // The scan is released once both found theirs.
      rig.settle(const Duration(seconds: 1));
      expect(rig.central.scanning, isFalse);
    });
  });

  test('the other foot\'s insole seen first: rejected, then this foot\'s '
      'is found', () {
    fakeAsync((async) {
      final rig = FinderRig(async, insoles: [rightBoard(), leftBoard()]);
      rig.left.find();
      rig.settle(const Duration(seconds: 3));
      expect(
        rig.logLines(),
        containsAllInOrder([
          'trying R1',
          'R1 is the right insole; looking further',
          'trying L1',
          "found this foot's insole L1",
        ]),
      );
      expect(rig.callsOn('R1'), isNot(contains(startWrite)));
      expect(rig.leftSource.state.deviceId, 'L1');
      expect(rig.left.state, isA<FinderIdle>());
    });
  });

  test('only the other foot\'s insole: wrong side after the grace time, '
      'and it was never started (rule 8)', () {
    fakeAsync((async) {
      final rig = FinderRig(async, insoles: [rightBoard()]);
      rig.left.find();
      rig.settle(const Duration(seconds: 1));
      expect(rig.left.state, isA<FinderSearching>());
      rig.settle(FootFinder.defaultWrongSideGrace);

      final s = rig.left.state;
      expect(s, isA<FinderWrongSide>());
      expect((s as FinderWrongSide).reportedSide, FootSide.right);
      expect(rig.callsOn('R1'), isNot(contains(startWrite)));
      expect(rig.remembered, isEmpty);
      // The rejected insole is free for the right foot.
      expect(rig.hub.claimedBy('R1'), isNull);
      rig.right.find();
      rig.settle(const Duration(seconds: 2));
      expect(rig.rightSource.state, isA<LinkStreaming>());
    });
  });

  test('nothing advertising: not found after the 20 s window', () {
    fakeAsync((async) {
      final rig = FinderRig(async);
      rig.left.find();
      rig.settle(const Duration(seconds: 19));
      expect(rig.left.state, isA<FinderSearching>());
      rig.settle(const Duration(seconds: 1));
      expect(rig.left.state, isA<FinderNotFound>());
      expect(rig.central.scanning, isFalse);
    });
  });

  test('a board switched on during the window is found', () {
    fakeAsync((async) {
      final board = leftBoard()..advertising = false;
      final rig = FinderRig(async, insoles: [board]);
      rig.left.find();
      rig.settle(const Duration(seconds: 8));
      board.advertising = true;
      rig.settle(const Duration(seconds: 1));
      expect(rig.leftSource.state, isA<LinkStreaming>());
      expect(rig.left.state, isA<FinderIdle>());
    });
  });

  test('"หยุดค้นหา" stops the search and the scan', () {
    fakeAsync((async) {
      final rig = FinderRig(async);
      rig.left.find();
      rig.settle(const Duration(seconds: 2));
      expect(rig.central.scanning, isTrue);
      rig.left.stop();
      rig.settle();
      expect(rig.left.state, isA<FinderIdle>());
      expect(rig.leftSource.state, isA<LinkIdle>());
      rig.settle(const Duration(seconds: 1));
      expect(rig.central.scanning, isFalse);
      // The window timer was cancelled: no "not found" later.
      rig.settle(const Duration(seconds: 30));
      expect(rig.left.state, isA<FinderIdle>());
    });
  });

  test('Bluetooth off mid-search: back to idle; find again once on', () {
    fakeAsync((async) {
      final rig = FinderRig(async);
      rig.left.find();
      rig.settle(const Duration(seconds: 2));
      rig.central.setAdapter(AdapterState.off);
      rig.settle();
      expect(rig.hub.readiness, BleReadiness.bluetoothOff);
      expect(rig.left.state, isA<FinderIdle>());

      // Finding while off does nothing (the screen shows the BT panel).
      rig.left.find();
      rig.settle();
      expect(rig.left.state, isA<FinderIdle>());

      rig.central.add(leftBoard());
      rig.central.setAdapter(AdapterState.on);
      rig.settle();
      rig.left.find();
      rig.settle(const Duration(seconds: 2));
      expect(rig.leftSource.state, isA<LinkStreaming>());
    });
  });

  test(
    'MTU too small: this foot\'s insole is kept, as "connected, no data"',
    () {
      fakeAsync((async) {
        final rig = FinderRig(async, insoles: [leftBoard(mtu: 23)]);
        rig.left.find();
        rig.settle(const Duration(seconds: 2));
        final s = rig.leftSource.state;
        expect(s, isA<LinkProblem>());
        expect((s as LinkProblem).kind, ProblemKind.mtuTooSmall);
        expect(rig.left.state, isA<FinderIdle>());
        expect(rig.remembered[FootSide.left], 'L1');
      });
    },
  );

  test('a failed connect (GATT 133) is tried again within the window', () {
    fakeAsync((async) {
      final rig = FinderRig(async, insoles: [leftBoard()..failConnects = 1]);
      rig.left.find();
      rig.settle(const Duration(seconds: 3));
      expect(rig.leftSource.state, isA<LinkStreaming>());
    });
  });

  test('"ยกเลิกการเชื่อมต่อ" stops streaming and forgets the insole', () {
    fakeAsync((async) {
      final rig = FinderRig(async, insoles: [leftBoard()]);
      rig.left.find();
      rig.settle(const Duration(seconds: 2));
      expect(rig.remembered[FootSide.left], 'L1');
      rig.left.disconnect();
      rig.settle();
      expect(rig.leftSource.state, isA<LinkIdle>());
      expect(rig.remembered, isEmpty);
      expect(rig.callsOn('L1'), contains('write control 02'));
    });
  });

  group('auto-reconnect and its record (BACKLOG 45)', () {
    test('at app start the remembered insole reconnects, and is logged', () {
      fakeAsync((async) {
        final rig = FinderRig(
          async,
          insoles: [leftBoard()],
          bound: {FootSide.left: 'L1'},
        );
        rig.left.autoConnect();
        rig.right.autoConnect(); // nothing remembered: does nothing
        rig.settle(const Duration(seconds: 2));

        expect(rig.leftSource.state, isA<LinkStreaming>());
        expect(rig.rightSource.state, isA<LinkIdle>());
        final r = rig.left.reconnects;
        expect(r.attempts, 1);
        expect(r.succeeded, 1);
        expect(r.pending, isFalse);
        expect(r.history.single.reason, 'app start');
        expect(r.history.single.outcome, 'streaming');
        expect(rig.right.reconnects.attempts, 0);
        expect(
          rig.logLines(),
          containsAllInOrder([
            'auto-reconnect #1 (app start) to L1',
            startsWith('auto-reconnect #1 → streaming after'),
          ]),
        );
      });
    });

    test('a lost link: attempt, failed tries and the time to streaming', () {
      fakeAsync((async) {
        final board = leftBoard();
        final rig = FinderRig(async, insoles: [board]);
        rig.left.find();
        rig.settle(const Duration(seconds: 2));
        expect(rig.left.reconnects.attempts, 0);

        // Power cycle: the link drops, and the board is away for 6 s.
        board.advertising = false;
        board.link!.drop();
        rig.settle();
        expect(rig.left.reconnects.pending, isTrue);
        expect(rig.left.reconnects.reason, 'link lost');
        rig.settle(const Duration(seconds: 6));
        board.advertising = true;
        rig.settle(const Duration(seconds: 2));

        expect(rig.leftSource.state, isA<LinkStreaming>());
        final r = rig.left.reconnects;
        expect(r.attempts, 1);
        expect(r.succeeded, 1);
        expect(r.lastDuration!.inSeconds, inInclusiveRange(6, 8));
        expect(rig.logLines(), contains('auto-reconnect #1 (link lost) to L1'));
      });
    });

    test('the user disconnecting ends a pending attempt as cancelled', () {
      fakeAsync((async) {
        final rig = FinderRig(async, bound: {FootSide.left: 'L1'});
        rig.left.autoConnect();
        rig.settle(const Duration(seconds: 5));
        expect(rig.leftSource.state, isA<LinkSearching>());
        rig.left.stop();
        rig.settle();
        expect(rig.left.reconnects.history.single.outcome, 'cancelled');
        // Stopping a search keeps the insole for the next app start.
        expect(rig.remembered[FootSide.left], 'L1');
      });
    });
  });
}
