import 'dart:async';

import 'package:smartinsole/ble/calibration.dart';
import 'package:smartinsole/ble/insole_data_source.dart';
import 'package:smartinsole/ble/link_state.dart';
import 'package:smartinsole/ble/packets.dart';

/// A hand-driven [InsoleDataSource] for DeviceManager tests.
class FakeSource implements InsoleDataSource {
  FakeSource(this.side, {required this.now});

  @override
  final FootSide side;
  final DateTime Function() now;

  LinkState _state = const LinkIdle();
  final _states = StreamController<LinkState>.broadcast(sync: true);
  final _frames = StreamController<SensorFrame>.broadcast(sync: true);
  final _temps = StreamController<TempFrame>.broadcast(sync: true);
  final _statuses = StreamController<StatusFrame>.broadcast(sync: true);

  int session = 0;
  int seq = 0;
  int t0 = 50000;

  @override
  LinkState get state => _state;
  @override
  Stream<LinkState> get states => _states.stream;
  @override
  Stream<SensorFrame> get frames => _frames.stream;
  @override
  Stream<TempFrame> get temps => _temps.stream;
  @override
  Calibration? calibration;

  @override
  Stream<StatusFrame> get statuses => _statuses.stream;

  int connects = 0;

  @override
  Future<void> connect() async {
    connects++;
    stream();
  }

  @override
  Future<void> disconnect() async => set(const LinkIdle(deviceId: 'X'));

  void set(LinkState s) {
    _state = s;
    _states.add(s);
  }

  /// A new streaming session.
  void stream() {
    session++;
    seq = 0;
    set(
      LinkStreaming(
        deviceId: 'X',
        mtu: 247,
        samplesPerPacket: 8,
        fsrCount: 6,
        since: now(),
      ),
    );
  }

  /// One packet of 8 samples, all channels at [kpa], or each sample from
  /// [sample] (given the sample's index in the packet).
  void packet({
    double kpa = 10,
    int missingBefore = 0,
    int? sessionOverride,
    DateTime? at,
    SensorSample Function(int i, int deviceMs)? sample,
  }) {
    _frames.add(
      SensorFrame(
        side: side,
        session: sessionOverride ?? session,
        seq: seq,
        missingBefore: missingBefore,
        receivedAt: at ?? now(),
        saturated: false,
        calibrating: false,
        samples: [
          for (var i = 0; i < 8; i++)
            if (sample != null)
              sample(i, (t0 + i * 20) & 0xFFFFFFFF)
            else
              SensorSample(
                deviceMs: (t0 + i * 20) & 0xFFFFFFFF,
                fsrAdc: List.filled(6, 1000),
                fsrKpa: List.filled(6, kpa),
                accelG: [0, 0, 1],
                gyroDps: [0, 0, 0],
              ),
        ],
      ),
    );
    _lastSampleMs = t0 + 140;
    _lastPacketAt = at ?? now();
    seq = (seq + 1) & 0xFFFF;
    t0 = (t0 + 160) & 0xFFFFFFFF;
  }

  int? _lastSampleMs;
  DateTime? _lastPacketAt;

  /// Device time now: the board's clock keeps running between packets.
  int get deviceNow {
    final last = _lastPacketAt;
    if (last == null) return t0;
    return (_lastSampleMs! + now().difference(last).inMilliseconds) &
        0xFFFFFFFF;
  }

  void temp(
    double? forefoot,
    double? heel, {
    TempQuality quality = TempQuality.normal,
  }) => _temps.add(
    TempFrame(
      side: side,
      session: session,
      receivedAt: now(),
      packet: TempPacket(
        seq: 0,
        tMs: deviceNow,
        forefootC: forefoot,
        heelC: heel,
        quality: quality,
      ),
    ),
  );

  void status({int battery = 80}) => _statuses.add(
    StatusFrame(
      side: side,
      receivedAt: now(),
      packet: StatusPacket(
        batteryPct: battery,
        batteryMv: 4000,
        footSide: side,
        fwMajor: 1,
        fwMinor: 2,
        state: DeviceState.streaming,
        errorCode: 0,
      ),
    ),
  );
}
