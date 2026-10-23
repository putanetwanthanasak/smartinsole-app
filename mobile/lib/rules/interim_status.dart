import 'dart:async';

import '../ble/packets.dart';
import '../config/foot_layout.dart';
import '../config/thresholds.dart';
import '../device/device_manager.dart';
import '../device/display_snapshot.dart';
import '../device/foot_sample.dart';
import '../device/mock_data_source.dart';
import 'alert_code.dart';
import 'patient_status.dart';

/// **INTERIM status source for S5; S7's rules engine replaces it.**
///
/// What it checks:
/// - No data unless both feet are usable (DESIGN-SPEC D7: one foot
///   missing shows No data; BACKLOG 38 has the S7 rule that a level 3+
///   from the connected foot must win).
/// - `TEMP_DELTA` → Rest your feet: |ΔT| at one site above `deltaC` on
///   `consecutiveReadings` reading pairs in a row (rule 6).
///
/// What it does **not** check (S7): every level-3 rule (`PRESSURE_PEAK`,
/// `PRESSURE_PTI`, `LOAD_CONCENTRATION`), so with real insoles Home can
/// show Safe while a level-3 condition holds. The orange dots (level 2,
/// `PRESSURE_WATCH`) and the balance note are drawn from the data
/// directly and do not need this class.
///
/// In a debug run with a mock preset, the one level-3 scenario the presets
/// model (`watch`, `PRESSURE_PTI` at the left forefoot) is taken from
/// [mockLevel3Cause] instead of a rule. Mock presets never exist in
/// release builds.
class InterimStatus {
  InterimStatus({
    required this.manager,
    required this.thresholds,
    this.mockPreset,
  }) {
    _sub = manager.temps.listen(_onTemp);
  }

  final DeviceManager manager;
  final Thresholds thresholds;

  /// The active mock preset, read on every [status] call.
  final MockPreset? Function()? mockPreset;

  late final StreamSubscription<FootTemp> _sub;
  final _fresh = {FootSide.left: false, FootSide.right: false};
  final _overCount = {TempSite.forefoot: 0, TempSite.heel: 0};

  /// Consecutive reading pairs above `deltaC`, per site (for tests).
  int overCount(TempSite site) => _overCount[site]!;

  void _onTemp(FootTemp t) {
    _fresh[t.side] = true;
    if (!_fresh.values.every((f) => f)) return;
    _fresh.updateAll((_, _) => false);
    final s = manager.snapshot();
    for (final site in TempSite.values) {
      final d = _delta(s, site);
      _overCount[site] = d != null && deltaAbove(d, thresholds.deltaC)
          ? _overCount[site]! + 1
          : 0;
    }
  }

  static double? _delta(DisplaySnapshot s, TempSite site) {
    if (!s.left.usable || !s.right.usable) return null;
    return site == TempSite.forefoot ? s.deltaForefootC : s.deltaHeelC;
  }

  /// The status for [s] (a snapshot of [manager]).
  PatientStatus status(DisplaySnapshot s) {
    if (!s.left.usable || !s.right.usable) return PatientStatus.noData;

    StatusCause? temp;
    for (final site in TempSite.values) {
      final d = _delta(s, site);
      if (d == null) continue;
      if (_overCount[site]! < thresholds.consecutiveReadings) continue;
      if (!deltaAbove(d, thresholds.deltaC)) continue;
      if (temp != null && temp.deltaC! >= d.abs()) continue;
      temp = StatusCause(
        code: AlertCode.tempDelta,
        // ΔT is left minus right: positive means the left foot is warmer.
        side: d > 0 ? FootSide.left : FootSide.right,
        site: site,
        deltaC: d.abs(),
      );
    }
    if (temp != null) return PatientStatus.from(temp);

    final preset = mockPreset?.call();
    final mock = preset == null ? null : mockLevel3Cause(preset);
    if (mock != null) return PatientStatus.from(mock);
    return PatientStatus.safe;
  }

  void dispose() => _sub.cancel();
}

/// |ΔT| strictly above [deltaC] (contract §8.3 "> 2.2 °C"), compared at
/// the sensor's 0.01 °C resolution so float noise (33.20 − 31.00 =
/// 2.2000000000000028) never crosses the boundary.
bool deltaAbove(double delta, double deltaC) =>
    (delta.abs() * 100).round() > (deltaC * 100).round();

/// Debug only: the level-3 cause a mock preset is built to trigger, which
/// no S5 code evaluates (see [InterimStatus]). `watch` is "ปลายเท้าซ้าย
/// รับน้ำหนักมากต่อเนื่องนานเกินไป": `PRESSURE_PTI` at the left first
/// metatarsal head (mock_data_source.dart).
StatusCause? mockLevel3Cause(MockPreset preset) => switch (preset) {
  MockPreset.watch => const StatusCause(
    code: AlertCode.pressurePti,
    side: FootSide.left,
    channel: 1,
  ),
  _ => null,
};
