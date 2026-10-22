import 'dart:async';
import 'dart:math' as math;

import '../ble/insole_data_source.dart';
import '../ble/link_state.dart';
import '../ble/packets.dart';
import 'device_clock.dart';
import 'display_snapshot.dart';
import 'foot_sample.dart';
import 'temp_history.dart';

/// Combines the two feet (FLUTTER-PLAN §3 `device/`). The only place that:
/// - gives every sample a unix time ([DeviceClock], one per foot per
///   session);
/// - runs the 50 Hz path ([batches], unthrottled) apart from the 10 Hz
///   display path ([snapshots]) (rule 10);
/// - decides staleness, from timestamps at read time, never with a timer
///   that latches a flag (rule 2);
/// - computes ΔT, null unless both feet are usable (rule 4).
///
/// The two feet stay independent sources (one can stream while the other
/// is missing), so everything here is per foot until the snapshot.
class DeviceManager {
  DeviceManager({
    required InsoleDataSource left,
    required InsoleDataSource right,
    required this.now,
    this.staleAfter = defaultStaleAfter,
    this.displayPeriod = defaultDisplayPeriod,
  }) {
    _feet = {FootSide.left: _Foot(left), FootSide.right: _Foot(right)};
    for (final f in _feet.values) {
      _watch(f);
    }
  }

  /// Streaming but silent for this long → stale (as the web app).
  /// Technical, not a clinical threshold: packets come every 160 ms.
  static const defaultStaleAfter = Duration(seconds: 3);

  /// The display path's rate: 10 Hz.
  static const defaultDisplayPeriod = Duration(milliseconds: 100);

  final DateTime Function() now;
  final Duration staleAfter;
  final Duration displayPeriod;

  late final Map<FootSide, _Foot> _feet;
  final _batches = StreamController<FootBatch>.broadcast(sync: true);
  late final _snapshots = StreamController<DisplaySnapshot>.broadcast(
    onListen: _startTicker,
    onCancel: _stopTicker,
  );
  Timer? _ticker;

  /// 50 Hz path: every accepted packet of either foot, as it arrives,
  /// unix-timed. Research capture (S4C) and the rules (S7) listen here.
  /// Delivered synchronously, in arrival order.
  Stream<FootBatch> get batches => _batches.stream;

  /// 10 Hz display path. The ticker runs only while someone listens.
  Stream<DisplaySnapshot> get snapshots => _snapshots.stream;

  /// Whether the 10 Hz ticker is running (for tests and the debug screen).
  bool get displayTicking => _ticker != null;

  InsoleDataSource source(FootSide side) => _feet[side]!.source;

  Future<void> connect(FootSide side) => _feet[side]!.source.connect();
  Future<void> disconnect(FootSide side) => _feet[side]!.source.disconnect();
  Future<void> connectAll() =>
      Future.wait([connect(FootSide.left), connect(FootSide.right)]);

  /// Temperature trend of one foot.
  TempHistory history(FootSide side) => _feet[side]!.history;

  /// Clock and continuity figures of one foot, for the timing log.
  FootTiming timing(FootSide side) {
    final f = _feet[side]!;
    final t = FootTiming(
      session: f.session,
      packets: f.sessionPackets,
      lost: f.sessionLost,
      lastSeq: f.lastSeq,
      offsetMs: f.clock?.offsetMs,
      targetMs: f.clock?.targetMs,
      lastExcessMs: f.clock?.lastExcessMs,
      clamps: f.clock?.clamps ?? 0,
      stepMinMs: f.stepMin,
      stepMaxMs: f.stepMax,
      droppedOldSession: f.droppedOldSession,
    );
    f.stepMin = null;
    f.stepMax = null;
    return t;
  }

  /// Both feet now, everything derived at this call.
  DisplaySnapshot snapshot() {
    final at = now();
    final left = _view(_feet[FootSide.left]!, at);
    final right = _view(_feet[FootSide.right]!, at);
    return DisplaySnapshot(
      at: at,
      left: left,
      right: right,
      deltaForefootC: _delta(left, right, (t) => t.forefootC),
      deltaHeelC: _delta(left, right, (t) => t.heelC),
    );
  }

  void dispose() {
    _stopTicker();
    for (final f in _feet.values) {
      for (final s in f.subs) {
        s.cancel();
      }
    }
    _batches.close();
    _snapshots.close();
  }

  // --- Inputs -------------------------------------------------------------

  void _watch(_Foot f) {
    f.subs
      ..add(f.source.states.listen((s) => _onState(f, s)))
      ..add(f.source.frames.listen((fr) => _onFrame(f, fr)))
      ..add(f.source.temps.listen((t) => _onTemp(f, t)))
      ..add(f.source.statuses.listen((s) => f.status = s.packet));
  }

  void _onState(_Foot f, LinkState s) {
    // The data goes with the link: a dead foot's last values must never be
    // shown as if current. (The connect sequence reads the status while
    // connecting, so that state keeps it.)
    if (s is! LinkStreaming && s is! LinkConnecting) f.clearData();
  }

  void _onFrame(_Foot f, SensorFrame fr) {
    final current = f.session;
    if (current != null && fr.session < current) {
      // Rule 9, again: the source already drops old connections' packets.
      f.droppedOldSession++;
      return;
    }
    if (fr.session != current) {
      f.session = fr.session;
      f.clock = DeviceClock();
      f.sessionPackets = 0;
      f.sessionLost = 0;
      f.lastUnix = null;
      f.temp = null;
    }
    final unix = f.clock!.mapPacket([
      for (final s in fr.samples) s.deviceMs,
    ], fr.receivedAt);
    final samples = [
      for (var i = 0; i < fr.samples.length; i++)
        FootSample(
          unixMs: unix[i],
          deviceMs: fr.samples[i].deviceMs,
          fsrAdc: fr.samples[i].fsrAdc,
          fsrKpa: fr.samples[i].fsrKpa,
          accelG: fr.samples[i].accelG,
          gyroDps: fr.samples[i].gyroDps,
        ),
    ];
    for (final u in unix) {
      final prev = f.lastUnix;
      if (prev != null) {
        final step = u - prev;
        f.stepMin = math.min(f.stepMin ?? step, step);
        f.stepMax = math.max(f.stepMax ?? step, step);
      }
      f.lastUnix = u;
    }
    f
      ..sessionPackets += 1
      ..sessionLost += fr.missingBefore
      ..lastSeq = fr.seq
      ..lastSampleAt = fr.receivedAt
      ..saturated = fr.saturated
      ..calibrating = fr.calibrating;
    if (samples.isNotEmpty) f.kpa = samples.last.fsrKpa;
    if (_batches.isClosed) return;
    _batches.add(
      FootBatch(
        side: fr.side,
        session: fr.session,
        seq: fr.seq,
        missingBefore: fr.missingBefore,
        receivedAt: fr.receivedAt,
        saturated: fr.saturated,
        calibrating: fr.calibrating,
        samples: samples,
      ),
    );
  }

  void _onTemp(_Foot f, TempFrame t) {
    f.temp = t.packet;
    final unix =
        f.clock?.unixOf(t.packet.tMs) ??
        t.receivedAt.millisecondsSinceEpoch.toDouble();
    f.history.add(unix, t.packet);
  }

  // --- Display ------------------------------------------------------------

  void _startTicker() {
    _ticker ??= Timer.periodic(displayPeriod, (_) {
      if (!_snapshots.isClosed) _snapshots.add(snapshot());
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  FootConnection _connection(_Foot f, DateTime at) {
    switch (f.source.state) {
      case LinkStreaming(:final since):
        final last = f.lastSampleAt;
        if (last == null) {
          return at.difference(since) > staleAfter
              ? FootConnection.stale
              : FootConnection.connecting;
        }
        return at.difference(last) > staleAfter
            ? FootConnection.stale
            : FootConnection.streaming;
      case LinkIdle() || LinkBlocked():
        return FootConnection.notConnected;
      case LinkSearching() || LinkConnecting() || LinkRetryWait():
        return FootConnection.connecting;
      case LinkProblem():
        return FootConnection.problem;
    }
  }

  FootView _view(_Foot f, DateTime at) {
    final connection = _connection(f, at);
    final usable = connection == FootConnection.streaming;
    final linked =
        connection == FootConnection.streaming ||
        connection == FootConnection.stale;
    final status = linked ? f.status : null;
    return FootView(
      side: f.source.side,
      connection: connection,
      batteryPct: status?.batteryPct,
      firmware: status == null ? null : '${status.fwMajor}.${status.fwMinor}',
      errorCode: status?.errorCode,
      kpa: usable ? f.kpa : null,
      saturated: usable && f.saturated,
      calibrating: usable && f.calibrating,
      temp: usable ? f.temp : null,
      lastSampleAt: f.lastSampleAt,
      lostPackets: f.sessionLost,
    );
  }

  static double? _delta(
    FootView l,
    FootView r,
    double? Function(TempPacket) pick,
  ) {
    if (!l.usable || !r.usable) return null;
    final lt = l.temp;
    final rt = r.temp;
    if (lt == null || rt == null) return null;
    if (lt.quality != TempQuality.normal || rt.quality != TempQuality.normal) {
      return null;
    }
    final lv = pick(lt);
    final rv = pick(rt);
    if (lv == null || rv == null) return null;
    return lv - rv;
  }
}

/// One foot's timing figures, for the timing log and the debug screen.
class FootTiming {
  const FootTiming({
    required this.session,
    required this.packets,
    required this.lost,
    required this.lastSeq,
    required this.offsetMs,
    required this.targetMs,
    required this.lastExcessMs,
    required this.clamps,
    required this.stepMinMs,
    required this.stepMaxMs,
    required this.droppedOldSession,
  });

  final int? session;

  /// Packets and lost packets in the current session.
  final int packets;
  final int lost;
  final int? lastSeq;

  /// [DeviceClock] figures (null before the first packet).
  final double? offsetMs;
  final double? targetMs;
  final double? lastExcessMs;
  final int clamps;

  /// Smallest and largest step between consecutive sample times since the
  /// previous [DeviceManager.timing] call.
  final double? stepMinMs;
  final double? stepMaxMs;
  final int droppedOldSession;
}

class _Foot {
  _Foot(this.source);

  final InsoleDataSource source;
  final subs = <StreamSubscription<Object?>>[];
  final history = TempHistory();

  int? session;
  DeviceClock? clock;
  int sessionPackets = 0;
  int sessionLost = 0;
  int? lastSeq;
  int droppedOldSession = 0;
  double? lastUnix;
  double? stepMin;
  double? stepMax;

  DateTime? lastSampleAt;
  List<double>? kpa;
  bool saturated = false;
  bool calibrating = false;
  StatusPacket? status;
  TempPacket? temp;

  void clearData() {
    lastSampleAt = null;
    kpa = null;
    saturated = false;
    calibrating = false;
    status = null;
    temp = null;
  }
}
