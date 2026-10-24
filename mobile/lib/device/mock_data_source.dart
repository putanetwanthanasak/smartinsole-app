import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../ble/ble_protocol.dart';
import '../ble/calibration.dart';
import '../ble/fsr_conversion.dart';
import '../ble/insole_data_source.dart';
import '../ble/link_state.dart';
import '../ble/packets.dart';
import '../ble/seq_tracker.dart';

/// Data for every Home state on the emulator, without an ESP32. Debug
/// builds only ([mockPresetFor]).
///
/// What each preset produces is synthetic sensor data, not a decision: S7's
/// rules turn it into a level. The kPa and °C below are chosen to land in
/// the right band of `shared/thresholds.json` and contract §8.3; they are
/// not thresholds (rule 12), and `test/device/mock_data_source_test.dart`
/// checks every preset against the threshold file, so a threshold change
/// that moves a preset into another band fails a test instead of silently
/// showing the wrong state.
enum MockPreset {
  /// Nothing triggers: peaks below `watchKpa`, small ΔT.
  safe,

  /// Level 2 only (Safe + orange dot): a short left forefoot peak above
  /// `watchKpa`, below every level-3 rule.
  safeOrangeDot,

  /// Level 3 `PRESSURE_PTI` (Be careful): the left forefoot carries a high
  /// load for most of a slow, long stance, "ปลายเท้าซ้ายรับน้ำหนักมาก
  /// ต่อเนื่องนานเกินไป". Zone levels match board HomeDWatch: left
  /// [medium, high, medium, low, low, medium], right [low, medium, low,
  /// low, low, medium]. The left meta1 peak is above `alertKpa`, so S7's
  /// `PRESSURE_PEAK` can fire here too (BACKLOG 37 note).
  watch,

  /// Level 4 `TEMP_DELTA` (Rest your feet): the right forefoot is 2.6 °C
  /// warmer on every reading.
  rest,

  /// Neither foot connects.
  noData,

  /// The left foot streams, the right never connects.
  oneFootMissing,

  /// [safe], with the left battery at 10 % (contract `BATTERY_LOW` < 15 %).
  lowBattery,
}

/// The preset named by `--dart-define=MOCK=<name>`, or null for the real
/// BLE stack. Release builds always get null: the mock can never reach a
/// patient's phone. An unknown name in a debug build throws, so a typo
/// never silently falls back to BLE.
MockPreset? mockPresetFor(String define, {required bool debugBuild}) {
  if (!debugBuild || define.isEmpty) return null;
  return MockPreset.values.byName(define);
}

/// One stride's pressure pattern for one foot.
class MockGait {
  const MockGait({
    required this.strideMs,
    required this.stanceMs,
    required this.peakKpa,
    this.windows = normalWindows,
    this.plateau = const {},
  });

  final int strideMs;
  final int stanceMs;

  /// Peak kPa per FSR channel: hallux, meta1, meta3, meta5, midfoot, heel
  /// (channel index order).
  final List<double> peakKpa;

  /// When each channel is loaded, as a fraction of stance.
  final List<(double, double)> windows;

  /// Channels that hold their peak (with short ramps) instead of a bump.
  final Set<int> plateau;

  /// Heel strike → midfoot → metatarsals → toe-off.
  static const normalWindows = [
    (0.60, 1.00),
    (0.35, 0.92),
    (0.35, 0.92),
    (0.35, 0.90),
    (0.15, 0.60),
    (0.00, 0.45),
  ];

  /// kPa per channel at [ms] into the walk.
  List<double> kpaAt(double ms) {
    final inStride = ms % strideMs;
    if (inStride >= stanceMs) return List.filled(peakKpa.length, 0);
    final s = inStride / stanceMs;
    return [
      for (var ch = 0; ch < peakKpa.length; ch++)
        peakKpa[ch] * _shape(s, windows[ch], plateau.contains(ch)),
    ];
  }

  /// The first 100 ms of stance (heel strike), 0–1, or −1 outside it.
  double strikePhase(double ms) {
    final inStride = ms % strideMs;
    return inStride < 100 ? inStride / 100 : -1;
  }

  /// Swing (foot in the air) or stance, for the IMU.
  double swingPhase(double ms) {
    final inStride = ms % strideMs;
    if (inStride < stanceMs) return -1;
    return (inStride - stanceMs) / (strideMs - stanceMs);
  }

  static double _shape(double s, (double, double) w, bool plateau) {
    final (a, b) = w;
    if (s < a || s > b) return 0;
    final u = (s - a) / (b - a);
    if (!plateau) return math.pow(math.sin(math.pi * u), 2).toDouble();
    const ramp = 0.15;
    if (u < ramp) return math.pow(math.sin(math.pi / 2 * u / ramp), 2) * 1.0;
    if (u > 1 - ramp) {
      return math.pow(math.sin(math.pi / 2 * (1 - u) / ramp), 2) * 1.0;
    }
    return 1;
  }
}

/// What one foot does under a preset.
class MockFootProfile {
  const MockFootProfile({
    this.streams = true,
    this.batteryPct = 92,
    this.forefootC = 31.6,
    this.heelC = 31.2,
    this.gait = normalWalk,
  });

  final bool streams;
  final int batteryPct;
  final double forefootC;
  final double heelC;
  final MockGait gait;

  /// Heel peak ≈ 60 kPa like the simulator's walk (S2B), all below watch.
  static const normalWalk = MockGait(
    strideMs: 1100,
    stanceMs: 660,
    peakKpa: [40, 45, 50, 30, 25, 60],
  );

  static MockFootProfile of(MockPreset preset, FootSide side) {
    final left = side == FootSide.left;
    return switch (preset) {
      MockPreset.safe => MockFootProfile(forefootC: left ? 31.8 : 31.5),
      MockPreset.safeOrangeDot => MockFootProfile(
        forefootC: left ? 31.8 : 31.5,
        gait: left
            ? const MockGait(
                strideMs: 1100,
                stanceMs: 660,
                peakKpa: [40, 95, 50, 30, 25, 60],
              )
            : normalWalk,
      ),
      MockPreset.watch => MockFootProfile(
        forefootC: left ? 31.8 : 31.5,
        // A slow walk (both feet keep the same cadence); the left forefoot
        // stays loaded for most of a 1.2 s stance.
        gait: left
            ? const MockGait(
                strideMs: 1600,
                stanceMs: 1200,
                peakKpa: [120, 240, 140, 50, 30, 110],
                windows: [
                  (0.60, 1.00),
                  (0.20, 0.98),
                  (0.20, 0.98),
                  (0.35, 0.90),
                  (0.15, 0.60),
                  (0.00, 0.45),
                ],
                plateau: {1, 2},
              )
            : const MockGait(
                strideMs: 1600,
                stanceMs: 960,
                peakKpa: [45, 120, 50, 30, 25, 100],
              ),
      ),
      MockPreset.rest => MockFootProfile(
        forefootC: left ? 31.0 : 33.6,
        heelC: left ? 30.6 : 30.9,
      ),
      MockPreset.noData => const MockFootProfile(streams: false),
      MockPreset.oneFootMissing => MockFootProfile(
        streams: left,
        forefootC: 31.8,
      ),
      MockPreset.lowBattery => MockFootProfile(
        forefootC: left ? 31.8 : 31.5,
        batteryPct: left ? 10 : 92,
      ),
    };
  }
}

/// Both mock insoles and the preset they follow. Changing [preset] applies
/// at once to both feet (connects or drops them, sends a new status and a
/// temperature reading), so the UI can be stepped through every state live.
class MockInsoles extends ChangeNotifier {
  MockInsoles(this._preset, {required this.now}) {
    _sources = {
      for (final side in FootSide.values)
        side: MockDataSource._(
          side,
          this,
          // Different boot times, so the two device clocks differ as two
          // real boards' do.
          bootDeviceMs: side == FootSide.left ? 123450 : 4012330,
        ),
    };
  }

  final DateTime Function() now;
  late final Map<FootSide, MockDataSource> _sources;
  MockPreset _preset;

  MockPreset get preset => _preset;
  set preset(MockPreset p) {
    if (p == _preset) return;
    _preset = p;
    for (final s in _sources.values) {
      s._apply();
    }
    notifyListeners();
  }

  MockDataSource source(FootSide side) => _sources[side]!;

  @override
  void dispose() {
    for (final s in _sources.values) {
      s._dispose();
    }
    super.dispose();
  }
}

/// One mock insole: 8-sample packets every 160 ms (6.25 Hz = 50 Hz), raw
/// ADC converted to kPa by the real `sampleKpa`, temperature at START and
/// every 30 s, status at START and on every preset change.
class MockDataSource implements InsoleDataSource {
  MockDataSource._(this.side, this._owner, {required int bootDeviceMs})
    : _bootUnixMs = _owner.now().millisecondsSinceEpoch - bootDeviceMs,
      calibration = Calibration(
        deviceId: 'MOCK-${side == FootSide.left ? 'L' : 'R'}-001',
        rPulldownOhm: 10000,
        sensorAreaM2: 0.000113,
        channels: [
          for (var i = 0; i < 6; i++)
            CalibrationChannel(index: i, a: 1.23e5, b: -1.05, offsetAdc: 12),
        ],
      );

  /// How long the mock spends "connecting", so that state is reachable.
  static const connectDelay = Duration(milliseconds: 600);
  static const packetPeriod = Duration(milliseconds: 160);
  static const tempPeriod = TempLayout.notifyPeriod;
  static const samplesPerPacket = 8;

  @override
  final FootSide side;
  final MockInsoles _owner;
  @override
  final Calibration calibration;

  /// Unix ms at which this "board" booted; device time counts from here.
  final int _bootUnixMs;

  LinkState _state = const LinkIdle();
  final _states = StreamController<LinkState>.broadcast();
  final _frames = StreamController<SensorFrame>.broadcast();
  final _temps = StreamController<TempFrame>.broadcast();
  final _statuses = StreamController<StatusFrame>.broadcast();

  bool _want = false;
  Timer? _connectTimer;
  Timer? _packetTimer;
  Timer? _tempTimer;
  int _session = 0;
  int _seq = 0;
  int _nextT0 = 0;
  int _tempCount = 0;
  final _seqTracker = SeqTracker();
  late final List<double> _kpaOfAdc = [
    for (var adc = 0; adc <= Scaling.adcMax; adc++)
      adcToKpa(adc, calibration.channels.first, calibration),
  ];

  String get _id => calibration.deviceId;
  MockFootProfile get _profile => MockFootProfile.of(_owner.preset, side);

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

  @override
  Future<void> connect() async {
    _want = true;
    _apply();
  }

  @override
  Future<void> disconnect() async {
    _want = false;
    _stop();
    _set(LinkIdle(deviceId: _id));
  }

  /// Brings this foot in line with the current preset.
  void _apply() {
    if (!_want) return;
    if (!_profile.streams) {
      _stop();
      _set(LinkIdle(deviceId: _id));
      return;
    }
    if (_state is LinkStreaming) {
      _sendStatus();
      _sendTemp();
      return;
    }
    if (_state is LinkConnecting) return;
    _set(LinkConnecting(deviceId: _id, step: ConnectStep.connect));
    _connectTimer = Timer(connectDelay, _start);
  }

  void _start() {
    _session++;
    _seq = 0;
    _seqTracker.newSession();
    _nextT0 = _owner.now().millisecondsSinceEpoch - _bootUnixMs;
    _set(
      LinkStreaming(
        deviceId: _id,
        mtu: MtuLayout.targetMtu,
        samplesPerPacket: samplesPerPacket,
        fsrCount: calibration.fsrCount,
        since: _owner.now(),
      ),
    );
    _sendStatus();
    _sendTemp();
    _packetTimer = Timer.periodic(packetPeriod, (_) => _sendPacket());
    _tempTimer = Timer.periodic(tempPeriod, (_) => _sendTemp());
  }

  void _stop() {
    _connectTimer?.cancel();
    _packetTimer?.cancel();
    _tempTimer?.cancel();
    _connectTimer = _packetTimer = _tempTimer = null;
  }

  void _dispose() {
    _stop();
    _states.close();
    _frames.close();
    _temps.close();
    _statuses.close();
  }

  void _set(LinkState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  /// The smallest ADC whose kPa reaches [kpa] (same curve as the real
  /// conversion, so ADC and kPa always agree).
  int _adcFor(double kpa) {
    if (kpa < 0.5) return 0;
    var lo = 0;
    var hi = Scaling.adcMax;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_kpaOfAdc[mid] >= kpa) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  void _sendPacket() {
    final gait = _profile.gait;
    // The two feet walk on one timeline, half a stride apart.
    final phaseShift = side == FootSide.right ? gait.strideMs / 2 : 0;
    final raw = <RawSensorSample>[];
    for (var i = 0; i < samplesPerPacket; i++) {
      final deviceMs = (_nextT0 + i * SensorLayout.sampleSpacingMs);
      final walkMs = _bootUnixMs + deviceMs + phaseShift;
      final swing = gait.swingPhase(walkMs.toDouble());
      // At rest the IMU reads 1 g; walking adds a heel-strike jolt and the
      // swing, enough for contract §8.3.2's walking gate.
      final strike = gait.strikePhase(walkMs.toDouble());
      final accel = swing < 0
          ? [0.0, 0.0, 1 + (strike < 0 ? 0 : 0.8 * math.sin(math.pi * strike))]
          : [
              0.4 * math.sin(2 * math.pi * swing),
              0.2 * math.cos(2 * math.pi * swing),
              1 + 0.5 * math.sin(2 * math.pi * swing),
            ];
      final gyro = swing < 0
          ? [0.0, 0.0, 0.0]
          : [0.0, 250 * math.sin(math.pi * swing), 0.0];
      raw.add(
        RawSensorSample(
          deviceMs: deviceMs & 0xFFFFFFFF,
          fsrAdc: [for (final k in gait.kpaAt(walkMs.toDouble())) _adcFor(k)],
          accelRaw: [for (final g in accel) (g * Scaling.accelLsbPerG).round()],
          gyroRaw: [for (final d in gyro) (d * Scaling.gyroLsbPerDps).round()],
        ),
      );
    }
    _nextT0 += samplesPerPacket * SensorLayout.sampleSpacingMs;
    final seq = _seq;
    _seq = (_seq + 1) & 0xFFFF;
    if (_frames.isClosed) return;
    _frames.add(
      SensorFrame(
        side: side,
        session: _session,
        seq: seq,
        missingBefore: _seqTracker.accept(seq),
        receivedAt: _owner.now(),
        saturated: raw.any((s) => s.fsrAdc.contains(Scaling.adcMax)),
        calibrating: false,
        samples: [
          for (final s in raw)
            SensorSample(
              deviceMs: s.deviceMs,
              fsrAdc: s.fsrAdc,
              fsrKpa: sampleKpa(s, calibration),
              accelG: [for (final v in s.accelRaw) accelRawToG(v)],
              gyroDps: [for (final v in s.gyroRaw) gyroRawToDps(v)],
            ),
        ],
      ),
    );
  }

  void _sendTemp() {
    if (_temps.isClosed) return;
    final p = _profile;
    // A small, steady wobble so a display visibly updates; far smaller
    // than any band edge.
    final wobble = ((_tempCount++ % 3) - 1) * 0.03;
    final at = _owner.now();
    _temps.add(
      TempFrame(
        side: side,
        session: _session,
        receivedAt: at,
        packet: TempPacket(
          seq: _tempCount,
          tMs: (at.millisecondsSinceEpoch - _bootUnixMs) & 0xFFFFFFFF,
          forefootC: _round2(p.forefootC + wobble),
          heelC: _round2(p.heelC + wobble),
          quality: TempQuality.normal,
        ),
      ),
    );
  }

  void _sendStatus() {
    if (_statuses.isClosed) return;
    final p = _profile;
    _statuses.add(
      StatusFrame(
        side: side,
        receivedAt: _owner.now(),
        packet: StatusPacket(
          batteryPct: p.batteryPct,
          batteryMv: 3300 + 9 * p.batteryPct,
          footSide: side,
          fwMajor: 1,
          fwMinor: 0,
          state: DeviceState.streaming,
          errorCode: 0,
        ),
      ),
    );
  }

  static double _round2(double v) => (v * 100).round() / 100;
}
