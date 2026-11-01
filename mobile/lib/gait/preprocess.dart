import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/packets.dart';
import '../storage/baseline_repository.dart';
import 'model_spec.dart';

/// Model A preprocessing "ทางเอ" (DATA-CONTRACT v1.6 §7.1,
/// `shared/model_preprocess.json`; decided 2026-10-25, details 2026-11-01),
/// the same two steps as training (`tools/model/preprocess.py`):
///
/// 1. **Personal baseline:** per foot and channel, the median of that
///    foot's samples over the 30 s quiet-standing recording
///    ([footBaseline]), subtracted from every one of the 28 channels.
/// 2. **Min-Max:** `((x − baseline) − min) / (max − min)` with the
///    training subjects' min/max from `normalization.json`, no clipping
///    ([normalizeWindow]).
///
/// Float64 in that order, then float32: the same bits as Python
/// (`shared/test_vectors/model_preprocess/`, checked by a test).
class PreprocessSpec {
  const PreprocessSpec({required this.version, required this.baselineSeconds});

  /// Parses `model_preprocess.json`; refuses any value other than the
  /// decided ones (median, all channels, Min-Max, no clipping) rather than
  /// compute something else than training did.
  factory PreprocessSpec.parse(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    const decided = {
      'version': 1,
      'baselineStatistic': 'median',
      'baselineChannels': 'all',
      'scale': 'minmax',
      'clip': false,
      'normalizationMethod': Normalization.method,
    };
    for (final MapEntry(:key, :value) in decided.entries) {
      if (m[key] != value) {
        throw FormatException(
          'model_preprocess.json $key is ${m[key]}, the app does $value',
        );
      }
    }
    return PreprocessSpec(
      version: (m['version'] as num).toInt(),
      baselineSeconds: (m['baselineSeconds'] as num).toInt(),
    );
  }

  static const assetPath = 'assets/config/model_preprocess.json';

  /// Loads the bundled copy. Call before `runApp`.
  static Future<PreprocessSpec> load([AssetBundle? bundle]) async =>
      PreprocessSpec.parse(await (bundle ?? rootBundle).loadString(assetPath));

  final int version;

  /// How long the quiet-standing recording lasts (sample time).
  final int baselineSeconds;

  Duration get baselineDuration => Duration(seconds: baselineSeconds);
}

/// Loaded once in `runSmartInsole` and injected with an override, like
/// `modelInputSpecProvider`; tests override it with the file from disk.
final preprocessSpecProvider = Provider<PreprocessSpec>(
  (ref) => throw StateError('preprocessSpecProvider must be overridden'),
);

/// The median of [values]: the middle one, or the mean of the two middle
/// ones (`(a + b) × 0.5`, as in Python) for an even count.
double medianOf(List<double> values) {
  if (values.isEmpty) throw ArgumentError('median of no values');
  final s = [...values]..sort();
  final mid = s.length >> 1;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) * 0.5;
}

/// One foot's baseline: the per-channel median of its rows (each the
/// foot's 14 model channels, `footModelChannels`).
List<double> footBaseline(List<List<double>> rows) {
  if (rows.isEmpty) throw ArgumentError('no rows for a baseline');
  return [
    for (var c = 0; c < rows.first.length; c++)
      medianOf([for (final r in rows) r[c]]),
  ];
}

/// The two feet's baselines as the 28 model channels (§7.1: the left
/// foot's 14, then the right's).
List<double> modelBaseline(List<double> left, List<double> right) => [
  ...left,
  ...right,
];

/// The 28-channel baseline for the insoles connected now ([leftId],
/// [rightId]: their calibration `device_id`s) from the [stored] ones, or
/// null when either insole is unknown or has none: then Model A is not
/// used (S9). A baseline belongs to its insole, so a swapped insole needs
/// a new recording.
List<double>? modelBaselineOf(
  List<FootBaseline> stored, {
  required String? leftId,
  required String? rightId,
}) {
  List<double>? of(FootSide side, String? id) {
    if (id == null) return null;
    for (final b in stored) {
      if (b.side == side && b.insoleId == id) return b.values;
    }
    return null;
  }

  final l = of(FootSide.left, leftId);
  final r = of(FootSide.right, rightId);
  return l == null || r == null ? null : modelBaseline(l, r);
}

/// [rows] (raw 28-channel rows) preprocessed into the model's float32
/// input, row-major `[1, rows, channels]`: the [baseline] subtracted, then
/// Min-Max with [norm]. No clipping.
Float32List normalizeWindow(
  List<List<double>> rows,
  List<double> baseline,
  Normalization norm,
) {
  final channels = norm.min.length;
  if (baseline.length != channels) {
    throw ArgumentError(
      'baseline has ${baseline.length} channels, not $channels',
    );
  }
  final out = Float32List(rows.length * channels);
  for (var t = 0; t < rows.length; t++) {
    final row = rows[t];
    if (row.length != channels) {
      throw ArgumentError('row $t has ${row.length} channels, not $channels');
    }
    for (var c = 0; c < channels; c++) {
      out[t * channels + c] =
          ((row[c] - baseline[c]) - norm.min[c]) / (norm.max[c] - norm.min[c]);
    }
  }
  return out;
}
