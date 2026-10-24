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
    required this.ptiWindowMin,
    required this.ptiMinSteps,
    required this.peakHoldMs,
    required this.deltaC,
    required this.consecutiveReadings,
    required this.peakAsymmetryPct,
    required this.ptiAsymmetryPct,
    required this.concentrationPct,
    required this.peakAsymmetrySteps,
    required this.concentrationSteps,
    required this.minConfidence,
    required this.walkingAccelG,
    required this.walkingWindowMs,
    required this.batteryLowPct,
    required this.deviceLostAfterMin,
    required this.repeatMin,
    required this.stepContactKpa,
    required this.minStanceMs,
    required this.maxStanceMs,
    this.sources = const {},
  });

  factory Thresholds.parse(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    Map<String, dynamic> block(String k) => m[k] as Map<String, dynamic>;
    double d(String b, String k) => (block(b)[k] as num).toDouble();
    int i(String b, String k) => (block(b)[k] as num).toInt();
    return Thresholds(
      watchKpa: d('pressure', 'watchKpa'),
      alertKpa: d('pressure', 'alertKpa'),
      ptiKpaS: d('pressure', 'ptiKpaS'),
      ptiWindowMin: i('pressure', 'ptiWindowMin'),
      ptiMinSteps: i('pressure', 'ptiMinSteps'),
      peakHoldMs: i('pressure', 'peakHoldMs'),
      deltaC: d('temperature', 'deltaC'),
      consecutiveReadings: i('temperature', 'consecutiveReadings'),
      peakAsymmetryPct: d('asymmetry', 'peakPct'),
      ptiAsymmetryPct: d('asymmetry', 'ptiPct'),
      concentrationPct: d('asymmetry', 'concentrationPct'),
      peakAsymmetrySteps: i('asymmetry', 'peakSteps'),
      concentrationSteps: i('asymmetry', 'concentrationSteps'),
      minConfidence: d('model', 'minConfidence'),
      walkingAccelG: d('motion', 'walkingAccelG'),
      walkingWindowMs: i('motion', 'walkingWindowMs'),
      batteryLowPct: d('battery', 'lowPct'),
      deviceLostAfterMin: i('device', 'lostAfterMin'),
      repeatMin: i('alerts', 'repeatMin'),
      stepContactKpa: d('steps', 'contactKpa'),
      minStanceMs: i('steps', 'minStanceMs'),
      maxStanceMs: i('steps', 'maxStanceMs'),
      sources: {
        for (final e
            in ((m['sources'] as Map<String, dynamic>?) ?? const {}).entries)
          e.key: e.value as String,
      },
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

  /// `PRESSURE_PTI`: a zone's mean per-step pressure–time integral over
  /// the steps of the last [ptiWindowMin] minutes above this, once at
  /// least [ptiMinSteps] steps are in the window (user decision
  /// 2026-10-24, BACKLOG 31).
  final double ptiKpaS;
  final int ptiWindowMin;
  final int ptiMinSteps;

  /// `PRESSURE_WATCH` / `PRESSURE_PEAK` stay active this long after the
  /// last sample above their boundary, so one condition covers a whole
  /// walk instead of one per stance. PROVISIONAL, technical.
  final int peakHoldMs;

  /// `TEMP_DELTA`: left–right difference at one site above this, on
  /// [consecutiveReadings] readings in a row (rule 6).
  final double deltaC;
  final int consecutiveReadings;

  /// `ASYMMETRY_PEAK`: PAI above this on [peakAsymmetrySteps] steps in a
  /// row.
  final double peakAsymmetryPct;
  final int peakAsymmetrySteps;
  final double ptiAsymmetryPct;

  /// `LOAD_CONCENTRATION`: one zone's share of a step's summed zone peaks
  /// above this, the same zone on [concentrationSteps] steps in a row.
  final double concentrationPct;
  final int concentrationSteps;

  /// Model A confidence needed for a gait note (contract §8.3.1).
  final double minConfidence;

  /// Walking gate (contract §8.3.2): mean |‖a‖ − 1 g| over
  /// [walkingWindowMs] at or above [walkingAccelG]. PROVISIONAL.
  final double walkingAccelG;
  final int walkingWindowMs;

  /// `BATTERY_LOW`: battery below this.
  final double batteryLowPct;

  /// `DEVICE_LOST`: no data for longer than this.
  final int deviceLostAfterMin;

  /// The same alert (code + side + zone or site) at most once per this
  /// many minutes (contract §8.5).
  final int repeatMin;

  /// Step detection: a stance is the summed zone kPa above
  /// [stepContactKpa], [minStanceMs] to [maxStanceMs] long, with the
  /// walking gate on during it. PROVISIONAL, technical (checked with the
  /// real boards in SR).
  final double stepContactKpa;
  final int minStanceMs;
  final int maxStanceMs;

  /// Where each alert code's boundary comes from, keyed by its wire name
  /// (`TEMP_DELTA`, …): the "ที่มา" column of DATA-CONTRACT §8.3, word for
  /// word. Shown under "ที่มาของเกณฑ์" on the alert detail.
  final Map<String, String> sources;

  /// The source of [wireCode], or null when it has none ("—" in the
  /// contract, or missing).
  String? sourceOf(String wireCode) {
    final s = sources[wireCode];
    return s == null || s == noSource ? null : s;
  }

  /// The contract's "no source" mark.
  static const noSource = '—';
}

/// Loaded once in `runSmartInsole` and injected with an override; tests
/// override it with the file from disk.
final thresholdsProvider = Provider<Thresholds>(
  (ref) => throw StateError('thresholdsProvider must be overridden'),
);
