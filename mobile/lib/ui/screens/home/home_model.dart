import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/packets.dart';
import '../../../config/foot_layout.dart';
import '../../../config/thresholds.dart';
import '../../../device/device_providers.dart';
import '../../../device/display_snapshot.dart';
import '../../../device/rolling_load.dart';
import '../../../device/rolling_peaks.dart';
import '../../../rules/alert_code.dart';
import '../../../rules/alert_engine.dart';
import '../../../rules/alert_providers.dart';
import '../../../rules/patient_status.dart';
import '../../../rules/pressure_level.dart';
import '../../../rules/weight_share.dart';

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
    this.asymmetrySide,
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

  /// Left foot's share of the weight, whole percent ([WeightShare]).
  final int? leftSharePct;

  /// The heavier foot, only while [uneven].
  final FootSide? heavierSide;

  /// The loads differ by more than `asymmetry.peakPct` ([WeightShare]):
  /// the note names the heavier foot, in `ink`.
  final bool uneven;

  /// Both feet usable but neither carries any load (the ratio is
  /// undefined).
  final bool balanceNoLoad;

  /// While `ASYMMETRY_PEAK` holds: the foot with the higher peak. The
  /// balance note then names it in the Be-careful colour with an icon
  /// (BACKLOG 37); otherwise null.
  final FootSide? asymmetrySide;

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
      other.balanceNoLoad == balanceNoLoad &&
      other.asymmetrySide == asymmetrySide;

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
    asymmetrySide,
  );
}

/// The balance card's window: weight share averaged over 10 s (user
/// decision 2026-10-23). Display only, not a threshold.
const balanceWindowMs = 10000;

/// Builds [HomeView] from the device layer: per-zone peaks ([RollingPeaks])
/// and mean loads ([RollingLoad]) from the 50 Hz path, connection, battery
/// and ΔT from the 10 Hz snapshot, and the status and `ASYMMETRY_PEAK` from
/// the [AlertEngine].
class HomeController extends Notifier<HomeView> {
  final _peaks = {
    for (final s in FootSide.values) s: RollingPeaks(windowMs: mapPeakWindowMs),
  };
  final _loads = {
    for (final s in FootSide.values) s: RollingLoad(windowMs: balanceWindowMs),
  };

  @override
  HomeView build() {
    final manager = ref.watch(deviceManagerProvider);
    final thresholds = ref.watch(thresholdsProvider);
    final engine = ref.watch(alertEngineProvider);
    final subs = <StreamSubscription<Object?>>[
      manager.batches.listen((b) {
        _peaks[b.side]!.add(b);
        _loads[b.side]!.add(b);
      }),
      manager.snapshots.listen((s) {
        final next = homeViewOf(
          s,
          thresholds: thresholds,
          rules: engine.view(s),
          channelPeaks: {
            for (final side in FootSide.values)
              side: _peaks[side]!.channelPeaks(),
          },
          meanLoads: {
            for (final side in FootSide.values) side: _loads[side]!.meanLoad(),
          },
          shownSharePct: state.leftSharePct,
        );
        if (next != state) state = next;
      }),
    ];
    ref.onDispose(() {
      for (final sub in subs) {
        sub.cancel();
      }
    });
    final s = manager.snapshot();
    return homeViewOf(
      s,
      thresholds: thresholds,
      rules: engine.view(s),
      channelPeaks: const {},
      meanLoads: const {},
    );
  }
}

final homeViewProvider = NotifierProvider<HomeController, HomeView>(
  HomeController.new,
);

/// Pure: what Home shows for [s]. [channelPeaks] are the windowed peaks
/// and [meanLoads] the windowed mean loads per foot; each falls back to the
/// snapshot's newest sample while its window is still empty.
///
/// [shownSharePct] is the balance number on screen now. It is kept while
/// the new share is within [shareDeadband] of it, so a 10 s mean that
/// moves by a fraction of a point as strides enter and leave the window
/// does not make the number flicker at 10 Hz (display only, not a
/// threshold).
HomeView homeViewOf(
  DisplaySnapshot s, {
  required Thresholds thresholds,
  required RulesView rules,
  required Map<FootSide, List<double>?> channelPeaks,
  required Map<FootSide, double?> meanLoads,
  int? shownSharePct,
}) {
  List<double>? peaksOf(FootView f) => mapPeaksOf(f, channelPeaks[f.side]);

  FootChipView chip(FootView f) => FootChipView(
    side: f.side,
    connected: f.usable,
    batteryPct: f.usable ? f.batteryPct : null,
    lowBattery:
        f.usable &&
        f.batteryPct != null &&
        f.batteryPct! < thresholds.batteryLowPct,
  );

  FootMapView map(FootView f) => footMapViewOf(f.side, peaksOf(f), thresholds);

  final both = s.left.usable && s.right.usable;

  double? delta;
  for (final d in [s.deltaForefootC, s.deltaHeelC]) {
    if (d != null && (delta == null || d.abs() > delta.abs())) delta = d;
  }
  if (!both) delta = null;

  WeightShare? share;
  if (both) {
    double loadOf(FootView f) =>
        meanLoads[f.side] ??
        (f.kpa ?? const <double>[]).fold(0, (a, k) => a + k);
    share = WeightShare.of(loadOf(s.left), loadOf(s.right));
  }
  final leftHeavier = share?.leftHeavier;
  final uneven = share?.isUneven(thresholds) ?? false;

  return HomeView(
    status: rules.status,
    left: chip(s.left),
    right: chip(s.right),
    leftMap: map(s.left),
    rightMap: map(s.right),
    deltaC: delta == null ? null : (delta.abs() * 10).round() / 10,
    warmerSide: delta == null || delta == 0
        ? null
        : (delta > 0 ? FootSide.left : FootSide.right),
    deltaOver: delta != null && deltaAbove(delta, thresholds.deltaC),
    leftSharePct: share == null
        ? null
        : (shownSharePct != null &&
                  (share.leftSharePct - shownSharePct).abs() <= shareDeadband
              ? shownSharePct
              : share.leftSharePct.round()),
    // Only when the note names a foot: below the cut-off which foot is a
    // hair heavier is not shown, and must not rebuild Home at 10 Hz.
    heavierSide: leftHeavier == null || !uneven
        ? null
        : (leftHeavier ? FootSide.left : FootSide.right),
    uneven: uneven,
    balanceNoLoad: both && share == null,
    asymmetrySide: both ? rules.asymmetry?.side : null,
  );
}

/// One foot map from its zone [peaks] (kPa; null = no data): the level
/// per zone and the zone the caption names. Home and My feet share it.
FootMapView footMapViewOf(
  FootSide side,
  List<double>? peaks,
  Thresholds thresholds,
) {
  if (peaks == null) return FootMapView(side: side);
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
  return FootMapView(side: side, levels: levels, topChannel: top);
}

/// Balance-number deadband, percentage points (see [homeViewOf]).
const shareDeadband = 1.0;

/// Zone names, for copy and labels.
FootZone zoneOf(int channel) => footLayout.zones[channel];
