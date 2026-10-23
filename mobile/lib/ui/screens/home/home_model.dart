import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/packets.dart';
import '../../../config/foot_layout.dart';
import '../../../config/thresholds.dart';
import '../../../device/device_providers.dart';
import '../../../device/display_snapshot.dart';
import '../../../device/rolling_peaks.dart';
import '../../../rules/alert_code.dart';
import '../../../rules/asymmetry.dart';
import '../../../rules/interim_status.dart';
import '../../../rules/patient_status.dart';
import '../../../rules/pressure_level.dart';

/// One foot chip on Home.
@immutable
class FootChipView {
  const FootChipView({
    required this.side,
    required this.connected,
    this.batteryPct,
    this.lowBattery = false,
  });

  final FootSide side;

  /// Streaming and fresh (the filled `connected` dot).
  final bool connected;

  /// Shown only while [connected].
  final int? batteryPct;

  /// Below `battery.lowPct` (`BATTERY_LOW`).
  final bool lowBattery;

  @override
  bool operator ==(Object other) =>
      other is FootChipView &&
      other.side == side &&
      other.connected == connected &&
      other.batteryPct == batteryPct &&
      other.lowBattery == lowBattery;

  @override
  int get hashCode => Object.hash(side, connected, batteryPct, lowBattery);
}

/// One foot map: a level per zone, or null for no data.
@immutable
class FootMapView {
  const FootMapView({required this.side, this.levels, this.topChannel});

  final FootSide side;

  /// Indexed by FSR channel; null unless the foot is usable.
  final List<PressureLevel>? levels;

  /// The most loaded channel among those at the highest level above low,
  /// for the caption and the screen-reader label; null when all are low.
  final int? topChannel;

  bool get hasData => levels != null;
  PressureLevel? get topLevel =>
      topChannel == null ? null : levels![topChannel!];

  @override
  bool operator ==(Object other) =>
      other is FootMapView &&
      other.side == side &&
      listEquals(other.levels, levels) &&
      other.topChannel == topChannel;

  @override
  int get hashCode =>
      Object.hash(side, Object.hashAll(levels ?? []), topChannel);
}

/// Everything Home shows, rounded to what is visible, so the screen only
/// rebuilds when something visible changes (the snapshot comes at 10 Hz).
/// Two-foot values are null unless both feet are usable (rule 4).
@immutable
class HomeView {
  const HomeView({
    required this.status,
    required this.left,
    required this.right,
    required this.leftMap,
    required this.rightMap,
    this.deltaC,
    this.warmerSide,
    this.deltaOver = false,
    this.leftSharePct,
    this.heavierSide,
    this.uneven = false,
    this.balanceNoLoad = false,
  });

  static const initial = HomeView(
    status: PatientStatus.noData,
    left: FootChipView(side: FootSide.left, connected: false),
    right: FootChipView(side: FootSide.right, connected: false),
    leftMap: FootMapView(side: FootSide.left),
    rightMap: FootMapView(side: FootSide.right),
  );

  final PatientStatus status;
  final FootChipView left;
  final FootChipView right;
  final FootMapView leftMap;
  final FootMapView rightMap;

  /// Larger |ΔT| of the two sites, rounded to 0.1 °C.
  final double? deltaC;
  final FootSide? warmerSide;

  /// That |ΔT| is above `deltaC` on this reading (not yet a `TEMP_DELTA`).
  final bool deltaOver;

  /// Left share of the two peaks, whole percent ([PeakAsymmetry]).
  final int? leftSharePct;
  final FootSide? heavierSide;

  /// PAI above `asymmetry.peakPct`.
  final bool uneven;

  /// Both feet usable but neither carries any load (the ratio is
  /// undefined).
  final bool balanceNoLoad;

  bool get bothUsable => left.connected && right.connected;
  FootChipView chip(FootSide s) => s == FootSide.left ? left : right;
  FootMapView map(FootSide s) => s == FootSide.left ? leftMap : rightMap;

  /// `TEMP_DELTA` is what set the status.
  bool get tempAlert => status.cause?.code == AlertCode.tempDelta;

  @override
  bool operator ==(Object other) =>
      other is HomeView &&
      other.status == status &&
      other.left == left &&
      other.right == right &&
      other.leftMap == leftMap &&
      other.rightMap == rightMap &&
      other.deltaC == deltaC &&
      other.warmerSide == warmerSide &&
      other.deltaOver == deltaOver &&
      other.leftSharePct == leftSharePct &&
      other.heavierSide == heavierSide &&
      other.uneven == uneven &&
      other.balanceNoLoad == balanceNoLoad;

  @override
  int get hashCode => Object.hash(
    status,
    left,
    right,
    leftMap,
    rightMap,
    deltaC,
    warmerSide,
    deltaOver,
    leftSharePct,
    heavierSide,
    uneven,
    balanceNoLoad,
  );
}

/// Builds [HomeView] from the device layer: per-zone peaks from the 50 Hz
/// path ([RollingPeaks]), connection, battery and ΔT from the 10 Hz
/// snapshot, and the status from [InterimStatus] (S7 replaces it).
class HomeController extends Notifier<HomeView> {
  final _peaks = {
    for (final s in FootSide.values)
      s: RollingPeaks(windowMs: PeakAsymmetry.peakWindowMs),
  };

  @override
  HomeView build() {
    final manager = ref.watch(deviceManagerProvider);
    final thresholds = ref.watch(thresholdsProvider);
    final mock = ref.watch(mockInsolesProvider);
    final interim = InterimStatus(
      manager: manager,
      thresholds: thresholds,
      mockPreset: mock == null ? null : () => mock.preset,
    );
    final subs = <StreamSubscription<Object?>>[
      manager.batches.listen((b) => _peaks[b.side]!.add(b)),
      manager.snapshots.listen((s) {
        final next = homeViewOf(
          s,
          thresholds: thresholds,
          status: interim.status(s),
          channelPeaks: {
            for (final side in FootSide.values)
              side: _peaks[side]!.channelPeaks(),
          },
        );
        if (next != state) state = next;
      }),
    ];
    ref.onDispose(() {
      for (final sub in subs) {
        sub.cancel();
      }
      interim.dispose();
    });
    final s = manager.snapshot();
    return homeViewOf(
      s,
      thresholds: thresholds,
      status: interim.status(s),
      channelPeaks: const {},
    );
  }
}

final homeViewProvider = NotifierProvider<HomeController, HomeView>(
  HomeController.new,
);

/// Pure: what Home shows for [s]. [channelPeaks] are the windowed peaks per
/// foot (falls back to the snapshot's newest sample when a window is still
/// empty).
HomeView homeViewOf(
  DisplaySnapshot s, {
  required Thresholds thresholds,
  required PatientStatus status,
  required Map<FootSide, List<double>?> channelPeaks,
}) {
  List<double>? peaksOf(FootView f) =>
      f.usable ? (channelPeaks[f.side] ?? f.kpa) : null;

  FootChipView chip(FootView f) => FootChipView(
    side: f.side,
    connected: f.usable,
    batteryPct: f.usable ? f.batteryPct : null,
    lowBattery:
        f.usable &&
        f.batteryPct != null &&
        f.batteryPct! < thresholds.batteryLowPct,
  );

  FootMapView map(FootView f) {
    final peaks = peaksOf(f);
    if (peaks == null) return FootMapView(side: f.side);
    final levels = [for (final k in peaks) pressureLevel(k, thresholds)];
    int? top;
    for (var c = 0; c < levels.length; c++) {
      if (levels[c] == PressureLevel.low) continue;
      if (top == null ||
          levels[c].index > levels[top].index ||
          (levels[c] == levels[top] && peaks[c] > peaks[top])) {
        top = c;
      }
    }
    return FootMapView(side: f.side, levels: levels, topChannel: top);
  }

  final both = s.left.usable && s.right.usable;

  double? delta;
  for (final d in [s.deltaForefootC, s.deltaHeelC]) {
    if (d != null && (delta == null || d.abs() > delta.abs())) delta = d;
  }
  if (!both) delta = null;

  PeakAsymmetry? asym;
  if (both) {
    double footPeak(List<double>? p) =>
        (p ?? const <double>[]).fold(0, (m, v) => v > m ? v : m);
    asym = PeakAsymmetry.of(
      footPeak(peaksOf(s.left)),
      footPeak(peaksOf(s.right)),
    );
  }
  final leftHigher = asym?.leftHigher;

  return HomeView(
    status: status,
    left: chip(s.left),
    right: chip(s.right),
    leftMap: map(s.left),
    rightMap: map(s.right),
    deltaC: delta == null ? null : (delta.abs() * 10).round() / 10,
    warmerSide: delta == null || delta == 0
        ? null
        : (delta > 0 ? FootSide.left : FootSide.right),
    deltaOver: delta != null && deltaAbove(delta, thresholds.deltaC),
    leftSharePct: asym?.leftSharePct.round(),
    heavierSide: leftHigher == null
        ? null
        : (leftHigher ? FootSide.left : FootSide.right),
    uneven: asym?.isUneven(thresholds) ?? false,
    balanceNoLoad: both && asym == null,
  );
}

/// Zone names, for copy and labels.
FootZone zoneOf(int channel) => footLayout.zones[channel];
