import 'package:drift/drift.dart';

import '../rules/patient_status.dart';
import 'alert_repository.dart';
import 'daily_summary_repository.dart';
import 'database.dart';
import 'local_date.dart';
import 'models.dart';

/// Daily foot checks (S8C builds the screens). Photo files live in the
/// foot-photo folder; rows hold paths relative to it.
abstract interface class FootCheckRepository {
  /// Saves a finished check. The result is decided here, never by the
  /// caller: any "มี / ไม่แน่ใจ" is a finding (rule 14). A finding is
  /// also stored as a `FOOT_CHECK_FINDING` alert, in the same transaction.
  ///
  /// Throws [ArgumentError] while any answer is still unanswered: the app
  /// never records a check as fine without all three answers.
  Future<FootCheck> save(FootCheckDraft draft);

  Future<FootCheck?> byId(int id);

  /// The day's last saved check (decision 8: the tab shows Saved then).
  Stream<FootCheck?> watchLatestOn(String localDate);

  /// Checks on days in `[fromDate, toDate]`, oldest first (the 7-day row).
  Future<List<FootCheck>> range(String fromDate, String toDate);
}

/// Rule 14: only the answers count, and "not sure" counts as abnormal.
FootCheckResult footCheckResultOf(Iterable<FootCheckAnswer> answers) =>
    answers.contains(FootCheckAnswer.yesOrUnsure)
    ? FootCheckResult.found
    : FootCheckResult.saved;

class DriftFootCheckRepository implements FootCheckRepository {
  DriftFootCheckRepository(this._db, [this._dates = const LocalDates()]);

  final AppDatabase _db;
  final LocalDates _dates;

  @override
  Future<FootCheck> save(FootCheckDraft d) async {
    final answers = [d.redness, d.wound, d.swelling];
    if (answers.contains(null)) {
      throw ArgumentError('a foot check is saved only with all 3 answers');
    }
    final result = footCheckResultOf(answers.cast<FootCheckAnswer>());
    final localDate = _dates.of(d.atMs);
    final id = await _db.transaction(() async {
      final id = await _db
          .into(_db.footChecks)
          .insert(
            FootChecksCompanion.insert(
              atMs: d.atMs,
              localDate: localDate,
              qRedness: Value(d.redness),
              qWound: Value(d.wound),
              qSwelling: Value(d.swelling),
              result: result,
              photoSoleLeft: Value(d.photos[FootView.soleLeft]),
              photoSoleRight: Value(d.photos[FootView.soleRight]),
              photoTopLeft: Value(d.photos[FootView.topLeft]),
              photoTopRight: Value(d.photos[FootView.topRight]),
              answerOnly: d.answerOnly,
            ),
          );
      await markFootCheckDone(_db, localDate, d.atMs);
      if (result == FootCheckResult.found) {
        await insertAlert(
          _db,
          _dates,
          NewAlert(
            kind: AlertKind.footCheckFinding,
            patientLevel: PatientLevel.careful,
            atMs: d.atMs,
          ),
          footCheckId: id,
        );
      }
      return id;
    });
    return (await byId(id))!;
  }

  @override
  Future<FootCheck?> byId(int id) async {
    final row = await (_db.select(
      _db.footChecks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : footCheckOf(row);
  }

  @override
  Stream<FootCheck?> watchLatestOn(String localDate) =>
      (_db.select(_db.footChecks)
            ..where((t) => t.localDate.equals(localDate))
            ..orderBy([
              (t) => OrderingTerm.desc(t.atMs),
              (t) => OrderingTerm.desc(t.id),
            ])
            ..limit(1))
          .map(footCheckOf)
          .watchSingleOrNull();

  @override
  Future<List<FootCheck>> range(String fromDate, String toDate) async {
    final rows =
        await (_db.select(_db.footChecks)
              ..where((t) => t.localDate.isBetweenValues(fromDate, toDate))
              ..orderBy([(t) => OrderingTerm.asc(t.atMs)]))
            .get();
    return rows.map(footCheckOf).toList();
  }
}

FootCheck footCheckOf(FootCheckRow r) => FootCheck(
  id: r.id,
  atMs: r.atMs,
  localDate: r.localDate,
  redness: r.qRedness,
  wound: r.qWound,
  swelling: r.qSwelling,
  result: r.result,
  photos: {
    FootView.soleLeft: ?r.photoSoleLeft,
    FootView.soleRight: ?r.photoSoleRight,
    FootView.topLeft: ?r.photoTopLeft,
    FootView.topRight: ?r.photoTopRight,
  },
  answerOnly: r.answerOnly,
);
