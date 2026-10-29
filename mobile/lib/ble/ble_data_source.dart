import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'ble_central.dart';
import 'ble_event_log.dart';
import 'ble_hub.dart';
import 'ble_protocol.dart';
import 'calibration.dart';
import 'control_commands.dart';
import 'fsr_conversion.dart';
import 'insole_control.dart';
import 'insole_data_source.dart';
import 'link_state.dart';
import 'link_stats.dart';
import 'packet_parser.dart';
import 'packets.dart';
import 'parse_result.dart';

/// One foot's insole over BLE (FLUTTER-PLAN §5, S3A).
///
/// On every connect and every reconnect it runs the full sequence:
/// connect → MTU 247 → high priority → discover → read status (`foot_side`
/// must be this foot, rule 8) → read calibration (N) → MTU fit check →
/// subscribe → `SYNC_TIME` → `START_STREAM`.
///
/// Rule 9 (BACKLOG 20): every attempt has a generation number, and a
/// notification from an earlier one is dropped; a sensor or temperature
/// packet that arrives before this connection's START is written is
/// dropped; within a connection `t0_ms` (and temperature `t_ms`) must
/// advance, compared modulo 2³² so the 49.7-day wrap is not "backwards".
/// Every drop and every parser rejection is counted in [stats].
///
/// The gate opens when START is written, not when the write is
/// acknowledged (BACKLOG 27): Android can deliver the board's first
/// notification before the write callback. That packet is genuine. This
/// connection's subscriptions are new and carry its generation, and
/// `onValueReceived` never replays a cached value, so nothing from an
/// earlier connection can arrive through them.
///
/// While streaming, `SYNC_TIME` is sent again every [syncInterval]
/// (contract §4). It is only sent and reported on [syncs]; the app's unix
/// time per sample does not come from it (BACKLOG 28, `DeviceClock`).
class BleDataSource implements InsoleDataSource, InsoleControl {
  BleDataSource({
    required this.side,
    required this.hub,
    required this.now,
    this.connectTimeout = const Duration(seconds: 10),
  }) {
    _readinessSub = hub.readinessChanges.listen(_onReadiness);
  }

  @override
  final FootSide side;
  final BleHub hub;
  final DateTime Function() now;
  final Duration connectTimeout;

  /// Waits after consecutive failed attempts: 1, 2, 4, then 5 s each.
  static const backoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 5),
  ];

  /// How long the user's Disconnect waits for its STOP_STREAM write.
  static const stopTimeout = Duration(seconds: 2);

  /// Contract §4: `SYNC_TIME` again every 5 minutes.
  static const defaultSyncInterval = Duration(minutes: 5);

  /// How often `SYNC_TIME` is resent while streaming. The debug timing
  /// check shortens it; a change restarts the running timer.
  Duration get syncInterval => _syncInterval;
  set syncInterval(Duration d) {
    _syncInterval = d;
    if (_syncTimer != null) _startSyncTimer(_gen);
  }

  Duration _syncInterval = defaultSyncInterval;
  Timer? _syncTimer;

  /// Counters for the insole this foot is bound to; a new binding starts
  /// fresh ones, so one insole's numbers never show under another's id.
  LinkStats get stats => _stats;
  LinkStats _stats = LinkStats();

  BleCentral get _central => hub.central;
  BleEventLog get _log => hub.log;

  LinkState _state = const LinkIdle();
  final _states = StreamController<LinkState>.broadcast();
  final _frames = StreamController<SensorFrame>.broadcast();
  final _temps = StreamController<TempFrame>.broadcast();
  final _statuses = StreamController<StatusFrame>.broadcast();
  final _syncs = StreamController<SyncSent>.broadcast();
  late final StreamSubscription<BleReadiness> _readinessSub;

  String? _deviceId;

  /// The user wants this foot connected; false after Disconnect or a
  /// [LinkProblem].
  bool _want = false;

  /// Bumped by every new attempt, every failure and every disconnect.
  int _gen = 0;
  int _failures = 0;
  BleLink? _link;
  final _linkSubs = <StreamSubscription<Object?>>[];
  StreamSubscription<SeenInsole>? _searchSub;
  Timer? _retryTimer;

  Calibration? _cal;
  int _mtu = 0;

  /// START has been written on this connection (the rule 9 gate is open).
  bool _startIssued = false;

  /// START was acknowledged (STOP is only sent after this).
  bool _startAcked = false;

  /// Streaming sessions so far; never reset, see [SensorFrame.session].
  int _session = 0;
  int? _lastT0;
  int? _lastTempT;
  bool _calibrating = false;
  bool _rereading = false;

  @override
  LinkState get state => _state;
  @override
  Stream<LinkState> get states => _states.stream;
  @override
  Stream<SensorFrame> get frames => _frames.stream;
  @override
  Stream<TempFrame> get temps => _temps.stream;
  @override
  Stream<StatusFrame> get statuses => _statuses.stream;

  /// Every `SYNC_TIME` written, with the phone time it carried.
  Stream<SyncSent> get syncs => _syncs.stream;

  String? get deviceId => _deviceId;
  @override
  Calibration? get calibration => _cal;

  /// Binds this foot to [deviceId] (picked from the scan list) and connects.
  /// The insole's side is checked from its status, never from [name].
  Future<void> connectTo(String deviceId, {String? name}) async {
    if (_deviceId != deviceId) {
      if (_deviceId != null) await disconnect();
      _stats = LinkStats();
      _cal = null;
    }
    _deviceId = deviceId;
    stats.advertisedName = name;
    await connect();
  }

  @override
  Future<void> connect() async {
    final id = _deviceId;
    if (id == null) throw StateError('no insole chosen for ${side.name}');
    final busy = _state is! LinkIdle && _state is! LinkProblem;
    if (_want && busy) return;
    if (!hub.claim(id, side)) {
      _problem(
        LinkProblem(
          deviceId: id,
          kind: ProblemKind.inUseByOtherFoot,
          detail: '$id is bound to the ${hub.claimedBy(id)!.name} foot',
        ),
      );
      return;
    }
    _want = true;
    _failures = 0;
    _log.add('connect $id', side: side);
    _search();
  }

  @override
  Future<void> disconnect() async {
    _want = false;
    _gen++;
    _stopSearching();
    final link = _link;
    if (link != null && _startAcked) {
      try {
        await link
            .write(BleUuids.control, stopStreamCommand())
            .timeout(stopTimeout);
      } on Object catch (e) {
        _log.add('STOP_STREAM failed: $e', side: side);
      }
    }
    _dropLink();
    if (_deviceId != null) hub.release(_deviceId!, side);
    if (_state is! LinkIdle) _log.add('disconnected by user', side: side);
    _set(LinkIdle(deviceId: _deviceId));
  }

  // --- Device-wide commands (S8B, BACKLOG 21) -------------------------------

  @override
  bool get canCommand => _link != null && _startAcked;

  @override
  Future<void> sendTare() => _sendDeviceCommand(tareCommand(), 'TARE');

  @override
  Future<void> sendReboot() => _sendDeviceCommand(rebootCommand(), 'REBOOT');

  /// Writes a device-wide command on the streaming link. The connect
  /// sequence is not involved: TARE shows up as calibrating packets (and a
  /// calibration re-read), REBOOT as a lost link that reconnects.
  Future<void> _sendDeviceCommand(Uint8List command, String name) async {
    final link = _link;
    if (link == null || !_startAcked) {
      throw const BleException('not streaming');
    }
    _log.add('$name sent', side: side);
    await link.write(BleUuids.control, command);
  }

  void dispose() {
    _gen++;
    _stopSearching();
    _dropLink();
    _readinessSub.cancel();
    _states.close();
    _frames.close();
    _temps.close();
    _statuses.close();
    _syncs.close();
  }

  // --- Searching and retries ----------------------------------------------

  /// Waits for the bound insole's advertisement, then runs the sequence.
  /// The scan stays held from here until streaming (or a stop): retries
  /// reuse the running scan instead of restarting it, because Android
  /// blocks an app's 6th scan start within 30 s.
  void _search() {
    final gen = ++_gen;
    final id = _deviceId!;
    _cancelWaits();
    if (hub.readiness != BleReadiness.ready) {
      hub.releaseScan(this);
      _set(LinkBlocked(hub.readiness, deviceId: id));
      return;
    }
    _set(LinkSearching(deviceId: id));
    hub.acquireScan(this);
    if (hub.seenRecently(id)) {
      unawaited(_attempt(gen));
      return;
    }
    _searchSub = hub.sightings.where((s) => s.deviceId == id).listen((_) {
      if (gen != _gen) return;
      _cancelWaits();
      unawaited(_attempt(gen));
    });
  }

  void _cancelWaits() {
    _searchSub?.cancel();
    _searchSub = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _stopSearching() {
    _cancelWaits();
    hub.releaseScan(this);
  }

  void _onReadiness(BleReadiness r) {
    if (!_want) return;
    if (r == BleReadiness.ready) {
      if (_state is LinkBlocked) _search();
      return;
    }
    // A live link ends on its own when Bluetooth goes off (and then lands
    // here as blocked); only a foot that is waiting changes state now.
    if (_state is LinkSearching || _state is LinkRetryWait) {
      _gen++;
      _stopSearching();
      _set(LinkBlocked(r, deviceId: _deviceId));
    }
  }

  void _failed(String reason) {
    final gen = ++_gen;
    _dropLink();
    stats.failedAttempts++;
    _failures++;
    _log.add('attempt $_failures failed: $reason', side: side);
    if (!_want) {
      _set(LinkIdle(deviceId: _deviceId));
      return;
    }
    final wait = backoff[math.min(_failures, backoff.length) - 1];
    _set(
      LinkRetryWait(
        deviceId: _deviceId!,
        attempt: _failures,
        retryAt: now().add(wait),
        lastError: reason,
      ),
    );
    _retryTimer = Timer(wait, () {
      if (gen == _gen && _want) _search();
    });
  }

  /// Stops for good: connecting again would not help, so no retry.
  void _problem(LinkProblem p) {
    _gen++;
    _want = false;
    _stopSearching();
    final link = _link;
    if (link != null && _startAcked) {
      unawaited(
        link
            .write(BleUuids.control, stopStreamCommand())
            .then((_) {}, onError: (_) {}),
      );
    }
    _dropLink();
    hub.release(p.deviceId, side);
    _log.add('problem ${p.kind.name}: ${p.detail}', side: side);
    _set(p);
  }

  void _dropLink() {
    for (final s in _linkSubs) {
      s.cancel();
    }
    _linkSubs.clear();
    _syncTimer?.cancel();
    _syncTimer = null;
    _startIssued = false;
    _startAcked = false;
    final link = _link;
    _link = null;
    if (link != null) {
      unawaited(
        link.disconnect().then(
          (_) {},
          onError: (Object e) => _log.add('disconnect: $e', side: side),
        ),
      );
    }
  }

  void _onClosed(int gen, BleLink link) {
    if (!identical(_link, link) || gen != _gen) return;
    final wasStreaming = _state is LinkStreaming;
    final step = switch (_state) {
      LinkConnecting(:final step) => step.name,
      _ => null,
    };
    _link = null;
    _dropLink();
    if (!_want) {
      _set(LinkIdle(deviceId: _deviceId));
      return;
    }
    if (wasStreaming) {
      stats.linkLosses++;
      _failures = 0;
      _log.add('link lost; reconnecting', side: side);
      _search();
    } else {
      _failed('link closed during ${step ?? 'setup'}');
    }
  }

  // --- Connect sequence -----------------------------------------------------

  Future<void> _attempt(int gen) =>
      hub.setupLock(() => gen == _gen ? _setup(gen) : Future.value());

  Future<void> _setup(int gen) async {
    final id = _deviceId!;
    void step(ConnectStep s) {
      if (gen == _gen) _set(LinkConnecting(deviceId: id, step: s));
    }

    bool stale() => gen != _gen;

    try {
      step(ConnectStep.connect);
      final link = await _central.connect(id, timeout: connectTimeout);
      if (stale()) {
        unawaited(link.disconnect().then((_) {}, onError: (_) {}));
        return;
      }
      _link = link;
      unawaited(link.closed.then((_) => _onClosed(gen, link)));

      step(ConnectStep.mtu);
      _mtu = await link.requestMtu(MtuLayout.targetMtu);
      if (stale()) return;
      _log.add('MTU requested ${MtuLayout.targetMtu}, got $_mtu', side: side);

      step(ConnectStep.priority);
      try {
        await link.requestHighPriority();
      } on BleException catch (e) {
        _log.add('high priority not set: ${e.message}', side: side);
      }
      if (stale()) return;

      step(ConnectStep.discover);
      try {
        await link.discover(serviceUuid: BleUuids.service);
      } on BleServiceMissing catch (e) {
        if (!stale()) {
          _problem(
            LinkProblem(
              deviceId: id,
              kind: ProblemKind.notAnInsole,
              detail: e.message,
            ),
          );
        }
        return;
      }
      if (stale()) return;

      step(ConnectStep.status);
      final statusBytes = await link.read(BleUuids.deviceStatus);
      if (stale()) return;
      final status = switch (parseStatusPacket(statusBytes)) {
        Parsed(:final value) => value,
        Rejected(:final reason, :final detail) => _rejectedDuringSetup(
          reason,
          'status $detail',
        ),
      };
      if (status.footSide != side) {
        _wrongSide(id, status.footSide);
        return;
      }
      _emitStatus(status);

      step(ConnectStep.calibration);
      final cal = await _readCalibration(link);
      if (stale()) return;
      switch (cal) {
        case Rejected(:final reason, :final detail):
          stats.countReject(reason);
          _problem(
            LinkProblem(
              deviceId: id,
              kind: ProblemKind.calibrationInvalid,
              detail: detail,
              rejectReason: reason,
            ),
          );
          return;
        case Parsed(:final value) when value.fsrCount != SensorLayout.fsrCount:
          const reason = RejectReason.calibrationFsrCount;
          stats
            ..countReject(reason)
            ..calibrationFsrCount = value.fsrCount;
          _log.add(
            'calibration ${value.deviceId}: N = ${value.fsrCount}, the app '
            'needs N = ${SensorLayout.fsrCount} (contract v1.6)',
            side: side,
          );
          _problem(
            LinkProblem(
              deviceId: id,
              kind: ProblemKind.calibrationInvalid,
              detail:
                  'calibration lists ${value.fsrCount} FSR channels, needs '
                  '${SensorLayout.fsrCount}',
              rejectReason: reason,
            ),
          );
          return;
        case Parsed(:final value):
          _cal = value;
          stats
            ..calibrationDeviceId = value.deviceId
            ..calibrationFsrCount = value.fsrCount;
          _log.add(
            'calibration ${value.deviceId}: N = ${value.fsrCount}, '
            'offset_adc ${value.channels.map((c) => c.offsetAdc).toList()}',
            side: side,
          );
      }
      final fit = _checkMtu(id);
      if (fit == null) return;

      step(ConnectStep.subscribe);
      _startIssued = false;
      _startAcked = false;
      _lastT0 = null;
      _lastTempT = null;
      _calibrating = false;
      stats.newSession();
      _linkSubs
        ..add(
          link
              .notifications(BleUuids.deviceStatus)
              .listen((b) => _onStatus(gen, b)),
        )
        ..add(
          link
              .notifications(BleUuids.sensorStream)
              .listen((b) => _onSensor(gen, b)),
        )
        ..add(
          link
              .notifications(BleUuids.temperature)
              .listen((b) => _onTemp(gen, b)),
        )
        ..add(link.mtuChanges.listen((m) => _onMtu(gen, m)));
      for (final uuid in const [
        BleUuids.deviceStatus,
        BleUuids.sensorStream,
        BleUuids.temperature,
      ]) {
        await link.enableNotify(uuid);
        if (stale()) return;
      }

      step(ConnectStep.syncTime);
      await _writeSync(link);
      if (stale()) return;

      step(ConnectStep.start);
      // The gate opens now, before the ack (BACKLOG 27); see the class doc.
      _session++;
      _startIssued = true;
      await link.write(BleUuids.control, startStreamCommand());
      if (stale()) return;
      _startAcked = true;
      _startSyncTimer(gen);
      _failures = 0;
      stats.sessions++;
      hub.releaseScan(this);
      _log.add(
        'streaming: MTU $_mtu, $fit samples/packet, N = ${_cal!.fsrCount}',
        side: side,
      );
      _set(
        LinkStreaming(
          deviceId: id,
          mtu: _mtu,
          samplesPerPacket: fit,
          fsrCount: _cal!.fsrCount,
          since: now(),
        ),
      );
    } on BleException catch (e) {
      if (!stale()) _failed(e.message);
    } on _SetupRejected catch (e) {
      if (!stale()) _failed(e.message);
    }
  }

  Future<void> _writeSync(BleLink link) async {
    final unixMs = now().millisecondsSinceEpoch;
    await link.write(BleUuids.control, syncTimeCommand(unixMs));
    if (!_syncs.isClosed) {
      final session = _startIssued ? _session : _session + 1;
      _syncs.add(SyncSent(side: side, session: session, unixMs: unixMs));
    }
  }

  void _startSyncTimer(int gen) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) async {
      final link = _link;
      if (gen != _gen || link == null || !_startAcked) return;
      try {
        await _writeSync(link);
      } on BleException catch (e) {
        _log.add('SYNC_TIME failed: ${e.message}', side: side);
      }
    });
  }

  Never _rejectedDuringSetup(RejectReason reason, String detail) {
    stats.countReject(reason);
    throw _SetupRejected(detail);
  }

  Future<ParseResult<Calibration>> _readCalibration(BleLink link) async {
    final bytes = await link.read(BleUuids.calibration);
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException catch (e) {
      return Rejected(RejectReason.calibrationNotJson, 'not UTF-8: $e');
    }
    return parseCalibration(text);
  }

  /// Samples per packet at the current MTU, or null after stopping with
  /// [ProblemKind.mtuTooSmall]: even the 4-sample fallback does not fit, and
  /// the device would send nothing at all.
  int? _checkMtu(String id) {
    final n = _cal!.fsrCount;
    final fit = MtuLayout.samplesPerPacket(_mtu, n);
    if (fit > 0) return fit;
    final min = MtuLayout.minUsableMtu(n);
    _problem(
      LinkProblem(
        deviceId: id,
        kind: ProblemKind.mtuTooSmall,
        detail:
            'MTU $_mtu fits no packet; ${MtuLayout.fallbackSamplesPerPacket}'
            ' samples of N = $n need MTU $min',
        mtu: _mtu,
        minMtu: min,
      ),
    );
    return null;
  }

  void _wrongSide(String id, FootSide reported) => _problem(
    LinkProblem(
      deviceId: id,
      kind: ProblemKind.wrongSide,
      detail:
          'insole reports foot_side ${reported.name}, this slot is '
          '${side.name}',
      reportedSide: reported,
    ),
  );

  // --- Notifications --------------------------------------------------------

  void _onMtu(int gen, int mtu) {
    if (gen != _gen || mtu == _mtu) return;
    _log.add('MTU changed $_mtu -> $mtu', side: side);
    _mtu = mtu;
    if (_cal == null) return;
    final fit = _checkMtu(_deviceId!);
    if (fit == null) return;
    if (_state case LinkStreaming s) {
      _set(
        LinkStreaming(
          deviceId: s.deviceId,
          mtu: mtu,
          samplesPerPacket: fit,
          fsrCount: s.fsrCount,
          since: s.since,
        ),
      );
    }
  }

  void _onStatus(int gen, Uint8List bytes) {
    if (gen != _gen) return;
    switch (parseStatusPacket(bytes)) {
      case Rejected(:final reason, :final detail):
        stats.countReject(reason);
        _log.add('status rejected: $detail', side: side);
      case Parsed(:final value):
        if (value.footSide != side) {
          _wrongSide(_deviceId!, value.footSide);
          return;
        }
        _emitStatus(value);
    }
  }

  void _emitStatus(StatusPacket status) {
    stats.statusPackets++;
    stats.lastStatus = status;
    _statuses.add(StatusFrame(side: side, receivedAt: now(), packet: status));
  }

  /// Rule 9 gate shared by sensor and temperature packets.
  bool _admit(int gen) {
    if (gen != _gen) {
      stats.droppedOldConnection++;
      return false;
    }
    if (!_startIssued) {
      stats.droppedBeforeStart++;
      if (stats.droppedBeforeStart == 1) {
        _log.add('dropped a packet that arrived before START', side: side);
      }
      return false;
    }
    if (!_startAcked) {
      stats.admittedBeforeAck++;
      if (stats.admittedBeforeAck == 1) {
        _log.add('a packet arrived before the START ack (kept)', side: side);
      }
    }
    return true;
  }

  void _onSensor(int gen, Uint8List bytes) {
    if (!_admit(gen)) return;
    final cal = _cal!;
    final packet = switch (parseSensorPacket(bytes, fsrCount: cal.fsrCount)) {
      Parsed(:final value) => value,
      Rejected(:final reason, :final detail) => _reject(reason, detail),
    };
    if (packet == null) return;
    final h = packet.header;

    if (_lastT0 != null && !advances(_lastT0!, h.t0Ms)) {
      stats.droppedNotForward++;
      _log.add('dropped seq ${h.seq}: t0 ${h.t0Ms} after $_lastT0', side: side);
      return;
    }
    _lastT0 = h.t0Ms;

    final last = stats.lastSeq;
    final missing = stats.seq.accept(h.seq);
    if (missing > 0) {
      _log.add(
        last == null
            ? 'first packet has seq ${h.seq} ($missing missing at start)'
            : 'seq gap: $last -> ${h.seq} ($missing missing)',
        side: side,
      );
    }

    // BACKLOG 23: offset_adc changes after a TARE, and nothing announces it;
    // re-read calibration once the calibrating flag clears.
    if (_calibrating && !h.calibrating) unawaited(_rereadCalibration(gen));
    _calibrating = h.calibrating;

    final at = now();
    stats.packetArrived(at);
    final samples = [
      for (final s in packet.samples)
        SensorSample(
          deviceMs: s.deviceMs,
          fsrAdc: s.fsrAdc,
          fsrKpa: sampleKpa(s, cal),
          accelG: [for (final v in s.accelRaw) accelRawToG(v)],
          gyroDps: [for (final v in s.gyroRaw) gyroRawToDps(v)],
        ),
    ];
    if (samples.isNotEmpty) stats.lastKpa = samples.last.fsrKpa;
    _frames.add(
      SensorFrame(
        side: side,
        session: _session,
        seq: h.seq,
        missingBefore: missing,
        receivedAt: at,
        saturated: h.saturated,
        calibrating: h.calibrating,
        samples: samples,
      ),
    );
  }

  void _onTemp(int gen, Uint8List bytes) {
    if (!_admit(gen)) return;
    final packet = switch (parseTempPacket(bytes)) {
      Parsed(:final value) => value,
      Rejected(:final reason, :final detail) => _reject(reason, detail),
    };
    if (packet == null) return;
    if (_lastTempT != null && !advances(_lastTempT!, packet.tMs)) {
      stats.droppedNotForward++;
      _log.add(
        'dropped temperature: t ${packet.tMs} after $_lastTempT',
        side: side,
      );
      return;
    }
    _lastTempT = packet.tMs;
    stats.tempPackets++;
    stats.lastTemp = packet;
    _temps.add(
      TempFrame(
        side: side,
        session: _session,
        receivedAt: now(),
        packet: packet,
      ),
    );
  }

  /// Counts the rejection; logs the first and then every 50th of a reason.
  Null _reject(RejectReason reason, String detail) {
    stats.countReject(reason);
    final n = stats.rejects[reason]!;
    if (n == 1 || n % 50 == 0) {
      _log.add('rejected (${reason.name} #$n): $detail', side: side);
    }
    return null;
  }

  Future<void> _rereadCalibration(int gen) async {
    final link = _link;
    if (_rereading || link == null) return;
    _rereading = true;
    try {
      final result = await _readCalibration(link);
      if (gen != _gen) return;
      switch (result) {
        case Rejected(:final reason, :final detail):
          stats.countReject(reason);
          _log.add(
            'calibration re-read rejected, keeping the old one: '
            '$detail',
            side: side,
          );
        case Parsed(:final value) when value.fsrCount != _cal!.fsrCount:
          _failed(
            'calibration N changed ${_cal!.fsrCount} -> '
            '${value.fsrCount}',
          );
        case Parsed(:final value):
          _cal = value;
          stats.calibrationRereads++;
          _log.add(
            'calibration re-read after TARE: offset_adc '
            '${value.channels.map((c) => c.offsetAdc).toList()}',
            side: side,
          );
      }
    } on BleException catch (e) {
      _log.add('calibration re-read failed: ${e.message}', side: side);
    } finally {
      _rereading = false;
    }
  }

  void _set(LinkState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }
}

/// True if device time [next] is after [prev], modulo 2³². A difference of
/// 2³¹ or more is a step backwards; equal is not an advance (a duplicate).
bool advances(int prev, int next) {
  final d = (next - prev) & 0xFFFFFFFF;
  return d != 0 && d < 0x80000000;
}

class _SetupRejected implements Exception {
  const _SetupRejected(this.message);
  final String message;
}

/// A `SYNC_TIME` the app wrote; [unixMs] is the phone time it carried, the
/// key that joins the app's timing log to the board's serial log.
class SyncSent {
  const SyncSent({
    required this.side,
    required this.session,
    required this.unixMs,
  });

  final FootSide side;

  /// The session it belongs to (the one about to start, for the SYNC_TIME
  /// in the connect sequence).
  final int session;
  final int unixMs;
}
