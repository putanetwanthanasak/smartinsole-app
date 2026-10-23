import 'calibration.dart';
import 'link_state.dart';
import 'packets.dart';

/// One insole, one foot (contract §6 `IDataSource`). The two feet are
/// independent peripherals, so there is one source per foot: one side can be
/// streaming while the other is missing, and the UI must be able to say
/// which. `BleDataSource` implements this over Bluetooth; `MockDataSource`
/// (`lib/device/`) implements it for the emulator in debug builds.
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

  /// The calibration in use (contract §5.1): read at every connect, and
  /// again after a TARE. Null before the first connect. Research capture
  /// records it with every trial.
  Calibration? get calibration;

  /// Connects (and keeps reconnecting) to this foot's insole.
  Future<void> connect();

  /// Stops streaming and disconnects; no reconnect follows.
  Future<void> disconnect();
}

/// A sensor packet's samples in app units, on the device clock. Unix time
/// per sample is worked out downstream by `DeviceManager`
/// (`lib/device/device_clock.dart`) from [receivedAt] and `deviceMs`.
class SensorFrame {
  const SensorFrame({
    required this.side,
    required this.session,
    required this.seq,
    required this.missingBefore,
    required this.receivedAt,
    required this.saturated,
    required this.calibrating,
    required this.samples,
  });

  final FootSide side;

  /// Which streaming session (one per `START_STREAM`) this packet belongs
  /// to. Counts up for the life of the source and never repeats, so a
  /// consumer can tell a new connection's packets from an old one's.
  final int session;
  final int seq;

  /// Packets missing just before this one in its session (a `seq` gap, or
  /// a first packet whose `seq` is above 0). See `SeqTracker`.
  final int missingBefore;

  /// Phone time the packet arrived (rule 3); never the device clock.
  final DateTime receivedAt;
  final bool saturated;
  final bool calibrating;
  final List<SensorSample> samples;
}

class SensorSample {
  const SensorSample({
    required this.deviceMs,
    required this.fsrAdc,
    required this.fsrKpa,
    required this.accelG,
    required this.gyroDps,
  });

  /// `t0_ms + i × 20` (rule 1), device clock.
  final int deviceMs;

  /// Raw ADC per FSR channel (0–4095), channel index order. Kept because
  /// it is the source of truth (contract §5.1) and research capture stores
  /// it next to kPa.
  final List<int> fsrAdc;

  /// kPa per FSR channel, in channel index order (N channels).
  final List<double> fsrKpa;
  final List<double> accelG;
  final List<double> gyroDps;
}

class TempFrame {
  const TempFrame({
    required this.side,
    required this.session,
    required this.receivedAt,
    required this.packet,
  });

  final FootSide side;

  /// The streaming session it belongs to, as [SensorFrame.session]: a
  /// reading can arrive before the session's first sensor packet.
  final int session;
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
