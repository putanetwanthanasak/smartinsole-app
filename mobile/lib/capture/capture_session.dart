import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../ble/insole_data_source.dart';
import '../ble/packets.dart';
import '../device/device_manager.dart';
import '../device/display_snapshot.dart';
import '../device/model_channels.dart';
import 'capture_files.dart';
import 'capture_protocol.dart';
import 'cues.dart';
import 'trial_recorder.dart';

/// Coded subject data, exactly what proposal doc 03 approves (S4C): sex,
/// an age range, foot length, under the code. Everything optional except
/// the code; no names, no free text.
class SubjectInfo {
  const SubjectInfo({
    required this.code,
    this.sex,
    this.ageRange,
    this.footLengthCm = const {},
  });

  final SubjectCode code;
  final Sex? sex;

  /// One of [ageRanges].
  final String? ageRange;
  final Map<FootSide, double> footLengthCm;

  Map<String, Object?> toJson() => {
    'code': code.code,
    'sex': sex?.id,
    'ageRange': ageRange,
    'footLengthCm': {
      for (final side in FootSide.values) sideCode(side): footLengthCm[side],
    },
  };

  static SubjectInfo fromJson(Map<String, Object?> j) {
    final lengths = j['footLengthCm']! as Map<String, Object?>;
    return SubjectInfo(
      code: SubjectCode.parse(j['code']! as String)!,
      sex: Sex.values.where((s) => s.id == j['sex']).firstOrNull,
      ageRange: j['ageRange'] as String?,
      footLengthCm: {
        for (final side in FootSide.values)
          if (lengths[sideCode(side)] case final num v) side: v.toDouble(),
      },
    );
  }
}

/// Why a foot can't start a session (pre-check). Empty = ready.
List<String> precheckIssues(FootView v, {required bool hasCalibration}) => [
  if (!v.usable) 'not streaming',
  if (v.usable && (v.kpa?.length ?? 0) != modelFsrCount)
    '${v.kpa?.length ?? 0} FSR channels, need $modelFsrCount',
  if (v.batteryPct == null)
    'battery unknown'
  else if (v.batteryPct! < CaptureTimings.minBatteryPct)
    'battery ${v.batteryPct} % < ${CaptureTimings.minBatteryPct} %',
  if (v.firmware == null) 'firmware unknown',
  if (!hasCalibration) 'no calibration read',
];

enum CapturePhase {
  /// Waiting for the researcher to start this trial.
  ready,

  /// 30 s practice (not recorded); recording follows on its own.
  practice,

  /// Recording, until the deadline or a held "Stop early".
  recording,

  /// The deadline passed; the last packets in flight are still landing.
  saving,

  /// Saved. The volunteer rests as long as they want (doc 03); the screen
  /// offers Redo and Next.
  saved,

  /// Every trial has a valid attempt.
  done,
}

enum EndReason { completed, stoppedEarly, interrupted }

String endReasonId(EndReason r) => switch (r) {
  EndReason.completed => 'completed',
  EndReason.stoppedEarly => 'stopped_early',
  EndReason.interrupted => 'interrupted',
};

/// One recorded attempt of a trial.
class AttemptInfo {
  AttemptInfo({
    required this.attempt,
    required this.baseName,
    this.rotation,
    this.endReason,
    this.valid = true,
    this.invalidReason,
    this.gapCount = 0,
    this.samples = const {},
  });

  final int attempt;
  final String baseName;
  final Rotation? rotation;
  EndReason? endReason;
  bool valid;
  String? invalidReason;
  int gapCount;
  Map<FootSide, int> samples;

  Map<String, Object?> toJson() => {
    'attempt': attempt,
    'baseName': baseName,
    'rotation': rotation?.id,
    'endReason': endReason == null ? null : endReasonId(endReason!),
    'valid': valid,
    'invalidReason': invalidReason,
    'gapCount': gapCount,
    'samples': {for (final e in samples.entries) sideCode(e.key): e.value},
  };

  static AttemptInfo fromJson(Map<String, Object?> j) {
    final samples = j['samples']! as Map<String, Object?>;
    return AttemptInfo(
      attempt: j['attempt']! as int,
      baseName: j['baseName']! as String,
      rotation: Rotation.values.where((r) => r.id == j['rotation']).firstOrNull,
      endReason: EndReason.values
          .where((r) => endReasonId(r) == j['endReason'])
          .firstOrNull,
      valid: j['valid']! as bool,
      invalidReason: j['invalidReason'] as String?,
      gapCount: j['gapCount']! as int,
      samples: {
        for (final side in FootSide.values)
          if (samples[sideCode(side)] case final int n) side: n,
      },
    );
  }
}

class TrialState {
  TrialState(this.plan, [List<AttemptInfo>? attempts])
    : attempts = attempts ?? [];

  final TrialPlan plan;
  final List<AttemptInfo> attempts;

  /// Done when it has a valid attempt that ended.
  bool get done => attempts.any((a) => a.valid && a.endReason != null);
}

/// Seams to the platform, replaced in tests.
class CaptureDeps {
  const CaptureDeps({
    required this.manager,
    required this.sources,
    required this.cues,
    required this.now,
    required this.appVersion,
  });

  final DeviceManager manager;
  final Map<FootSide, InsoleDataSource> sources;
  final CaptureCues cues;
  final DateTime Function() now;
  final String appVersion;
}

/// One research-capture session: the protocol's state machine, its files
/// in `<root>/research/<sessionId>/`, and the cues.
///
/// Every time limit is a deadline compared with the clock on a tick, never
/// a count of ticks, and the recorder only writes samples inside the
/// deadline's window: a starved or late timer can delay a cue, never
/// change what is recorded (rule 2 spirit).
class CaptureSession extends ChangeNotifier {
  CaptureSession._({
    required this.deps,
    required this.dir,
    required this.subject,
    required this.roomTempC,
    required this.seed,
    required this.createdAt,
    required this.trials,
  }) : timings = CaptureTimings.of(subject.code);

  /// A new session; writes `session.json` at once.
  factory CaptureSession.create({
    required CaptureDeps deps,
    required Directory researchRoot,
    required SubjectInfo subject,
    double? roomTempC,
    int? seed,
  }) {
    final at = deps.now();
    final s = seed ?? newOrderSeed();
    final order = trialOrder(s);
    final session = CaptureSession._(
      deps: deps,
      dir: Directory('${researchRoot.path}/${sessionIdOf(subject.code, at)}'),
      subject: subject,
      roomTempC: roomTempC,
      seed: s,
      createdAt: at,
      trials: [
        TrialState(const TrialPlan.calibration()),
        for (var i = 0; i < order.length; i++)
          TrialState(TrialPlan.gait(i + 1, order[i])),
      ],
    );
    session.dir.createSync(recursive: true);
    session._saveSession();
    return session;
  }

  /// Reopens a session after the app was closed or killed. An attempt that
  /// was still recording is closed as `interrupted` and marked invalid, so
  /// the trial must be redone.
  factory CaptureSession.resume({
    required CaptureDeps deps,
    required Directory dir,
  }) {
    final j = readJson(File('${dir.path}/session.json'));
    final subject = SubjectInfo.fromJson(j['subject']! as Map<String, Object?>);
    final order = [
      for (final id in j['order']! as List<Object?>)
        GaitClass.values.firstWhere((g) => g.id == id),
    ];
    final saved = j['trials']! as List<Object?>;
    final trials = [
      TrialState(const TrialPlan.calibration()),
      for (var i = 0; i < order.length; i++)
        TrialState(TrialPlan.gait(i + 1, order[i])),
    ];
    for (var i = 0; i < trials.length && i < saved.length; i++) {
      final t = saved[i]! as Map<String, Object?>;
      for (final a in t['attempts']! as List<Object?>) {
        trials[i].attempts.add(
          AttemptInfo.fromJson(a! as Map<String, Object?>),
        );
      }
    }
    final session = CaptureSession._(
      deps: deps,
      dir: dir,
      subject: subject,
      roomTempC: (j['roomTempC'] as num?)?.toDouble(),
      seed: j['orderSeed']! as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        j['createdUnixMs']! as int,
      ),
      trials: trials,
    );
    session.calibrationSummary =
        j['calibrationSummary'] as Map<String, Object?>?;
    session.exports.addAll([
      for (final e in j['exports'] as List<Object?>? ?? const []) e! as String,
    ]);
    for (final t in trials) {
      for (final a in t.attempts) {
        if (a.endReason != null) continue;
        a
          ..endReason = EndReason.interrupted
          ..valid = false
          ..invalidReason = 'interrupted';
        session._patchSidecar(a, {
          'endReason': endReasonId(EndReason.interrupted),
          'valid': false,
          'invalidReason': 'interrupted',
        });
      }
    }
    session._index = trials.indexWhere((t) => !t.done);
    if (session._index < 0) {
      session._index = trials.length - 1;
      session._phase = CapturePhase.done;
    }
    session._saveSession();
    return session;
  }

  final CaptureDeps deps;
  final Directory dir;
  final SubjectInfo subject;
  final double? roomTempC;
  final int seed;
  final DateTime createdAt;
  final List<TrialState> trials;
  final CaptureTimings timings;

  /// Resting kPa, starting temperatures and ΔT, from the calibration trial.
  Map<String, Object?>? calibrationSummary;

  /// ISO times of every export staged.
  final exports = <String>[];

  String get sessionId => dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
  List<GaitClass> get order => [
    for (final t in trials)
      if (t.plan.gait != null) t.plan.gait!,
  ];

  int _index = 0;
  CapturePhase _phase = CapturePhase.ready;
  Rotation? _rotation;
  TrialRecorder? _recorder;
  AttemptInfo? _attempt;
  Map<FootSide, Map<String, Object?>>? _feetAtStart;
  DateTime? _deadline;
  DateTime? _savedAt;
  bool _warned = false;
  Timer? _ticker;
  Timer? _grace;
  final _lostSince = <FootSide, DateTime>{};
  final _lastLostCue = <FootSide, DateTime>{};
  bool _disposed = false;

  /// How often the deadline and the links are checked.
  static const tick = Duration(milliseconds: 250);

  /// After the deadline, how long the recorder keeps listening for packets
  /// already in flight (their samples are still inside the window).
  static const grace = Duration(milliseconds: 600);

  CapturePhase get phase => _phase;
  int get index => _index;
  TrialState get current => trials[_index];
  Rotation? get rotation => _rotation;
  bool get markedInvalid => _recorder?.markedInvalid ?? false;
  TrialRecorder? get recorder => _recorder;

  /// The attempt being recorded, or the one just saved.
  AttemptInfo? get attempt => _attempt;

  /// Feet whose link is down right now (practice and recording only).
  Set<FootSide> get linkLost => _lostSince.keys.toSet();

  /// Gaps of the attempt just saved.
  List<CaptureGap> lastGaps = const [];

  Duration get plannedDuration =>
      current.plan.isCalibration ? timings.calibration : timings.trial;

  /// Time left in practice / recording, derived at read time.
  Duration? get remaining {
    final d = _deadline;
    if (d == null) return null;
    final left = d.difference(deps.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Rest so far, since the last attempt was saved (doc 03: no limit).
  Duration? get restElapsed {
    final s = _savedAt;
    return s == null ? null : deps.now().difference(s);
  }

  /// The rotated-foot trial needs the direction first.
  bool get canStart =>
      _phase == CapturePhase.ready &&
      (current.plan.gait != GaitClass.rotatedFoot || _rotation != null);

  void setRotation(Rotation r) {
    if (_phase != CapturePhase.ready) return;
    _rotation = r;
    _notify();
  }

  // --- Flow ---------------------------------------------------------------

  /// Practice (gaits only), then recording on its own when it ends.
  void startPractice() {
    if (!canStart || current.plan.isCalibration) return;
    _phase = CapturePhase.practice;
    _deadline = deps.now().add(timings.practice);
    deps.cues.play(Cue.practice);
    _startTicker();
    _notify();
  }

  /// Back to ready during practice (nothing was recorded).
  void cancelPractice() {
    if (_phase != CapturePhase.practice) return;
    _stopTicker();
    _deadline = null;
    _phase = CapturePhase.ready;
    _notify();
  }

  void startRecording() {
    if (!(canStart || _phase == CapturePhase.practice)) return;
    final now = deps.now();
    final plan = current.plan;
    final n = current.attempts.length + 1;
    final a = AttemptInfo(
      attempt: n,
      baseName: attemptBaseName(subject.code, plan, n),
      rotation: plan.gait == GaitClass.rotatedFoot ? _rotation : null,
    );
    current.attempts.add(a);
    _attempt = a;
    _deadline = now.add(plannedDuration);
    _warned = false;
    final snap = deps.manager.snapshot();
    _feetAtStart = {
      for (final side in FootSide.values)
        side: {
          'calibration': calibrationJson(deps.sources[side]!.calibration),
          'firmware': snap.of(side).firmware,
          'batteryStartPct': snap.of(side).batteryPct,
        },
    };
    _recorder = TrialRecorder(
      manager: deps.manager,
      csv: File('${dir.path}/${a.baseName}.csv'),
      fsrCount: modelFsrCount,
      now: deps.now,
      startUnixMs: _ms(now),
      endUnixMs: _ms(_deadline!),
    )..start();
    _phase = CapturePhase.recording;
    _writeSidecar();
    _saveSession();
    deps.cues.play(Cue.start);
    _startTicker();
    _notify();
  }

  /// The held "Stop early" button.
  void stopEarly() {
    if (_phase != CapturePhase.recording) return;
    _finish(EndReason.stoppedEarly, cutAt: deps.now());
  }

  /// The held "Mark invalid" toggle.
  void toggleMarkInvalid() {
    final r = _recorder;
    if (_phase != CapturePhase.recording || r == null) return;
    r.setMarkedInvalid(!r.markedInvalid);
    deps.cues.play(r.markedInvalid ? Cue.warning : Cue.linkBack);
    _notify();
  }

  /// Keeps the attempt just saved but marks it invalid; the trial is
  /// recorded again as a new attempt (`a2`, …). Files are never removed.
  void redo() {
    final a = _attempt;
    if (_phase != CapturePhase.saved || a == null) return;
    a
      ..valid = false
      ..invalidReason = 'redo';
    _patchSidecar(a, {'valid': false, 'invalidReason': 'redo'});
    _phase = CapturePhase.ready;
    _attempt = null;
    _savedAt = null;
    _saveSession();
    _notify();
  }

  /// On to the next trial not yet done.
  void next() {
    if (_phase != CapturePhase.saved) return;
    final i = trials.indexWhere((t) => !t.done);
    _attempt = null;
    _savedAt = null;
    _rotation = null;
    if (i < 0) {
      _phase = CapturePhase.done;
    } else {
      _index = i;
      _phase = CapturePhase.ready;
    }
    _saveSession();
    _notify();
  }

  /// From the summary: records a done trial again. Its valid attempt is
  /// marked invalid (`redo`) and kept.
  void reopen(int trialIndex) {
    if (_phase != CapturePhase.done && _phase != CapturePhase.ready) return;
    for (final a in trials[trialIndex].attempts) {
      if (!a.valid) continue;
      a
        ..valid = false
        ..invalidReason = 'redo';
      _patchSidecar(a, {'valid': false, 'invalidReason': 'redo'});
    }
    _index = trialIndex;
    _rotation = null;
    _phase = CapturePhase.ready;
    _saveSession();
    _notify();
  }

  /// Stops anything running (leaving the screen mid-recording counts as
  /// interrupted) and releases the timers.
  @override
  void dispose() {
    if (_phase == CapturePhase.recording || _phase == CapturePhase.saving) {
      _grace?.cancel();
      _finalize(EndReason.interrupted, notify: false);
    }
    _stopTicker();
    _disposed = true;
    super.dispose();
  }

  // --- Ticking ------------------------------------------------------------

  void _startTicker() {
    _ticker ??= Timer.periodic(tick, (_) => _onTick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _lostSince.clear();
    _lastLostCue.clear();
  }

  void _onTick() {
    final now = deps.now();
    final deadline = _deadline;
    switch (_phase) {
      case CapturePhase.practice:
        if (deadline != null && !now.isBefore(deadline)) {
          _deadline = null;
          startRecording();
          return;
        }
      case CapturePhase.recording:
        if (deadline == null) break;
        if (!_warned &&
            plannedDuration > CaptureTimings.endWarning &&
            deadline.difference(now) <= CaptureTimings.endWarning) {
          _warned = true;
          deps.cues.play(Cue.warning);
        }
        if (!now.isBefore(deadline)) {
          _finish(EndReason.completed);
          return;
        }
      case _:
        return;
    }
    _checkLinks(now);
    _notify();
  }

  /// Link loss, read at read time from the display path's derived state.
  void _checkLinks(DateTime now) {
    final snap = deps.manager.snapshot();
    for (final side in FootSide.values) {
      final usable = snap.of(side).usable;
      final since = _lostSince[side];
      if (!usable) {
        if (since == null) {
          _lostSince[side] = now;
          _lastLostCue[side] = now;
          deps.cues.play(Cue.linkLost);
        } else if (now.difference(_lastLostCue[side]!) >=
            CaptureTimings.linkLostRepeat) {
          _lastLostCue[side] = now;
          deps.cues.play(Cue.linkLost);
        }
      } else if (since != null) {
        _lostSince.remove(side);
        _lastLostCue.remove(side);
        deps.cues.play(Cue.linkBack);
      }
    }
  }

  void _finish(EndReason reason, {DateTime? cutAt}) {
    _stopTicker();
    if (cutAt != null) _recorder?.cut(_ms(cutAt));
    _deadline = null;
    _phase = CapturePhase.saving;
    deps.cues.play(Cue.end);
    _notify();
    _grace = Timer(grace, () => _finalize(reason));
  }

  void _finalize(EndReason reason, {bool notify = true}) {
    final r = _recorder;
    final a = _attempt;
    if (r == null || a == null) return;
    r.stop();
    a
      ..endReason = reason
      ..gapCount = r.gaps.length
      ..samples = {
        for (final side in FootSide.values) side: r.feet[side]!.samples,
      };
    if (reason == EndReason.interrupted) {
      a
        ..valid = false
        ..invalidReason = 'interrupted';
    }
    lastGaps = List.unmodifiable(r.gaps);
    _writeSidecar(final_: true);
    if (current.plan.isCalibration && a.valid) _summariseCalibration(r);
    _recorder = null;
    _savedAt = deps.now();
    _phase = CapturePhase.saved;
    _saveSession();
    if (notify) _notify();
  }

  // --- Files --------------------------------------------------------------

  File _sidecarOf(AttemptInfo a) => File('${dir.path}/${a.baseName}.json');

  void _writeSidecar({bool final_ = false}) {
    final a = _attempt!;
    final r = _recorder!;
    final plan = current.plan;
    final snap = deps.manager.snapshot();
    writeJsonAtomic(_sidecarOf(a), {
      'schema': captureSchema,
      'kind': 'trial',
      'sessionId': sessionId,
      'subject': subject.code.code,
      'rehearsal': subject.code.rehearsal,
      'trial': plan.number,
      'label': plan.label,
      'gait': plan.gait == null
          ? null
          : {'id': plan.gait!.id, 'modelIndex': plan.gait!.modelIndex},
      'attempt': a.attempt,
      'painSide': plan.gait == GaitClass.antalgic
          ? sideCode(subject.code.painSide)
          : null,
      'rotation': a.rotation?.id,
      'csv': '${a.baseName}.csv',
      'columns': csvColumns(modelFsrCount),
      'plannedS': plannedDuration.inMilliseconds / 1000,
      'startUnixMs': r.startUnixMs,
      'endUnixMs': final_ ? r.endUnixMs : null,
      'durationS': final_ ? (r.endUnixMs - r.startUnixMs) / 1000 : null,
      'endReason': a.endReason == null ? null : endReasonId(a.endReason!),
      'valid': a.valid,
      'invalidReason': a.invalidReason,
      'invalidSegments': [for (final s in r.segments) s.toJson()],
      'gaps': [for (final g in r.gaps) g.toJson()],
      'feet': {
        for (final side in FootSide.values)
          sideCode(side): {
            ..._feetAtStart![side]!,
            if (final_) 'batteryEndPct': snap.of(side).batteryPct,
            ...r.feet[side]!.toJson(),
          },
      },
      'roomTempC': roomTempC,
      'appVersion': deps.appVersion,
      'timings': timings.toJson(),
    });
  }

  /// Rewrites fields of an attempt's sidecar (redo, interrupted).
  void _patchSidecar(AttemptInfo a, Map<String, Object?> fields) {
    final f = _sidecarOf(a);
    if (!f.existsSync()) return;
    writeJsonAtomic(f, {...readJson(f), ...fields});
  }

  void _summariseCalibration(TrialRecorder r) {
    final temps = {
      for (final side in FootSide.values)
        side: r.feet[side]!.temps
            .where((t) => t.packet.quality == TempQuality.normal)
            .firstOrNull
            ?.packet,
    };
    final l = temps[FootSide.left]?.forefootC;
    final rt = temps[FootSide.right]?.forefootC;
    calibrationSummary = {
      'attempt': _attempt!.baseName,
      'restingKpaMean': {
        for (final side in FootSide.values)
          sideCode(side): r.feet[side]!.kpaMeans,
      },
      'startTempC': {
        for (final side in FootSide.values)
          sideCode(side): {
            'forefoot': temps[side]?.forefootC,
            'heel': temps[side]?.heelC,
          },
      },
      // Rule 4: both feet, or no number.
      'startDeltaForefootC': l == null || rt == null ? null : l - rt,
    };
  }

  void _saveSession() {
    writeJsonAtomic(File('${dir.path}/session.json'), {
      'schema': captureSchema,
      'kind': 'session',
      'sessionId': sessionId,
      'createdUnixMs': createdAt.millisecondsSinceEpoch,
      'subject': subject.toJson(),
      'rehearsal': subject.code.rehearsal,
      'roomTempC': roomTempC,
      'orderSeed': seed,
      'order': [for (final g in order) g.id],
      'painSide': sideCode(subject.code.painSide),
      'status': _phase == CapturePhase.done ? 'done' : 'open',
      'appVersion': deps.appVersion,
      'timings': timings.toJson(),
      'calibrationSummary': calibrationSummary,
      'trials': [
        for (final t in trials)
          {
            'trial': t.plan.number,
            'label': t.plan.label,
            'attempts': [for (final a in t.attempts) a.toJson()],
          },
      ],
      'exports': exports,
    });
  }

  /// Records an export staged now (before the files are copied, so the
  /// copy carries it).
  void noteExport() {
    exports.add(deps.now().toIso8601String());
    _saveSession();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static double _ms(DateTime t) => t.microsecondsSinceEpoch / 1000;
}

/// A session on the phone, as listed on the capture home screen.
class SessionListing {
  const SessionListing({
    required this.dir,
    required this.sessionId,
    required this.createdUnixMs,
    required this.done,
    required this.exported,
  });

  final Directory dir;
  final String sessionId;
  final int createdUnixMs;
  final bool done;
  final bool exported;
}

/// Every session under [researchRoot], newest first.
List<SessionListing> listSessions(Directory researchRoot) {
  if (!researchRoot.existsSync()) return const [];
  final out = <SessionListing>[];
  for (final d in researchRoot.listSync().whereType<Directory>()) {
    final f = File('${d.path}/session.json');
    if (!f.existsSync()) continue;
    try {
      final j = readJson(f);
      out.add(
        SessionListing(
          dir: d,
          sessionId: j['sessionId']! as String,
          createdUnixMs: j['createdUnixMs']! as int,
          done: j['status'] == 'done',
          exported: (j['exports'] as List<Object?>? ?? const []).isNotEmpty,
        ),
      );
    } on Object catch (e) {
      debugPrint('capture: unreadable ${f.path}: $e');
    }
  }
  out.sort((a, b) => b.createdUnixMs.compareTo(a.createdUnixMs));
  return out;
}
