import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Model A's input (DATA-CONTRACT §7.1), from `shared/model_input.json`.
/// The app bundles an identical copy (`assets/config/model_input.json`, a
/// test checks it), so the window, the stride and the channel order the
/// app feeds the model are the ones the training scripts read.
class ModelInputSpec {
  const ModelInputSpec({
    required this.version,
    required this.channels,
    required this.sampleRateHz,
    required this.windowSamples,
    required this.strideSamples,
  });

  factory ModelInputSpec.parse(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return ModelInputSpec(
      version: (m['version'] as num).toInt(),
      channels: [for (final c in m['channels'] as List) c as String],
      sampleRateHz: (m['sampleRateHz'] as num).toInt(),
      windowSamples: (m['windowSamples'] as num).toInt(),
      strideSamples: (m['strideSamples'] as num).toInt(),
    );
  }

  static const assetPath = 'assets/config/model_input.json';

  /// Loads the bundled copy. Call before `runApp`.
  static Future<ModelInputSpec> load([AssetBundle? bundle]) async =>
      ModelInputSpec.parse(await (bundle ?? rootBundle).loadString(assetPath));

  /// The file's format version; a model's `normalization.json` must carry
  /// the same one.
  final int version;

  /// The 28 channel names, in model order.
  final List<String> channels;
  final int sampleRateHz;
  final int windowSamples;
  final int strideSamples;

  /// Milliseconds between samples (20 at 50 Hz).
  double get samplePeriodMs => Duration.millisecondsPerSecond / sampleRateHz;

  /// The window's length (2 s) and the time between estimates (1 s).
  double get windowMs => windowSamples * samplePeriodMs;
  double get strideMs => strideSamples * samplePeriodMs;
}

/// Loaded once in `runSmartInsole` and injected with an override, like
/// `thresholdsProvider`; tests override it with the file from disk.
final modelInputSpecProvider = Provider<ModelInputSpec>(
  (ref) => throw StateError('modelInputSpecProvider must be overridden'),
);

/// `normalization.json`, delivered with the model: the training subjects'
/// min and max per channel, after each subject's baseline was subtracted
/// (contract §7.1, preprocessing "ทางเอ", `shared/model_preprocess.json`).
/// Format: `{"version": 2, "method": "baseline-minmax", "channels": [28
/// names], "min": [28], "max": [28]}`. A z-score file (`mean` / `std`,
/// before S9) is refused.
class Normalization {
  const Normalization({
    required this.channels,
    required this.min,
    required this.max,
  });

  /// The only method the app computes (`model_preprocess.json`
  /// `normalizationMethod`).
  static const method = 'baseline-minmax';

  /// Parses and checks [json] against [spec]: the same `version` (user
  /// decision 2026-10-25), the method, the same channels in the same order
  /// (so a model trained on another order is refused, never run), and
  /// every max above its min. Throws [FormatException] with the reason.
  factory Normalization.parse(String json, ModelInputSpec spec) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final version = m['version'];
    if (version is! num || version != spec.version) {
      throw FormatException(
        'normalization.json version is $version, '
        'model_input.json ${spec.version}',
      );
    }
    if (m['method'] != method) {
      throw FormatException(
        'normalization.json method is ${m['method']}, the app does $method'
        '${m.containsKey('mean') ? ' (a z-score file from before S9)' : ''}',
      );
    }
    final channels = [for (final c in m['channels'] as List) c as String];
    final min = [for (final v in m['min'] as List) (v as num).toDouble()];
    final max = [for (final v in m['max'] as List) (v as num).toDouble()];
    if (channels.length != spec.channels.length) {
      throw FormatException(
        'normalization.json has ${channels.length} channels, '
        'model_input.json ${spec.channels.length}',
      );
    }
    for (var i = 0; i < channels.length; i++) {
      if (channels[i] != spec.channels[i]) {
        throw FormatException(
          'normalization.json channel $i is ${channels[i]}, '
          'model_input.json says ${spec.channels[i]}',
        );
      }
    }
    if (min.length != channels.length || max.length != channels.length) {
      throw const FormatException(
        'normalization.json min/max length differs from its channels',
      );
    }
    for (var i = 0; i < channels.length; i++) {
      if (!(max[i] > min[i])) {
        throw FormatException(
          'normalization.json max of ${channels[i]} is ${max[i]}; '
          'it must be above its min ${min[i]}',
        );
      }
    }
    return Normalization(channels: channels, min: min, max: max);
  }

  final List<String> channels;
  final List<double> min;
  final List<double> max;
}
