import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../ble/packets.dart';
import '../config/foot_layout.dart';
import '../rules/patient_status.dart';
import 'models.dart';

part 'database.g.dart';

// Schema v1 (S6A). Every time is UTC ms (`*_ms`); `local_date` is the
// phone's calendar day `YYYY-MM-DD` at that time (`LocalDates`). Enums are
// stored by name (`textEnum`), so renaming an enum value is a migration.
// No names or subject codes anywhere in this file (IRB).

@DataClassName('AlertRow')
@TableIndex(name: 'alerts_at', columns: {#atMs})
@TableIndex(name: 'alerts_read_at', columns: {#readAtMs})
@TableIndex(name: 'alerts_capture', columns: {#captureStamp})
class Alerts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `AlertKind.wireName`: the contract code, or `FOOT_CHECK_FINDING`.
  TextColumn get code => text().map(const _AlertKindConverter())();

  /// Internal level 1–5, from the code.
  // Drift names the column in its own check this way.
  // ignore: recursive_getters
  IntColumn get level => integer().check(level.isBetweenValues(1, 5))();
  TextColumn get patientStatus => textEnum<PatientLevel>()();
  TextColumn get side => textEnum<FootSide>().nullable()();
  TextColumn get zone => text().nullable()();
  TextColumn get site => textEnum<TempSite>().nullable()();
  RealColumn get measuredValue => real().nullable()();
  RealColumn get threshold => real().nullable()();
  TextColumn get gaitClass => text().nullable()();
  RealColumn get gaitConfidence => real().nullable()();
  TextColumn get details => text().map(const _JsonMapConverter()).nullable()();
  IntColumn get atMs => integer()();
  TextColumn get localDate => text()();
  IntColumn get readAtMs => integer().nullable()();

  /// The research capture's time stamp (`captureStampOf`). An alert with
  /// one is study data: retention never deletes it.
  TextColumn get captureStamp => text().nullable()();
  IntColumn get footCheckId => integer().nullable().references(
    FootChecks,
    #id,
    onDelete: KeyAction.setNull,
  )();
}

/// One row per foot per 30 s reading.
@DataClassName('TemperatureRow')
@TableIndex(name: 'temperature_side_at', columns: {#side, #atMs})
@TableIndex(name: 'temperature_date', columns: {#localDate})
class TemperatureReadings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get atMs => integer()();
  TextColumn get localDate => text()();
  TextColumn get side => textEnum<FootSide>()();
  RealColumn get forefootC => real().nullable()();
  RealColumn get heelC => real().nullable()();
  TextColumn get quality => textEnum<TempQuality>()();
  BoolColumn get timeFromArrival => boolean()();
}

@DataClassName('DailySummaryRow')
class DailySummaries extends Table {
  @override
  String get tableName => 'daily_summary';

  TextColumn get localDate => text()();

  // Filled by later sessions (steps in S8A).
  IntColumn get steps => integer().nullable()();
  IntColumn get walkingMin => integer().nullable()();
  IntColumn get wornMin => integer().nullable()();

  RealColumn get maxDeltaForefootC => real().nullable()();
  RealColumn get maxDeltaHeelC => real().nullable()();
  IntColumn get alertsL1 => integer().withDefault(const Constant(0))();
  IntColumn get alertsL2 => integer().withDefault(const Constant(0))();
  IntColumn get alertsL3 => integer().withDefault(const Constant(0))();
  IntColumn get alertsL4 => integer().withDefault(const Constant(0))();
  IntColumn get alertsL5 => integer().withDefault(const Constant(0))();
  BoolColumn get footCheckDone =>
      boolean().withDefault(const Constant(false))();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {localDate};
}

@DataClassName('FootCheckRow')
@TableIndex(name: 'foot_checks_date', columns: {#localDate})
class FootChecks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get atMs => integer()();
  TextColumn get localDate => text()();

  // null = unanswered (decision 9); a saved check has all three.
  TextColumn get qRedness => textEnum<FootCheckAnswer>().nullable()();
  TextColumn get qWound => textEnum<FootCheckAnswer>().nullable()();
  TextColumn get qSwelling => textEnum<FootCheckAnswer>().nullable()();
  TextColumn get result => textEnum<FootCheckResult>()();

  // Relative to the foot-photo folder; null = skipped.
  TextColumn get photoSoleLeft => text().nullable()();
  TextColumn get photoSoleRight => text().nullable()();
  TextColumn get photoTopLeft => text().nullable()();
  TextColumn get photoTopRight => text().nullable()();
  BoolColumn get answerOnly => boolean()();
}

@DriftDatabase(
  tables: [Alerts, TemperatureReadings, DailySummaries, FootChecks],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// The app's file, `smartinsole.sqlite` in the app-private support folder
  /// (`/data/data/th.ac.kmutt.smartinsole/files`).
  factory AppDatabase.open() => AppDatabase(
    driftDatabase(
      name: fileName,
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    ),
  );

  /// In memory: mock runs, the emulator's fake BLE, and tests. Mock data
  /// never lands in the phone's real file.
  factory AppDatabase.memory() => AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );

  static const fileName = 'smartinsole';

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

class _AlertKindConverter extends TypeConverter<AlertKind, String> {
  const _AlertKindConverter();

  @override
  AlertKind fromSql(String fromDb) => AlertKind.fromWire(fromDb);

  @override
  String toSql(AlertKind value) => value.wireName;
}

class _JsonMapConverter extends TypeConverter<Map<String, Object?>, String> {
  const _JsonMapConverter();

  @override
  Map<String, Object?> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as Map).cast<String, Object?>();

  @override
  String toSql(Map<String, Object?> value) => jsonEncode(value);
}
