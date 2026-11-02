import '../ble/packets.dart';
import '../config/thresholds.dart';
import '../device/foot_sample.dart';
import '../device/model_channels.dart';
import '../storage/baseline_repository.dart';
import 'baseline_window.dart';
import 'preprocess.dart';

export 'baseline_window.dart' show BaselineFailure;

/// Records one quiet-standing baseline per foot (S9, Model A
/// preprocessing "ทางเอ", `shared/model_preprocess.json`): the first
/// [PreprocessSpec.baselineSeconds] × 50 Hz samples per foot from the 50 Hz
/// path (`DeviceManager.batches`), then the per-channel median.
///
/// The rules are [FootBaselineWindow]'s, the same function capture trial 00
/// goes through (BACKLOG 74): lost packets, a reconnect, a TARE, the
/// walking gate turning on (`motion.walkingAccelG` over
/// `motion.walkingWindowMs`, the same gate as the alert rules) or a foot
/// not loaded above `steps.contactKpa` refuse it. Nothing is saved on a
/// failure; the researcher records again.
class BaselineRecorder {
  BaselineRecorder({
    required this.spec,
    required this.thresholds,
    required this.insoleIds,
  }) : _feet = {
         for (final side in FootSide.values)
           side: FootBaselineWindow.of(spec, thresholds),
       };

  final PreprocessSpec spec;
  final Thresholds thresholds;

  /// Each foot's calibration `device_id` when the recording started.
  final Map<FootSide, String> insoleIds;

  final Map<FootSide, FootBaselineWindow> _feet;
  BaselineFailure? _failure;
  FootSide? _failedSide;

  BaselineFailure? get failure => _failure;

  /// The foot the failure came from (null for one not tied to a foot).
  FootSide? get failedSide => _failedSide;

  /// 0–1 of the recording done on [side] (samples kept, so sample time).
  double progress(FootSide side) => _feet[side]!.progress;

  /// Both feet have their window and nothing failed.
  bool get done => _failure == null && _feet.values.every((f) => f.complete);

  /// Stops the recording with [why] (first failure wins).
  void fail(BaselineFailure why, [FootSide? side]) {
    if (_failure != null) return;
    _failure = why;
    _failedSide = side;
  }

  /// Feeds one 50 Hz batch, one [BaselineRow] per sample (the batch's
  /// lost-packet count on its first sample). Batches after [done] or a
  /// failure are ignored.
  void add(FootBatch b) {
    if (_failure != null || done) return;
    final f = _feet[b.side]!;
    for (var i = 0; i < b.samples.length && !f.complete; i++) {
      final s = b.samples[i];
      final why = f.add(
        BaselineRow(
          unixMs: s.unixMs,
          session: b.session,
          missingBefore: i == 0 ? b.missingBefore : 0,
          calibrating: b.calibrating,
          valid: true,
          fsrKpa: s.fsrKpa,
          accelG: s.accelG,
          model: footModelChannels(s),
        ),
      );
      if (why != null) return fail(why, b.side);
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
          values: _feet[side]!.values!,
        ),
    ];
  }
}
