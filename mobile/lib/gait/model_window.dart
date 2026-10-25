import 'dart:typed_data';

import '../ble/packets.dart';
import '../device/foot_sample.dart';
import '../device/model_channels.dart';
import 'model_spec.dart';

/// Model A's input window (DATA-CONTRACT §7.1) from the 50 Hz path (rule
/// 10): each foot's newest samples, paired in time by the same rule as the
/// capture files and the training scripts ([pairFeet]), turned into
/// 24-channel rows ([modelRow]) in `shared/model_input.json` order.
///
/// A window is exactly [ModelInputSpec.windowSamples] consecutive rows: a
/// gap between two rows (lost packets, a foot that dropped out, a pairing
/// miss) means no window until enough new rows have come, so the model is
/// never fed data stitched across a hole.
class ModelWindowBuilder {
  ModelWindowBuilder(this.spec);

  final ModelInputSpec spec;

  final _samples = {for (final side in FootSide.values) side: <FootSample>[]};
  final _session = <FootSide, int>{};

  /// Adds one packet of one foot.
  void add(FootBatch b) {
    final buf = _samples[b.side]!;
    // A new connection, or packets lost before this one: the old samples
    // no longer join up with the new ones.
    if (_session[b.side] != b.session || b.missingBefore > 0) buf.clear();
    _session[b.side] = b.session;
    buf.addAll(b.samples);
    if (buf.isEmpty) return;
    final keepFrom = buf.last.unixMs - spec.windowMs - spec.strideMs;
    buf.removeWhere((s) => s.unixMs < keepFrom);
  }

  /// Unix ms up to which both feet have samples, or null.
  double? get newestPairedMs {
    final l = _samples[FootSide.left]!;
    final r = _samples[FootSide.right]!;
    if (l.isEmpty || r.isEmpty) return null;
    return l.last.unixMs < r.last.unixMs ? l.last.unixMs : r.last.unixMs;
  }

  /// The newest [ModelInputSpec.windowSamples] consecutive rows, raw (kPa,
  /// g, °/s), or null when there are not that many without a gap.
  List<List<double>>? latestRows() {
    final pairs = pairFeet(_samples[FootSide.left]!, _samples[FootSide.right]!);
    final n = spec.windowSamples;
    if (pairs.length < n) return null;
    final window = pairs.sublist(pairs.length - n);
    // Left is the time base: consecutive rows are one sample period apart,
    // give or take the pairing tolerance.
    final maxStep = spec.samplePeriodMs + pairToleranceMs;
    for (var i = 1; i < window.length; i++) {
      if (window[i].$1.unixMs - window[i - 1].$1.unixMs > maxStep) return null;
    }
    final rows = <List<double>>[];
    for (final (l, r) in window) {
      final row = modelRow(l, r);
      if (row == null) return null;
      rows.add(row);
    }
    return rows;
  }

  /// Drops everything (both feet).
  void clear() {
    for (final buf in _samples.values) {
      buf.clear();
    }
    _session.clear();
  }
}

/// [rows] z-scored with [norm] into the model's float32 input, row-major
/// `[1, rows, channels]`.
Float32List normalizeWindow(List<List<double>> rows, Normalization norm) {
  final channels = norm.mean.length;
  final out = Float32List(rows.length * channels);
  for (var t = 0; t < rows.length; t++) {
    final row = rows[t];
    if (row.length != channels) {
      throw ArgumentError('row $t has ${row.length} channels, not $channels');
    }
    for (var c = 0; c < channels; c++) {
      out[t * channels + c] = (row[c] - norm.mean[c]) / norm.std[c];
    }
  }
  return out;
}
