import 'link_state.dart';
import 'packets.dart';

/// One insole, one foot (contract §6 `IDataSource`). The two feet are
/// independent peripherals, so there is one source per foot: one side can be
/// streaming while the other is missing, and the UI must be able to say
/// which. `BleDataSource` implements this over Bluetooth; S4 adds a
/// `MockDataSource` with the same interface for the emulator.
///
/// Every stream is a broadcast stream. Listeners cancel their subscriptions
/// when they go away; the source keeps running regardless.
abstract interface class InsoleDataSource {
  FootSide get side;

  LinkState get state;
  Stream<LinkState> get states;

  /// One frame per sensor packet that passed every check (50 Hz path).
  Stream<SensorFrame> get frames;
  Stream<TempFrame> get temps;
  Stream<StatusFrame> get statuses;

  /// Connects (and keeps reconnecting) to this foot's insole.
  Future<void> connect();

  /// Stops streaming and disconnects; no reconnect follows.
  Future<void> disconnect();
}

/// A sensor packet's samples in app units. No unix time yet: converting
/// `deviceMs` with the `SYNC_TIME` offset is S4's job.
class SensorFrame {
  const SensorFrame({
    required this.side,
    required this.seq,
    required this.receivedAt,
    required this.saturated,
    required this.calibrating,
    required this.samples,
  });

  final FootSide side;
  final int seq;

  /// Phone time the packet arrived (rule 3); never the device clock.
  final DateTime receivedAt;
  final bool saturated;
  final bool calibrating;
  final List<SensorSample> samples;
}

class SensorSample {
  const SensorSample({
    required this.deviceMs,
    required this.fsrKpa,
    required this.accelG,
    required this.gyroDps,
  });

  /// `t0_ms + i × 20` (rule 1), device clock.
  final int deviceMs;

  /// kPa per FSR channel, in channel index order (N channels).
  final List<double> fsrKpa;
  final List<double> accelG;
  final List<double> gyroDps;
}

class TempFrame {
  const TempFrame({
    required this.side,
    required this.receivedAt,
    required this.packet,
  });

  final FootSide side;
  final DateTime receivedAt;
  final TempPacket packet;
}

class StatusFrame {
  const StatusFrame({
    required this.side,
    required this.receivedAt,
    required this.packet,
  });

  final FootSide side;
  final DateTime receivedAt;
  final StatusPacket packet;
}
