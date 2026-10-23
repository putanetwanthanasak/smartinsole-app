import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `shared/thresholds.json` (DATA-CONTRACT §8.3). Every clinical boundary
/// the app uses comes from here (rule 12). The app bundles an identical
/// copy as `assets/config/thresholds.json`.
class Thresholds {
  const Thresholds({
    required this.watchKpa,
    required this.alertKpa,
    required this.ptiKpaS,
    required this.deltaC,
    required this.consecutiveReadings,
    required this.peakAsymmetryPct,
    required this.ptiAsymmetryPct,
    required this.concentrationPct,
    required this.minConfidence,
    required this.walkingAccelG,
    required this.walkingWindowMs,
    required this.batteryLowPct,
  });

  factory Thresholds.parse(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    Map<String, dynamic> block(String k) => m[k] as Map<String, dynamic>;
    double d(String b, String k) => (block(b)[k] as num).toDouble();
    return Thresholds(
      watchKpa: d('pressure', 'watchKpa'),
      alertKpa: d('pressure', 'alertKpa'),
      ptiKpaS: d('pressure', 'ptiKpaS'),
      deltaC: d('temperature', 'deltaC'),
      consecutiveReadings: (block('temperature')['consecutiveReadings'] as num)
          .toInt(),
      peakAsymmetryPct: d('asymmetry', 'peakPct'),
      ptiAsymmetryPct: d('asymmetry', 'ptiPct'),
      concentrationPct: d('asymmetry', 'concentrationPct'),
      minConfidence: d('model', 'minConfidence'),
      walkingAccelG: d('motion', 'walkingAccelG'),
      walkingWindowMs: (block('motion')['walkingWindowMs'] as num).toInt(),
      batteryLowPct: d('battery', 'lowPct'),
    );
  }

  static const assetPath = 'assets/config/thresholds.json';

  /// Loads the bundled copy. Call before `runApp`.
  static Future<Thresholds> load([AssetBundle? bundle]) async =>
      Thresholds.parse(await (bundle ?? rootBundle).loadString(assetPath));

  /// `PRESSURE_WATCH`: a zone above this is "medium" (orange dot).
  final double watchKpa;

  /// `PRESSURE_PEAK`: a zone above this is "high".
  final double alertKpa;
  final double ptiKpaS;

  /// `TEMP_DELTA`: left–right difference at one site above this, on
  /// [consecutiveReadings] readings in a row (rule 6).
  final double deltaC;
  final int consecutiveReadings;

  /// `ASYMMETRY_PEAK`: PAI above this.
  final double peakAsymmetryPct;
  final double ptiAsymmetryPct;
  final double concentrationPct;
  final double minConfidence;
  final double walkingAccelG;
  final int walkingWindowMs;

  /// `BATTERY_LOW`: battery below this.
  final double batteryLowPct;
}

/// Loaded once in `runSmartInsole` and injected with an override; tests
/// override it with the file from disk.
final thresholdsProvider = Provider<Thresholds>(
  (ref) => throw StateError('thresholdsProvider must be overridden'),
);
