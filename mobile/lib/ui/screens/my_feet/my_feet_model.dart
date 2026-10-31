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
import '../../../rules/alert_engine.dart';
import '../../../rules/alert_providers.dart';
import '../../../rules/patient_status.dart';
import '../../../storage/models.dart' show TempSiteEntry;
import '../home/home_model.dart';

/// The level-3 pressure codes: the ones that turn the Pressure banner to
/// Be careful (`PRESSURE_WATCH`, level 2, stays Safe with orange dots).
final bannerPressureCodes = {
  for (final c in pressureCodes)
    if (c.level >= carefulLevel) c,
};

/// One foot on the Pressure tab. Values are rounded to what is shown
/// (whole kPa, kPa·s and %), so a 10 Hz snapshot only rebuilds the tab
/// when something visible changes.
@immutable
class PressureFootView {
  const PressureFootView({
    required this.map,
    this.kpa,
    this.walkingPeakKpa,
    this.ptiKpaS,
    this.concentrationPct,
  });

  /// Levels and the caption zone, from the same 2 s peaks as Home.
  final FootMapView map;

  /// Those peaks in whole kPa per zone; null unless the foot is usable.
  final List<int>? kpa;

  /// [PressureFigures], rounded; null for a foot that is not usable or
  /// has no such figure yet.
  final int? walkingPeakKpa;
  final int? ptiKpaS;
  final int? concentrationPct;

  FootSide get side => map.side;
  bool get usable => map.hasData;

  @override
  bool operator ==(Object other) =>
      other is PressureFootView &&
      other.map == map &&
      listEquals(other.kpa, kpa) &&
      other.walkingPeakKpa == walkingPeakKpa &&
      other.ptiKpaS == ptiKpaS &&
      other.concentrationPct == concentrationPct;

  @override
  int get hashCode => Object.hash(
    map,
    Object.hashAll(kpa ?? const []),
    walkingPeakKpa,
    ptiKpaS,
    concentrationPct,
  );
}

@immutable
class PressureTabView {
  const PressureTabView({required this.left, required this.right, this.cause});

  static const initial = PressureTabView(
    left: PressureFootView(map: FootMapView(side: FootSide.left)),
    right: PressureFootView(map: FootMapView(side: FootSide.right)),
  );

  final PressureFootView left;
  final PressureFootView right;

  /// The level-3 pressure rule that names the banner (the status ranking,
  /// [RulesView.top]), or null.
  final StatusCause? cause;

  PressureFootView foot(FootSide s) => s == FootSide.left ? left : right;

  @override
  bool operator ==(Object other) =>
      other is PressureTabView &&
      other.left == left &&
      other.right == right &&
      other.cause == cause;

  @override
  int get hashCode => Object.hash(left, right, cause);
}

/// One foot on the Temperature tab.
@immutable
class TempFootView {
  const TempFootView({
    required this.side,
    required this.usable,
    this.celsius = const [],
    this.quality = const [],
    this.lastDataAt,
  });

  final FootSide side;
  final bool usable;

  /// Newest reading per site (index = zone), rounded to 0.1 °C; empty
  /// unless [usable] and a reading arrived; null where the sensor could
  /// not read.
  final List<double?> celsius;

  /// Each site's quality in that reading; empty with no reading.
  final List<TempQuality> quality;

  double? at(int site) => site < celsius.length ? celsius[site] : null;

  /// When this foot's newest sample arrived in this run, kept only while
  /// it is not usable ("ตั้งแต่ HH:mm"); null otherwise.
  final DateTime? lastDataAt;

  @override
  bool operator ==(Object other) =>
      other is TempFootView &&
      other.side == side &&
      other.usable == usable &&
      listEquals(other.celsius, celsius) &&
      listEquals(other.quality, quality) &&
      other.lastDataAt == lastDataAt;

  @override
  int get hashCode => Object.hash(
    side,
    usable,
    Object.hashAll(celsius),
    Object.hashAll(quality),
    lastDataAt,
  );
}

/// `TEMP_DELTA` holding at one site (every qualifying site of the warmer
/// foot's condition, `details.tempSites`).
@immutable
class TempAlertView {
  const TempAlertView({
    required this.site,
    required this.warmerSide,
    required this.deltaC,
    this.consecutive,
  });

  /// Zone index.
  final int site;
  final FootSide warmerSide;

  /// |ΔT|, rounded to 0.1 °C.
  final double deltaC;

  /// Readings above the threshold in a row; only for the site the alert
  /// names (the engine's details carry it for that one).
  final int? consecutive;

  @override
  bool operator ==(Object other) =>
      other is TempAlertView &&
      other.site == site &&
      other.warmerSide == warmerSide &&
      other.deltaC == deltaC &&
      other.consecutive == consecutive;

  @override
  int get hashCode => Object.hash(site, warmerSide, deltaC, consecutive);
}

@immutable
class TempTabView {
  const TempTabView({
    required this.left,
    required this.right,
    required this.minute,
    this.deltaC = const [],
    this.alerts = const {},
  });

  static final initial = TempTabView(
    left: const TempFootView(side: FootSide.left, usable: false),
    right: const TempFootView(side: FootSide.right, usable: false),
    minute: DateTime.fromMillisecondsSinceEpoch(0),
  );

  final TempFootView left;
  final TempFootView right;

  /// Now, to the minute: the chart's end and its open gaps move once a
  /// minute, not at 10 Hz.
  final DateTime minute;

  /// ΔT left minus right per site (index = zone), rounded to 0.1 °C;
  /// empty unless both feet are usable. A site is null unless both feet
  /// read it with normal quality (rule 4).
  final List<double?> deltaC;

  /// The sites (zone index) where `TEMP_DELTA` holds now.
  final Map<int, TempAlertView> alerts;

  TempFootView foot(FootSide s) => s == FootSide.left ? left : right;
  bool get bothUsable => left.usable && right.usable;

  double? delta(int site) => site < deltaC.length ? deltaC[site] : null;

  /// No site has a two-foot ΔT.
  bool get noDelta => deltaC.every((d) => d == null);

  /// The site that names the Rest banner: the larger ΔT.
  TempAlertView? get topAlert {
    TempAlertView? best;
    for (final a in alerts.values) {
      if (best == null || a.deltaC > best.deltaC) best = a;
    }
    return best;
  }

  @override
  bool operator ==(Object other) =>
      other is TempTabView &&
      other.left == left &&
      other.right == right &&
      other.minute == minute &&
      listEquals(other.deltaC, deltaC) &&
      mapEquals(other.alerts, alerts);

  @override
  int get hashCode => Object.hash(
    left,
    right,
    minute,
    Object.hashAll(deltaC),
    Object.hashAll(alerts.values),
  );
}

/// Everything My feet shows (DESIGN-SPEC §8).
@immutable
class MyFeetView {
  const MyFeetView({required this.pressure, required this.temp});

  static final initial = MyFeetView(
    pressure: PressureTabView.initial,
    temp: TempTabView.initial,
  );

  final PressureTabView pressure;
  final TempTabView temp;

  /// "อัปเดตเมื่อสักครู่" while a foot streams; "ยังไม่มีข้อมูล" otherwise.
  bool get anyUsable => pressure.left.usable || pressure.right.usable;

  @override
  bool operator ==(Object other) =>
      other is MyFeetView && other.pressure == pressure && other.temp == temp;

  @override
  int get hashCode => Object.hash(pressure, temp);
}

/// Builds [MyFeetView] like Home's controller: the 2 s zone peaks from the
/// 50 Hz path ([RollingPeaks], rule 10), everything else from the 10 Hz
/// snapshot and the alert engine.
class MyFeetController extends Notifier<MyFeetView> {
  final _peaks = {
    for (final s in FootSide.values) s: RollingPeaks(windowMs: mapPeakWindowMs),
  };

  @override
  MyFeetView build() {
    final manager = ref.watch(deviceManagerProvider);
    final thresholds = ref.watch(thresholdsProvider);
    final engine = ref.watch(alertEngineProvider);
    MyFeetView viewOf(DisplaySnapshot s) => myFeetViewOf(
      s,
      thresholds: thresholds,
      rules: engine.view(s),
      figures: {
        for (final side in FootSide.values) side: engine.pressureFigures(side),
      },
      channelPeaks: {
        for (final side in FootSide.values) side: _peaks[side]!.channelPeaks(),
      },
    );
    final subs = <StreamSubscription<Object?>>[
      manager.batches.listen((b) => _peaks[b.side]!.add(b)),
      manager.snapshots.listen((s) {
        final next = viewOf(s);
        if (next != state) state = next;
      }),
    ];
    ref.onDispose(() {
      for (final sub in subs) {
        sub.cancel();
      }
    });
    return viewOf(manager.snapshot());
  }
}

final myFeetViewProvider = NotifierProvider<MyFeetController, MyFeetView>(
  MyFeetController.new,
);

double? _round1(double? v) => v == null ? null : (v * 10).round() / 10;

/// Pure: what My feet shows for [s]. A foot that is not usable gets no
/// values at all, only its No-data style (rules 4 and 5).
MyFeetView myFeetViewOf(
  DisplaySnapshot s, {
  required Thresholds thresholds,
  required RulesView rules,
  required Map<FootSide, PressureFigures> figures,
  required Map<FootSide, List<double>?> channelPeaks,
}) {
  PressureFootView pressureFoot(FootView f) {
    final peaks = mapPeaksOf(f, channelPeaks[f.side]);
    final map = footMapViewOf(f.side, peaks, thresholds);
    if (peaks == null) return PressureFootView(map: map);
    final fig = figures[f.side] ?? PressureFigures.none;
    return PressureFootView(
      map: map,
      kpa: [for (final k in peaks) k.round()],
      walkingPeakKpa: fig.walkingPeakKpa?.round(),
      ptiKpaS: fig.ptiKpaS?.round(),
      concentrationPct: fig.concentrationPct?.round(),
    );
  }

  TempFootView tempFoot(FootView f) {
    if (!f.usable) {
      return TempFootView(
        side: f.side,
        usable: false,
        lastDataAt: f.lastSampleAt,
      );
    }
    final t = f.temp;
    return TempFootView(
      side: f.side,
      usable: true,
      celsius: t == null ? const [] : [for (final c in t.celsius) _round1(c)],
      quality: t?.quality ?? const [],
    );
  }

  final both = s.left.usable && s.right.usable;
  final alerts = <int, TempAlertView>{};
  for (final c in rules.conditions) {
    if (c.code != AlertCode.tempDelta) continue;
    for (final e in TempSiteEntry.listOf(c.details)) {
      final site = footLayout.zones.indexWhere((z) => z.id == e.zone);
      if (site < 0) continue;
      alerts[site] = TempAlertView(
        site: site,
        warmerSide: c.side,
        deltaC: _round1(e.deltaC)!,
        consecutive: site == c.channel
            ? (c.details['consecutive'] as int?)
            : null,
      );
    }
  }
  final at = s.at;
  return MyFeetView(
    pressure: PressureTabView(
      left: pressureFoot(s.left),
      right: pressureFoot(s.right),
      cause: rules.top(bannerPressureCodes)?.cause,
    ),
    temp: TempTabView(
      left: tempFoot(s.left),
      right: tempFoot(s.right),
      minute: at.subtract(
        Duration(
          seconds: at.second,
          milliseconds: at.millisecond,
          microseconds: at.microsecond,
        ),
      ),
      deltaC: both ? [for (final d in s.deltaC) _round1(d)] : const [],
      alerts: both ? alerts : const {},
    ),
  );
}
