import 'package:drift/drift.dart';

import 'daily_summary_repository.dart';
import 'database.dart';
import 'local_date.dart';
import 'models.dart';

/// Stored alerts. S7's AlertEngine writes through [add]; the Alerts screen
/// (S6B) and the bottom-bar badge read through [watchVisible] and
/// [watchUnreadCount], which share one visibility rule.
abstract interface class AlertRepository {
  /// Stores [alert] and counts it in its day's summary. Returns its id.
  Future<int> add(NewAlert alert);

  /// What the Alerts list shows at [nowMs]: patient-visible alerts of the
  /// last [retentionPeriod], newest first.
  Stream<List<StoredAlert>> watchVisible(int nowMs);

  /// Unread alerts among exactly the ones [watchVisible] lists.
  Stream<int> watchUnreadCount(int nowMs);

  Future<StoredAlert?> byId(int id);

  /// Marks it read the first time it is opened (decision 7); later calls
  /// keep the first time.
  Future<void> markRead(int id, int atMs);

  /// Marks the foot-check finding of check [footCheckId] read: Something
  /// found is that alert's result screen, however it was opened (§7.2,
  /// decision 7). Keeps an earlier read time.
  Future<void> markFootCheckRead(int footCheckId, int atMs);

  /// Every alert of one research capture, all levels, oldest first (for
  /// the capture export, BACKLOG).
  Future<List<StoredAlert>> forCapture(String captureStamp);

  /// Removes one capture's alerts. Only for "Delete from phone" of that
  /// capture; retention never removes them. Returns how many went.
  Future<int> deleteForCapture(String captureStamp);

  /// Every alert raised at or after [fromMs], all levels, oldest first:
  /// the AlertEngine's repeat-suppression memory after a restart.
  Future<List<StoredAlert>> since(int fromMs);

  /// Row counts for the BLE debug screen.
  Stream<AlertStats> watchStats();
}

/// What the BLE debug screen shows about the alerts table.
class AlertStats {
  const AlertStats({required this.count, required this.tagged, this.latest});

  /// All rows, every level.
  final int count;

  /// Rows with a research-capture stamp.
  final int tagged;

  /// The newest row.
  final StoredAlert? latest;
}

class DriftAlertRepository implements AlertRepository {
  DriftAlertRepository(this._db, [this._dates = const LocalDates()]);

  final AppDatabase _db;
  final LocalDates _dates;

  @override
  Future<int> add(NewAlert alert) =>
      _db.transaction(() => insertAlert(_db, _dates, alert));

  @override
  Stream<List<StoredAlert>> watchVisible(int nowMs) {
    final a = _db.alerts;
    final q = _db.select(a)
      ..where((_) => _visible(a, nowMs))
      ..orderBy([
        (t) => OrderingTerm.desc(t.atMs),
        (t) => OrderingTerm.desc(t.id),
      ]);
    return q.map(_toModel).watch();
  }

  @override
  Stream<int> watchUnreadCount(int nowMs) {
    final a = _db.alerts;
    final count = a.id.count();
    final q = _db.selectOnly(a)
      ..addColumns([count])
      ..where(_visible(a, nowMs) & a.readAtMs.isNull());
    return q.map((r) => r.read(count) ?? 0).watchSingle();
  }

  @override
  Future<StoredAlert?> byId(int id) async {
    final row = await (_db.select(
      _db.alerts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  @override
  Future<void> markRead(int id, int atMs) =>
      (_db.update(_db.alerts)
            ..where((t) => t.id.equals(id) & t.readAtMs.isNull()))
          .write(AlertsCompanion(readAtMs: Value(atMs)));

  @override
  Future<void> markFootCheckRead(int footCheckId, int atMs) =>
      (_db.update(_db.alerts)..where(
            (t) => t.footCheckId.equals(footCheckId) & t.readAtMs.isNull(),
          ))
          .write(AlertsCompanion(readAtMs: Value(atMs)));

  @override
  Future<List<StoredAlert>> forCapture(String captureStamp) async {
    final rows =
        await (_db.select(_db.alerts)
              ..where((t) => t.captureStamp.equals(captureStamp))
              ..orderBy([(t) => OrderingTerm.asc(t.atMs)]))
            .get();
    return rows.map(_toModel).toList();
  }

  @override
  Future<int> deleteForCapture(String captureStamp) => (_db.delete(
    _db.alerts,
  )..where((t) => t.captureStamp.equals(captureStamp))).go();

  @override
  Future<List<StoredAlert>> since(int fromMs) async {
    final rows =
        await (_db.select(_db.alerts)
              ..where((t) => t.atMs.isBiggerOrEqualValue(fromMs))
              ..orderBy([(t) => OrderingTerm.asc(t.atMs)]))
            .get();
    return rows.map(_toModel).toList();
  }

  @override
  Stream<AlertStats> watchStats() {
    final a = _db.alerts;
    final count = a.id.count();
    final tagged = a.captureStamp.count();
    final counts = _db.selectOnly(a)..addColumns([count, tagged]);
    return counts.watchSingle().asyncMap((r) async {
      final latest =
          await (_db.select(a)
                ..orderBy([
                  (t) => OrderingTerm.desc(t.atMs),
                  (t) => OrderingTerm.desc(t.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      return AlertStats(
        count: r.read(count) ?? 0,
        tagged: r.read(tagged) ?? 0,
        latest: latest == null ? null : _toModel(latest),
      );
    });
  }

  /// The patient-visibility rule, the one place both queries take it from:
  /// a kind the patient sees ([AlertKind.patientVisible]) inside the
  /// 30-day window the list footer promises.
  static Expression<bool> _visible(Alerts a, int nowMs) =>
      a.code.isIn([
        for (final k in AlertKind.values)
          if (k.patientVisible) k.wireName,
      ]) &
      a.atMs.isBiggerOrEqualValue(nowMs - retentionPeriod.inMilliseconds);
}

/// Inserts one alert and counts it in the day's summary. Callers run it
/// inside a transaction (a foot-check finding is written with its check).
Future<int> insertAlert(
  AppDatabase db,
  LocalDates dates,
  NewAlert a, {
  int? footCheckId,
}) async {
  final localDate = dates.of(a.atMs);
  final id = await db
      .into(db.alerts)
      .insert(
        AlertsCompanion.insert(
          code: a.kind,
          level: a.kind.level,
          patientStatus: a.patientLevel,
          side: Value(a.side),
          zone: Value(a.zone),
          site: Value(a.site),
          measuredValue: Value(a.measuredValue),
          threshold: Value(a.threshold),
          gaitClass: Value(a.gaitClass),
          gaitConfidence: Value(a.gaitConfidence),
          details: Value(a.details),
          atMs: a.atMs,
          localDate: localDate,
          captureStamp: Value(a.captureStamp),
          footCheckId: Value(footCheckId),
        ),
      );
  await countAlertInSummary(db, localDate, a.kind.level, a.atMs);
  return id;
}

StoredAlert _toModel(AlertRow r) => StoredAlert(
  id: r.id,
  kind: r.code,
  level: r.level,
  patientLevel: r.patientStatus,
  atMs: r.atMs,
  localDate: r.localDate,
  side: r.side,
  zone: r.zone,
  site: r.site,
  measuredValue: r.measuredValue,
  threshold: r.threshold,
  gaitClass: r.gaitClass,
  gaitConfidence: r.gaitConfidence,
  details: r.details,
  readAtMs: r.readAtMs,
  captureStamp: r.captureStamp,
  footCheckId: r.footCheckId,
);
