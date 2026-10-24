import 'package:drift/drift.dart';

import 'database.dart';
import 'local_date.dart';
import 'models.dart';

/// One row per local day. Alert counts and the foot-check flag are kept by
/// the alert and foot-check writes; ΔT by `TemperatureRecorder`; activity
/// by S8A.
abstract interface class DailySummaryRepository {
  Future<DailySummary?> get(String localDate);
  Stream<DailySummary?> watch(String localDate);

  /// Days in `[fromDate, toDate]` that have a row, oldest first.
  Future<List<DailySummary>> range(String fromDate, String toDate);

  /// Raises the day's max |ΔT| at [atMs]. Pass only two-foot values: a ΔT
  /// from one foot is never a reading (rule 4).
  Future<void> recordDelta(int atMs, {double? forefootC, double? heelC});

  /// Sets the activity figures given (S8A); null leaves a field as it is.
  Future<void> setActivity(
    String localDate,
    int atMs, {
    int? steps,
    int? walkingMin,
    int? wornMin,
  });
}

class DriftDailySummaryRepository implements DailySummaryRepository {
  DriftDailySummaryRepository(this._db, [this._dates = const LocalDates()]);

  final AppDatabase _db;
  final LocalDates _dates;

  SimpleSelectStatement<DailySummaries, DailySummaryRow> _day(String d) =>
      _db.select(_db.dailySummaries)..where((t) => t.localDate.equals(d));

  @override
  Future<DailySummary?> get(String localDate) async {
    final row = await _day(localDate).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  @override
  Stream<DailySummary?> watch(String localDate) =>
      _day(localDate)
          .watchSingleOrNull()
          .map((r) => r == null ? null : _toModel(r));

  @override
  Future<List<DailySummary>> range(String fromDate, String toDate) async {
    final rows =
        await (_db.select(_db.dailySummaries)
              ..where((t) => t.localDate.isBetweenValues(fromDate, toDate))
              ..orderBy([(t) => OrderingTerm.asc(t.localDate)]))
            .get();
    return rows.map(_toModel).toList();
  }

  @override
  Future<void> recordDelta(int atMs, {double? forefootC, double? heelC}) {
    if (forefootC == null && heelC == null) return Future.value();
    // SQLite's two-argument MAX() is NULL if either side is, hence the
    // COALESCE: a day's first value replaces NULL.
    return _db.customInsert(
      'INSERT INTO daily_summary '
      '(local_date, max_delta_forefoot_c, max_delta_heel_c, updated_at_ms) '
      'VALUES (?1, ?2, ?3, ?4) '
      'ON CONFLICT (local_date) DO UPDATE SET '
      'max_delta_forefoot_c = MAX(COALESCE(max_delta_forefoot_c, '
      'excluded.max_delta_forefoot_c), COALESCE(excluded.max_delta_forefoot_c, '
      'max_delta_forefoot_c)), '
      'max_delta_heel_c = MAX(COALESCE(max_delta_heel_c, '
      'excluded.max_delta_heel_c), COALESCE(excluded.max_delta_heel_c, '
      'max_delta_heel_c)), '
      'updated_at_ms = excluded.updated_at_ms',
      variables: [
        Variable.withString(_dates.of(atMs)),
        Variable<double>(forefootC?.abs()),
        Variable<double>(heelC?.abs()),
        Variable.withInt(atMs),
      ],
      updates: {_db.dailySummaries},
    );
  }

  @override
  Future<void> setActivity(
    String localDate,
    int atMs, {
    int? steps,
    int? walkingMin,
    int? wornMin,
  }) {
    final changes = DailySummariesCompanion(
      steps: steps == null ? const Value.absent() : Value(steps),
      walkingMin: walkingMin == null ? const Value.absent() : Value(walkingMin),
      wornMin: wornMin == null ? const Value.absent() : Value(wornMin),
      updatedAtMs: Value(atMs),
    );
    return _db
        .into(_db.dailySummaries)
        .insert(
          changes.copyWith(localDate: Value(localDate)),
          onConflict: DoUpdate((_) => changes),
        );
  }
}

/// Counts one alert of [level] on [localDate]. Part of the alert write.
Future<void> countAlertInSummary(
  AppDatabase db,
  String localDate,
  int level,
  int atMs,
) {
  final column = 'alerts_l$level'; // level is checked 1–5 by the schema
  return db.customInsert(
    'INSERT INTO daily_summary (local_date, $column, updated_at_ms) '
    'VALUES (?1, 1, ?2) '
    'ON CONFLICT (local_date) DO UPDATE SET $column = $column + 1, '
    'updated_at_ms = excluded.updated_at_ms',
    variables: [Variable.withString(localDate), Variable.withInt(atMs)],
    updates: {db.dailySummaries},
  );
}

/// Sets the day's foot-check flag. Part of the foot-check write.
Future<void> markFootCheckDone(AppDatabase db, String localDate, int atMs) =>
    db.customInsert(
      'INSERT INTO daily_summary (local_date, foot_check_done, updated_at_ms) '
      'VALUES (?1, 1, ?2) '
      'ON CONFLICT (local_date) DO UPDATE SET foot_check_done = 1, '
      'updated_at_ms = excluded.updated_at_ms',
      variables: [Variable.withString(localDate), Variable.withInt(atMs)],
      updates: {db.dailySummaries},
    );

DailySummary _toModel(DailySummaryRow r) => DailySummary(
  localDate: r.localDate,
  steps: r.steps,
  walkingMin: r.walkingMin,
  wornMin: r.wornMin,
  maxDeltaForefootC: r.maxDeltaForefootC,
  maxDeltaHeelC: r.maxDeltaHeelC,
  alertsByLevel: [r.alertsL1, r.alertsL2, r.alertsL3, r.alertsL4, r.alertsL5],
  footCheckDone: r.footCheckDone,
);
