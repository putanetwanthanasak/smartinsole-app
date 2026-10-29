import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../ble/packets.dart';
import '../rules/patient_status.dart';
import 'database.steps.dart';
import 'models.dart';

part 'database.g.dart';

// Schema v1 (S6A), v2 (S8D: 8 temperature sites, DATA-CONTRACT v1.6).
// Every time is UTC ms (`*_ms`); `local_date` is the phone's calendar day
// `YYYY-MM-DD` at that time (`LocalDates`). Enums are stored by name
// (`textEnum`), so renaming an enum value is a migration. v2 only adds
// columns: rows written before it keep their values and are never
// rewritten. No names or subject codes anywhere in this file (IRB).

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

  /// Zone id (`FootZone.id`). Since v2 also the temperature site of a
  /// `TEMP_DELTA` (site i = zone i).
  TextColumn get zone => text().nullable()();

  /// The v1 temperature site of a `TEMP_DELTA` raised before v2
  /// (forefoot or heel); never written since.
  TextColumn get site => textEnum<LegacyTempSite>().nullable()();
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

  /// v1 rows only (the 12-byte packet's two sites); null since v2.
  RealColumn get forefootC => real().nullable()();
  RealColumn get heelC => real().nullable()();

  /// v1: the packet's quality. v2: the worst of the 8 sites' qualities.
  TextColumn get quality => textEnum<TempQuality>()();
  BoolColumn get timeFromArrival => boolean()();

  // v2: one value and one quality per site (index = zone, NTC i next to
  // FSR i); null in v1 rows, and a null value = could not read.
  RealColumn get site0C => real().named('site0_c').nullable()();
  RealColumn get site1C => real().named('site1_c').nullable()();
  RealColumn get site2C => real().named('site2_c').nullable()();
  RealColumn get site3C => real().named('site3_c').nullable()();
  RealColumn get site4C => real().named('site4_c').nullable()();
  RealColumn get site5C => real().named('site5_c').nullable()();
  RealColumn get site6C => real().named('site6_c').nullable()();
  RealColumn get site7C => real().named('site7_c').nullable()();
  TextColumn get site0Q =>
      textEnum<TempQuality>().named('site0_q').nullable()();
  TextColumn get site1Q =>
      textEnum<TempQuality>().named('site1_q').nullable()();
  TextColumn get site2Q =>
      textEnum<TempQuality>().named('site2_q').nullable()();
  TextColumn get site3Q =>
      textEnum<TempQuality>().named('site3_q').nullable()();
  TextColumn get site4Q =>
      textEnum<TempQuality>().named('site4_q').nullable()();
  TextColumn get site5Q =>
      textEnum<TempQuality>().named('site5_q').nullable()();
  TextColumn get site6Q =>
      textEnum<TempQuality>().named('site6_q').nullable()();
  TextColumn get site7Q =>
      textEnum<TempQuality>().named('site7_q').nullable()();
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

  /// v1 days only (the two v1 sites); never written since v2.
  RealColumn get maxDeltaForefootC => real().nullable()();
  RealColumn get maxDeltaHeelC => real().nullable()();

  /// v2: the day's largest |ΔT| over the 8 sites and the site it was at
  /// (zone index).
  RealColumn get maxDeltaC => real().nullable()();
  IntColumn get maxDeltaSite => integer().nullable()();
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
  AppDatabase(super.e, {this.inMemory = false});

  /// True for [AppDatabase.memory]. Its foot photos go to a separate
  /// folder (`footPhotoPath` in storage_providers.dart), never the real
  /// one.
  final bool inMemory;

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
    inMemory: true,
  );

  static const fileName = 'smartinsole';

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        final t = schema.temperatureReadings;
        for (final c in [
          t.site0C, t.site1C, t.site2C, t.site3C, //
          t.site4C, t.site5C, t.site6C, t.site7C,
          t.site0Q, t.site1Q, t.site2Q, t.site3Q,
          t.site4Q, t.site5Q, t.site6Q, t.site7Q,
        ]) {
          await m.addColumn(t, c);
        }
        await m.addColumn(schema.dailySummary, schema.dailySummary.maxDeltaC);
        await m.addColumn(
          schema.dailySummary,
          schema.dailySummary.maxDeltaSite,
        );
      },
    ),
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
