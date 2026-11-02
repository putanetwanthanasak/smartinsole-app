import '../ble/ble_protocol.dart';
import '../config/thresholds.dart';
import '../rules/walking_gate.dart';
import 'preprocess.dart';

/// Why a quiet-standing baseline was not made. The names are the shared
/// failure ids: `tools/model/preprocess.py` and
/// `shared/test_vectors/baseline/expected.json` use the same strings.
enum BaselineFailure {
  /// A packet was lost: the median would be over a hole.
  lostPackets,

  /// A foot reconnected (new streaming session) mid-recording.
  reconnected,

  /// A TARE was running on a board.
  calibrating,

  /// The researcher marked part of the trial invalid (capture trial 00
  /// only; a live recording has no marks).
  markedInvalid,

  /// The insole does not give the 14 model channels (not 8 FSR).
  wrongInsole,

  /// The walking gate turned on: the person moved.
  moved,

  /// A foot's summed pressure fell to `steps.contactKpa` or below: it was
  /// not standing on that insole.
  notLoaded,

  /// The rows ended with fewer than [FootBaselineWindow.minSamples] kept
  /// (capture trial 00 only, e.g. a 10 s rehearsal calibration).
  tooShort,

  /// A foot stopped streaming (the Researcher screen's read-time check;
  /// never from [FootBaselineWindow]).
  stopped,
}

/// One sample as the baseline rules see it, from the 50 Hz path
/// (`BaselineRecorder`) or from a capture trial's CSV row
/// (`lib/capture/trial_baseline.dart`).
class BaselineRow {
  const BaselineRow({
    required this.unixMs,
    required this.session,
    required this.missingBefore,
    required this.calibrating,
    required this.valid,
    required this.fsrKpa,
    required this.accelG,
    required this.model,
  });

  final double unixMs;

  /// Streaming session (`conn_session`).
  final int session;

  /// Packets lost just before this sample's packet (on the packet's first
  /// sample only).
  final int missingBefore;
  final bool calibrating;

  /// False inside a segment the researcher marked invalid.
  final bool valid;
  final List<double> fsrKpa;
  final List<double> accelG;

  /// The foot's 14 model channels (`footModelChannels`), or null when the
  /// insole does not have 8 FSR.
  final List<double>? model;
}

/// The one baseline function (S9, BACKLOG 74, DATA-CONTRACT §7.1) for one
/// foot: the Researcher recording and capture trial 00 both feed it, and
/// `tools/model/preprocess.py foot_baseline_window` is its port, matched
/// on `shared/test_vectors/baseline/`.
///
/// Rows are taken in order. The first [samples] rows that pass make the
/// window (`baselineSeconds` × 50 Hz: that much sample time, rule 1); rows
/// after it are ignored. Rows that end before it ([end]) with every rule
/// passed still give a baseline from at least [minSamples] rows
/// (`baselineToleranceSamples` short). Any row before then that breaks a rule ends it
/// with a [BaselineFailure], checked in this order: a new session after
/// the first row, packets lost after the first row, a TARE, a row marked
/// invalid, not 8 FSR, the walking gate on, summed kPa at or below
/// `steps.contactKpa`.
class FootBaselineWindow {
  FootBaselineWindow({
    required this.samples,
    int? minSamples,
    required int walkingWindowMs,
    required double walkingAccelG,
    required this.contactKpa,
  }) : minSamples = minSamples ?? samples,
       _gate = WalkingGate(windowMs: walkingWindowMs, accelG: walkingAccelG);

  /// [PreprocessSpec.baselineSeconds] at 50 Hz, with this app's thresholds.
  FootBaselineWindow.of(PreprocessSpec spec, Thresholds thresholds)
    : this(
        samples: windowSamples(spec),
        minSamples: windowSamples(spec) - spec.baselineToleranceSamples,
        walkingWindowMs: thresholds.walkingWindowMs,
        walkingAccelG: thresholds.walkingAccelG,
        contactKpa: thresholds.stepContactKpa,
      );

  /// Rows in the window: `baselineSeconds` of 20 ms samples.
  static int windowSamples(PreprocessSpec spec) =>
      spec.baselineSeconds *
      Duration.millisecondsPerSecond ~/
      SensorLayout.sampleSpacingMs;

  final int samples;

  /// The fewest rows that still give a baseline when the rows [end] early.
  final int minSamples;
  final double contactKpa;
  final WalkingGate _gate;

  final rows = <List<double>>[];
  int? _session;
  BaselineFailure? _failure;
  bool _endedShort = false;

  BaselineFailure? get failure => _failure;

  bool get complete => _failure == null && rows.length >= samples;

  /// 0–1 of the window filled.
  double get progress => rows.length >= samples ? 1 : rows.length / samples;

  /// Takes one row; returns the failure it caused, if any. Rows after the
  /// window is complete or has failed are ignored.
  BaselineFailure? add(BaselineRow r) {
    if (_failure != null || complete) return null;
    final first = _session == null;
    if (!first && r.session != _session) {
      return _failure = BaselineFailure.reconnected;
    }
    if (!first && r.missingBefore > 0) {
      return _failure = BaselineFailure.lostPackets;
    }
    if (r.calibrating) return _failure = BaselineFailure.calibrating;
    if (!r.valid) return _failure = BaselineFailure.markedInvalid;
    final model = r.model;
    if (model == null) return _failure = BaselineFailure.wrongInsole;
    _session = r.session;
    if (_gate.add(r.unixMs, r.accelG)) return _failure = BaselineFailure.moved;
    var load = 0.0;
    for (final k in r.fsrKpa) {
      load += k;
    }
    if (load <= contactKpa) return _failure = BaselineFailure.notLoaded;
    rows.add(model);
    return null;
  }

  /// No more rows will come: a window with fewer than [minSamples] rows by
  /// now is [tooShort].
  BaselineFailure? end() {
    if (_failure == null && !complete) {
      if (rows.length >= minSamples) {
        _endedShort = true;
      } else {
        _failure = BaselineFailure.tooShort;
      }
    }
    return _failure;
  }

  /// The per-channel median, once [complete], or once [end] found at least
  /// [minSamples] rows.
  List<double>? get values =>
      complete || (_endedShort && _failure == null) ? footBaseline(rows) : null;
}
