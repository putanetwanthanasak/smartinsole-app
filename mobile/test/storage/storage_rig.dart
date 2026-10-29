import 'package:flutter_test/flutter_test.dart';
import 'package:smartinsole/ble/ble_protocol.dart';
import 'package:smartinsole/ble/packets.dart';
import 'package:smartinsole/rules/patient_status.dart';
import 'package:smartinsole/storage/alert_repository.dart';
import 'package:smartinsole/storage/daily_summary_repository.dart';
import 'package:smartinsole/storage/database.dart';
import 'package:smartinsole/storage/foot_check_repository.dart';
import 'package:smartinsole/storage/local_date.dart';
import 'package:smartinsole/storage/models.dart';
import 'package:smartinsole/storage/temperature_repository.dart';

/// Bangkok, UTC+7 all year: local midnight is 17:00 UTC.
const bangkok = LocalDates(_plus7);
Duration _plus7(DateTime _) => const Duration(hours: 7);

/// UTC ms of a Bangkok wall-clock time.
int bkk(int y, int mo, int d, [int h = 0, int mi = 0, int s = 0, int ms = 0]) =>
    DateTime.utc(
      y,
      mo,
      d,
      h,
      mi,
      s,
      ms,
    ).subtract(const Duration(hours: 7)).millisecondsSinceEpoch;

/// An in-memory database with every repository, on Bangkok dates.
class StorageRig {
  StorageRig() {
    addTearDown(db.close);
  }

  final db = AppDatabase.memory();
  late final alerts = DriftAlertRepository(db, bangkok);
  late final temperatures = DriftTemperatureRepository(db, bangkok);
  late final summaries = DriftDailySummaryRepository(db, bangkok);
  late final footChecks = DriftFootCheckRepository(db, bangkok);
}

NewAlert alertOf(
  AlertKind kind,
  int atMs, {
  PatientLevel level = PatientLevel.careful,
  String? captureStamp,
  FootSide? side,
}) => NewAlert(
  kind: kind,
  patientLevel: level,
  atMs: atMs,
  side: side,
  captureStamp: captureStamp,
);

FootCheckDraft draftOf(
  int atMs, {
  FootCheckAnswer? redness = FootCheckAnswer.none,
  FootCheckAnswer? wound = FootCheckAnswer.none,
  FootCheckAnswer? swelling = FootCheckAnswer.none,
  Map<FootView, String> photos = const {},
}) => FootCheckDraft(
  atMs: atMs,
  redness: redness,
  wound: wound,
  swelling: swelling,
  answerOnly: photos.isEmpty,
  photos: photos,
);

/// One reading's 8 sites: [c] at every site, [at] overriding some (null:
/// the sensor could not read).
List<double?> sitesC(double? c, [Map<int, double?> at = const {}]) => [
  for (var i = 0; i < TempLayout.siteCount; i++) at.containsKey(i) ? at[i] : c,
];

/// One reading's 8 qualities: [q] at every site, [at] overriding some.
List<TempQuality> sitesQ([
  TempQuality q = TempQuality.normal,
  Map<int, TempQuality> at = const {},
]) => [for (var i = 0; i < TempLayout.siteCount; i++) at[i] ?? q];

/// Stores one reading of [side] (every site [c] unless [at] says).
Future<void> addReading(
  TemperatureRepository repo,
  FootSide side,
  int atMs, {
  double? c = 31.0,
  Map<int, double?> at = const {},
  TempQuality quality = TempQuality.normal,
  Map<int, TempQuality> qualityAt = const {},
  bool fromArrival = false,
}) => repo.add(
  side: side,
  atMs: atMs,
  celsius: sitesC(c, at),
  quality: sitesQ(quality, qualityAt),
  timeFromArrival: fromArrival,
);
