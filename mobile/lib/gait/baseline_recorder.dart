import '../ble/packets.dart';
import '../config/thresholds.dart';
import '../device/foot_sample.dart';
import '../device/model_channels.dart';
import '../rules/walking_gate.dart';
import '../storage/baseline_repository.dart';
import 'preprocess.dart';

/// Why a quiet-standing recording was not saved.
enum BaselineFailure {
  /// A packet was lost: the median would be over a hole.
  lostPackets,

  /// A foot reconnected (new streaming session) mid-recording.
  reconnected,

  /// A TARE was running on a board.
  calibrating,

  /// The walking gate turned on: the person moved.
  moved,

  /// A foot's summed pressure fell to `steps.contactKpa` or below: it was
  /// not standing on that insole.
  notLoaded,

  /// The insole does not give the 14 model channels (not 8 FSR).
  wrongInsole,

  /// A foot stopped streaming (the screen's read-time check).
  stopped,
}

/// Records one quiet-standing baseline per foot (S9, Model A
/// preprocessing "ทางเอ", `shared/model_preprocess.json`): every sample of
/// [PreprocessSpec.baselineSeconds] of **sample time** per foot, from the
/// 50 Hz path (`DeviceManager.batches`), then the per-channel median.
///
/// Refuses, with a [BaselineFailure], anything that would make the median
/// describe something other than this person standing still on these two
/// insoles: lost packets, a reconnect, a TARE, the walking gate turning on
/// (`motion.walkingAccelG` over `motion.walkingWindowMs`, the same gate as
/// the alert rules) or a foot not loaded above `steps.contactKpa`. Nothing
/// is saved on a failure; the researcher records again.
class BaselineRecorder {
  BaselineRecorder({
    required this.spec,
    required this.thresholds,
    required this.insoleIds,
  }) : _feet = {
         for (final side in FootSide.values)
           side: _Foot(
             WalkingGate(
               windowMs: thresholds.walkingWindowMs,
               accelG: thresholds.walkingAccelG,
             ),
           ),
       };

  final PreprocessSpec spec;
  final Thresholds thresholds;

  /// Each foot's calibration `device_id` when the recording started.
  final Map<FootSide, String> insoleIds;

  final Map<FootSide, _Foot> _feet;
  BaselineFailure? _failure;
  FootSide? _failedSide;

  BaselineFailure? get failure => _failure;

  /// The foot the failure came from (null for one not tied to a foot).
  FootSide? get failedSide => _failedSide;

  int get _durationMs => spec.baselineSeconds * 1000;

  /// 0–1 of the recording done on [side], in sample time.
  double progress(FootSide side) {
    final f = _feet[side]!;
    if (f.complete) return 1;
    final first = f.firstMs;
    if (first == null) return 0;
    final p = (f.lastMs! - first) / _durationMs;
    return p > 1 ? 1 : p;
  }

  /// Both feet have [PreprocessSpec.baselineSeconds] of samples and
  /// nothing failed.
  bool get done => _failure == null && _feet.values.every((f) => f.complete);

  /// Stops the recording with [why] (first failure wins).
  void fail(BaselineFailure why, [FootSide? side]) {
    if (_failure != null) return;
    _failure = why;
    _failedSide = side;
  }

  /// Feeds one 50 Hz batch. Batches after [done] or a failure are ignored.
  void add(FootBatch b) {
    if (_failure != null || done) return;
    final f = _feet[b.side]!;
    if (f.complete) return;
    if (f.session != null && b.session != f.session) {
      return fail(BaselineFailure.reconnected, b.side);
    }
    if (f.session != null && b.missingBefore > 0) {
      return fail(BaselineFailure.lostPackets, b.side);
    }
    if (b.calibrating) return fail(BaselineFailure.calibrating, b.side);
    f.session = b.session;
    for (final s in b.samples) {
      final row = footModelChannels(s);
      if (row == null) return fail(BaselineFailure.wrongInsole, b.side);
      if (f.gate.add(s.unixMs, s.accelG)) {
        return fail(BaselineFailure.moved, b.side);
      }
      var load = 0.0;
      for (final k in s.fsrKpa) {
        load += k;
      }
      if (load <= thresholds.stepContactKpa) {
        return fail(BaselineFailure.notLoaded, b.side);
      }
      final first = f.firstMs ??= s.unixMs;
      if (s.unixMs - first >= _durationMs) {
        f.complete = true;
        return;
      }
      f.rows.add(row);
      f.lastMs = s.unixMs;
    }
  }

  /// The two baselines, once [done]; null before.
  List<FootBaseline>? result(int recordedAtMs) {
    if (!done) return null;
    return [
      for (final side in FootSide.values)
        FootBaseline(
          side: side,
          insoleId: insoleIds[side]!,
          recordedAtMs: recordedAtMs,
          sampleCount: _feet[side]!.rows.length,
          values: footBaseline(_feet[side]!.rows),
        ),
    ];
  }
}

class _Foot {
  _Foot(this.gate);

  final WalkingGate gate;
  final rows = <List<double>>[];
  int? session;
  double? firstMs;
  double? lastMs;
  bool complete = false;
}
