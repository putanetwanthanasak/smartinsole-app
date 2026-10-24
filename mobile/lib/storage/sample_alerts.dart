import '../ble/packets.dart';
import '../config/foot_layout.dart';
import '../config/thresholds.dart';
import '../rules/patient_status.dart';
import '../rules/pressure_level.dart';
import 'alert_repository.dart';
import 'foot_check_repository.dart';
import 'models.dart';

/// DEBUG ONLY: one alert of each listed kind with the design boards'
/// example values (DESIGN-SPEC §7.3, boards AlertsD / AlertDetailD /
/// AlertDetailDPressure / AlertDetailDDevice), for the design screenshots.
///
/// Reached only from Settings in a mock-preset run, whose database is in
/// memory: these rows never reach the phone's file. They do not come from
/// the alert engine. Threshold fields come from `thresholds.json`.
Future<void> seedSampleAlerts({
  required AlertRepository alerts,
  required FootCheckRepository footChecks,
  required Thresholds thresholds,
  required DateTime now,
}) async {
  final t = thresholds;
  int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  int at(DateTime day, int h, int m, [int s = 0]) =>
      DateTime(day.year, day.month, day.day, h, m, s).millisecondsSinceEpoch;

  Map<String, Object?> foot(List<double> kpa) => {
    'kpa': kpa,
    'levels': [for (final k in kpa) pressureLevel(k, t).name],
  };
  Map<String, Object?> map(List<double> left, List<double> right) => {
    'left': foot(left),
    'right': foot(right),
  };
  const lowLeft = <double>[40, 55, 35, 30, 20, 60];
  const lowRight = <double>[38, 50, 34, 28, 22, 58];
  String zone(int channel) => footLayout.zones[channel].id;

  await alerts.add(
    NewAlert(
      kind: AlertKind.deviceLost,
      patientLevel: PatientLevel.noData,
      atMs: at(yesterday, 16, 20),
      side: FootSide.left,
      measuredValue: 6,
      threshold: t.deviceLostAfterMin.toDouble(),
      details: {'lastDataAtMs': at(yesterday, 16, 14, 5), 'lastBatteryPct': 43},
    ),
  );
  await alerts.add(
    NewAlert(
      kind: AlertKind.batteryLow,
      patientLevel: PatientLevel.safe,
      atMs: at(yesterday, 18, 5),
      side: FootSide.right,
      measuredValue: 12,
      threshold: t.batteryLowPct,
    ),
  );
  await alerts.add(
    NewAlert(
      kind: AlertKind.pressurePti,
      patientLevel: PatientLevel.careful,
      atMs: ago(const Duration(hours: 3)),
      side: FootSide.left,
      zone: zone(1),
      measuredValue: 92,
      threshold: t.ptiKpaS,
      details: {
        'steps': 24,
        'windowMin': t.ptiWindowMin,
        'map': map(const [60, 140, 50, 30, 20, 70], lowRight),
      },
    ),
  );
  await alerts.add(
    NewAlert(
      kind: AlertKind.pressurePeak,
      patientLevel: PatientLevel.careful,
      atMs: ago(const Duration(hours: 2)),
      side: FootSide.left,
      zone: zone(1),
      measuredValue: 236,
      threshold: t.alertKpa,
      gaitClass: 'toe_walking',
      gaitConfidence: 0.78,
      details: {
        'walking': true,
        'map': map(const [90, 236, 60, 30, 20, 40], lowRight),
      },
    ),
  );
  await alerts.add(
    NewAlert(
      kind: AlertKind.loadConcentration,
      patientLevel: PatientLevel.careful,
      atMs: ago(const Duration(hours: 1)),
      side: FootSide.right,
      zone: zone(5),
      measuredValue: 46,
      threshold: t.concentrationPct,
      details: {
        'steps': t.concentrationSteps,
        'map': map(lowLeft, const [30, 40, 30, 25, 30, 150]),
      },
    ),
  );
  await alerts.add(
    NewAlert(
      kind: AlertKind.tempDelta,
      patientLevel: PatientLevel.rest,
      atMs: ago(const Duration(minutes: 30)),
      side: FootSide.right,
      site: TempSite.heel,
      measuredValue: 2.6,
      threshold: t.deltaC,
      details: {
        'leftC': 31.4,
        'rightC': 34.0,
        'consecutive': 3,
        'otherSiteDeltaC': 0.4,
      },
    ),
  );
  // A foot-check finding, through the real save path (it also stores the
  // check and marks that day's check done).
  await footChecks.save(
    FootCheckDraft(
      atMs: ago(const Duration(days: 2)),
      redness: FootCheckAnswer.none,
      wound: FootCheckAnswer.yesOrUnsure,
      swelling: FootCheckAnswer.none,
      answerOnly: true,
    ),
  );
}
