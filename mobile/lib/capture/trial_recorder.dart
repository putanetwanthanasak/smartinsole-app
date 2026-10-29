import 'dart:async';
import 'dart:io';

import '../ble/packets.dart';
import '../device/device_manager.dart';
import '../device/foot_sample.dart';
import 'capture_files.dart';

/// A stretch with no data from one foot inside a trial.
class CaptureGap {
  const CaptureGap({
    required this.side,
    required this.kind,
    required this.fromUnixMs,
    required this.toUnixMs,
    required this.missingPackets,
  });

  final FootSide side;

  /// - `seq_gap`: packets lost mid-stream;
  /// - `missing_at_start`: a session's first packets never arrived;
  /// - `link_lost`: the connection dropped and came back (a new session,
  ///   so nobody can count the packets);
  /// - `no_data_at_start` / `no_data_at_end`: the foot's first / last
  ///   sample is more than [TrialRecorder.edgeSlackMs] from the window's
  ///   edge (e.g. the link was down when the trial started or ended);
  /// - `no_data`: nothing at all from this foot.
  final String kind;

  /// Last sample before the gap, or the window start.
  final double? fromUnixMs;

  /// First sample after it, or the window end.
  final double? toUnixMs;

  /// Null for `link_lost`: seq restarts, so nobody can count them.
  final int? missingPackets;

  Map<String, Object?> toJson() => {
    'side': sideCode(side),
    'kind': kind,
    'fromUnixMs': fromUnixMs,
    'toUnixMs': toUnixMs,
    'missingPackets': missingPackets,
  };
}

/// A stretch the researcher marked invalid (the volunteer broke form).
class InvalidSegment {
  InvalidSegment(this.fromUnixMs);
  final double fromUnixMs;
  double? toUnixMs;

  bool contains(double unix) =>
      unix >= fromUnixMs && (toUnixMs == null || unix < toUnixMs!);

  Map<String, Object?> toJson() => {
    'fromUnixMs': fromUnixMs,
    'toUnixMs': toUnixMs,
  };
}

/// What one foot gave a trial.
class FootRecord {
  int packets = 0;
  int samples = 0;
  int missingPackets = 0;
  double? firstUnixMs;
  double? lastUnixMs;
  final sessions = <int>{};
  final temps = <FootTemp>[];

  /// Sum of kPa per channel, for the calibration trial's resting means.
  List<double>? kpaSums;

  int? _session;
  FootTemp? _pendingTemp;

  List<double>? get kpaMeans => kpaSums == null || samples == 0
      ? null
      : [for (final s in kpaSums!) s / samples];

  Map<String, Object?> toJson() => {
    'packets': packets,
    'samples': samples,
    'missingPackets': missingPackets,
    'firstUnixMs': firstUnixMs,
    'lastUnixMs': lastUnixMs,
    'connSessions': sessions.toList()..sort(),
    'temps': [
      for (final t in temps)
        {
          'unixMs': t.unixMs,
          'fromArrival': t.fromArrival,
          'celsius': t.packet.celsius,
          'quality': [for (final q in t.packet.quality) q.name],
        },
    ],
  };
}

/// Records one trial attempt from the 50 Hz path ([DeviceManager.batches]
/// and [DeviceManager.temps], rule 10) into a CSV, row by row as packets
/// arrive. Rows reach the OS at once and are flushed to disk every
/// [flushEvery], so a crash or a killed app loses at most that much.
///
/// Only samples whose unix time is inside the window `[start, end)` are
/// written. The window is set by the controller from its deadline, so a
/// late timer tick never makes a trial longer than planned (rule 2 spirit:
/// time comes from timestamps, not from how often a timer fired).
class TrialRecorder {
  TrialRecorder({
    required this.manager,
    required this.csv,
    required this.fsrCount,
    required this.now,
    required this.startUnixMs,
    required this.endUnixMs,
    this.flushEvery = const Duration(seconds: 1),
  });

  final DeviceManager manager;
  final File csv;
  final int fsrCount;
  final DateTime Function() now;
  final double startUnixMs;

  /// The window's end; an early stop moves it earlier.
  double endUnixMs;
  final Duration flushEvery;

  /// How far a foot's first/last sample may be from the window's edge
  /// before it counts as a gap: packets come every 80–160 ms and carry
  /// samples up to that old.
  static const edgeSlackMs = 500.0;

  final feet = {FootSide.left: FootRecord(), FootSide.right: FootRecord()};
  final gaps = <CaptureGap>[];
  final segments = <InvalidSegment>[];

  RandomAccessFile? _file;
  double? _lastWrittenUnixMs;
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _flush;
  int _rejected = 0;

  /// Rows of a foot whose FSR count differs from the header; expected 0
  /// (the pre-check requires both feet to have [fsrCount]).
  int get rejectedBatches => _rejected;

  bool get recording => _file != null;

  bool get markedInvalid =>
      segments.isNotEmpty && segments.last.toUnixMs == null;

  void start() {
    csv.parent.createSync(recursive: true);
    _file = csv.openSync(mode: FileMode.writeOnly)
      ..writeStringSync('${csvColumns(fsrCount).join(',')}\n');
    _subs
      ..add(manager.batches.listen(_onBatch))
      ..add(manager.temps.listen(_onTemp));
    _flush = Timer.periodic(flushEvery, (_) => _file?.flushSync());
  }

  /// Starts or ends an invalid segment at the phone's time now; samples
  /// are judged by their own unix time, not by when they arrive. An edge
  /// never falls at or before a row already written (that row's `valid`
  /// can't change any more), so the file and the sidecar always agree.
  void setMarkedInvalid(bool invalid) {
    if (invalid == markedInvalid) return;
    var t = now().microsecondsSinceEpoch / 1000;
    final written = _lastWrittenUnixMs;
    if (written != null && written >= t) t = written + 0.001;
    if (invalid) {
      segments.add(InvalidSegment(t));
    } else {
      segments.last.toUnixMs = t;
    }
  }

  /// Ends the window early (a held "Stop early"). Never at or before a row
  /// already written, so every row is inside the window the sidecar gives.
  void cut(double atUnixMs) {
    final written = _lastWrittenUnixMs;
    final at = written != null && written >= atUnixMs
        ? written + 0.001
        : atUnixMs;
    if (at < endUnixMs) endUnixMs = at;
  }

  /// Stops listening and closes the file. Ends an open invalid segment.
  /// [cutAtUnixMs] cuts the window short (an early stop).
  void stop({double? cutAtUnixMs}) {
    if (_file == null) return;
    if (cutAtUnixMs != null && cutAtUnixMs < endUnixMs) {
      cut(cutAtUnixMs);
    }
    setMarkedInvalid(false);
    for (final side in FootSide.values) {
      final f = feet[side]!;
      final first = f.firstUnixMs;
      final last = f.lastUnixMs;
      if (first == null || last == null) {
        gaps.add(
          CaptureGap(
            side: side,
            kind: 'no_data',
            fromUnixMs: startUnixMs,
            toUnixMs: endUnixMs,
            missingPackets: null,
          ),
        );
        continue;
      }
      if (first - startUnixMs > edgeSlackMs) {
        gaps.insert(
          0,
          CaptureGap(
            side: side,
            kind: 'no_data_at_start',
            fromUnixMs: startUnixMs,
            toUnixMs: first,
            missingPackets: null,
          ),
        );
      }
      if (endUnixMs - last > edgeSlackMs) {
        gaps.add(
          CaptureGap(
            side: side,
            kind: 'no_data_at_end',
            fromUnixMs: last,
            toUnixMs: endUnixMs,
            missingPackets: null,
          ),
        );
      }
    }
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _flush?.cancel();
    _file!
      ..flushSync()
      ..closeSync();
    _file = null;
  }

  void _onTemp(FootTemp t) {
    final f = feet[t.side]!;
    f.temps.add(t);
    f._pendingTemp = t;
  }

  void _onBatch(FootBatch b) {
    final file = _file;
    if (file == null || b.samples.isEmpty) return;
    if (b.samples.first.fsrKpa.length != fsrCount) {
      _rejected++;
      return;
    }
    final inWindow = [
      for (var i = 0; i < b.samples.length; i++)
        if (b.samples[i].unixMs >= startUnixMs &&
            b.samples[i].unixMs < endUnixMs)
          i,
    ];
    if (inWindow.isEmpty) return;
    final f = feet[b.side]!;
    final first = b.samples[inWindow.first].unixMs;
    if (f._session != null && b.session != f._session) {
      gaps.add(
        CaptureGap(
          side: b.side,
          kind: 'link_lost',
          fromUnixMs: f.lastUnixMs,
          toUnixMs: first,
          missingPackets: null,
        ),
      );
    }
    if (b.missingBefore > 0) {
      // On a session's first packet, the lost ones were its start.
      final atStart = b.session != f._session && b.seq == b.missingBefore;
      gaps.add(
        CaptureGap(
          side: b.side,
          kind: atStart ? 'missing_at_start' : 'seq_gap',
          fromUnixMs: atStart ? null : f.lastUnixMs,
          toUnixMs: first,
          missingPackets: b.missingBefore,
        ),
      );
      f.missingPackets += b.missingBefore;
    }
    f._session = b.session;
    f.sessions.add(b.session);
    f.packets++;

    final rows = StringBuffer();
    for (final i in inWindow) {
      final s = b.samples[i];
      final temp = f._pendingTemp;
      f._pendingTemp = null;
      final valid = !segments.any((seg) => seg.contains(s.unixMs));
      rows.writeln(
        csvRow(
          side: b.side,
          batch: b,
          i: i,
          valid: valid,
          missingBefore: i == inWindow.first ? b.missingBefore : 0,
          temp: temp,
        ),
      );
      f.samples++;
      f.firstUnixMs ??= s.unixMs;
      f.lastUnixMs = s.unixMs;
      if (_lastWrittenUnixMs == null || s.unixMs > _lastWrittenUnixMs!) {
        _lastWrittenUnixMs = s.unixMs;
      }
      final sums = f.kpaSums ??= List.filled(fsrCount, 0);
      for (var c = 0; c < fsrCount; c++) {
        sums[c] += s.fsrKpa[c];
      }
    }
    file.writeStringSync(rows.toString());
  }
}
